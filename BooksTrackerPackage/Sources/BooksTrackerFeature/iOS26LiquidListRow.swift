import SwiftUI
import SwiftData

/// Liquid list row with iOS 26 design patterns
/// Optimized for dense information display with smooth interactions
@available(iOS 26.0, *)
struct iOS26LiquidListRow: View {
    let work: Work
    let displayStyle: ListRowStyle

    @Environment(\.iOS26ThemeStore) private var themeStore
    @State private var showingQuickActions = false

    // Current user's library entry for this work
    private var userEntry: UserLibraryEntry? {
        work.userLibraryEntries?.first
    }

    // Primary edition for display
    // ✅ FIXED: Now uses work.primaryEdition which delegates to EditionSelectionStrategy
    // AutoStrategy gives +10 bonus for editions with covers
    private var primaryEdition: Edition? {
        work.primaryEdition
    }

    init(work: Work, displayStyle: ListRowStyle = .standard) {
        self.work = work
        self.displayStyle = displayStyle
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .top, spacing: rowSpacing) {
                // Book cover thumbnail
                coverThumbnail

                // Main content area
                mainContent

                // Trailing accessories
                trailingAccessories
            }

            // Overlay badges (library status + enrichment indicator)
            VStack(alignment: .trailing, spacing: 4) {
                // Library status badge (shows if book is already in library)
                if let entry = userEntry {
                    LibraryStatusBadge(status: entry.readingStatus)
                }

                // Enrichment indicator overlay
                EnrichmentIndicator(workId: work.persistentModelID)
            }
            .padding(8)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background {
            liquidRowBackground
        }
        .contextMenu {
            quickActionsMenu
        }
        .sheet(isPresented: $showingQuickActions) {
            QuickActionsSheet(work: work)
                .presentationDetents([.medium])
                .iOS26SheetGlass()
        }
        // iOS 26 HIG: Accessibility support for context menu
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Long press for quick actions")
        .accessibilityActions {
            if userEntry != nil {
                Button("Mark as Reading") {
                    updateReadingStatus(.reading)
                }
                Button("Mark as Read") {
                    updateReadingStatus(.read)
                }
            }
            // ⚠️ REMOVED: Non-functional Add to Library/Wishlist accessibility actions
            // These actions had no ModelContext and couldn't persist changes
        }
    }

    // MARK: - Cover Thumbnail

    private var coverThumbnail: some View {
        // ✅ FIXED: Uses CoverImageService with Edition → Work fallback logic
        CachedAsyncImage(url: CoverImageService.coverURL(for: work)) { image in
            image
                .resizable()
                .aspectRatio(2/3, contentMode: .fill)
        } placeholder: {
            Rectangle()
                .fill(LinearGradient(
                    colors: [
                        themeStore.primaryColor.opacity(0.3),
                        themeStore.secondaryColor.opacity(0.2)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay {
                    Image(systemName: "book.closed")
                        .font(thumbnailIconFont)
                        .foregroundColor(.white.opacity(0.8))
                }
        }
        .frame(width: thumbnailSize.width, height: thumbnailSize.height)
        .clipShape(RoundedRectangle(cornerRadius: thumbnailCornerRadius))
        .glassEffect(.subtle, tint: themeStore.primaryColor.opacity(0.1))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            // Title and author
            titleAndAuthorSection

            // Metadata row
            if displayStyle != .minimal {
                metadataRow
            }

            // Reading progress (if applicable)
            if let userEntry = userEntry,
               userEntry.readingStatus == .reading,
               userEntry.readingProgress > 0,
               displayStyle == .detailed {
                readingProgressSection(userEntry.readingProgress)
            }

            // ✅ FIXED: Spacer prevents vertical collapse on multi-line titles
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleAndAuthorSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Book title
            Text(work.title)
                .font(titleFont)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(titleLineLimit)
                .multilineTextAlignment(.leading)

            // Author names
            Text(work.authorNames)
                .font(authorFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 12) {
            // Publication year
            if let year = work.firstPublicationYear {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%d", year))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Page count
            if let edition = primaryEdition, let pageCount = edition.pageCount, pageCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "book.pages")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(pageCount)p")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Publisher (if available)
            if let edition = primaryEdition, let publisher = edition.publisher, !publisher.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "building.2")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(publisher)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // Edition format
            if let edition = primaryEdition {
                HStack(spacing: 4) {
                    Image(systemName: edition.format.icon)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(edition.format.shortName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Cultural diversity indicator
            if let primaryAuthor = work.primaryAuthor,
               primaryAuthor.representsMarginalizedVoices() {
                culturalDiversityIndicator
            }

            Spacer()
        }
    }

    private var culturalDiversityIndicator: some View {
        HStack(spacing: 2) {
            Image(systemName: "globe.americas.fill")
                .font(.caption2)
                .foregroundColor(themeStore.culturalColors.international)

            if let region = work.primaryAuthor?.culturalRegion {
                Text(region.emoji)
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            themeStore.culturalColors.international.opacity(0.1),
            in: Capsule()
        )
    }

    private func readingProgressSection(_ progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Progress")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(Int(progress * 100))%")
                    .font(.caption2.bold())
                    .foregroundStyle(.primary)
            }

            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: themeStore.primaryColor))
                .scaleEffect(y: 0.8)
        }
    }

    // MARK: - Trailing Accessories

    private var trailingAccessories: some View {
        VStack(spacing: accessorySpacing) {
            // Status indicator
            if let userEntry = userEntry {
                statusIndicator(for: userEntry.readingStatus)
            }

            // Quick action button
            if displayStyle == .detailed {
                quickActionButton
            }
        }
    }

    private func statusIndicator(for status: ReadingStatus) -> some View {
        Group {
            switch displayStyle {
            case .minimal:
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)

            case .standard:
                VStack(spacing: 2) {
                    Image(systemName: status.systemImage)
                        .font(.caption)
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(status.color, in: Circle())
                        .glassEffect(.subtle, interactive: true)

                    if displayStyle == .standard {
                        Text(status.shortName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

            case .detailed:
                VStack(alignment: .trailing, spacing: 4) {
                    Label(status.displayName, systemImage: status.systemImage)
                        .font(.caption)
                        .foregroundColor(status.color)
                        .labelStyle(.iconOnly)
                        .frame(width: 28, height: 28)
                        .background(status.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        .glassEffect(.subtle, tint: status.color.opacity(0.2))

                    Text(status.shortName)
                        .font(.caption2.bold())
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    private var quickActionButton: some View {
        Button {
            showingQuickActions = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(.quaternary, in: Circle())
                .glassEffect(.subtle, interactive: true)
        }
        .buttonStyle(.plain) // Native press animation
    }

    // MARK: - Background

    private var liquidRowBackground: some View {
        RoundedRectangle(cornerRadius: rowCornerRadius)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: rowCornerRadius)
                    .fill(themeStore.primaryColor.opacity(0.05))
                    .blendMode(.overlay)
            }
            .overlay {
                // Subtle glass reflection
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.2), location: 0),
                        .init(color: .white.opacity(0.05), location: 0.3),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.overlay)
                .clipShape(RoundedRectangle(cornerRadius: rowCornerRadius))
            }
            .overlay {
                RoundedRectangle(cornerRadius: rowCornerRadius)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            }
    }

    // MARK: - Quick Actions

    private var quickActionsMenu: some View {
        Group {
            if userEntry != nil {
                Button("Mark as Reading", systemImage: "book.pages") {
                    updateReadingStatus(.reading)
                }

                Button("Mark as Read", systemImage: "checkmark.circle") {
                    updateReadingStatus(.read)
                }

                Button("Remove from Library", systemImage: "trash", role: .destructive) {
                    removeFromLibrary()
                }
            }
            // ⚠️ REMOVED: Non-functional Add to Library/Wishlist buttons
            // These buttons had no ModelContext and couldn't persist changes
            // For full book details and persistence actions, navigate to WorkDetailView

            Button("View Details", systemImage: "info.circle") {
                // Navigate to detail view
            }
        }
    }

    // MARK: - Helper Properties

    private var accessibilityDescription: String {
        var description = "Book: \(work.title) by \(work.authorNames)"
        if let year = work.firstPublicationYear {
            description += ", Published \(year)"
        }
        if let userEntry = userEntry {
            description += ", Status: \(userEntry.readingStatus.displayName). Already in library."
            if userEntry.readingStatus == .reading && userEntry.readingProgress > 0 {
                description += ", Progress: \(Int(userEntry.readingProgress * 100))%"
            }
        }
        return description
    }

    // MARK: - Style Properties

    private var rowSpacing: CGFloat {
        switch displayStyle {
        case .minimal: return 8
        case .standard: return 12
        case .detailed: return 16
        }
    }

    private var horizontalPadding: CGFloat {
        switch displayStyle {
        case .minimal: return 12
        case .standard: return 16
        case .detailed: return 20
        }
    }

    private var verticalPadding: CGFloat {
        switch displayStyle {
        case .minimal: return 8
        case .standard: return 12
        case .detailed: return 16
        }
    }

    private var thumbnailSize: CGSize {
        switch displayStyle {
        case .minimal: return CGSize(width: 32, height: 48)
        case .standard: return CGSize(width: 48, height: 72)
        case .detailed: return CGSize(width: 60, height: 90)
        }
    }

    private var thumbnailCornerRadius: CGFloat {
        switch displayStyle {
        case .minimal: return 4
        case .standard: return 6
        case .detailed: return 8
        }
    }

    private var thumbnailIconFont: Font {
        switch displayStyle {
        case .minimal: return .caption2
        case .standard: return .caption
        case .detailed: return .body
        }
    }

    private var contentSpacing: CGFloat {
        switch displayStyle {
        case .minimal: return 2
        case .standard: return 4
        case .detailed: return 6
        }
    }

    private var titleFont: Font {
        switch displayStyle {
        case .minimal: return .caption
        case .standard: return .subheadline
        case .detailed: return .headline
        }
    }

    private var authorFont: Font {
        switch displayStyle {
        case .minimal: return .caption2
        case .standard: return .caption
        case .detailed: return .subheadline
        }
    }

    private var titleLineLimit: Int {
        switch displayStyle {
        case .minimal: return 1
        case .standard: return 2
        case .detailed: return 3
        }
    }

    private var accessorySpacing: CGFloat {
        switch displayStyle {
        case .minimal: return 4
        case .standard: return 6
        case .detailed: return 8
        }
    }

    private var rowCornerRadius: CGFloat {
        switch displayStyle {
        case .minimal: return 8
        case .standard: return 12
        case .detailed: return 16
        }
    }

    // MARK: - Actions


    private func triggerHapticFeedback() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }

    private func updateReadingStatus(_ status: ReadingStatus) {
        guard let userEntry = userEntry else { return }

        userEntry.readingStatus = status
        if status == .reading && userEntry.dateStarted == nil {
            userEntry.dateStarted = Date()
        } else if status == .read {
            userEntry.markAsCompleted()
        }
        userEntry.touch()

        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.success)
    }

    // ⚠️ REMOVED: Non-functional addToLibrary() and addToWishlist() functions
    // These functions had no ModelContext and couldn't persist changes
    // For full book details and persistence actions, navigate to WorkDetailView
    // See ISSUE_DEAD_CODE_CARD_PERSISTENCE.md for context

    private func removeFromLibrary() {
        guard userEntry != nil else { return }
        // Remove from SwiftData context
    }
}

