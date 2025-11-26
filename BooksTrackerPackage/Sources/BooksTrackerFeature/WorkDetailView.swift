import SwiftUI
import SwiftData

/// Single Book Detail View - iOS 26 Immersive Design
/// Features blurred cover art background with floating metadata card
@available(iOS 26.0, *)
struct WorkDetailView: View {
    @Bindable var work: Work

    @Environment(\.dismiss) private var dismiss
    @Environment(\.iOS26ThemeStore) private var themeStore
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
        ScrollView {
            VStack(spacing: 20) {
                ImmersiveHeaderView(work: work)

                FloatingPillsView(work: work)

                BentoGridView(
                    readingProgress: { ReadingProgressModule(work: work) },
                    readingHabits: { ReadingHabitsModule(work: work) },
                    diversity: { DiversityPreviewModule(work: work) },
                    annotations: { AnnotationsModule(work: work) }
                )

                BookActionsModule(work: work)
                    .padding(.horizontal, 20)
            }
            .padding(.bottom, 40)
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .accessibilityLabel("Back")
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                if work.availableEditions.count > 1 {
                    Button("Editions") {
                        showingEditionPicker.toggle()
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Capsule().fill(.ultraThinMaterial))
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
                    EditionRow(edition: edition, work: work)
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

    private struct EditionRow: View {
        let edition: Edition
        let work: Work

        var body: some View {
            HStack(spacing: 12) {
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

// No replacement