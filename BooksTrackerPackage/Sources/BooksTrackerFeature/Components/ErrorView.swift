import SwiftUI

/// Reusable error display component
///
/// Displays user-friendly error messages with appropriate icons and actions.
/// Part of Phase 2, Task 4 of V3 Migration Plan.
///
/// Usage:
/// ```swift
/// ErrorView(error: apiError) {
///     // Retry action
/// }
/// ```
struct ErrorView: View {
    let error: ApiErrorInfo
    var retryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: errorIcon)
                .font(.system(size: 48))
                .foregroundColor(.red.opacity(0.8))

            Text(error.userMessage)
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if error.requiresUserAction {
                Text("Please check your input and try again")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if error.isRetryable, let retryAction = retryAction {
                Button("Try Again") {
                    retryAction()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    /// Map error code to SF Symbol icon
    private var errorIcon: String {
        guard let code = error.code else {
            return "exclamationmark.triangle"
        }

        switch code {
        case "NOT_FOUND":
            return "magnifyingglass"
        case "NETWORK_ERROR", "TIMEOUT":
            return "wifi.slash"
        case "UNAUTHORIZED", "FORBIDDEN", "TOKEN_EXPIRED":
            return "lock.shield"
        case "RATE_LIMITED":
            return "clock.badge.exclamationmark"
        case "CIRCUIT_OPEN", "PROVIDER_ERROR", "SERVICE_UNAVAILABLE":
            return "server.rack"
        case "INVALID_ISBN", "INVALID_QUERY", "VALIDATION_ERROR", "MISSING_FIELD":
            return "text.badge.xmark"
        case "INTERNAL_ERROR", "SERVER_ERROR", "DATABASE_ERROR":
            return "exclamationmark.triangle.fill"
        default:
            return "exclamationmark.triangle"
        }
    }
}

// MARK: - Previews

#Preview("Not Found") {
    ErrorView(error: ApiErrorInfo(
        message: "Book not found",
        code: "NOT_FOUND",
        details: nil,
        statusCode: 404,
        retryable: false
    ))
}

#Preview("Network Error - Retryable") {
    ErrorView(
        error: ApiErrorInfo(
            message: "Network connection failed",
            code: "NETWORK_ERROR",
            details: nil,
            statusCode: nil,
            retryable: true
        ),
        retryAction: {
            print("Retry tapped")
        }
    )
}

#Preview("Validation Error - User Action") {
    ErrorView(error: ApiErrorInfo(
        message: "Invalid ISBN format",
        code: "INVALID_ISBN",
        details: nil,
        statusCode: 400,
        retryable: false
    ))
}

#Preview("Rate Limited") {
    ErrorView(
        error: ApiErrorInfo(
            message: "Too many requests",
            code: "RATE_LIMITED",
            details: nil,
            statusCode: 429,
            retryable: true
        ),
        retryAction: {
            print("Retry after rate limit")
        }
    )
}
