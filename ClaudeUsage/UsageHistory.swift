import Foundation

// MARK: — Lightweight utilization time-series

/// One polling snapshot — bucket name → utilization (0–100).
struct UsageSnapshot: Codable {
    let ts: Int64                  // Unix milliseconds
    let buckets: [String: Double]  // e.g. "fiveHour" → 73.0
}

/// Persistent ring-buffer of utilization snapshots stored in ~/.claude/usage-history.json.
/// All methods are synchronous and safe to call from any context; file I/O is brief (~100 KB max).
enum UsageHistory {

    private static let maxPoints = 2016  // ~7 days at 5-min cadence

    static var historyURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("usage-history.json")
    }

    // MARK: Write

    /// Append one snapshot and trim to the most recent `maxPoints` entries.
    static func append(_ snapshot: UsageSnapshot) {
        var all = load()
        all.append(snapshot)
        if all.count > maxPoints {
            all = Array(all.suffix(maxPoints))
        }
        save(all)
    }

    // MARK: Read

    /// Return ordered (oldest → newest) (ts, utilization) points for a specific bucket key.
    static func series(for bucket: String) -> [(ts: Int64, utilization: Double)] {
        load().compactMap { snap in
            guard let u = snap.buckets[bucket] else { return nil }
            return (snap.ts, u)
        }
    }

    /// Load all snapshots from disk — returns [] on any read/decode error.
    static func load() -> [UsageSnapshot] {
        guard let data = try? Data(contentsOf: historyURL),
              let decoded = try? JSONDecoder().decode([UsageSnapshot].self, from: data)
        else { return [] }
        return decoded
    }

    // MARK: Private

    private static func save(_ snapshots: [UsageSnapshot]) {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        try? data.write(to: historyURL, options: .atomic)
    }
}
