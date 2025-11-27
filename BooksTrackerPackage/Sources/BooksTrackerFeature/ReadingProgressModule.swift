import SwiftUI

struct ReadingProgressModule: View {
    @Bindable var work: Work
    @Environment(\.modelContext) private var modelContext
    @State private var isSessionActive = false
    @State private var showEndSessionSheet = false
    @State private var endingPage: Int = 0

    private var libraryEntry: UserLibraryEntry? {
        work.userLibraryEntries?.first
    }

    private var edition: Edition? {
        work.primaryEdition ?? work.availableEditions.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModuleHeader(title: "Progress", icon: "chart.bar.fill")

            ProgressView(value: libraryEntry?.readingProgress ?? 0.0)
                .tint(.green)

            // Manual Page Input
            HStack {
                Text("Page")
                TextField("0", value: Binding(
                    get: { libraryEntry?.currentPage ?? 0 },
                    set: { newPage in
                        guard let entry = libraryEntry else { return }
                        entry.currentPage = newPage
                        updateReadingProgress()
                    }
                ), format: .number)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)

                if let pageCount = edition?.pageCount {
                    Text("of \(pageCount)")
                }
                Spacer()
                Text("\(Int((libraryEntry?.readingProgress ?? 0.0) * 100))%")
            }

            // Session Control
            Button(action: {
                if isSessionActive {
                    showEndSessionSheet = true
                } else {
                    startSession()
                }
            }) {
                Text(isSessionActive ? "End Session" : "Start Session")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(isSessionActive ? Color.orange : Color.blue)
                    .cornerRadius(12)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .sheet(isPresented: $showEndSessionSheet) {
            EndSessionSheet(
                workTitle: work.title,
                currentPage: libraryEntry?.currentPage ?? 0,
                pageCount: edition?.pageCount ?? 0,
                endingPage: $endingPage,
                onSave: {
                    endSession()
                }
            )
            .iOS26SheetGlass()
        }
    }

    private func updateReadingProgress() {
        guard let entry = libraryEntry, let pageCount = edition?.pageCount, pageCount > 0 else { return }
        entry.readingProgress = Double(entry.currentPage) / Double(pageCount)
        try? modelContext.save()
    }

    private func startSession() {
        guard let entry = libraryEntry else { return }
        let service = ReadingSessionService(modelContext: modelContext)
        try? service.startSession(for: entry)
        isSessionActive = true
        endingPage = entry.currentPage
    }

    private func endSession() {
        let service = ReadingSessionService(modelContext: modelContext)
        try? service.endSession(endPage: endingPage)
        isSessionActive = false
    }
}
