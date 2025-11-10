//
//  ManualMatchView.swift
//  BooksTrackerFeature
//
//  Manual search and match selection for books with failed enrichment
//  Integrates with existing SearchModel and DTOMapper infrastructure
//

import SwiftUI
import SwiftData

/// Manual book matching view for failed enrichments
/// Allows users to search and select the correct book when automatic enrichment fails
@MainActor
public struct ManualMatchView: View {
    @Bindable var work: Work
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.dtoMapper) private var dtoMapper
    
    @State private var searchModel: SearchModel?
    @State private var searchText: String = ""
    @State private var searchScope: SearchScope = .all
    @State private var selectedResult: SearchResult?
    @State private var isApplyingMatch = false
    @State private var showingConfirmation = false
    @State private var errorAlert: ErrorAlert?
    
    private struct ErrorAlert: Identifiable {
        let id = UUID()
        let message: String
    }
    
    public init(work: Work) {
        self.work = work
        _searchText = State(initialValue: work.title) // Pre-populate with work title
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                themeStore.backgroundGradient
                    .ignoresSafeArea()
                
                if let searchModel = searchModel {
                    contentView(searchModel: searchModel)
                } else {
                    ProgressView("Initializing search...")
                }
            }
            .navigationTitle("Find Match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                setupSearchModel()
            }
            .confirmationDialog(
                "Replace Book Data?",
                isPresented: $showingConfirmation,
                presenting: selectedResult
            ) { result in
                Button("Replace with This Match", role: .destructive) {
                    Task {
                        await applyMatch(result)
                    }
                }
                Button("Cancel", role: .cancel) {
                    selectedResult = nil
                }
            } message: { result in
                Text("This will replace '\(work.title)' with '\(result.displayTitle)' by \(result.displayAuthors). This action cannot be undone.")
            }
            .alert(item: $errorAlert) { alert in
                Alert(
                    title: Text("Error Saving Match"),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
    
    // MARK: - Content View
    
    @ViewBuilder
    private func contentView(searchModel: SearchModel) -> some View {
        VStack(spacing: 0) {
            // Search header
            searchHeaderView(searchModel: searchModel)
            
            // Search results
            searchResultsView(searchModel: searchModel)
        }
    }
    
    // MARK: - Search Header
    
    private func searchHeaderView(searchModel: SearchModel) -> some View {
        VStack(spacing: 16) {
            // Info banner
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.title2)
                    .foregroundStyle(themeStore.primaryColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Find the Correct Book")
                        .font(.subheadline.weight(.semibold))
                    
                    Text("Search and select the right match for '\(work.title)'")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            }
            
            // Search field
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                
                TextField("Search books...", text: Binding(
                    get: { searchModel.searchText },
                    set: { searchModel.searchText = $0 }
                ))
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .onSubmit {
                    performSearch(searchModel: searchModel)
                }
                
                if !searchModel.searchText.isEmpty {
                    Button {
                        searchModel.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            }
            
            // Search scope picker
            Picker("Search Scope", selection: $searchScope) {
                ForEach(SearchScope.allCases) { scope in
                    Text(scope.displayName).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: searchScope) { _, newScope in
                if !searchModel.searchText.isEmpty {
                    searchModel.search(query: searchModel.searchText, scope: newScope)
                }
            }
        }
        .padding()
    }
    
    // MARK: - Search Results
    
    @ViewBuilder
    private func searchResultsView(searchModel: SearchModel) -> some View {
        switch searchModel.viewState {
        case .loadingTrending:
            searchingStateView

        case .initial:
            initialStateView

        case .searching:
            searchingStateView

        case .results(_, _, let items, _, _):
            resultsListView(items: items)

        case .noResults(let query, _):
            noResultsView(query: query, searchModel: searchModel)

        case .error(let message, _, _, _):
            errorView(message: message, searchModel: searchModel)
        }
    }
    
    // MARK: - State Views
    
    private var initialStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "book.circle")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("Search to Find the Correct Book")
                .font(.title3.weight(.medium))
            
            Text("Enter a title, author, or ISBN to search")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
        }
        .padding()
    }
    
    private var searchingStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Searching...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
        }
    }
    
    private func resultsListView(items: [SearchResult]) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(items) { result in
                    ManualMatchResultRow(result: result) {
                        selectedResult = result
                        showingConfirmation = true
                    }
                    .disabled(isApplyingMatch)
                }
            }
            .padding()
        }
    }
    
    private func noResultsView(query: String, searchModel: SearchModel) -> some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("No Results Found")
                .font(.title3.weight(.medium))
            
            Text("No books found for '\(query)'")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Try Different Search") {
                searchModel.clearSearch()
            }
            .buttonStyle(.borderedProminent)
            .tint(themeStore.primaryColor)
            
            Spacer()
        }
        .padding()
    }
    
    private func errorView(message: String, searchModel: SearchModel) -> some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.orange)
            
            Text("Search Error")
                .font(.title3.weight(.medium))
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Try Again") {
                searchModel.retryLastSearch()
            }
            .buttonStyle(.borderedProminent)
            .tint(themeStore.primaryColor)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Logic
    
    private func setupSearchModel() {
        if searchModel == nil, let dtoMapper = dtoMapper {
            let model = SearchModel(modelContext: modelContext, dtoMapper: dtoMapper)
            searchModel = model
            
            // Auto-trigger initial search with work title
            if !searchText.isEmpty {
                model.searchText = searchText
                model.search(query: searchText, scope: .all)
            }
        }
    }
    
    private func performSearch(searchModel: SearchModel) {
        guard !searchModel.searchText.isEmpty else { return }
        searchModel.search(query: searchModel.searchText, scope: searchScope)
    }
    
    /// Apply the selected match to replace the current work's data
    private func applyMatch(_ result: SearchResult) async {
        isApplyingMatch = true
        
        // Update work with selected result's data
        work.title = result.work.title
        work.originalLanguage = result.work.originalLanguage
        work.firstPublicationYear = result.work.firstPublicationYear
        work.subjectTags = result.work.subjectTags
        
        // Update external IDs for better deduplication
        work.openLibraryID = result.work.openLibraryID
        work.openLibraryWorkID = result.work.openLibraryWorkID
        work.isbndbID = result.work.isbndbID
        work.googleBooksVolumeID = result.work.googleBooksVolumeID
        work.goodreadsID = result.work.goodreadsID
        work.googleBooksVolumeIDs = result.work.googleBooksVolumeIDs
        work.goodreadsWorkIDs = result.work.goodreadsWorkIDs
        work.amazonASINs = result.work.amazonASINs
        work.librarythingIDs = result.work.librarythingIDs
        
        // Update authors - proper SwiftData relationship management
        // Remove existing author relationships (doesn't delete Author entities)
        if let existingAuthors = work.authors {
            for author in existingAuthors {
                author.works?.removeAll { $0 == work }
            }
            work.authors = []
        }
        
        // Add new authors (already inserted in context by SearchResult)
        work.authors = result.authors
        
        // Update/replace editions - copy data, don't reassign entities
        // Keep existing user library entries but update edition metadata
        if let newPrimaryEdition = result.work.primaryEdition {
            if let existingPrimaryEdition = work.primaryEdition {
                // Update existing primary edition with new data (preserves user library entries)
                existingPrimaryEdition.coverImageURL = newPrimaryEdition.coverImageURL
                existingPrimaryEdition.publisher = newPrimaryEdition.publisher
                existingPrimaryEdition.publicationDate = newPrimaryEdition.publicationDate
                existingPrimaryEdition.pageCount = newPrimaryEdition.pageCount
                existingPrimaryEdition.isbn = newPrimaryEdition.isbn
                existingPrimaryEdition.isbns = newPrimaryEdition.isbns
                existingPrimaryEdition.openLibraryID = newPrimaryEdition.openLibraryID
                existingPrimaryEdition.googleBooksVolumeID = newPrimaryEdition.googleBooksVolumeID
            } else {
                // No existing edition - create a new one with matched data
                let newEdition = Edition(
                    isbn: newPrimaryEdition.isbn,
                    publisher: newPrimaryEdition.publisher,
                    publicationDate: newPrimaryEdition.publicationDate,
                    pageCount: newPrimaryEdition.pageCount,
                    format: newPrimaryEdition.format,
                    coverImageURL: newPrimaryEdition.coverImageURL
                )
                newEdition.isbns = newPrimaryEdition.isbns
                newEdition.openLibraryID = newPrimaryEdition.openLibraryID
                newEdition.googleBooksVolumeID = newPrimaryEdition.googleBooksVolumeID
                
                modelContext.insert(newEdition)
                newEdition.work = work
            }
        }
        
        // Mark as user-edited and verified
        work.reviewStatus = .userEdited
        work.synthetic = false // No longer synthetic after manual match
        
        // Save changes
        do {
            try modelContext.save()
            
            // Dismiss view
            isApplyingMatch = false
            dismiss()
            
        } catch {
            // Show error to user
            #if DEBUG
            print("❌ ManualMatchView: Failed to save - \(error)")
            #endif
            errorAlert = ErrorAlert(message: "Failed to save changes: \(error.localizedDescription)")
            isApplyingMatch = false
        }
    }
}

