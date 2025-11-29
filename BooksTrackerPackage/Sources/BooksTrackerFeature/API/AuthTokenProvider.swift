import Foundation

/// Protocol for providing authentication tokens to BooksTrackAPI
/// Separates token management (storage, retrieval, refresh) from network operations
///
/// Implementations should handle:
/// - Secure token storage (Keychain recommended)
/// - Token refresh logic when expired
/// - Concurrency-safe token access
///
/// Actor isolation ensures thread-safe token operations, crucial for refresh flows
public protocol AuthTokenProvider: Actor {
    /// Provides the current valid access token. May involve retrieving from storage.
    /// - Throws: AuthTokenError if token is unavailable or expired
    /// - Returns: Valid Bearer token string
    func getAccessToken() async throws -> String

    /// Attempts to refresh the access token and returns the new valid token.
    /// Should handle token expiry and re-authentication if refresh fails.
    /// - Throws: AuthTokenError if refresh fails or requires user login
    /// - Returns: Newly refreshed Bearer token string
    func refreshAndGetAccessToken() async throws -> String

    /// Clears all authentication tokens, typically used during logout.
    func clearTokens() async
}

/// Errors related to token management
public enum AuthTokenError: Error, LocalizedError {
    case tokenUnavailable
    case tokenExpired
    case refreshFailed(String)
    case loginRequired

    public var errorDescription: String? {
        switch self {
        case .tokenUnavailable:
            return "Authentication token is not available."
        case .tokenExpired:
            return "Authentication token has expired."
        case .refreshFailed(let message):
            return "Token refresh failed: \(message)"
        case .loginRequired:
            return "User login is required to obtain a valid token."
        }
    }
}
