import SwiftUI

/// Displays data source attribution for book metadata
/// Shows where the book data originated (Alexandria, Google Books, etc.)
public struct ProviderAttributionView: View {
    let provider: String?
    let cached: Bool?

    public init(provider: String?, cached: Bool? = nil) {
        self.provider = provider
        self.cached = cached
    }

    public var body: some View {
        if let provider = provider {
            HStack(spacing: 4) {
                Image(systemName: sourceIcon(for: provider))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text(sourceDisplayName(for: provider))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if let cached = cached, cached {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(4)
        }
    }

    /// Map provider string to user-friendly display name
    private func sourceDisplayName(for provider: String) -> String {
        let lowercased = provider.lowercased()

        // Handle orchestrated providers
        if lowercased.contains("orchestrated:") {
            let providers = lowercased.replacingOccurrences(of: "orchestrated:", with: "")
                .split(separator: "+")
                .map { $0.capitalized }
                .joined(separator: " + ")
            return providers
        }

        // Handle specific providers
        switch lowercased {
        case "alexandria":
            return "Alexandria"
        case "google-books", "google":
            return "Google Books"
        case "openlibrary":
            return "Open Library"
        case "curated":
            return "Curated Collection"
        case let s where s.starts(with: "trending:"):
            return "Trending"
        case let s where s.starts(with: "v2-unified"):
            return "BooksTrack API"
        default:
            return provider.capitalized
        }
    }

    /// Map provider to appropriate SF Symbol icon
    private func sourceIcon(for provider: String) -> String {
        let lowercased = provider.lowercased()

        switch lowercased {
        case _ where lowercased.contains("alexandria"):
            return "building.columns"
        case _ where lowercased.contains("google"):
            return "magnifyingglass"
        case _ where lowercased.contains("openlibrary"):
            return "books.vertical"
        case _ where lowercased.contains("curated"):
            return "star.fill"
        case _ where lowercased.contains("trending"):
            return "chart.line.uptrend.xyaxis"
        default:
            return "network"
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        ProviderAttributionView(provider: "alexandria", cached: true)
        ProviderAttributionView(provider: "google-books", cached: false)
        ProviderAttributionView(provider: "orchestrated:google+openlibrary")
        ProviderAttributionView(provider: "curated")
        ProviderAttributionView(provider: "trending:lastweek")
    }
    .padding()
}
