import SwiftUI
import SwiftData

/// SwiftUI component displaying AI-curated weekly book recommendations
///
/// **Features:**
/// - Displays weekly "Staff Picks" with cover, title, authors
/// - Shows AI-generated recommendation reason for each book
/// - Countdown to next refresh
/// - Tap to navigate to book details
/// - Handles loading, error, and empty states
///
/// **Integration Points:**
/// - Service: WeeklyRecommendationsService (actor-isolated)
/// - Navigation: Integrates with SearchView for book details
/// - Theming: Uses iOS26ThemeStore for consistent styling
///
/// **UX Considerations:**
/// - Shows loading skeleton on first load
/// - Gracefully handles 404 (no recommendations yet)
/// - Displays next refresh countdown
/// - Horizontal scroll for recommendations
///
/// See: docs/API_CONTRACT.md Section 6.5.4
@available(iOS 26.0, *)
public struct WeeklyPicksView: View {
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dtoMapper) private var dtoMapper
    
    @State private var recommendations: WeeklyRecommendationsDTO?
    @State private var isLoading = false
    @State private var error: RecommendationsError?
    @State private var service = WeeklyRecommendationsService()
    @State private var selectedBook: RecommendedBookDTO?
    @State private var showingBookDetail = false
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            headerSection
            
            // Content
            if isLoading {
                loadingView
            } else if let error = error {
                errorView(error)
            } else if let recommendations = recommendations {
                recommendationsContent(recommendations)
            } else {
                noRecommendationsView
            }
        }
        .padding(.vertical, 16)
        .task {
            await loadRecommendations()
        }
        .sheet(isPresented: $showingBookDetail) {
            if let book = selectedBook {
                bookDetailSheet(for: book)
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Weekly Picks")
                    .font(.title2.bold())
                    .foregroundStyle(themeStore.primaryColor)
                
                if let recommendations = recommendations {
                    Text("Curated for week of \(formattedWeekDate(recommendations.week_of))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Next refresh countdown
            if let recommendations = recommendations {
                nextRefreshBadge(recommendations.next_refresh)
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(0..<3) { _ in
                    RecommendationCardSkeleton()
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Recommendations Content
    
    private func recommendationsContent(_ data: WeeklyRecommendationsDTO) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(data.books) { book in
                    RecommendationCard(book: book)
                        .onTapGesture {
                            selectedBook = book
                            showingBookDetail = true
                        }
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Error View
    
    private func errorView(_ error: RecommendationsError) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            
            Text(error.errorDescription ?? "Failed to load recommendations")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Try Again") {
                Task {
                    await loadRecommendations(forceRefresh: true)
                }
            }
            .buttonStyle(.bordered)
            .tint(themeStore.primaryColor)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }
    
    // MARK: - No Recommendations View
    
    private var noRecommendationsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            
            Text("Weekly recommendations coming soon")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Text("Check back on Sunday for AI-curated picks")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }
    
    // MARK: - Helper Views
    
    private func nextRefreshBadge(_ nextRefreshISO: String) -> some View {
        Group {
            if let nextRefresh = parseISODate(nextRefreshISO) {
                let timeUntil = nextRefresh.timeIntervalSince(Date())
                if timeUntil > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Next refresh")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(timeUntilString(timeUntil))
                            .font(.caption.bold())
                            .foregroundStyle(themeStore.primaryColor)
                    }
                }
            }
        }
    }
    
    private func bookDetailSheet(for book: RecommendedBookDTO) -> some View {
        NavigationStack {
            VStack(spacing: 20) {
                // TODO: Navigate to full WorkDetailView after fetching full Work data
                Text("Book Detail Placeholder")
                Text("ISBN: \(book.isbn)")
                Text("Title: \(book.title)")
                Text("Authors: \(book.authors.joined(separator: ", "))")
            }
            .navigationTitle("Book Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        showingBookDetail = false
                    }
                }
            }
        }
    }
    
    // MARK: - Data Loading
    
    private func loadRecommendations(forceRefresh: Bool = false) async {
        isLoading = true
        error = nil
        
        do {
            recommendations = try await service.fetchWeeklyRecommendations(forceRefresh: forceRefresh)
            isLoading = false
        } catch let err as RecommendationsError {
            error = err
            isLoading = false
        } catch {
            self.error = .networkError(error)
            isLoading = false
        }
    }
    
    // MARK: - Formatting Helpers
    
    private func formattedWeekDate(_ isoDate: String) -> String {
        guard let date = parseISODate(isoDate) else {
            return isoDate
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func parseISODate(_ isoString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: isoString)
    }
    
    private func timeUntilString(_ timeInterval: TimeInterval) -> String {
        let days = Int(timeInterval / (24 * 60 * 60))
        if days > 0 {
            return "\(days)d"
        }
        let hours = Int(timeInterval / (60 * 60))
        if hours > 0 {
            return "\(hours)h"
        }
        let minutes = Int(timeInterval / 60)
        return "\(minutes)m"
    }
}

// MARK: - Recommendation Card

@available(iOS 26.0, *)
private struct RecommendationCard: View {
    let book: RecommendedBookDTO
    @Environment(\.iOS26ThemeStore) private var themeStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Cover image
            if let coverURL = book.cover_url, let url = URL(string: coverURL) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholderCover
                }
                .frame(width: 140, height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
            } else {
                placeholderCover
                    .frame(width: 140, height: 210)
            }
            
            // Book info
            VStack(alignment: .leading, spacing: 6) {
                Text(book.title)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                Text(book.authors.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                // AI recommendation reason
                Text(book.reason)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 140)
        }
        .frame(width: 140)
    }
    
    private var placeholderCover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(themeStore.primaryColor.opacity(0.1))
            
            Image(systemName: "book.closed")
                .font(.largeTitle)
                .foregroundStyle(themeStore.primaryColor.opacity(0.3))
        }
        .frame(width: 140, height: 210)
    }
}

// MARK: - Loading Skeleton

@available(iOS 26.0, *)
private struct RecommendationCardSkeleton: View {
    @Environment(\.iOS26ThemeStore) private var themeStore
    @State private var isAnimating = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Cover skeleton
            RoundedRectangle(cornerRadius: 12)
                .fill(themeStore.primaryColor.opacity(isAnimating ? 0.1 : 0.2))
                .frame(width: 140, height: 210)
            
            // Info skeleton
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(themeStore.primaryColor.opacity(isAnimating ? 0.1 : 0.2))
                    .frame(width: 120, height: 12)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(themeStore.primaryColor.opacity(isAnimating ? 0.1 : 0.2))
                    .frame(width: 90, height: 10)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(themeStore.primaryColor.opacity(isAnimating ? 0.1 : 0.2))
                    .frame(width: 130, height: 24)
            }
            .frame(width: 140)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Display Mode

@available(iOS 26.0, *)
enum AdaptiveDisplayMode {
    case automatic
    case compact
    case standard
    case detailed
    case hero
}
