import SwiftUI

struct FloatingPillsView: View {
    let work: Work

    private var edition: Edition? {
        work.primaryEdition ?? work.availableEditions.first
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Format Pill
                if let formatName = edition?.format.displayName {
                    InfoPillView(text: formatName, icon: edition?.format.icon)
                }

                // Page Count Pill
                if let pageCount = edition?.pageCount, pageCount > 0 {
                    InfoPillView(text: "\(pageCount) Pages", icon: "book.pages")
                }

                // Publication Year Pill
                if let year = edition?.publicationDate?.prefix(4) {
                    InfoPillView(text: String(year), icon: "calendar")
                }

                // Personal Rating Pill (from user library entry)
                if let entry = work.userLibraryEntries?.first,
                   let rating = entry.personalRating, rating > 0 {
                    let formattedRating = String(format: "%.1f ★", Double(rating))
                    InfoPillView(text: formattedRating, icon: "star.fill")
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(height: 50)
    }
}

// Helper view for individual pills with glass-morphism effect
private struct InfoPillView: View {
    let text: String
    let icon: String?

    var body: some View {
        HStack(spacing: 8) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
            }
            Text(text)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .foregroundColor(.primary)
        .background(
            Capsule().fill(.ultraThinMaterial)
        )
    }
}
