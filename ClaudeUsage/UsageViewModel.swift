import Foundation
import AppKit
import Combine
import Security
import SwiftUI
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.stoneros.claude-usage", category: "api")

@MainActor
final class UsageViewModel: ObservableObject {
    // API usage (real-time plan limits)
    @Published var usage: UsageResponse?
    @Published var apiError: String?
    @Published var lastAPIRefresh: Date?
    @Published var refreshState: RefreshState = .idle

    enum RefreshState: Sendable {
        case idle, refreshing, done, failed
    }

    enum ExportState: Sendable {
        case idle, exporting, success, failed
    }
    @Published var exportState: ExportState = .idle

    // Local stats
    @Published var stats: StatsCache?
    @Published var todayActivity: DailyActivity?
    @Published var currentWeek: WeeklySummary?
    @Published var usageHours: UsageHours?
    @Published var costAnalysis: CostAnalysis?
    @Published var dailyHoursMap: [String: Double] = [:]  // "yyyy-MM-dd" -> hours

    // Utilization time-series (Stream 2)
    @Published var usageHistory: [UsageSnapshot] = []

    @Published var selectedTab: Tab = .limits

    enum Tab: String, CaseIterable, Sendable {
        case limits = "Plan"
        case week = "Week"
        case cost = "Cost"
        case patterns = "When"
        case trends = "Trends"
    }

    private var apiTimer: AnyCancellable?
    private var statsTimer: AnyCancellable?
    private let statsComputer = StatsComputer()

    // Token cache (in-memory) — tier 1 of the 3-tier read in readOAuthToken()
    private var cachedToken: String?
    private var cachedTokenExpiresAt: Int64 = 0

    // Notification tracking — keyed by "threshold_resetsAt" to avoid re-firing per window
    private var notifiedThresholds: Set<String> = []

    private let apiURL = "https://api.anthropic.com/api/oauth/usage"
    // Effective poll interval — starts at user preference, doubles on 429, resets on 200
    private var pollInterval: TimeInterval
    private var backoffUntil: Date?

