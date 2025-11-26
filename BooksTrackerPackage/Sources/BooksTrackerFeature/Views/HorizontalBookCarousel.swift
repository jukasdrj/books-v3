import SwiftUI

/// Horizontal scrolling carousel for displaying a list of books
struct HorizontalBookCarousel: View {
    let title: String
    let books: [SearchResult]
    @Binding var selectedBook: SearchResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(books) { book in
                        Button(action: {
                            selectedBook = book
                        }) {
                            RemoteBookCover(work: book.work)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

/// A single book cover view for the carousel
struct RemoteBookCover: View {
    let work: Work

    var body: some View {
        CachedAsyncImage(url: CoverImageService.coverURL(for: work)) { image in
            image
                .resizable()
                .aspectRatio(2/3, contentMode: .fill)
                .frame(width: 120, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        } placeholder: {
            RoundedRectangle(cornerRadius: 8)
                .fill(.gray.opacity(0.2))
                .frame(width: 120, height: 180)
                .overlay {
                    Image(systemName: "book.closed")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                }
        }
    }
}

/// Skeleton loader for the horizontal book carousel
struct HorizontalBookCarouselSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(.gray.opacity(0.2))
                .frame(width: 200, height: 24)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(0..<5) { _ in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.gray.opacity(0.2))
                            .frame(width: 120, height: 180)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}
