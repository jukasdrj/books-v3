import SwiftUI

/// View component for displaying enrichment status with appropriate UI for each state
///
/// Supports all enrichment statuses defined in API Contract v3.1:
/// - `pending`: Shows spinner, indicates enrichment in progress
/// - `success`: Shows checkmark, book enriched successfully
/// - `not_found`: Shows question mark, suggests manual search
/// - `error`: Shows exclamation, allows manual retry
/// - `circuit_open`: Shows clock, countdown to auto-retry
///
/// **Usage:**
/// ```swift
/// EnrichmentStatusView(
///     status: .circuitOpen,
///     retryAfterMs: 60000,
///     onRetry: { await retryEnrichment() }
/// )
/// ```
///
/// **Swift 6 Concurrency:**
/// Uses Task.sleep for countdown (no Timer.publish per Swift 6 actor isolation rules).
///
/// Related:
/// - API Contract v3.1 Section 7.6.1 (Enrichment Status)
/// - GitHub Issue: #104
@available(iOS 26.0, *)
@MainActor
struct EnrichmentStatusView: View {
    // MARK: - Properties

    let status: EnrichmentStatus
    let retryAfterMs: Int?
    let onRetry: (() async -> Void)?

    /// Countdown seconds remaining (for circuit_open status)
    @State private var countdown: Int = 0

    // MARK: - Body

    var body: some View {
        HStack(spacing: 8) {
            statusIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(status.displayDescription)
                    .font(.caption)
                    .foregroundStyle(statusColor)

                if status == .circuitOpen, countdown > 0 {
                    Text("Retry in \(countdown)s")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if status.isRetryable && status != .circuitOpen {
                Button("Retry") {
                    Task {
                        await onRetry?()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        .task(id: retryAfterMs) {
            // Start countdown when circuit_open with retryAfterMs
            // .task modifier automatically cancels on view disappear
            guard status == .circuitOpen, let ms = retryAfterMs else { return }
            await runCountdown(seconds: ms / 1000)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Status Icon

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .pending:
            ProgressView()
                .scaleEffect(0.7)
                .accessibilityLabel("Loading")
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Success")
        case .notFound:
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.orange)
                .accessibilityLabel("Not found")
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("Error")
        case .circuitOpen:
            Image(systemName: "clock.badge.exclamationmark.fill")
                .foregroundStyle(.yellow)
                .accessibilityLabel("Temporarily unavailable")
        }
    }

    // MARK: - Status Color

    private var statusColor: Color {
        switch status {
        case .pending:
            return .secondary
        case .success:
            return .green
        case .notFound:
            return .orange
        case .error:
            return .red
        case .circuitOpen:
            return .yellow
        }
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        var label = status.displayDescription

        if status == .circuitOpen, countdown > 0 {
            label += ". Retry in \(countdown) seconds."
        }

        if status.isRetryable && status != .circuitOpen {
            label += ". Retry button available."
        }

        return label
    }

    // MARK: - Countdown Logic (Swift 6 Concurrency)

    /// Run countdown using Swift 6 concurrency (called from .task modifier)
    /// - Parameter seconds: Initial countdown seconds
    private func runCountdown(seconds: Int) async {
        countdown = max(0, seconds)

        while countdown > 0 {
            // Wait 1 second (Swift 6 pattern, no Combine!)
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                // Task was cancelled or error - exit gracefully
                return
            }

            // Check if task was cancelled
            guard !Task.isCancelled else { return }

            // Decrement countdown
            countdown -= 1

            // Announce to VoiceOver at key intervals
            if shouldAnnounce(countdown) {
                announceCountdown(countdown)
            }
        }

        // Countdown complete - auto-retry
        await onRetry?()
    }

    /// Determine if VoiceOver should announce this countdown value
    /// - Parameter seconds: Current remaining seconds
    /// - Returns: True if should announce (every 15s or last 5 seconds)
    private func shouldAnnounce(_ seconds: Int) -> Bool {
        // Announce every 15 seconds
        if seconds > 0 && seconds % 15 == 0 { return true }

        // Announce final countdown (5, 4, 3, 2, 1)
        if seconds <= 5 && seconds > 0 { return true }

        return false
    }

    /// Post accessibility announcement for VoiceOver
    /// - Parameter seconds: Remaining seconds to announce
    private func announceCountdown(_ seconds: Int) {
        let message = seconds == 1
            ? "Retrying in 1 second"
            : "Retrying in \(seconds) seconds"

        UIAccessibility.post(
            notification: .announcement,
            argument: message
        )
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview("All Enrichment Statuses") {
    VStack(spacing: 16) {
        Text("Enrichment Status States")
            .font(.headline)

        EnrichmentStatusView(status: EnrichmentStatus.pending, retryAfterMs: nil, onRetry: nil)
        EnrichmentStatusView(status: EnrichmentStatus.success, retryAfterMs: nil, onRetry: nil)
        EnrichmentStatusView(
            status: EnrichmentStatus.notFound,
            retryAfterMs: nil,
            onRetry: { print("Retry tapped") }
        )
        EnrichmentStatusView(
            status: EnrichmentStatus.error,
            retryAfterMs: nil,
            onRetry: { print("Retry tapped") }
        )
        EnrichmentStatusView(
            status: EnrichmentStatus.circuitOpen,
            retryAfterMs: 60000,
            onRetry: { print("Auto-retry triggered") }
        )
    }
    .padding()
}

@available(iOS 26.0, *)
#Preview("Circuit Open Countdown") {
    VStack(spacing: 20) {
        Text("Circuit Breaker Active")
            .font(.title2)

        EnrichmentStatusView(
            status: EnrichmentStatus.circuitOpen,
            retryAfterMs: 10000, // 10 seconds for preview
            onRetry: { print("Circuit closed, retrying...") }
        )
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }

        Text("Will auto-retry when countdown reaches 0")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding()
}

@available(iOS 26.0, *)
#Preview("Dark Mode") {
    VStack(spacing: 16) {
        EnrichmentStatusView(status: EnrichmentStatus.circuitOpen, retryAfterMs: 30000, onRetry: nil)
        EnrichmentStatusView(status: EnrichmentStatus.error, retryAfterMs: nil, onRetry: { print("Retry") })
    }
    .padding()
    .preferredColorScheme(.dark)
}
