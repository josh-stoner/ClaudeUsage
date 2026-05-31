import Foundation
import AppKit
import Combine
import Security
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

    @Published var selectedTab: Tab = .limits

    enum Tab: String, CaseIterable, Sendable {
        case limits = "Plan"
        case week = "Week"
        case cost = "Cost"
        case patterns = "When"
    }

    private var apiTimer: AnyCancellable?
    private var statsTimer: AnyCancellable?
    private let statsComputer = StatsComputer()

    // Token cache — avoid repeated keychain reads across polls
    private var cachedToken: String?
    private var cachedTokenExpiresAt: Int64 = 0

    private let apiURL = "https://api.anthropic.com/api/oauth/usage"
    private var pollInterval: TimeInterval = 300 // poll every 5 min
    private var backoffUntil: Date?

    private var cacheURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        return dir.appendingPathComponent("usage-cache.json")
    }

    // MARK: - Menu bar display

    var menuBarTitle: String {
        if let u = usage?.fiveHour {
            return "\(Int(u.utilization))%"
        }
        return "—"
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
        loadCachedUsage()
        fetchUsage()
        loadLocalStats()

        // Poll API every 2 min (backs off on 429)
        apiTimer = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    // Check backoff
                    if let until = self.backoffUntil, Date.now < until { return }
                    // Check poll interval
                    if let last = self.lastAPIRefresh,
                       Date.now.timeIntervalSince(last) < self.pollInterval { return }
                    self.fetchUsage()
                }
            }

        // Poll local stats every 60s (parses JSONL files, uses dir mod time to skip if unchanged)
        statsTimer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in self?.loadLocalStats() }
            }
    }

    // MARK: - API Usage

    func fetchUsage(force: Bool = false) {
        // Respect backoff unless forced (manual refresh)
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
                    let wait = max(retryAfter, 60) // at least 1 min
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
                    self.cachedToken = nil  // force keychain re-read next poll
                    self.cachedTokenExpiresAt = 0
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
                self.pollInterval = 300
                self.backoffUntil = nil
                try? data.write(to: self.cacheURL, options: .atomic)
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
        guard let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder().decode(UsageResponse.self, from: data)
        else { return }
        self.usage = decoded
        // Show cached timestamp from file modification date
        if let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
           let modDate = attrs[.modificationDate] as? Date {
            self.lastAPIRefresh = modDate
        }
    }

    // MARK: - Keychain

    private func readOAuthToken() -> String? {
        // Return cached token if it won't expire for at least 60 s.
        // This cuts cross-app keychain reads from every 5 min to ~once per
        // token lifetime, so "Always Allow" isn't re-evaluated as often.
        let nowMs = Int64(Date.now.timeIntervalSince1970 * 1000)
        if let token = cachedToken, cachedTokenExpiresAt - nowMs > 60_000 {
            logger.info("Keychain read skipped — using cached token (expires in \((self.cachedTokenExpiresAt - nowMs) / 1000)s)")
            return token
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecAttrAccount as String: NSUserName(),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        logger.info("Keychain read status: \(status) (0 = success)")

        guard status == errSecSuccess,
              let data = result as? Data,
              let creds = try? JSONDecoder().decode(ClaudeCredentials.self, from: data)
        else {
            logger.error("Keychain read failed: status=\(status), hasData=\(result != nil)")
            return nil
        }

        // Update in-memory cache
        cachedToken = creds.claudeAiOauth.accessToken
        cachedTokenExpiresAt = creds.claudeAiOauth.expiresAt
        return creds.claudeAiOauth.accessToken
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
        // Compute hours first — history.jsonl often has an earlier start date than project JSONLs
        let (hours, hoursMap) = computeUsageHours(todayStr: todayStr, mondayStr: mondayStr)
        self.usageHours = hours
        self.dailyHoursMap = hoursMap
        // Use earliest date across both sources for an accurate calendar span
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
        // API pricing per million tokens, keyed by display family so any
        // future model version (e.g. claude-opus-4-8, claude-opus-4-9…)
        // is automatically priced correctly via shortModel() family matching.
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
        // Aggregate by display family — deduplicates multi-version histories
        // and excludes third-party/image models (recraft, flux, dalle-3, etc.)
        var costByFamily: [String: Double] = [:]

        for (model, usage) in stats.modelUsage {
            let family = Self.shortModel(model)
            // Skip non-Claude models — only the three known families have pricing
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

        // Use calendar span (earliest known session → today) for daily avg and
        // monthly projection. history.jsonl often predates project JSONLs, so
        // use whichever source gives the earlier start date.
        let activeDays = max(stats.dailyActivity.count, 1)
        let spanDays: Int = {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.timeZone = .current
            let today = df.string(from: Date())
            // Pick the earliest date across stats and history sources
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
        let planCost = 100.0 // Max 5x

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

        // Parse sessions from history.jsonl
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

        // Calculate active time: sum gaps between messages that are < 10 min apart
        let maxGap: Int64 = 600_000 // 10 min in ms
        var dailyMs: [String: Int64] = [:]

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = .current  // match StatsComputer — ensure buckets align

        for (_, timestamps) in sessions {
            let sorted = timestamps.sorted()
            guard sorted.count >= 2 else { continue }

            let startDate = dateFormatter.string(from: Date(timeIntervalSince1970: Double(sorted[0]) / 1000))

            var activeMs: Int64 = 0
            for i in 1..<sorted.count {
                let gap = sorted[i] - sorted[i - 1]
                if gap <= maxGap {
                    activeMs += gap
                }
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

        // Build the Encodable payload on the main actor, then encode+write off-thread.
        // Using Codable instead of [String: Any] + JSONSerialization eliminates the
        // Obj-C NSInvalidArgumentException that try? cannot catch.
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
                    // modelCosts is already deduplicated by family in computeCost()
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
