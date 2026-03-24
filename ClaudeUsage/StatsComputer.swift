import Foundation

/// Parses Claude Code JSONL session files directly to compute usage stats.
/// Replaces the external stats-cache.json dependency.
actor StatsComputer {
    private var lastDirectoryMod: Date?
    private var cachedResult: StatsCache?

    private var projectDirs: [URL] {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: base, includingPropertiesForKeys: nil
        ) else { return [] }
        return contents.filter { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
    }

    /// Returns cached stats if the JSONL directory hasn't changed, otherwise recomputes.
    func computeIfNeeded() -> StatsCache? {
        let dirs = projectDirs
        let latestMod = dirs.compactMap { dir -> Date? in
            (try? FileManager.default.attributesOfItem(atPath: dir.path))?[.modificationDate] as? Date
        }.max()

        if let cached = cachedResult, let lastMod = lastDirectoryMod, latestMod == lastMod {
            return cached
        }

        let result = compute(dirs: dirs)
        cachedResult = result
        lastDirectoryMod = latestMod
        return result
    }

    /// Force a full recomputation.
    func forceCompute() -> StatsCache? {
        let result = compute(dirs: projectDirs)
        cachedResult = result
        lastDirectoryMod = Date()
        return result
    }

    private func compute(dirs: [URL]) -> StatsCache {
        var daily: [String: DailyBucket] = [:]
        var modelTokens: [String: TokenBucket] = [:]
        var dailyModelTokens: [String: [String: Int]] = [:]
        var hourCounts: [String: Int] = [:]
        var allSessions: Set<String> = []
        var firstDate: String?
        var totalMsgs = 0

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        // Use local timezone so daily buckets align with user's day
        dateFormatter.timeZone = .current

        for dir in dirs {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            ) else { continue }

            for file in files where file.pathExtension == "jsonl" {
                let sessionId = file.deletingPathExtension().lastPathComponent

                guard let data = try? Data(contentsOf: file),
                      let content = String(data: data, encoding: .utf8)
                else { continue }

                for line in content.split(separator: "\n") {
                    guard let lineData = line.data(using: .utf8),
                          let entry = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
                    else { continue }

                    // Get timestamp
                    guard let ts = entry["timestamp"] as? String,
                          let date = isoFormatter.date(from: ts)
                    else { continue }

                    let dateStr = dateFormatter.string(from: date)
                    // Use local timezone for hour-of-day heatmap
                    let hour = Calendar.current.component(.hour, from: date)

                    if firstDate == nil || dateStr < firstDate! {
                        firstDate = dateStr
                    }

                    let entryType = entry["type"] as? String ?? ""
                    let msg = entry["message"] as? [String: Any] ?? [:]
                    let role = msg["role"] as? String ?? ""

                    // Count messages
                    if entryType == "user" || entryType == "assistant" ||
                       role == "user" || role == "assistant" {
                        if daily[dateStr] == nil {
                            daily[dateStr] = DailyBucket()
                        }
                        daily[dateStr]!.messages += 1
                        daily[dateStr]!.sessions.insert(sessionId)
                        allSessions.insert(sessionId)
                        totalMsgs += 1
                        hourCounts[String(hour), default: 0] += 1
                    }

                    // Count tool calls
                    if let content = msg["content"] as? [[String: Any]] {
                        for item in content {
                            if item["type"] as? String == "tool_use" {
                                if daily[dateStr] == nil {
                                    daily[dateStr] = DailyBucket()
                                }
                                daily[dateStr]!.toolCalls += 1
                            }
                        }
                    }

                    // Count tokens
                    if let model = msg["model"] as? String, !model.isEmpty,
                       let usage = msg["usage"] as? [String: Any] {
                        let inp = usage["input_tokens"] as? Int ?? 0
                        let out = usage["output_tokens"] as? Int ?? 0
                        let cr = usage["cache_read_input_tokens"] as? Int ?? 0
                        let cc = usage["cache_creation_input_tokens"] as? Int ?? 0

                        if modelTokens[model] == nil {
                            modelTokens[model] = TokenBucket()
                        }
                        modelTokens[model]!.input += inp
                        modelTokens[model]!.output += out
                        modelTokens[model]!.cacheRead += cr
                        modelTokens[model]!.cacheCreate += cc

                        dailyModelTokens[dateStr, default: [:]][model, default: 0] += inp + out + cr + cc
                    }
                }
            }
        }

        // Build arrays
        let dailyActivity = daily.keys.sorted().map { date -> DailyActivity in
            let b = daily[date]!
            return DailyActivity(
                date: date,
                messageCount: b.messages,
                sessionCount: b.sessions.count,
                toolCallCount: b.toolCalls
            )
        }

        let dmt = dailyModelTokens.keys.sorted().map { date -> DailyModelTokens in
            DailyModelTokens(date: date, tokensByModel: dailyModelTokens[date]!)
        }

        let modelUsage = modelTokens.mapValues { b in
            ModelUsage(
                inputTokens: b.input,
                outputTokens: b.output,
                cacheReadInputTokens: b.cacheRead,
                cacheCreationInputTokens: b.cacheCreate
            )
        }

        return StatsCache(
            version: 3,
            lastComputedDate: dateFormatter.string(from: Date()),
            dailyActivity: dailyActivity,
            dailyModelTokens: dmt,
            modelUsage: modelUsage,
            totalSessions: allSessions.count,
            totalMessages: totalMsgs,
            firstSessionDate: firstDate ?? "",
            hourCounts: hourCounts
        )
    }
}

// Internal accumulator types
private struct DailyBucket {
    var messages = 0
    var sessions: Set<String> = []
    var toolCalls = 0
}

private struct TokenBucket {
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheCreate = 0
}
