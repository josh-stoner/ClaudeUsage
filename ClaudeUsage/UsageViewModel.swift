import Foundation
import Combine
import Security

@MainActor
final class UsageViewModel: ObservableObject {
    // API usage (real-time plan limits)
    @Published var usage: UsageResponse?
    @Published var apiError: String?
    @Published var lastAPIRefresh: Date?

    // Local stats
    @Published var stats: StatsCache?
    @Published var todayActivity: DailyActivity?
    @Published var currentWeek: WeeklySummary?
    @Published var usageHours: UsageHours?
    @Published var costAnalysis: CostAnalysis?

    @Published var selectedTab: Tab = .limits

    enum Tab: String, CaseIterable, Sendable {
        case limits = "Plan"
        case week = "Week"
        case cost = "Cost"
        case patterns = "When"
    }

    private var apiTimer: AnyCancellable?
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var statsTimer: AnyCancellable?

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
        startFileMonitor()

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

        // Poll local stats every 30s
        statsTimer = Timer.publish(every: 30, on: .main, in: .common)
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
            apiError = "No OAuth token found"
            return
        }

        Task {
            do {
                var request = URLRequest(url: URL(string: apiURL)!)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let http = response as? HTTPURLResponse else {
                    self.apiError = "Invalid response"
                    return
                }

                if http.statusCode == 429 {
                    let retryAfter = http.value(forHTTPHeaderField: "retry-after")
                        .flatMap { Double($0) } ?? 300
                    let wait = max(retryAfter, 60) // at least 1 min
                    self.pollInterval = min(self.pollInterval * 2, 600)
                    self.backoffUntil = Date.now.addingTimeInterval(wait)
                    // Never wipe last good data on 429
                    if self.usage == nil {
                        self.apiError = "Rate limited — retrying in \(Int(wait / 60))m"
                    }
                    return
                }

                if http.statusCode == 401 {
                    self.apiError = "Token expired — re-auth Claude Code"
                    return
                }

                guard http.statusCode == 200 else {
                    self.apiError = "HTTP \(http.statusCode)"
                    return
                }

                let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
                self.usage = decoded
                self.apiError = nil
                self.lastAPIRefresh = .now
                self.pollInterval = 300
                self.backoffUntil = nil
                // Cache to disk
                try? data.write(to: self.cacheURL, options: .atomic)
            } catch {
                self.apiError = error.localizedDescription
            }
        }
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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecAttrAccount as String: NSUserName(),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let creds = try? JSONDecoder().decode(ClaudeCredentials.self, from: data)
        else { return nil }

        return creds.claudeAiOauth.accessToken
    }

    // MARK: - Local Stats

    private var statsPath: String {
        FileManager.default.homeDirectoryForCurrentUser.path + "/.claude/stats-cache.json"
    }

    func loadLocalStats() {
        guard let data = FileManager.default.contents(atPath: statsPath),
              let decoded = try? JSONDecoder().decode(StatsCache.self, from: data)
        else { return }

        let today = Date()
        let todayStr = Self.dateString(from: today)
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: today)!
        let mondayStr = Self.dateString(from: monday)

        self.stats = decoded
        self.todayActivity = decoded.dailyActivity.first { $0.date == todayStr }
        self.currentWeek = buildWeekSummary(from: decoded, weekStart: mondayStr, weekEnd: todayStr)
        self.usageHours = computeUsageHours(todayStr: todayStr, mondayStr: mondayStr)
        self.costAnalysis = computeCost(from: decoded)
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

    private func computeCost(from stats: StatsCache) -> CostAnalysis {
        // API pricing per million tokens
        struct ModelPrice {
            let input: Double; let output: Double
            let cacheRead: Double; let cacheCreate: Double
        }
        let prices: [String: ModelPrice] = [
            "claude-opus-4-6": ModelPrice(input: 15, output: 75, cacheRead: 1.5, cacheCreate: 18.75),
            "claude-sonnet-4-6": ModelPrice(input: 3, output: 15, cacheRead: 0.3, cacheCreate: 3.75),
            "claude-haiku-4-5-20251001": ModelPrice(input: 0.8, output: 4, cacheRead: 0.08, cacheCreate: 1.0),
        ]
        let fallback = ModelPrice(input: 3, output: 15, cacheRead: 0.3, cacheCreate: 3.75)

        var totalCost = 0.0
        var modelCosts: [(String, Double)] = []

        for (model, usage) in stats.modelUsage {
            let p = prices[model] ?? fallback
            let cost = Double(usage.inputTokens) / 1e6 * p.input
                + Double(usage.outputTokens) / 1e6 * p.output
                + Double(usage.cacheReadInputTokens) / 1e6 * p.cacheRead
                + Double(usage.cacheCreationInputTokens) / 1e6 * p.cacheCreate
            totalCost += cost
            modelCosts.append((Self.shortModel(model), cost))
        }
        modelCosts.sort { $0.1 > $1.1 }

        let days = max(stats.dailyActivity.count, 1)
        let daily = totalCost / Double(days)
        let monthly = daily * 30
        let planCost = 100.0 // Max 5x

        return CostAnalysis(
            totalAPICost: totalCost,
            dailyAvgCost: daily,
            monthlyProjection: monthly,
            modelCosts: modelCosts,
            daysTracked: days,
            planCost: planCost,
            roi: monthly / planCost
        )
    }

    private func computeUsageHours(todayStr: String, mondayStr: String) -> UsageHours? {
        let historyPath = FileManager.default.homeDirectoryForCurrentUser.path + "/.claude/history.jsonl"
        guard let content = try? String(contentsOfFile: historyPath, encoding: .utf8) else { return nil }

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

        return UsageHours(
            totalHours: totalHours,
            thisWeekHours: Double(weekMs) / 3_600_000,
            todayHours: Double(todayMs) / 3_600_000,
            avgDailyHours: daysActive > 0 ? totalHours / Double(daysActive) : 0,
            daysActive: daysActive
        )
    }

    private func startFileMonitor() {
        let path = statsPath
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename], queue: .global()
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.loadLocalStats() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileMonitor = source
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

    deinit {
        fileMonitor?.cancel()
    }
}
