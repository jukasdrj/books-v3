import SwiftUI
import SwiftData

/// Floating Pills - Horizontal Ribbon of Quick Facts
/// Glass-morphism pills inspired by iOS Control Center
@available(iOS 26.0, *)
public struct FloatingPillsView: View {
    @Bindable var work: Work
    let edition: Edition
    
    @Environment(\.iOS26ThemeStore) private var themeStore
    
    public init(work: Work, edition: Edition) {
        self.work = work
        self.edition = edition
    }
    
    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // Format pill
                if edition.format != .unknown {
                    QuickFactPill(
                        icon: edition.format.icon,
                        text: edition.format.displayName
                    )
                }
                
                // Page count pill
                if let pageCount = edition.pageCount, pageCount > 0 {
                    QuickFactPill(
                        icon: "book.pages",
                        text: "\(pageCount) Pages"
                    )
                }
                
                // Publication year pill
                if let year = edition.publicationYear {
                    QuickFactPill(
                        icon: "calendar",
                        text: year
                    )
                }
                
                // Average rating pill (if available)
                if let rating = work.userEntry?.personalRating, rating > 0 {
                    QuickFactPill(
                        icon: "star.fill",
                        text: String(format: "%.1f ★", rating),
                        color: .yellow
                    )
                }
                
                // Series position pill
                if let seriesInfo = seriesText {
                    QuickFactPill(
                        icon: "books.vertical",
                        text: seriesInfo
                    )
                }
                
                // Ownership status pill
                if let entry = work.userEntry {
                    QuickFactPill(
                        icon: entry.readingStatus.systemImage,
                        text: entry.readingStatus.displayName,
                        color: entry.readingStatus.color
                    )
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(height: 44)
    }
    
    private var seriesText: String? {
        // For now, return nil (series data not yet in model)
        // TODO: Add when series support is implemented
        return nil
    }
}

/// Single pill in the floating ribbon
@available(iOS 26.0, *)
private struct QuickFactPill: View {
    let icon: String
    let text: String
    var color: Color = .white
    
    @Environment(\.iOS26ThemeStore) private var themeStore
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2.bold())
                .foregroundStyle(pillColor)
            
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(pillColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
        }
        .overlay {
            Capsule()
                .strokeBorder(pillColor.opacity(0.3), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
    
    private var pillColor: Color {
        // Use custom color if provided, otherwise use theme color
        if color == .white {
            return themeStore.primaryColor
        }
        return color
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview("Floating Pills") {
    @Previewable @State var container: ModelContainer = {
        let container = try! ModelContainer(for: Work.self, Edition.self, UserLibraryEntry.self, Author.self)
        let context = container.mainContext
        
        let work = Work(title: "Sample Book")
        let edition = Edition(
            isbn: "9780123456789",
            publisher: "Sample Publisher",
            publicationDate: "2023",
            pageCount: 350,
            format: .hardcover
        )
        let entry = UserLibraryEntry(readingStatus: .reading)
        
        context.insert(work)
        context.insert(edition)
        context.insert(entry)
        
        edition.work = work
        entry.work = work
        entry.edition = edition
        entry.personalRating = 4.5
        
        return container
    }()
    
    let work = try! container.mainContext.fetch(FetchDescriptor<Work>()).first!
    let edition = try! container.mainContext.fetch(FetchDescriptor<Edition>()).first!
    let themeStore = BooksTrackerFeature.iOS26ThemeStore()
    
    VStack(spacing: 20) {
        FloatingPillsView(work: work, edition: edition)
        
        Text("Pills adapt to available data")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .modelContainer(container)
    .environment(\.iOS26ThemeStore, themeStore)
    .padding()
    .themedBackground()
}