// MARK: - List Row Styles

enum ListRowStyle: String, CaseIterable {
    case minimal = "minimal"
    case standard = "standard"
    case detailed = "detailed"

    var displayName: String {
        switch self {
        case .minimal: return "Minimal"
        case .standard: return "Standard"
        case .detailed: return "Detailed"
        }
    }
}

// MARK: - Extensions are now defined in ModelTypes.swift

// MARK: - Preview

@available(iOS 26.0, *)
#Preview {
    @Previewable @State var container: ModelContainer = {
        let container = try! ModelContainer(for: Work.self, Author.self)
        let context = container.mainContext

        let author = Author(name: "Kazuo Ishiguro")
        let work = Work(
            title: "Klara and the Sun",
            originalLanguage: "English",
            firstPublicationYear: 2021
        )

        context.insert(author)
        context.insert(work)
        work.authors = [author]

        return container
    }()

    let sampleWork = try! container.mainContext.fetch(FetchDescriptor<Work>()).first!

    NavigationStack {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(ListRowStyle.allCases, id: \.self) { style in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(style.displayName)
                            .font(.headline.bold())
                            .padding(.horizontal)

                        iOS26LiquidListRow(work: sampleWork, displayStyle: style)
                            .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Liquid List Rows")
        .themedBackground()
        .iOS26NavigationGlass()
    }
    .modelContainer(for: [Work.self, Edition.self, UserLibraryEntry.self, Author.self])
    .iOS26ThemeStore(BooksTrackerFeature.iOS26ThemeStore())
}