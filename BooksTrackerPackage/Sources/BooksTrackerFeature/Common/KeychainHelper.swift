import Foundation
import Security

/// Secure storage for authentication tokens using iOS Keychain
/// Prevents token exposure in memory dumps or crash logs
public final class KeychainHelper {

    // MARK: - Errors

    enum KeychainError: Error, LocalizedError {
        case unexpectedData
        case unhandledError(status: OSStatus)

        var errorDescription: String? {
            switch self {
            case .unexpectedData:
                return "Unexpected data format in Keychain"
            case .unhandledError(let status):
                return "Keychain error: \(status)"
            }
        }
    }

    // MARK: - Token Storage

    private static let serviceName = "com.oooefam.booksV3.websocket"

    /// Save authentication token to Keychain
    /// - Parameters:
    ///   - token: Token string to store securely
    ///   - account: Account identifier (e.g., jobId)
    /// - Throws: KeychainError if save fails
    public static func saveToken(_ token: String, for account: String) throws {
        guard let tokenData = token.data(using: .utf8) else {
            throw KeychainError.unexpectedData
        }

        // Query for existing item
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        // Delete any existing item
        SecItemDelete(query as CFDictionary)

        // Add new item
        var addQuery = query
        addQuery[kSecValueData as String] = tokenData
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(addQuery as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }

        #if DEBUG
        print("🔐 Token saved to Keychain for account: \(account)")
        #endif
    }

    /// Retrieve authentication token from Keychain
    /// - Parameter account: Account identifier (e.g., jobId)
    /// - Returns: Token string if found, nil otherwise
    /// - Throws: KeychainError if retrieval fails
    public static func getToken(for account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status != errSecItemNotFound else {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }

        guard let tokenData = item as? Data,
              let token = String(data: tokenData, encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }

        return token
    }

    /// Delete authentication token from Keychain
    /// - Parameter account: Account identifier (e.g., jobId)
    public static func deleteToken(for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        #if DEBUG
        print("🔐 Token deleted from Keychain for account: \(account)")
        #endif
    }

    /// Delete all tokens from Keychain
    public static func deleteAllTokens() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]

        SecItemDelete(query as CFDictionary)

        #if DEBUG
        print("🔐 All tokens deleted from Keychain")
        #endif
    }
}
