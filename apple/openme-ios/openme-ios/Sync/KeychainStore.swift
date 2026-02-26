import Foundation
import LocalAuthentication
import Security

/// Low-level Keychain read/write helpers used by both ``SecureEnclaveKeyGen``
/// and ``KeychainSync``.
enum KeychainStore {

    private static let service = "org.merlos.openme"

    // MARK: - Private key storage

    static func storePrivateKey(
        _ keyData: Data,
        account: String,
        syncToiCloud: Bool
    ) throws {
        // Delete any existing item first.
        try? deletePrivateKey(account: account)

        var query: [CFString: Any] = [
            kSecClass:           kSecClassGenericPassword,
            kSecAttrService:     service,
            kSecAttrAccount:     account,
            kSecValueData:       keyData,
            kSecAttrAccessible:  kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable: syncToiCloud ? kCFBooleanTrue! : kCFBooleanFalse!,
        ]

        // On real devices, attempt to tie retrieval to biometric / passcode
        // confirmation via a SecAccessControl.  Fails gracefully on simulator.
        if let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            [.userPresence],
            nil
        ) {
            query[kSecAttrAccessControl] = access
            query.removeValue(forKey: kSecAttrAccessible)   // mutually exclusive
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.writeFailed(status)
        }
    }

    static func loadPrivateKey(account: String) throws -> Data {
        let context = LAContext()
        context.localizedReason = "Unlock openme key for '\(account)'"
        let query: [CFString: Any] = [
            kSecClass:                  kSecClassGenericPassword,
            kSecAttrService:            service,
            kSecAttrAccount:            account,
            kSecReturnData:             true,
            kSecMatchLimit:             kSecMatchLimitOne,
            kSecUseAuthenticationContext: context,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.notFound(account)
        }
        return data
    }

    static func deletePrivateKey(account: String) throws {
        let query: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  service,
            kSecAttrAccount:  account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - iCloud sync helpers

    /// Returns all accounts whose items have `kSecAttrSynchronizable = true`.
    static func syncedAccounts() throws -> [String] {
        let query: [CFString: Any] = [
            kSecClass:             kSecClassGenericPassword,
            kSecAttrService:       service,
            kSecAttrSynchronizable: kCFBooleanTrue!,
            kSecReturnAttributes:  true,
            kSecMatchLimit:        kSecMatchLimitAll,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[CFString: Any]] else {
            return []
        }
        return items.compactMap { $0[kSecAttrAccount] as? String }
    }

    // MARK: - Errors

    enum KeychainError: LocalizedError {
        case writeFailed(OSStatus)
        case notFound(String)
        case deleteFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .writeFailed(let s):  return "Keychain write failed (\(s))"
            case .notFound(let a):     return "No key found for '\(a)'"
            case .deleteFailed(let s): return "Keychain delete failed (\(s))"
            }
        }
    }
}