    private var cacheURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        return dir.appendingPathComponent("usage-cache.json")
    }

    // MARK: - Configurable thresholds (read from UserDefaults at call time)

    private var alertThreshold1: Double {
        let v = UserDefaults.standard.integer(forKey: "alertThreshold1")
        return Double(v > 0 ? v : 80)
    }

    private var alertThreshold2: Double {
        let v = UserDefaults.standard.integer(forKey: "alertThreshold2")
        return Double(v > 0 ? v : 95)
    }

    private var basePollInterval: TimeInterval {
        let mins = UserDefaults.standard.integer(forKey: "pollIntervalMinutes")
        return TimeInterval(mins > 0 ? mins * 60 : 300)
    }

    // MARK: - Menu bar display

    /// Current 5-hour utilization as an integer percentage — nil before first successful fetch.
    var fiveHourPercent: Int? {
        usage?.fiveHour.map { Int($0.utilization) }
    }

    /// Compact countdown to next 5-hour reset, e.g. "3:12" or "48m" — nil when no reset date.
    var fiveHourCountdown: String? {
        usage?.fiveHour?.compactTimeUntilReset
    }

    var menuBarColor: MenuBarColor {
        guard let pct = usage?.fiveHour?.utilization else { return .normal }
        if pct >= 80 { return .critical }
        if pct >= 60 { return .warning }
        return .normal
    }

    enum MenuBarColor: Sendable {
        case normal, warning, critical
    }

    // MARK: - Init

    init() {
        // Initialise poll interval from user preference (default 5 min)
        let mins = UserDefaults.standard.integer(forKey: "pollIntervalMinutes")
        pollInterval = TimeInterval(mins > 0 ? mins * 60 : 300)

        usageHistory = UsageHistory.load()
        loadCachedUsage()
        fetchUsage()
        loadLocalStats()

        // Check every 30s; fire a fetch when pollInterval has elapsed
        apiTimer = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    if let until = self.backoffUntil, Date.now < until { return }
                    if let last = self.lastAPIRefresh,
                       Date.now.timeIntervalSince(last) < self.pollInterval { return }
                    self.fetchUsage()
                }
            }

        // Poll local stats every 60s (parses JSONL files, skips if unchanged via dir mod-time)
        statsTimer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in self?.loadLocalStats() }
            }
    }

    // MARK: - API Usage

    func fetchUsage(force: Bool = false) {
        if !force, let until = backoffUntil, Date.now < until {
            return
        }

        guard let token = readOAuthToken() else {
            apiError = "Grant keychain access in the dialog, or re-authenticate Claude Code"
            logger.error("No OAuth token found in keychain")
            if force {
                refreshState = .failed
                Task {
                    try? await Task.sleep(for: .seconds(1.0))
                    self.refreshState = .idle
                }
            }
            return
        }

        if force { refreshState = .refreshing }

        Task {
            let startTime = ContinuousClock.now

            var resultState: RefreshState = .done
            do {
                guard let endpoint = URL(string: apiURL) else {
                    self.apiError = "Invalid API URL"
                    return
                }
                var request = URLRequest(url: endpoint)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

                let (data, response) = try await URLSession.shared.data(for: request)
                logger.info("API response: \(data.count) bytes")

                guard let http = response as? HTTPURLResponse else {
                    self.apiError = "Invalid response"
                    resultState = .failed
                    if force { await finishRefresh(resultState, startedAt: startTime) }
                    return
                }

                if http.statusCode == 429 {
                    let retryAfter = http.value(forHTTPHeaderField: "retry-after")
                        .flatMap { Double($0) } ?? 300
                    let wait = max(retryAfter, 60)
                    self.pollInterval = min(self.pollInterval * 2, 600)
                    self.backoffUntil = Date.now.addingTimeInterval(wait)
                    if self.usage == nil {
                        self.apiError = "Rate limited — retrying in \(Int(wait / 60))m"
                    }
                    resultState = .failed
                    if force { await finishRefresh(resultState, startedAt: startTime) }
                    return
                }

                if http.statusCode == 401 {
                    self.cachedToken = nil
                    self.cachedTokenExpiresAt = 0
                    KeychainStore.clearOwn()
                    self.apiError = "Token expired — re-auth Claude Code"
                    resultState = .failed
                    if force { await finishRefresh(resultState, startedAt: startTime) }
                    return
                }

                guard http.statusCode == 200 else {
                    logger.error("API error: HTTP \(http.statusCode), body: \(String(data: data, encoding: .utf8) ?? "nil")")
                    self.apiError = "HTTP \(http.statusCode)"
                    resultState = .failed
                    if force { await finishRefresh(resultState, startedAt: startTime) }
                    return
                }

                let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
                self.usage = decoded
                self.apiError = nil
                self.lastAPIRefresh = .now
                self.pollInterval = self.basePollInterval  // reset backoff to user preference
                self.backoffUntil = nil
                self.checkThresholdNotifications()
                try? data.write(to: self.cacheURL, options: .atomic)

                // Stream 2: persist snapshot + refresh in-memory history
                let snap = UsageSnapshot(
                    ts: Int64(Date.now.timeIntervalSince1970 * 1000),
                    buckets: {
                        var b: [String: Double] = [:]
                        if let v = decoded.fiveHour?.utilization         { b["fiveHour"] = v }
                        if let v = decoded.sevenDay?.utilization          { b["sevenDay"] = v }
                        if let v = decoded.sevenDayOpus?.utilization      { b["sevenDayOpus"] = v }
                        if let v = decoded.sevenDaySonnet?.utilization    { b["sevenDaySonnet"] = v }
                        if let v = decoded.sevenDayCowork?.utilization    { b["sevenDayCowork"] = v }
                        if let v = decoded.sevenDayOauthApps?.utilization { b["sevenDayOauthApps"] = v }
                        return b
                    }()
                )
                UsageHistory.append(snap)
                self.usageHistory = UsageHistory.load()

                if force { await finishRefresh(.done, startedAt: startTime) }
            } catch {
                logger.error("Fetch error: \(error)")
                self.apiError = error.localizedDescription
                if force { await finishRefresh(.failed, startedAt: startTime) }
            }
        }
    }

    /// Ensures the spinner shows for at least 0.6s, then flashes done/failed for 1s
    private func finishRefresh(_ state: RefreshState, startedAt: ContinuousClock.Instant) async {
        let elapsed = ContinuousClock.now - startedAt
        let minSpin = Duration.milliseconds(600)
        if elapsed < minSpin {
            try? await Task.sleep(for: minSpin - elapsed)
        }
        refreshState = state
        try? await Task.sleep(for: .seconds(1.0))
        refreshState = .idle
    }

    // MARK: - Cache

    private func loadCachedUsage() {
        guard let data = try? Data(contentsOf: cacheURL) else { return }
        guard let decoded = try? JSONDecoder().decode(UsageResponse.self, from: data) else {
            logger.debug("Cache decode failed — corrupt or schema mismatch at \(self.cacheURL.path)")
            return
        }
        self.usage = decoded
        if let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
           let modDate = attrs[.modificationDate] as? Date {
            self.lastAPIRefresh = modDate
        }
    }

    // MARK: - Keychain (3-tier read)
    //
    // Tier 1 — in-memory cache: fastest, lost on process exit.
    // Tier 2 — own keychain item (service com.stoneros.claude-usage): the app owns it,
    //           so reads never prompt. Survives reboots (AfterFirstUnlock). Populated on
    //           every successful foreign read; cleared on 401.
    // Tier 3 — foreign item (Claude Code-credentials): the one-time "Always Allow" lives here.
    //           Only reached when tiers 1 and 2 are empty or near-expired.
    //
    // Net effect: the "Always Allow" dialog appears at most once per OAuth token lifetime
    // rather than once per process start, making the grant durable.

    private func readOAuthToken() -> String? {
        let nowMs = Int64(Date.now.timeIntervalSince1970 * 1000)

        // Tier 1: in-memory
        if let token = cachedToken, cachedTokenExpiresAt - nowMs > 60_000 {
            logger.info("Token: in-memory cache hit (expires in \((self.cachedTokenExpiresAt - nowMs) / 1000)s)")
            return token
        }

        // Tier 2: own keychain item (no ACL prompt — we own it)
        if let own = KeychainStore.readOwn(), own.expiresAt - nowMs > 60_000 {
            logger.info("Token: own-keychain cache hit (expires in \((own.expiresAt - nowMs) / 1000)s)")
            cachedToken = own.token
            cachedTokenExpiresAt = own.expiresAt
            return own.token
        }

        // Tier 3: foreign "Claude Code-credentials" item — ACL prompt if grant missing/changed
        let query: [String: Any] = [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecAttrAccount as String: NSUserName(),
            kSecReturnData  as String: true,
            kSecMatchLimit  as String: kSecMatchLimitOne
        ]
        var raw: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &raw)
        logger.info("Foreign keychain read: status \(status) (0 = success)")

        guard status == errSecSuccess,
              let data = raw as? Data,
              let creds = try? JSONDecoder().decode(ClaudeCredentials.self, from: data)
        else {
            logger.error("Foreign keychain read failed: status=\(status), hasData=\(raw != nil)")
            return nil
        }

        let token = creds.claudeAiOauth.accessToken
        let expiresAt = creds.claudeAiOauth.expiresAt
        cachedToken = token
        cachedTokenExpiresAt = expiresAt
        KeychainStore.writeOwn(.init(token: token, expiresAt: expiresAt))
        return token
    }

    // MARK: - Burn rate (Stream 2)

    /// Projected cap-time for a utilization bucket, based on linear regression over points
    /// since the last reset (detected as a utilization drop > 30 pct-points).
    /// Returns nil when there are fewer than 2 in-window points or the slope is flat/falling.
    func burnRate(for bucket: String) -> BurnRate? {
        let pts = UsageHistory.series(for: bucket)
        guard pts.count >= 2 else { return nil }

        // Find the start of the current window — last big drop signals a reset
        var windowStart = 0
        for i in 1..<pts.count {
            if pts[i - 1].utilization - pts[i].utilization > 30 {
                windowStart = i
            }
        }
        let window = Array(pts[windowStart...])
        guard window.count >= 2 else { return nil }

        // Ordinary least-squares slope (pct per millisecond)
        let t0 = Double(window[0].ts)
        let xs = window.map { Double($0.ts) - t0 }
        let ys = window.map { $0.utilization }
        let n = Double(window.count)
        let sumX  = xs.reduce(0, +)
        let sumY  = ys.reduce(0, +)
        let sumXY = zip(xs, ys).map(*).reduce(0, +)
        let sumX2 = xs.map { $0 * $0 }.reduce(0, +)
        let denom = n * sumX2 - sumX * sumX
        guard abs(denom) > 1e-9 else { return nil }
        let slope = (n * sumXY - sumX * sumY) / denom

        guard slope > 1e-10 else { return nil }  // flat or falling — won't cap

        let lastU  = ys.last ?? 0
        let lastTs = xs.last ?? 0
        let msToCap = (100.0 - lastU) / slope
        guard msToCap > 0 else { return nil }

        let capAt = Date(timeIntervalSince1970: (t0 + lastTs + msToCap) / 1000)
        return BurnRate(projectedCapAt: capAt)
    }

    /// Ordered (oldest → newest) utilization values for a bucket, sourced from the
    /// in-memory history (avoids re-reading the file on every view render).
    func utilizationSeries(for bucket: String) -> [Double] {
        usageHistory.compactMap { $0.buckets[bucket] }
    }

    // MARK: - Notifications

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { logger.error("Notification permission error: \(error)") }
            logger.info("Notification permission granted: \(granted)")
        }
    }

    /// Fire threshold alerts if the 5-hour window crosses the configured thresholds and we
    /// haven't already notified for this specific window (keyed by resetsAt timestamp).
    private func checkThresholdNotifications() {
        guard UserDefaults.standard.bool(forKey: "notificationsEnabled"),
              let five = usage?.fiveHour else { return }
        let windowKey = five.resetsAt ?? "static"
        let pct = five.utilization
        for threshold in [alertThreshold1, alertThreshold2] where pct >= threshold {
            let key = "\(Int(threshold))_\(windowKey)"
            guard !notifiedThresholds.contains(key) else { continue }
            notifiedThresholds.insert(key)
            sendUsageNotification(threshold: Int(threshold), pct: pct, resetStr: five.timeUntilReset)
        }
    }

    private func sendUsageNotification(threshold: Int, pct: Double, resetStr: String) {
        let content = UNMutableNotificationContent()
        content.title = "Claude Usage \(threshold)%"
        content.body = "\(Int(pct))% of your 5-hour window used. \(resetStr)."
        content.sound = .default
        let id = "claudeusage_\(threshold)_\(Int(Date.now.timeIntervalSince1970))"
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { error in
            if let error { logger.error("Notification send error: \(error)") }
        }
    }

    // MARK: - Local Stats

    func loadLocalStats() {
        Task {
            guard let decoded = await statsComputer.computeIfNeeded() else { return }
            await MainActor.run {
                applyStats(decoded)
            }
        }
    }

    func forceReloadStats() {
        Task {
            guard let decoded = await statsComputer.forceCompute() else { return }
            await MainActor.run {
                applyStats(decoded)
            }
        }
    }

    private func applyStats(_ decoded: StatsCache) {
        let today = Date()
        let todayStr = Self.dateString(from: today)
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: today) ?? today
        let mondayStr = Self.dateString(from: monday)

        self.stats = decoded
        self.todayActivity = decoded.dailyActivity.first { $0.date == todayStr }
        self.currentWeek = buildWeekSummary(from: decoded, weekStart: mondayStr, weekEnd: todayStr)
        let (hours, hoursMap) = computeUsageHours(todayStr: todayStr, mondayStr: mondayStr)
        self.usageHours = hours
        self.dailyHoursMap = hoursMap
        let historyFirstDate = hoursMap.keys.min()
        self.costAnalysis = computeCost(from: decoded, historyFirstDate: historyFirstDate)
    }

    private func buildWeekSummary(from stats: StatsCache, weekStart: String, weekEnd: String) -> WeeklySummary {
        let days = stats.dailyActivity.filter { $0.date >= weekStart && $0.date <= weekEnd }
        var tokensByDay: [String: Int] = [:]
        var totalTokens = 0
        for dt in stats.dailyModelTokens where dt.date >= weekStart && dt.date <= weekEnd {
            tokensByDay[dt.date] = dt.totalTokens
            totalTokens += dt.totalTokens
        }
        return WeeklySummary(
            weekStart: weekStart,
            days: days.sorted { $0.date < $1.date },
            tokensByDay: tokensByDay,
            totalMessages: days.map(\.messageCount).reduce(0, +),
            totalSessions: days.map(\.sessionCount).reduce(0, +),
            totalToolCalls: days.map(\.toolCallCount).reduce(0, +),
            totalTokens: totalTokens
        )
    }

    private func computeCost(from stats: StatsCache, historyFirstDate: String? = nil) -> CostAnalysis {
        struct ModelPrice {
            let input: Double; let output: Double
            let cacheRead: Double; let cacheCreate: Double
        }
        let familyPrices: [String: ModelPrice] = [
            "Opus":   ModelPrice(input: 15,  output: 75,  cacheRead: 1.5,  cacheCreate: 18.75),
            "Sonnet": ModelPrice(input: 3,   output: 15,  cacheRead: 0.3,  cacheCreate: 3.75),
            "Haiku":  ModelPrice(input: 0.8, output: 4,   cacheRead: 0.08, cacheCreate: 1.0),
        ]

        var totalCost = 0.0
        var costByFamily: [String: Double] = [:]

        for (model, usage) in stats.modelUsage {
            let family = Self.shortModel(model)
            guard familyPrices[family] != nil else { continue }
            let p = familyPrices[family]!
            let cost = Double(usage.inputTokens) / 1e6 * p.input
                + Double(usage.outputTokens) / 1e6 * p.output
                + Double(usage.cacheReadInputTokens) / 1e6 * p.cacheRead
                + Double(usage.cacheCreationInputTokens) / 1e6 * p.cacheCreate
            totalCost += cost
            costByFamily[family, default: 0] += cost
        }
        let modelCosts = costByFamily
            .map { (model: $0.key, cost: $0.value) }
            .sorted { $0.cost > $1.cost }

        let activeDays = max(stats.dailyActivity.count, 1)
        let spanDays: Int = {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.timeZone = .current
            let today = df.string(from: Date())
            let candidates = [stats.firstSessionDate, historyFirstDate]
                .compactMap { $0 }.filter { !$0.isEmpty }
            guard let earliestStr = candidates.min(),
                  let first = df.date(from: earliestStr),
                  let last = df.date(from: today) else { return activeDays }
            let span = Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0
            return max(span + 1, activeDays)
        }()
        let daily = totalCost / Double(spanDays)
        let monthly = daily * 30
        let planCost = 100.0

        return CostAnalysis(
            totalAPICost: totalCost,
            dailyAvgCost: daily,
            monthlyProjection: monthly,
            modelCosts: modelCosts,
            daysTracked: spanDays,
            planCost: planCost,
            roi: monthly / planCost
        )
    }

    private func computeUsageHours(todayStr: String, mondayStr: String) -> (UsageHours?, [String: Double]) {
        let historyPath = FileManager.default.homeDirectoryForCurrentUser.path + "/.claude/history.jsonl"
        guard let content = try? String(contentsOfFile: historyPath, encoding: .utf8) else { return (nil, [:]) }

        struct HistoryEntry: Codable {
            let timestamp: Int64
            let sessionId: String?
        }

        var sessions: [String: [Int64]] = [:]
        for line in content.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let entry = try? JSONDecoder().decode(HistoryEntry.self, from: data),
                  let sid = entry.sessionId
            else { continue }
            sessions[sid, default: []].append(entry.timestamp)
        }

        let maxGap: Int64 = 600_000
        var dailyMs: [String: Int64] = [:]

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = .current

        for (_, timestamps) in sessions {
            let sorted = timestamps.sorted()
            guard sorted.count >= 2 else { continue }
            let startDate = dateFormatter.string(from: Date(timeIntervalSince1970: Double(sorted[0]) / 1000))
            var activeMs: Int64 = 0
            for i in 1..<sorted.count {
                let gap = sorted[i] - sorted[i - 1]
                if gap <= maxGap { activeMs += gap }
            }
            dailyMs[startDate, default: 0] += activeMs
        }

        let totalMs = dailyMs.values.reduce(Int64(0), +)
        let totalHours = Double(totalMs) / 3_600_000
        let daysActive = dailyMs.count
        let weekMs = dailyMs.filter { $0.key >= mondayStr }.values.reduce(Int64(0), +)
        let todayMs = dailyMs[todayStr] ?? 0
        let hoursMap = dailyMs.mapValues { Double($0) / 3_600_000 }

        return (UsageHours(
            totalHours: totalHours,
            thisWeekHours: Double(weekMs) / 3_600_000,
            todayHours: Double(todayMs) / 3_600_000,
            avgDailyHours: daysActive > 0 ? totalHours / Double(daysActive) : 0,
            daysActive: daysActive
        ), hoursMap)
    }

    // MARK: - Export

    func exportData() {
        guard exportState == .idle else { return }
        exportState = .exporting

        let payload = buildExportPayload()

        Task.detached(priority: .utility) { [weak self] in
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(payload)

                let dateStr = UsageViewModel.dateString(from: .now)
                let url = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Desktop")
                    .appendingPathComponent("claude-usage-export-\(dateStr).json")
                try data.write(to: url, options: .atomic)

                await MainActor.run {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    self?.exportState = .success
                }
            } catch {
                await MainActor.run { self?.exportState = .failed }
            }

            try? await Task.sleep(for: .seconds(2.0))
            await MainActor.run { self?.exportState = .idle }
        }
    }

    private func buildExportPayload() -> ExportPayload {
        ExportPayload(
            exportedAt: ISO8601DateFormatter().string(from: .now),
            apiUsage: usage.map { u in
                ExportAPIUsage(
                    fiveHour: u.fiveHour.map { ExportAPIBucket(utilization: $0.utilization, resetsAt: $0.resetsAt ?? "") },
                    sevenDay: u.sevenDay.map { ExportAPIBucket(utilization: $0.utilization, resetsAt: $0.resetsAt ?? "") },
                    sevenDayOpus: u.sevenDayOpus.map { ExportAPIBucket(utilization: $0.utilization, resetsAt: $0.resetsAt ?? "") },
                    sevenDaySonnet: u.sevenDaySonnet.map { ExportAPIBucket(utilization: $0.utilization, resetsAt: $0.resetsAt ?? "") },
                    sevenDayCowork: u.sevenDayCowork.map { ExportAPIBucket(utilization: $0.utilization, resetsAt: $0.resetsAt ?? "") }
                )
            },
            totalSessions: stats?.totalSessions,
            totalMessages: stats?.totalMessages,
            firstSessionDate: stats?.firstSessionDate,
            dailyActivity: stats?.dailyActivity.map {
                ExportDailyActivity(date: $0.date, messages: $0.messageCount, sessions: $0.sessionCount, toolCalls: $0.toolCallCount)
            },
            modelUsage: stats?.modelUsage.mapValues {
                ExportModelUsage(input: $0.inputTokens, output: $0.outputTokens,
                                 cacheRead: $0.cacheReadInputTokens, cacheCreate: $0.cacheCreationInputTokens)
            },
            hourCounts: stats?.hourCounts,
            cost: costAnalysis.map { c in
                ExportCost(
                    totalAPICost: c.totalAPICost,
                    dailyAvgCost: c.dailyAvgCost,
                    monthlyProjection: c.monthlyProjection,
                    roi: c.roi,
                    daysTracked: c.daysTracked,
                    byModel: Dictionary(c.modelCosts.map { ($0.model, $0.cost) },
                                        uniquingKeysWith: { a, _ in a })
                )
            },
            dailyHours: dailyHoursMap.isEmpty ? nil : dailyHoursMap.mapValues { round($0 * 100) / 100 },
            usageHoursSummary: usageHours.map {
                ExportUsageHours(
                    totalHours: round($0.totalHours * 10) / 10,
                    thisWeekHours: round($0.thisWeekHours * 10) / 10,
                    todayHours: round($0.todayHours * 10) / 10,
                    avgDailyHours: round($0.avgDailyHours * 10) / 10,
                    daysActive: $0.daysActive
                )
            }
        )
    }

    // MARK: - Helpers

    nonisolated static func dateString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    nonisolated static func shortModel(_ name: String) -> String {
        if name.contains("opus") { return "Opus" }
        if name.contains("sonnet") { return "Sonnet" }
        if name.contains("haiku") { return "Haiku" }
        return name
    }
}

// MARK: - Burn Rate

struct BurnRate {
    let projectedCapAt: Date

    /// Human-readable caption for display in the 5-hour meter subtitle.
    func caption(resetDate: Date?) -> String {
        let now = Date.now
        guard projectedCapAt > now else { return "at capacity" }

        let interval = projectedCapAt.timeIntervalSince(now)
        let hours = Int(interval) / 3600
        let mins  = (Int(interval) % 3600) / 60
        let timeStr = hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"

        if let reset = resetDate, projectedCapAt < reset {
            return "caps ~\(timeStr) from now"
        }
        return "won't cap this window"
    }
}
