import Foundation

/// Canonical API error codes from backend TypeScript contracts
/// Source: api-worker/src/types/enums.ts:ApiErrorCode
/// Backend repo: https://github.com/jukasdrj/bookstrack-backend
///
/// **Contract Adherence:** Backend must maintain these exact error codes.
/// Any changes require issues in BOTH repos (iOS + backend) to keep contracts in sync.
///
/// Related:
/// - GitHub Issue: #429
/// - FRONTEND_HANDOFF.md:196-202
/// - Backend contracts: api-worker/src/types/enums.ts
public enum ApiErrorCode: String, Codable, Sendable {
    case invalidQuery = "INVALID_QUERY"
    case invalidISBN = "INVALID_ISBN"
    case providerError = "PROVIDER_ERROR"
    case internalError = "INTERNAL_ERROR"
    case rateLimitExceeded = "RATE_LIMIT_EXCEEDED"

    // MARK: - User-Facing Messages

    /// Localized error message suitable for display to users
    /// Ready for NSLocalizedString integration when localization is needed
    public var localizedMessage: String {
        switch self {
        case .invalidQuery:
            return "Please enter a search term"
        case .invalidISBN:
            return "Invalid ISBN format (use 10 or 13 digits)"
        case .providerError:
            return "Book search unavailable. Try again."
        case .internalError:
            return "Something went wrong. We've been notified."
        case .rateLimitExceeded:
            return "Too many requests. Please wait before trying again."
        }
    }

    /// Suggested action the user can take to resolve the error
    public var actionSuggestion: String {
        switch self {
        case .invalidQuery:
            return "Enter a title or author name"
        case .invalidISBN:
            return "Check ISBN format (10 or 13 digits)"
        case .providerError:
            return "Try again in a few moments"
        case .internalError:
            return "Contact support if this persists"
        case .rateLimitExceeded:
            return "Wait for countdown timer"
        }
    }

    // MARK: - Dynamic Message Support

    /// Generate error message with dynamic values from backend response details
    /// - Parameter details: Optional details dictionary from ResponseEnvelope.error.details
    /// - Returns: Formatted error message with substituted values
    ///
    /// Example:
    /// ```swift
    /// let code = ApiErrorCode.rateLimitExceeded
    /// let details = ["retryAfter": 42]
    /// let message = code.messageWithDetails(details)
    /// // Returns: "Too many requests. Wait 42s before trying again."
    /// ```
    public func messageWithDetails(_ details: [String: Any]?) -> String {
        guard let details = details else {
            return localizedMessage
        }

        switch self {
        case .rateLimitExceeded:
            // Extract retryAfter from details (can be Int or String)
            if let retryAfter = details["retryAfter"] as? Int {
                return "Too many requests. Wait \(retryAfter)s before trying again."
            } else if let retryAfter = details["retryAfter"] as? String,
                      let seconds = Int(retryAfter) {
                return "Too many requests. Wait \(seconds)s before trying again."
            }

            #if DEBUG
            print("⚠️ [ApiErrorCode] Failed to extract retryAfter from details: \(details)")
            #endif
            return localizedMessage

        default:
            // Other error codes don't have dynamic values yet
            return localizedMessage
        }
    }

    // MARK: - Error Severity

    /// Severity level for error tracking and analytics
    public var severity: ErrorSeverity {
        switch self {
        case .invalidQuery, .invalidISBN:
            return .low // User input validation errors
        case .rateLimitExceeded:
            return .medium // Temporary throttling, user can retry
        case .providerError:
            return .high // External API failure, impacts functionality
        case .internalError:
            return .critical // Server error, needs investigation
        }
    }

    /// Error severity levels for logging and analytics
    public enum ErrorSeverity: String, Sendable {
        case low = "low"
        case medium = "medium"
        case high = "high"
        case critical = "critical"
    }

    // MARK: - Retry Strategy

    /// Whether the operation should be retryable for this error type
    public var isRetryable: Bool {
        switch self {
        case .invalidQuery, .invalidISBN:
            return false // User must fix input first
        case .rateLimitExceeded:
            return true // Can retry after waiting
        case .providerError:
            return true // Temporary external API issue
        case .internalError:
            return false // Server error, retry won't help immediately
        }
    }

    /// Suggested retry delay in seconds (nil if not retryable)
    public var retryDelay: TimeInterval? {
        switch self {
        case .providerError:
            return 5.0 // Wait 5 seconds for external API recovery
        case .rateLimitExceeded:
            return nil // Use retryAfter from details instead
        default:
            return nil
        }
    }

    // MARK: - Stable Error Codes

    /// Stable integer error code for NSError (replaces non-deterministic hashValue)
    /// - Note: Uses 4xxx range to avoid conflicts with HTTP status codes
    public var errorCode: Int {
        switch self {
        case .invalidQuery:
            return 4001
        case .invalidISBN:
            return 4002
        case .providerError:
            return 4003
        case .internalError:
            return 4004
        case .rateLimitExceeded:
            return 4005
        }
    }
}

// MARK: - Convenience Initializer

extension ApiErrorCode {
    /// Create ApiErrorCode from backend error code string with fallback
    /// - Parameter code: Error code string from backend (e.g., "INVALID_QUERY")
    /// - Returns: Matching ApiErrorCode or nil if unknown
    ///
    /// Example:
    /// ```swift
    /// let errorCode = ApiErrorCode.from(code: "INVALID_QUERY")
    /// // Returns: .invalidQuery
    ///
    /// let unknown = ApiErrorCode.from(code: "UNKNOWN_ERROR")
    /// // Returns: nil
    /// ```
    public static func from(code: String?) -> ApiErrorCode? {
        guard let code = code else { return nil }
        return ApiErrorCode(rawValue: code)
    }
}

// MARK: - Error Helper

extension ApiErrorCode {
    /// Create user-friendly NSError from ApiErrorCode
    /// - Parameters:
    ///   - details: Optional details dictionary from backend
    ///   - underlyingError: Optional underlying error for debugging
    /// - Returns: NSError with localized description and metadata
    public func toNSError(details: [String: Any]? = nil, underlyingError: Error? = nil) -> NSError {
        var userInfo: [String: Any] = [
            NSLocalizedDescriptionKey: messageWithDetails(details),
            NSLocalizedRecoverySuggestionErrorKey: actionSuggestion,
            "errorCode": rawValue,
            "severity": severity.rawValue,
            "isRetryable": isRetryable
        ]

        if let details = details {
            userInfo["details"] = details
        }

        if let underlyingError = underlyingError {
            userInfo[NSUnderlyingErrorKey] = underlyingError
        }

        return NSError(
            domain: "com.bookstrack.api",
            code: errorCode,
            userInfo: userInfo
        )
    }
}
