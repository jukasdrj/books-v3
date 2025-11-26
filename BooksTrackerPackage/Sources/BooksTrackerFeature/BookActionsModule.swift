import SwiftUI

struct BookActionsModule: View {
    @Bindable var work: Work
    @Environment(\.modelContext) private var modelContext
    @State private var showingStatusPicker = false

    private var libraryEntry: UserLibraryEntry? {
        work.userLibraryEntries?.first
    }

    private var currentStatus: ReadingStatus {
        libraryEntry?.readingStatus ?? .wishlist
    }

    var body: some View {
        VStack(spacing: 16) {
            // Reading Status Button
            Button(action: { showingStatusPicker.toggle() }) {
                HStack {
                    Image(systemName: currentStatus.systemImage)
                    Text(currentStatus.displayName)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .background(Color.secondary.cornerRadius(12))
            }

            // Remove from Library Button
            Button(action: deleteFromLibrary) {
                HStack {
                    Image(systemName: "trash")
                    Text("Remove from Library")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.red.cornerRadius(12))
            }
        }
        .sheet(isPresented: $showingStatusPicker) {
            ReadingStatusPicker(selectedStatus: Binding(
                get: { currentStatus },
                set: { newStatus in
                    updateReadingStatus(to: newStatus)
                }
            ))
            .iOS26SheetGlass()
        }
    }

    private func updateReadingStatus(to newStatus: ReadingStatus) {
        guard let entry = libraryEntry else { return }
        entry.readingStatus = newStatus

        if newStatus == .read && entry.dateCompleted == nil {
            entry.dateCompleted = Date()
        }

        try? modelContext.save()
    }

    private func deleteFromLibrary() {
        guard let entry = libraryEntry else { return }
        modelContext.delete(entry)
        if work.userLibraryEntries?.isEmpty ?? true {
            modelContext.delete(work)
        }
        try? modelContext.save()
    }
}

// Re-creating the ReadingStatusPicker
private struct ReadingStatusPicker: View {
    @Binding var selectedStatus: ReadingStatus
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(ReadingStatus.allCases, id: \.self) { status in
                Button(action: {
                    selectedStatus = status
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: status.systemImage).foregroundColor(status.color)
                        Text(status.displayName)
                        Spacer()
                        if status == selectedStatus {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .foregroundColor(.primary)
            }
            .navigationTitle("Select Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