// MARK: - Manual Match Result Row

struct ManualMatchResultRow: View {
    let result: SearchResult
    let onSelect: () -> Void
    
    @Environment(\.iOS26ThemeStore) private var themeStore
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Cover image
                CachedAsyncImage(url: URL(string: result.work.primaryEdition?.coverImageURL ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Image(systemName: "book.closed")
                                .foregroundStyle(.secondary)
                        }
                }
                .frame(width: 60, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // Book info
                VStack(alignment: .leading, spacing: 6) {
                    Text(result.displayTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    
                    Text(result.displayAuthors)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    if let year = result.work.firstPublicationYear {
                        Text("Published \(year)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    
                    // Provider badge
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                        Text(result.provider.uppercased())
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(themeStore.primaryColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background {
                        Capsule()
                            .fill(themeStore.primaryColor.opacity(0.15))
                    }
                }
                
                Spacer()
                
                // Select indicator
                Image(systemName: "arrow.right.circle")
                    .font(.title3)
                    .foregroundStyle(themeStore.primaryColor)
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(themeStore.primaryColor.opacity(0.2), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var container: ModelContainer = {
        do {
            let container = try ModelContainer(for: Work.self, Author.self, Edition.self)
            let context = container.mainContext

            let author = Author(name: "Unknown Author")
            let work = Work(
                title: "Unmatched Book",
                originalLanguage: "English",
                firstPublicationYear: nil
            )
            work.reviewStatus = .needsReview

            context.insert(author)
            context.insert(work)
            work.authors = [author]

            return container
        } catch {
            fatalError("Failed to create preview container: \(error)")
        }
    }()

    let context = container.mainContext
    if let work = try? context.fetch(FetchDescriptor<Work>()).first {
        let dtoMapper = DTOMapper(modelContext: context)

        return AnyView(
            NavigationStack {
                ManualMatchView(work: work)
                    .modelContainer(container)
                    .environment(BooksTrackerFeature.iOS26ThemeStore())
                    .environment(\.dtoMapper, dtoMapper)
            }
        )
    } else {
        return AnyView(Text("Preview failed: No work found"))
    }
}
