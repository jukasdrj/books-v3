import SwiftUI
import SwiftData
import Foundation
import OSLog

/// A SwiftUI component to display author information, including metadata,
/// cascade status to associated works, and a list of books by the author.
@available(iOS 26.0, *)
@MainActor
public struct AuthorProfileView: View {
    public let authorId: String // Author's persistent ID (as String from hashValue)
    @Environment(\.modelContext) private var modelContext
    @Environment(\.iOS26ThemeStore) private var themeStore

    @State private var authorMetadata: AuthorMetadata?
    @State private var authorWorks: [Work] = []
    @State private var isLoading: Bool = true
    @State private var overriddenWorkCount: Int = 0
    @State private var workStatuses: [String: WorkStatus] = [:] // Map workId to its status

    private let logger = Logger(subsystem: "com.oooefam.booksV3", category: "AuthorProfileView")

    /// Initializes a new `AuthorProfileView`.
    /// - Parameter authorId: The persistent ID of the author to display.
    public init(authorId: String) {
        self.authorId = authorId
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if isLoading {
                    ProgressView("Loading Author Data...")
                        .progressViewStyle(.circular)
                        .tint(themeStore.primaryColor)
                        .padding()
                } else {
                    AuthorHeaderView(
                        authorName: authorName,
                        culturalRegion: authorMetadata?.culturalBackground.first,
                        genderIdentity: authorMetadata?.genderIdentity
                    )

                    MetadataCard(authorMetadata: authorMetadata, themeStore: themeStore)

                    CascadeStatusCard(
                        cascadedWorkCount: cascadedWorkCount,
                        overriddenWorkCount: overriddenWorkCount,
                        themeStore: themeStore
                    )

                    BooksListCard(
                        authorWorks: authorWorks,
                        workStatuses: workStatuses,
                        themeStore: themeStore
                    )
                }
            }
            .padding()
        }
        .background(Color.gray.opacity(0.1))
        .navigationTitle("Author Profile")
        .task {
            await loadAuthorData()
        }
    }

    // MARK: - Computed Properties

    private var cascadedWorkCount: Int {
        authorMetadata?.cascadedToWorkIds.count ?? 0
    }

    private var authorName: String {
        // Get name from first work's author that matches the authorId
        authorWorks.first?.authors?.first(where: {
            $0.persistentModelID.hashValue.description == authorId
        })?.name ?? "Unknown Author"
    }

    // MARK: - Data Loading

    private func loadAuthorData() async {
        isLoading = true
        defer { isLoading = false }

        let cascadeService = CascadeMetadataService(modelContext: modelContext)

        do {
            let metadata = try cascadeService.fetchOrCreateAuthorMetadata(
                authorId: authorId,
                userId: "default-user"
            )
            authorMetadata = metadata

            // Fetch all works and filter in-memory
            let allWorks = try modelContext.fetch(FetchDescriptor<Work>())
            let filteredWorks = allWorks.filter { work in
                work.authors?.contains(where: { author in
                    author.persistentModelID.hashValue.description == authorId
                }) ?? false
            }
            authorWorks = filteredWorks.sorted { $0.title < $1.title }

            // Fetch WorkOverrides to count overridden works
            let allOverrides = try modelContext.fetch(FetchDescriptor<WorkOverride>())
            let workIDs = authorWorks.map { $0.persistentModelID.hashValue.description }
            let relevantOverrides = allOverrides.filter { override in
                override.authorMetadata?.authorId == authorId && workIDs.contains(override.workId)
            }
            let distinctOverriddenWorkIds = Set(relevantOverrides.map { $0.workId })
            overriddenWorkCount = distinctOverriddenWorkIds.count

            // Update work statuses for the Books List
            updateWorkStatuses(for: authorWorks, metadata: authorMetadata, allOverrides: relevantOverrides)

        } catch {
            logger.error("Failed to load author data for ID \(self.authorId): \(error.localizedDescription)")
        }
    }

    /// Determines the cascade or override status for a given work.
    private func updateWorkStatuses(for works: [Work], metadata: AuthorMetadata?, allOverrides: [WorkOverride]) {
        var newStatuses: [String: WorkStatus] = [:]
        guard let metadata = metadata else {
            workStatuses = newStatuses
            return
        }

        let overridesMap = Dictionary(grouping: allOverrides, by: { $0.workId })

        for work in works {
            let workId = work.persistentModelID.hashValue.description
            let isCascaded = metadata.cascadedToWorkIds.contains(workId)
            let hasOverride = overridesMap[workId]?.contains(where: { $0.authorMetadata?.authorId == authorId }) ?? false

            if hasOverride {
                newStatuses[workId] = .overridden
            } else if isCascaded {
                newStatuses[workId] = .cascaded
            } else {
                newStatuses[workId] = .none
            }
        }
        workStatuses = newStatuses
    }

    /// Enum to represent the status of a work in relation to author metadata.
    fileprivate enum WorkStatus {
        case cascaded
        case overridden
        case none
    }
}

// MARK: - Supporting Views

