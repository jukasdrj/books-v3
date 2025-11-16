import SwiftUI
import SwiftData

/// Subtle indicator overlay shown on book cards during active enrichment
/// Appears only while book is in enrichment queue (Issue #445)
@available(iOS 26.0, *)
struct EnrichmentIndicator: View {
    let workId: PersistentIdentifier
    @Environment(EnrichmentQueue.self) private var enrichmentQueue
    @Environment(\.iOS26ThemeStore) private var themeStore

    var isEnriching: Bool {
        enrichmentQueue.activeEnrichments.contains(workId)
    }

    var body: some View {
        if isEnriching {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(themeStore.primaryColor)
                Text("Updating...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            .transition(.opacity.combined(with: .scale))
            .accessibilityLabel("Enriching book metadata")
            .accessibilityHint("Book data is being updated in the background")
        }
    }
}