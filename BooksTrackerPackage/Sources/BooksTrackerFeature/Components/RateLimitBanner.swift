import SwiftUI

/// Rate limit countdown banner for API throttling responses (HTTP 429)
///
/// **Usage:**
/// ```swift
/// @State private var showRateLimitBanner = false
/// @State private var retryAfterSeconds = 0
///
/// if showRateLimitBanner {
///     RateLimitBanner(retryAfter: retryAfterSeconds) {
///         showRateLimitBanner = false
///     }
/// }
/// ```
///
/// **Backend Contract:**
/// - HTTP 429 responses include `Retry-After` header (seconds)
/// - Fallback to `details.retryAfter` in response body
/// - Defaults to 60s if neither provided
///
/// **Accessibility:**
/// - VoiceOver announces countdown updates
/// - Clear visual countdown for sighted users
/// - Auto-dismisses at zero (no manual action needed)
///
/// Related:
/// - GitHub Issue: #426
/// - ApiErrorCode.rateLimitExceeded
/// - FRONTEND_HANDOFF.md:196-206 (backend rate limits)
@MainActor
public struct RateLimitBanner: View {
    // MARK: - Properties

    /// Seconds remaining until retry allowed
    @State private var remainingSeconds: Int

    /// Callback when banner should dismiss (countdown reaches zero)
    private let onDismiss: () -> Void

    /// Timer task for countdown
    @State private var countdownTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Create rate limit banner with countdown
    /// - Parameters:
    ///   - retryAfter: Seconds to wait before retry (from Retry-After header or response body)
    ///   - onDismiss: Callback when countdown completes
    public init(retryAfter: Int, onDismiss: @escaping () -> Void = {}) {
        self._remainingSeconds = State(initialValue: max(1, retryAfter)) // Minimum 1 second
        self.onDismiss = onDismiss
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Rate limit icon
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title2)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Too Many Requests")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Wait \(remainingSeconds)s before trying again")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Countdown badge
                Text("\(remainingSeconds)s")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background {
                        Capsule()
                            .fill(.orange.opacity(0.15))
                    }
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.orange.opacity(0.1))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.orange.opacity(0.3), lineWidth: 1)
                    }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rate limit exceeded. Wait \(remainingSeconds) seconds before trying again.")
        .onAppear {
            startCountdown()
        }
        .onDisappear {
            stopCountdown()
        }
    }

    // MARK: - Countdown Logic

    /// Start countdown timer using Swift 6 concurrency (no Timer.publish!)
    /// Updates every second until reaching zero
    private func startCountdown() {
        countdownTask?.cancel() // Cancel any existing task

        countdownTask = Task { @MainActor in
            while remainingSeconds > 0 {
                // Wait 1 second (Swift 6 pattern, no Combine!)
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch is CancellationError {
                    // Task was cancelled, exit gracefully
                    return
                } catch {
                    // Unexpected error during sleep (e.g., clock changes)
                    #if DEBUG
                    print("⚠️ RateLimitBanner: Unexpected error in countdown - \(error)")
                    #endif
                    return
                }

                // Check if task was cancelled
                guard !Task.isCancelled else { return }

                // Decrement countdown
                remainingSeconds -= 1

                // Announce to VoiceOver every 10 seconds or at 5/4/3/2/1
                if shouldAnnounce(remainingSeconds) {
                    announceCountdown(remainingSeconds)
                }
            }

            // Countdown complete - dismiss banner
            onDismiss()
        }
    }

    /// Stop countdown timer (cleanup on disappear)
    private func stopCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
    }

    /// Determine if VoiceOver should announce this countdown value
    /// - Parameter seconds: Current remaining seconds
    /// - Returns: True if should announce (every 10s or last 5 seconds)
    private func shouldAnnounce(_ seconds: Int) -> Bool {
        // Announce every 10 seconds (60, 50, 40...)
        if seconds % 10 == 0 { return true }

        // Announce final countdown (5, 4, 3, 2, 1)
        if seconds <= 5 { return true }

        return false
    }

    /// Post accessibility announcement for VoiceOver
    /// - Parameter seconds: Remaining seconds to announce
    private func announceCountdown(_ seconds: Int) {
        let message = "\(seconds) seconds remaining"

        UIAccessibility.post(
            notification: .announcement,
            argument: message
        )
    }
}

// MARK: - Preview

#Preview("Rate Limit Banner") {
    VStack(spacing: 20) {
        Text("Rate Limit UI Preview")
            .font(.title)

        RateLimitBanner(retryAfter: 42) {
            print("Banner dismissed after countdown")
        }

        Spacer()
    }
    .padding()
}

#Preview("Dark Mode") {
    VStack(spacing: 20) {
        Text("Rate Limit UI Preview")
            .font(.title)

        RateLimitBanner(retryAfter: 15) {
            print("Banner dismissed")
        }

        Spacer()
    }
    .padding()
    .preferredColorScheme(.dark)
}