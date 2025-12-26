import SwiftUI
import SwiftData

struct EnrichmentQueueRow: View {
    let workId: PersistentIdentifier
    @Environment(\.modelContext) private var modelContext

    /// Computed property ensures we always get fresh data from SwiftData context
    private var work: Work? {
        modelContext.model(for: workId) as? Work
    }

    var body: some View {
        if let work {
            LabeledContent {
                ProgressView()
                    .scaleEffect(0.8)
            } label: {
                Text(work.title)
            }
        } else {
            LabeledContent {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.secondary)
            } label: {
                Text("Book no longer available")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
