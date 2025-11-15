import SwiftUI
import SwiftData

struct EnrichmentQueueDetailsView: View {
    @Environment(EnrichmentQueue.self) private var enrichmentQueue
    @State private var showingClearConfirmation = false

    var body: some View {
        List {
            Section {
                if enrichmentQueue.activeEnrichments.isEmpty {
                    ContentUnavailableView {
                        Label("No Active Enrichments", systemImage: "checkmark.circle")
                    } description: {
                        Text("All books are up to date with the latest metadata.")
                    }
                } else {
                    ForEach(Array(enrichmentQueue.activeEnrichments), id: \.self) { workId in
                        EnrichmentQueueRow(workId: workId)
                    }
                }
            } header: {
                Text("Active Enrichments (\(enrichmentQueue.activeEnrichments.count))")
            }

            Section {
                Button("Stop Enrichment") {
                    Task { await enrichmentQueue.stop() }
                }
                .disabled(enrichmentQueue.activeEnrichments.isEmpty)

                Button("Clear Queue", role: .destructive) {
                    showingClearConfirmation = true
                }
                .disabled(enrichmentQueue.activeEnrichments.isEmpty)
            }
        }
        .navigationTitle("Enrichment Queue")
        .confirmationDialog(
            "Clear Enrichment Queue?",
            isPresented: $showingClearConfirmation
        ) {
            Button("Clear Queue", role: .destructive) {
                Task { enrichmentQueue.clearQueue() }
            }
        } message: {
            Text("Books will remain in your library but won't receive metadata updates.")
        }
    }
}