import SwiftUI

struct EditionComparisonSheet: View {
    let searchResult: Edition
    let ownedEdition: Edition
    @Environment(\.dismiss) private var dismiss
    @Environment(TabCoordinator.self) private var tabCoordinator
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HStack(spacing: 16) {
                    EditionDetailCard(edition: ownedEdition, title: "You Own")
                    EditionDetailCard(edition: searchResult, title: "Search Result")
                }

                VStack(spacing: 12) {
                    Button("View in Library") {
                        // Navigate to Library tab
                        dismiss()
                        navigateToLibraryEntry()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Add Different Edition") {
                        // Proceed with adding
                        dismiss()
                        addDifferentEdition()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .navigationTitle("Edition Comparison")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func navigateToLibraryEntry() {
        if ownedEdition.work != nil {
            tabCoordinator.selectedTab = .library
            tabCoordinator.switchToLibrary()
        }
    }

    private func addDifferentEdition() {
        guard let work = searchResult.work else { return }
        // Insert models into context if not already present
        modelContext.insert(work)
        modelContext.insert(searchResult)
        
        // Now safe to create UserLibraryEntry using factory method
        _ = UserLibraryEntry.createOwnedEntry(for: work, edition: searchResult, context: modelContext)
        do {
            try modelContext.save()
        } catch {
            // Handle error - log silently for now
            print("Error saving UserLibraryEntry: \(error)")
        }
    }
}

struct EditionDetailCard: View {
    let edition: Edition
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 4) {
                Text("Format: \(edition.format.displayName)")
                Text("Publisher: \(edition.publisher ?? "N/A")")
                Text("Year: \((edition.publicationDate?.prefix(4)).map(String.init) ?? "N/A")")
                Text("ISBN: \(edition.primaryISBN ?? "N/A")")
            }
            .font(.subheadline)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}