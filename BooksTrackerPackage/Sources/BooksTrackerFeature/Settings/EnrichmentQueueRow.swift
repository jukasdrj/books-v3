import SwiftUI
import SwiftData

struct EnrichmentQueueRow: View {
    let workId: PersistentIdentifier
    @Environment(\.modelContext) private var modelContext
    @State private var work: Work?

    var body: some View {
        LabeledContent {
            ProgressView()
                .scaleEffect(0.8)
        } label: {
            Text(work?.title ?? "Loading book...")
        }
        .task {
            // Fetch the work object when the view appears
            work = modelContext.model(for: workId) as? Work
        }
    }
}
