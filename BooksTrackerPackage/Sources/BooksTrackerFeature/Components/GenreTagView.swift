import SwiftUI

/// Compact genre/subject tag chips with horizontal scrolling
/// Shows up to maxVisible tags in a scrollable row
@available(iOS 26.0, *)
public struct GenreTagView: View {
    let genres: [String]
    let maxVisible: Int
    let style: GenreTagStyle

    @Environment(\.iOS26ThemeStore) private var themeStore

    public enum GenreTagStyle {
        case compact      // For card views - smaller, inline
        case prominent    // For detail view - larger, scrollable row
    }

    public init(genres: [String], maxVisible: Int = 4, style: GenreTagStyle = .compact) {
        self.genres = genres
        self.maxVisible = maxVisible
        self.style = style
    }

    public var body: some View {
        if !genres.isEmpty {
            switch style {
            case .compact:
                compactLayout
            case .prominent:
                prominentLayout
            }
        } else {
            EmptyView()
        }
    }

    // MARK: - Compact Layout (for cards)

    private var compactLayout: some View {
        HStack(spacing: 6) {
            ForEach(Array(genres.prefix(maxVisible).enumerated()), id: \.offset) { _, genre in
                genreChip(genre, size: .small)
            }
            if genres.count > maxVisible {
                Text("+\(genres.count - maxVisible)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(genres.count - maxVisible) more genres")
            }
        }
    }

    // MARK: - Prominent Layout (for detail view)

    private var prominentLayout: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(genres.prefix(maxVisible).enumerated()), id: \.offset) { _, genre in
                    genreChip(genre, size: .large)
                }
                if genres.count > maxVisible {
                    moreChip
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Chip Components

    private enum ChipSize {
        case small, large

        var font: Font {
            switch self {
            case .small: return .caption2
            case .large: return .caption
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .small: return 8
            case .large: return 12
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .small: return 4
            case .large: return 6
            }
        }
    }

    @ViewBuilder
    private func genreChip(_ genre: String, size: ChipSize) -> some View {
        Text(genre)
            .font(size.font.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .stroke(themeStore.primaryColor.opacity(0.2), lineWidth: 0.5)
                    )
            )
            .lineLimit(1)
    }

    private var moreChip: some View {
        Text("+\(genres.count - maxVisible) more")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.secondary.opacity(0.1))
            )
            .accessibilityLabel("\(genres.count - maxVisible) more genres")
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview("Genre Tags - Compact") {
    VStack(spacing: 16) {
        GenreTagView(genres: ["Fiction", "Romance", "Historical", "Drama"], style: .compact)
        GenreTagView(genres: ["Non-Fiction"], style: .compact)
        GenreTagView(genres: [], style: .compact)
    }
    .padding()
    .environment(\.iOS26ThemeStore, BooksTrackerFeature.iOS26ThemeStore())
}

@available(iOS 26.0, *)
#Preview("Genre Tags - Prominent") {
    VStack(spacing: 16) {
        GenreTagView(
            genres: ["Fiction", "Literary Fiction", "Contemporary", "Drama", "Award Winner"],
            maxVisible: 5,
            style: .prominent
        )
        GenreTagView(genres: ["Science Fiction", "Space Opera"], style: .prominent)
    }
    .padding()
    .background(Color.black.opacity(0.8))
    .environment(\.iOS26ThemeStore, BooksTrackerFeature.iOS26ThemeStore())
}
