import Foundation

// MARK: - API Usage Response

struct UsageResponse: Codable {
    let fiveHour: UsageBucket?
    let sevenDay: UsageBucket?
    let sevenDayOauthApps: UsageBucket?
    let sevenDayOpus: UsageBucket?
    let sevenDaySonnet: UsageBucket?
    let sevenDayCowork: UsageBucket?
    let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOauthApps = "seven_day_oauth_apps"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayCowork = "seven_day_cowork"
        case extraUsage = "extra_usage"
    }
}

struct UsageBucket: Codable {
    let utilization: Double
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    var resetDate: Date? {
        guard let s = resetsAt else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    var timeUntilReset: String {
        guard let date = resetDate else { return "" }
        let interval = date.timeIntervalSince(.now)
        guard interval > 0 else { return "resetting..." }
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        }
        return "Resets in \(minutes)m"
    }

    var resetTimeFormatted: String {
        guard let date = resetDate else { return "" }
        let f = DateFormatter()
        f.dateFormat = "EEE h:mm a"
        return "Resets \(f.string(from: date))"
    }
}

struct ExtraUsage: Codable {
    let isEnabled: Bool
    let monthlyLimit: Double?
    let usedCredits: Double?
    let utilization: Double?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization
    }
}

// MARK: - Keychain Credentials

struct ClaudeCredentials: Codable {
    let claudeAiOauth: OAuthData
    let organizationUuid: String

    struct OAuthData: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Int64
        let subscriptionType: String?
        let rateLimitTier: String?
    }
}

// MARK: - Local Stats Cache

struct StatsCache: Codable {
    let version: Int
    let lastComputedDate: String
    let dailyActivity: [DailyActivity]
    let dailyModelTokens: [DailyModelTokens]
    let modelUsage: [String: ModelUsage]
    let totalSessions: Int
    let totalMessages: Int
    let firstSessionDate: String
    let hourCounts: [String: Int]?
}

struct DailyActivity: Codable, Identifiable {
    let date: String
    let messageCount: Int
    let sessionCount: Int
    let toolCallCount: Int

    var id: String { date }

    var weekday: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let d = formatter.date(from: date) else { return "" }
        let display = DateFormatter()
        display.dateFormat = "EEE"
        return display.string(from: d)
    }
}

struct DailyModelTokens: Codable {
    let date: String
    let tokensByModel: [String: Int]

    var totalTokens: Int {
        tokensByModel.values.reduce(0, +)
    }
}

struct ModelUsage: Codable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadInputTokens: Int
    let cacheCreationInputTokens: Int
}

struct CostAnalysis {
    let totalAPICost: Double
    let dailyAvgCost: Double
    let monthlyProjection: Double
    let modelCosts: [(model: String, cost: Double)]
    let daysTracked: Int
    let planCost: Double  // Max 5x = 200
    let roi: Double
}

struct UsageHours {
    let totalHours: Double
    let thisWeekHours: Double
    let todayHours: Double
    let avgDailyHours: Double
    let daysActive: Int
}

struct WeeklySummary {
    let weekStart: String
    let days: [DailyActivity]
    let tokensByDay: [String: Int]
    let totalMessages: Int
    let totalSessions: Int
    let totalToolCalls: Int
    let totalTokens: Int

    var maxDailyMessages: Int {
        days.map(\.messageCount).max() ?? 1
    }
}
