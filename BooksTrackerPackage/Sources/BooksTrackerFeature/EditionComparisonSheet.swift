import SwiftUI
import SwiftData

/// Sheet for comparing a search result with an existing library entry.
///
/// **Usage in SearchView:**
/// ```swift
/// .sheet(item: $comparisonItem) { item in
///     EditionComparisonSheet(
///         searchResult: item.searchResultEdition,
///         ownedEdition: item.ownedEdition
///     )
/// }
/// ```
struct EditionComparisonSheet: View {
    let searchResult: Edition
    let ownedEdition: Edition
    @Environment(\.dismiss) private var dismiss
    @Environment(TabCoordinator.self) private var tabCoordinator
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header message
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)

                        Text("Book Already in Library")
                            .font(.title2.weight(.semibold))

                        if let work = ownedEdition.work,
                           let entry = work.userLibraryEntries?.first {
                            Text("This book is already in your \(entry.readingStatus.displayName) collection")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top)

                    // Edition comparison
                    VStack(spacing: 16) {
                        Text("Compare Editions")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(alignment: .top, spacing: 12) {
                            EditionDetailCard(edition: ownedEdition, title: "You Own")
                            Divider()
                            EditionDetailCard(edition: searchResult, title: "Search Result")
                        }
                    }

                    // Action buttons
                    VStack(spacing: 12) {
                        Button {
                            dismiss()
                            navigateToLibraryEntry()
                        } label: {
                            Label("View in Library", systemImage: "books.vertical.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button {
                            dismiss()
                            addDifferentEdition()
                        } label: {
                            Label("Add Different Edition", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        Button("Cancel", role: .cancel) {
                            dismiss()
                        }
                        .controlSize(.large)
                    }
                }
                .padding()
            }
            .navigationTitle("Duplicate Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            // Cover image if available
            if let work = edition.work,
               let coverURL = work.coverImageURL,
               let url = URL(string: coverURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    Rectangle()
                        .fill(.gray.opacity(0.2))
                        .overlay {
                            Image(systemName: "book.closed.fill")
                                .foregroundStyle(.secondary)
                        }
                }
                .frame(height: 100)
                .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Format: \(edition.format.displayName)")
                Text("Publisher: \(edition.publisher ?? "N/A")")
                Text("Year: \((edition.publicationDate?.prefix(4)).map(String.init) ?? "N/A")")
                Text("ISBN: \(edition.primaryISBN ?? "N/A")")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
    }
}