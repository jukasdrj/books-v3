import SwiftUI

struct WeeklyPicksView: View {
    @State private var recommendationsResponse: WeeklyRecommendationsResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let recommendationsService: WeeklyRecommendationsService

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    init(recommendationsService: WeeklyRecommendationsService = WeeklyRecommendationsService()) {
        self.recommendationsService = recommendationsService
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Weekly Picks")
                .font(.headline)
                .padding(.horizontal)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else if let recommendationsResponse = recommendationsResponse {
                VStack(alignment: .leading, spacing: 4) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(recommendationsResponse.books) { book in
                                NavigationLink(value: book) {
                                    BookRecommendationCard(book: book)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }

                    Text("Next refresh on \(recommendationsResponse.nextRefresh, formatter: Self.dateFormatter)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
            }
        }
        .task {
            await loadRecommendations()
        }
        // NOTE: navigationDestination for WeeklyRecommendation is in SearchView.swift
        // because this view is inside a LazyVStack which ignores nested navigationDestination
    }

    private func loadRecommendations() async {
        do {
            let response = try await recommendationsService.fetchWeeklyRecommendations()
            recommendationsResponse = response
        } catch let error as WeeklyRecommendationsService.APIError {
            switch error {
            case .noRecommendations:
                errorMessage = "No recommendations available this week. Check back next week!"
            default:
                errorMessage = "Failed to load recommendations."
            }
        } catch {
            errorMessage = "An unexpected error occurred."
        }
        isLoading = false
    }
}

struct BookRecommendationCard: View {
    let book: WeeklyRecommendation

    var body: some View {
        VStack(alignment: .leading) {
            CachedAsyncImage(url: book.coverURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } placeholder: {
                Rectangle()
                    .foregroundColor(.gray.opacity(0.3))
            }
            .frame(width: 120, height: 180)
            .cornerRadius(8)

            Text(book.title)
                .font(.subheadline)
                .fontWeight(.bold)
                .lineLimit(2)

            Text(book.authors.joined(separator: ", "))
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Text(book.reason)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)
                .padding(.top, 2)
        }
        .frame(width: 120)
    }
}
