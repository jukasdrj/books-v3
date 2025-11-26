import SwiftUI
import SwiftData

/// Similar Books Section - Displays horizontally scrolling carousel of similar books
/// Uses vector embeddings from /v1/search/similar endpoint
///
/// **UX Patterns:**
/// - Horizontal scroll carousel with cover images
/// - Loading skeleton while fetching
/// - Empty state when no similar books found
/// - Tap navigates to book detail
@available(iOS 26.0, *)
struct SimilarBooksSection: View {
    let sourceWork: Work
    
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dtoMapper) private var dtoMapper
    
    @State private var similarBooks: [SimilarBooksResponse.SimilarBookItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedBook: SimilarBooksResponse.SimilarBookItem?
    
    private let apiService: BookSearchAPIService
    
    init(sourceWork: Work, apiService: BookSearchAPIService) {
        self.sourceWork = sourceWork
        self.apiService = apiService
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack {
                Label {
                    Text("You Might Also Like")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                } icon: {
                    Image(systemName: "sparkles")
                        .foregroundColor(themeStore.primaryColor)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            
            // Content
            Group {
                if isLoading {
                    loadingView
                } else if let error = errorMessage {
                    errorView(message: error)
                } else if similarBooks.isEmpty {
                    emptyView
                } else {
                    booksCarousel
                }
            }
        }
        .padding(.vertical, 12)
        .task {
            await loadSimilarBooks()
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(0..<5, id: \.self) { _ in
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 100, height: 150)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 100, height: 12)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Books Carousel
    
    private var booksCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(similarBooks) { book in
                    Button {
                        selectedBook = book
                    } label: {
                        VStack(spacing: 8) {
                            // Cover image
                            AsyncImage(url: book.coverUrl.flatMap { URL(string: $0) }) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(2/3, contentMode: .fill)
                                        .frame(width: 100, height: 150)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                                case .failure, .empty:
                                    placeholderCover
                                @unknown default:
                                    placeholderCover
                                }
                            }
                            
                            // Title
                            Text(book.title)
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: 100)
                                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                            
                            // Similarity indicator
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.caption2)
                                Text("\(Int(book.similarityScore * 100))% match")
                                    .font(.caption2)
                            }
                            .foregroundColor(themeStore.primaryColor.opacity(0.9))
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .sheet(item: $selectedBook) { book in
            // Navigate to book detail by searching for the ISBN
            SimilarBookDetailSheet(isbn: book.isbn, title: book.title)
        }
    }
    
    private var placeholderCover: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(LinearGradient(
                colors: [
                    themeStore.primaryColor.opacity(0.4),
                    themeStore.secondaryColor.opacity(0.3)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .frame(width: 100, height: 150)
            .overlay {
                Image(systemName: "book.closed")
                    .font(.title)
                    .foregroundColor(.white.opacity(0.8))
            }
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Empty State
    
    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "books.vertical")
                .font(.title)
                .foregroundStyle(.secondary)
            
            Text("No similar books found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - Error View
    
    private func errorView(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
            
            Text(message)
                .font(.caption)
                .foregroundColor(.white)
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Data Loading
    
    private func loadSimilarBooks() async {
        // Get ISBN from the source work's primary edition
        guard let isbn = sourceWork.primaryEdition?.primaryISBN else {
            // No ISBN available, cannot search for similar books
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await apiService.findSimilarBooks(isbn: isbn, limit: 10)
            await MainActor.run {
                similarBooks = response.results
                isLoading = false
            }
        } catch let error as SearchError {
            await MainActor.run {
                isLoading = false
                // Don't show error for 404 (book not in index) - just show empty state
                if case .httpError(404) = error {
                    errorMessage = nil
                } else {
                    errorMessage = error.errorDescription ?? "Failed to load similar books"
                }
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = "Failed to load similar books"
            }
        }
    }
}

// MARK: - Similar Book Detail Sheet

/// Sheet that displays a book from the similar books results
/// Searches for the full book data using ISBN and shows WorkDetailView
@available(iOS 26.0, *)
private struct SimilarBookDetailSheet: View {
    let isbn: String
    let title: String
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dtoMapper) private var dtoMapper
    
    @State private var searchResult: SearchResult?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                themeStore.backgroundGradient
                    .ignoresSafeArea()
                
                Group {
                    if isLoading {
                        ProgressView("Loading...")
                            .tint(themeStore.primaryColor)
                    } else if let error = errorMessage {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundStyle(.red)
                            
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            
                            Button("Dismiss") {
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(themeStore.primaryColor)
                        }
                        .padding()
                    } else if let result = searchResult {
                        WorkDetailView(work: result.work)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadBookDetails()
            }
        }
    }
    
    private func loadBookDetails() async {
        guard let dtoMapper = dtoMapper else {
            await MainActor.run {
                errorMessage = "Configuration error"
                isLoading = false
            }
            return
        }
        
        let apiService = BookSearchAPIService(modelContext: modelContext, dtoMapper: dtoMapper)
        
        do {
            let response = try await apiService.search(query: isbn, maxResults: 1, scope: .isbn, persist: false)
            await MainActor.run {
                if let first = response.results.first {
                    searchResult = first
                } else {
                    errorMessage = "Book not found"
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load book details"
                isLoading = false
            }
        }
    }
}
