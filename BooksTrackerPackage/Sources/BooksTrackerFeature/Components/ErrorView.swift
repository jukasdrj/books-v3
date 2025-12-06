import SwiftUI

/// Reusable error display component with Liquid Glass design system
///
/// Displays user-friendly error messages with appropriate icons and actions.
/// Enhanced with glass morphism and theme-aware styling (Issue #143, Phase 1.1).
///
/// Usage:
/// ```swift
/// ErrorView(error: apiError) {
///     // Retry action
/// }
/// ```
@available(iOS 26.0, *)
struct ErrorView: View {
    let error: ApiErrorInfo
    var retryAction: (() -> Void)?

    @Environment(\.iOS26ThemeStore) private var themeStore

    var body: some View {
        VStack(spacing: 24) {
            // Error icon with glass background
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.red.opacity(0.15),
                                Color.red.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)

                Image(systemName: errorIcon)
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.red,
                                Color.red.opacity(0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.pulse, options: .repeating)
            }

            // Error message
            VStack(spacing: 8) {
                Text(error.userMessage)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                if error.requiresUserAction {
                    Text("Please check your input and try again")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)

            // Retry action button
            if error.isRetryable, let retryAction = retryAction {
                Button(action: retryAction) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                            .font(.headline)

                        Text("Try Again")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background {
                        Capsule()
                            .fill(themeStore.primaryColor)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(32)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.red.opacity(0.2),
                                    Color.red.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
        }
        .shadow(color: Color.red.opacity(0.1), radius: 20, x: 0, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(error.userMessage)")
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
    let themeStore = BooksTrackerFeature.iOS26ThemeStore()

    return ErrorView(error: ApiErrorInfo(
        message: "Book not found",
        code: "NOT_FOUND",
        details: nil,
        statusCode: 404,
        retryable: false
    ))
    .environment(\.iOS26ThemeStore, themeStore)
    .padding()
}

#Preview("Network Error - Retryable") {
    let themeStore = BooksTrackerFeature.iOS26ThemeStore()

    return ErrorView(
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
    .environment(\.iOS26ThemeStore, themeStore)
    .padding()
}

#Preview("Validation Error - User Action") {
    let themeStore = BooksTrackerFeature.iOS26ThemeStore()

    return ErrorView(error: ApiErrorInfo(
        message: "Invalid ISBN format",
        code: "INVALID_ISBN",
        details: nil,
        statusCode: 400,
        retryable: false
    ))
    .environment(\.iOS26ThemeStore, themeStore)
    .padding()
}

#Preview("Rate Limited") {
    let themeStore = BooksTrackerFeature.iOS26ThemeStore()

    return ErrorView(
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
    .environment(\.iOS26ThemeStore, themeStore)
    .padding()
}