/// Displays the author's photo placeholder, name, and bio.
@available(iOS 26.0, *)
private struct AuthorHeaderView: View {
    let authorName: String
    let culturalRegion: String?
    let genderIdentity: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundStyle(.gray.opacity(0.6))
                .clipShape(Circle())
                .padding(.bottom, 5)

            Text(authorName)
                .font(.title.weight(.bold))
                .foregroundStyle(.primary)
                .accessibilityLabel("Author name: \(authorName)")

            if let culturalRegion = culturalRegion, !culturalRegion.isEmpty {
                Text("Cultural Background: \(culturalRegion)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let genderIdentity = genderIdentity, !genderIdentity.isEmpty {
                Text("Gender Identity: \(genderIdentity)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Author biography would appear here from external API.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.top, 5)
                .accessibilityLabel("Author biography placeholder")
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Author profile header for \(authorName)")
    }
}

/// Displays the author's detailed metadata.
@available(iOS 26.0, *)
private struct MetadataCard: View {
    let authorMetadata: AuthorMetadata?
    let themeStore: iOS26ThemeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Metadata")
                .font(.headline)
                .foregroundStyle(themeStore.primaryColor)

            Divider().overlay(Color.primary.opacity(0.3))

            MetadataRow(
                icon: "globe",
                label: "Cultural Background",
                value: authorMetadata?.culturalBackground.joined(separator: ", ").isEmpty == false ? authorMetadata!.culturalBackground.joined(separator: ", ") : "Not set"
            )
            MetadataRow(
                icon: "person.text.rectangle",
                label: "Gender Identity",
                value: authorMetadata?.genderIdentity ?? "Not set"
            )
            MetadataRow(
                icon: "flag.fill",
                label: "Nationality",
                value: authorMetadata?.nationality.joined(separator: ", ").isEmpty == false ? authorMetadata!.nationality.joined(separator: ", ") : "Not set"
            )
            MetadataRow(
                icon: "text.book.closed.fill",
                label: "Languages",
                value: authorMetadata?.languages.joined(separator: ", ").isEmpty == false ? authorMetadata!.languages.joined(separator: ", ") : "Not set"
            )
            MetadataRow(
                icon: "hand.raised.fill",
                label: "Marginalized Identities",
                value: authorMetadata?.marginalizedIdentities.joined(separator: ", ").isEmpty == false ? authorMetadata!.marginalizedIdentities.joined(separator: ", ") : "Not set"
            )
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Author metadata card")
    }
}

/// A single row for displaying a metadata field.
@available(iOS 26.0, *)
private struct MetadataRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text("\(label):")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// Displays the cascade status of author metadata to works.
@available(iOS 26.0, *)
private struct CascadeStatusCard: View {
    let cascadedWorkCount: Int
    let overriddenWorkCount: Int
    let themeStore: iOS26ThemeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cascade Status")
                .font(.headline)
                .foregroundStyle(themeStore.primaryColor)

            Divider().overlay(Color.primary.opacity(0.3))

            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Applied to \(cascadedWorkCount) books")
                    .foregroundStyle(.primary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Metadata applied to \(cascadedWorkCount) books")

            if overriddenWorkCount > 0 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("\(overriddenWorkCount) books with overrides")
                        .foregroundStyle(.primary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(overriddenWorkCount) books have metadata overrides")
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Author metadata cascade status")
    }
}

/// Lists books by the author, indicating their cascade and override status.
@available(iOS 26.0, *)
private struct BooksListCard: View {
    let authorWorks: [Work]
    let workStatuses: [String: AuthorProfileView.WorkStatus]
    let themeStore: iOS26ThemeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Books by This Author")
                .font(.headline)
                .foregroundStyle(themeStore.primaryColor)

            Divider().overlay(Color.primary.opacity(0.3))

            if authorWorks.isEmpty {
                Text("No books found for this author.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 5)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(authorWorks) { work in
                        BookListItem(
                            work: work,
                            status: workStatuses[work.persistentModelID.hashValue.description] ?? .none
                        )
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("List of books by this author")
    }
}

/// A single item in the books list, showing title and status.
@available(iOS 26.0, *)
private struct BookListItem: View {
    let work: Work
    let status: AuthorProfileView.WorkStatus

    var body: some View {
        Button {
            // Future: Navigate to WorkDetailView
            print("Tapped on work: \(work.title)")
        } label: {
            HStack {
                Text(work.title)
                    .foregroundStyle(.primary)
                Spacer()
                statusIndicator
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(work.title). Status: \(accessibilityStatusDescription)")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch status {
        case .cascaded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Cascaded")
        case .overridden:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityLabel("Overridden")
        case .none:
            EmptyView()
        }
    }

    private var accessibilityStatusDescription: String {
        switch status {
        case .cascaded: return "Metadata cascaded."
        case .overridden: return "Metadata overridden."
        case .none: return "No specific metadata status."
        }
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview("Author Profile View") {
    // Create in-memory container
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Work.self, Author.self, AuthorMetadata.self, WorkOverride.self,
        configurations: config
    )

    // Mock data would be inserted here for preview
    let themeStore = iOS26ThemeStore()

    return NavigationStack {
        AuthorProfileView(authorId: "mock-author-id")
            .modelContainer(container)
            .environment(\.iOS26ThemeStore, themeStore)
    }
}
