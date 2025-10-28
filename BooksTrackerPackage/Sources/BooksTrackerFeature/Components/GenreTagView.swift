import SwiftUI

/// Compact genre/subject tag chips with progressive disclosure
/// Only renders in detailed/hero card modes to preserve compact layouts
@available(iOS 26.0, *)
public struct GenreTagView: View {
    let genres: [String]
    let maxVisible: Int

    @Environment(\.iOS26ThemeStore) private var themeStore

    public init(genres: [String], maxVisible: Int = 2) {
        self.genres = genres
        self.maxVisible = maxVisible
    }

    public var body: some View {
        if !genres.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(genres.prefix(maxVisible).enumerated()), id: \.offset) { index, genre in
                    genreChip(genre)
                }
            }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func genreChip(_ genre: String) -> some View {
        Text(genre)
            .font(.caption2)
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(themeStore.primaryColor.opacity(0.15))
            )
            .lineLimit(1)
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview("Genre Tags") {
    VStack(spacing: 16) {
        // Multiple tags (shows 2)
        GenreTagView(genres: ["Fiction", "Romance", "Historical", "Drama"])

        // Single tag
        GenreTagView(genres: ["Non-Fiction"])

        // Empty array
        GenreTagView(genres: [])
    }
    .padding()
    .iOS26ThemeStore(iOS26ThemeStore())
}
