import Foundation
import Security
import os.log

private let logger = Logger(subsystem: "com.stoneros.claude-usage", category: "keychain")

/// Manages the app's own keychain item so cold starts don't re-read the foreign
/// "Claude Code-credentials" item and re-evaluate its ACL.
///
/// Flow: in-memory cache → own item (no prompt) → foreign item (one-time "Always Allow").
/// The app owns this item, so reads never trigger a password prompt.
enum KeychainStore {
    private static let ownService  = "com.stoneros.claude-usage"
    private static let ownAccount  = "oauth-token-cache"

    struct Cached: Codable {
        let token: String
        let expiresAt: Int64
    }

    // MARK: - Read

    static func readOwn() -> Cached? {
        let query: [String: Any] = [
            kSecClass        as String: kSecClassGenericPassword,
            kSecAttrService  as String: ownService,
            kSecAttrAccount  as String: ownAccount,
            kSecReturnData   as String: true,
            kSecMatchLimit   as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess,
              let data = out as? Data,
              let cached = try? JSONDecoder().decode(Cached.self, from: data) else {
            logger.debug("Own keychain read: no item (status \(status))")
            return nil
        }
        logger.debug("Own keychain read: hit, expires in \((cached.expiresAt - Int64(Date.now.timeIntervalSince1970 * 1000)) / 1000)s")
        return cached
    }

    // MARK: - Write (upsert — delete then add so the app always owns the item)

    static func writeOwn(_ cached: Cached) {
        guard let data = try? JSONEncoder().encode(cached) else { return }
        let base: [String: Any] = [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrService as String: ownService,
            kSecAttrAccount as String: ownAccount
        ]
        // Remove any existing entry first (preserves clean ownership + ACL)
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData    as String] = data
        // AfterFirstUnlock: item survives reboot and is available once the user logs in —
        // exactly what a LaunchAgent that starts at login needs.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        logger.debug("Own keychain write: status \(status) (0 = success)")
    }

    // MARK: - Clear (on 401 — force fresh foreign read next poll)

    static func clearOwn() {
        let query: [String: Any] = [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrService as String: ownService,
            kSecAttrAccount as String: ownAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        logger.debug("Own keychain clear: status \(status)")
    }
}
