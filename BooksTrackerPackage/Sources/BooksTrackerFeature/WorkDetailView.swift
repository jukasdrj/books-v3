import SwiftUI
import SwiftData

/// Single Book Detail View - iOS 26 Immersive Design
/// Features blurred cover art background with floating metadata card
@available(iOS 26.0, *)
struct WorkDetailView: View {
    @Bindable var work: Work

    @Environment(\.dismiss) private var dismiss
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dtoMapper) private var dtoMapper
    @State private var selectedEdition: Edition?
    @State private var showingEditionPicker = false
    @State private var selectedAuthor: Author?
    @State private var selectedEditionID: PersistentIdentifier?

    // Primary edition for display
    private var primaryEdition: Edition {
        selectedEdition ?? work.primaryEdition ?? work.availableEditions.first ?? placeholderEdition
    }

    // Placeholder edition for works without editions
    private var placeholderEdition: Edition {
        Edition()
    }

    var body: some View {
        ZStack {
            // MARK: - Immersive Background
            immersiveBackground

            // MARK: - Main Content
            mainContent
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 44, height: 44)
                        }
                }
                .accessibilityLabel("Back")
                .accessibilityHint("Return to previous screen")
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                if work.availableEditions.count > 1 {
                    Button("Editions") {
                        showingEditionPicker.toggle()
                    }
                    .foregroundColor(.white)
                    .background {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .frame(height: 32)
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .onAppear {
            selectedEdition = work.primaryEdition
        }
        .sheet(isPresented: $showingEditionPicker) {
            EditionPickerView(
                work: work,
                selectedEdition: Binding(
                    get: { selectedEdition ?? primaryEdition },
                    set: { selectedEdition = $0 }
                )
            )
            .iOS26SheetGlass()
        }
        .sheet(item: $selectedAuthor) { author in
            AuthorSearchResultsView(author: author)
        }
    }

    // MARK: - Immersive Background

    private var immersiveBackground: some View {
        GeometryReader { geometry in
            ZStack {
                // Blurred cover art background
                CachedAsyncImage(url: CoverImageService.coverURL(for: work)) { image in  // ✅ FIXED
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .blur(radius: 20)
                        .overlay {
                            // Color shift overlay
                            LinearGradient(
                                colors: [
                                    themeStore.primaryColor.opacity(0.3),
                                    themeStore.secondaryColor.opacity(0.2),
                                    Color.black.opacity(0.4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                } placeholder: {
                    // Fallback gradient background
                    LinearGradient(
                        colors: [
                            themeStore.primaryColor.opacity(0.6),
                            themeStore.secondaryColor.opacity(0.4),
                            Color.black.opacity(0.8)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Top spacer for navigation bar
                Color.clear.frame(height: 60)

                // MARK: - Book Cover Hero
                bookCoverHero

                // MARK: - Edition Metadata Card
                EditionMetadataView(work: work, edition: primaryEdition)
                    .padding(.horizontal, 20)

                // MARK: - Similar Books Section
                if let dtoMapper = dtoMapper {
                    SimilarBooksSection(
                        sourceWork: work,
                        apiService: BookSearchAPIService(modelContext: modelContext, dtoMapper: dtoMapper)
                    )
                }

                // MARK: - Manual Edition Selection
                if FeatureFlags.shared.coverSelectionStrategy == .manual,
                   let userEntry = work.userEntry,
                   work.availableEditions.count > 1 {
                    editionSelectionSection(userEntry: userEntry)
                        .padding(.horizontal, 20)
                }

                // Bottom padding
                Color.clear.frame(height: 40)
            }
        }
    }

    private var bookCoverHero: some View {
        VStack(spacing: 16) {
            // Large cover image
            CachedAsyncImage(url: CoverImageService.coverURL(for: work)) { image in  // ✅ FIXED
                image
                    .resizable()
                    .aspectRatio(2/3, contentMode: .fill)
                    .frame(width: 200, height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            } placeholder: {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(
                        colors: [
                            themeStore.primaryColor.opacity(0.4),
                            themeStore.secondaryColor.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 200, height: 300)
                    .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: "book.closed")
                                .font(.system(size: 48))
                                .foregroundColor(.white.opacity(0.8))

                            Text(work.title)
                                .font(.headline.bold())
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                                .padding(.horizontal)
                        }
                    }
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            }

            // Work title and author (large, readable)
            VStack(spacing: 8) {
                Text(work.title)
                    .font(.title.bold())
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)

                // Clickable author names
                if let authors = work.authors {
                    HStack(spacing: 8) {
                        ForEach(authors) { author in
                            Button {
                                selectedAuthor = author
                            } label: {
                                HStack(spacing: 4) {
                                    Text(author.name)
                                        .font(.title2)
                                        .foregroundColor(.white)
                                    Image(systemName: "magnifyingglass")
                                        .font(.footnote)
                                        .foregroundColor(.white.opacity(0.9))
                                }
                                .shadow(color: .black.opacity(0.95), radius: 6, x: 0, y: 2)  // Primary shadow for depth
                                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)   // Secondary shadow for WCAG AA contrast
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Manual Edition Selection Section
    private func editionSelectionSection(userEntry: UserLibraryEntry) -> some View {
        GroupBox {
        Picker("Display Edition", selection: $selectedEditionID) {
                ForEach(work.availableEditions) { edition in
                    EditionRow(edition: edition, work: work)
                        .tag(edition.id)
                }
            }
            .pickerStyle(.navigationLink)
        } label: {
            Label("Edition Selection", systemImage: "highlighter")
                .foregroundColor(themeStore.primaryColor)
        }
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
        .onAppear {
            selectedEditionID = userEntry.preferredEdition?.id
        }
        .onChange(of: selectedEditionID) { oldValue, newValue in
            if let newID = newValue {
                userEntry.preferredEdition = work.availableEditions.first { $0.id == newID }
            } else {
                userEntry.preferredEdition = nil  // Clear when no edition selected
            }
        }
    }
}

// MARK: - Edition Picker View

struct EditionPickerView: View {
    let work: Work
    @Binding var selectedEdition: Edition
    @Environment(\.dismiss) private var dismiss
    @Environment(\.iOS26ThemeStore) private var themeStore

    var body: some View {
        NavigationStack {
            List(work.availableEditions, id: \.id) { edition in
                Button(action: {
                    selectedEdition = edition
                    dismiss()
                }) {
                    VStack(alignment: .leading, spacing: 8) {
                        // Edition title or format
                        Text(edition.editionTitle ?? edition.format.displayName)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)

                        // Publisher info
                        if !edition.publisherInfo.isEmpty {
                            Text(edition.publisherInfo)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        // Format and pages
                        HStack {
                            Label(edition.format.displayName, systemImage: edition.format.icon)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let pageCount = edition.pageCountString {
                                Spacer()
                                Text(pageCount)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // ISBN
                        if let isbn = edition.primaryISBN {
                            Text("ISBN: \(isbn)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    edition.id == selectedEdition.id ?
                    Color.blue.opacity(0.1) : Color.clear
                )
            }
            .navigationTitle("Choose Edition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Author Search Results View

/// Dedicated view for displaying search results for a specific author
@available(iOS 26.0, *)
struct AuthorSearchResultsView: View {
    let author: Author

    @Environment(\.dismiss) private var dismiss
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dtoMapper) private var dtoMapper
    @State private var searchModel: SearchModel?
    @State private var selectedBook: SearchResult?

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                themeStore.backgroundGradient
                    .ignoresSafeArea()

                // Content
                Group {
                    if let searchModel = searchModel {
                        switch searchModel.viewState {
                        case .searching:
                            searchingView
                        case .results:
                            resultsView
                        case .noResults:
                            noResultsView
                        case .error:
                            errorView
                        default:
                            searchingView
                        }
                    } else {
                        ProgressView("Loading...")
                    }
                }
            }
            .navigationTitle("Books by \(author.name)")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(themeStore.primaryColor)
                }
            }
            .navigationDestination(item: $selectedBook) { result in
                WorkDiscoveryView(searchResult: result)
            }
            .task {
                // Initialize searchModel with modelContext and environment dtoMapper
                if let dtoMapper = dtoMapper {
                    searchModel = SearchModel(modelContext: modelContext, dtoMapper: dtoMapper)

                    let criteria = AdvancedSearchCriteria()
                    criteria.authorName = author.name
                    searchModel?.advancedSearch(criteria: criteria)
                }
            }
        }
    }

    // MARK: - State Views

    private var searchingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(themeStore.primaryColor)

            Text("Searching for books by \(author.name)...")
                .font(.headline)
                .foregroundStyle(.primary)
        }
    }

    private var resultsView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(searchModel?.viewState.currentResults ?? []) { result in
                    Button {
                        selectedBook = result
                    } label: {
                        iOS26AdaptiveBookCard(
                            work: result.work,
                            displayMode: .standard
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }

    private var noResultsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "books.vertical")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No books found")
                .font(.title2.bold())
                .foregroundStyle(.primary)

            Text("We couldn't find any books by \(author.name)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var errorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.red)

            Text("Search Error")
                .font(.title2.bold())
                .foregroundStyle(.primary)

            if let searchModel = searchModel, case .error(let message, _, _, _) = searchModel.viewState {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button("Try Again") {
                Task {
                    let criteria = AdvancedSearchCriteria()
                    criteria.authorName = author.name
                    searchModel?.advancedSearch(criteria: criteria)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(themeStore.primaryColor)
        }
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview {
    @Previewable @State var container: ModelContainer = {
        let container = try! ModelContainer(for: Work.self, Edition.self, UserLibraryEntry.self, Author.self)
        let context = container.mainContext

        // Sample data
        let author = Author(name: "Kazuo Ishiguro", culturalRegion: .asia)
        let work = Work(
            title: "Klara and the Sun",
            originalLanguage: "English",
            firstPublicationYear: 2021
        )
        let edition = Edition(
            isbn: "9780571364893",
            publisher: "Faber & Faber",
            publicationDate: "2021",
            pageCount: 303,
            format: .hardcover
        )

        context.insert(author)
        context.insert(work)
        context.insert(edition)

        work.authors = [author]
        edition.work = work

        return container
    }()

    let work = try! container.mainContext.fetch(FetchDescriptor<Work>()).first!
    let themeStore = BooksTrackerFeature.iOS26ThemeStore()

    NavigationStack {
        WorkDetailView(work: work)
    }
    .modelContainer(container)
    .environment(\.iOS26ThemeStore, themeStore)
}

// MARK: - EditionRow View
private struct EditionRow: View {
    let edition: Edition
    let work: Work

    var body: some View {
        HStack(spacing: 12) {
            // ✅ FIXED: Uses CoverImageService with Work fallback for edition picker
            CachedAsyncImage(url: CoverImageService.coverURL(for: edition, work: work)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Image(systemName: "book.closed")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 40, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(edition.editionTitle ?? "Edition")
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(edition.publisherInfo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}