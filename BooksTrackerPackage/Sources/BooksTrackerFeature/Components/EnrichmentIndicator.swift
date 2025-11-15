import SwiftUI
import SwiftData

struct EnrichmentIndicator: View {
    let workId: PersistentIdentifier
    @Environment(EnrichmentQueue.self) private var enrichmentQueue

    var isEnriching: Bool {
        enrichmentQueue.activeEnrichments.contains(workId)
    }

    var body: some View {
        if isEnriching {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Updating...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .cornerRadius(8)
            .transition(.opacity.combined(with: .scale))
        }
    }
}
