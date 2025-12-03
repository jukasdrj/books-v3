import SwiftUI
import SwiftData

/// V1.0 Specification: "Floating cover images with a small info card below"
/// Fluid grid layout adapting to screen size (2 columns phone, more on tablet)
@available(iOS 26.0, *)
struct iOS26FloatingBookCard: View {
    let work: Work
    let namespace: Namespace.ID
    let uniqueID: String?  // Optional unique ID for matched geometry (uses work.id if nil)

    @State private var showingQuickActions = false
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.modelContext) private var modelContext

    // Computed property for safe matched geometry ID
    private var matchedGeometryID: String {
        uniqueID ?? "\(work.id)"
    }

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

    var body: some View {
        VStack(spacing: 10) {
            // FLOATING COVER IMAGE (Main V1.0 Requirement)
            floatingCoverImage
                .glassEffectID("cover-\(matchedGeometryID)", in: namespace)

            // SMALL INFO CARD BELOW (V1.0 Requirement)
            smallInfoCard
                .glassEffectID("info-\(matchedGeometryID)", in: namespace)
        }
        // ✅ FIX: Removed .contentShape(Rectangle()) to allow NavigationLink taps through
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

    // MARK: - Floating Cover Image

    private var floatingCoverImage: some View {
        // ✅ FIXED: Uses CoverImageService with Edition → Work fallback logic
        CachedAsyncImage(url: CoverImageService.coverURL(for: work)) { image in
            image
                .resizable()
                .aspectRatio(2/3, contentMode: .fill)
        } placeholder: {
            // Refined Placeholder with Theme Colors
            ZStack {
                Rectangle()
                    .fill(themeStore.primaryColor.gradient.opacity(0.3))
                
                VStack(spacing: 8) {
                    Image(systemName: "book.closed")
                        .font(.largeTitle)
                        .foregroundColor(.white.opacity(0.8))

                    Text(work.title)
                        .font(.caption.bold())
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
        }
        .frame(height: 240) // Consistent card height
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .glassEffect(.regular, tint: .white.opacity(0.1))
        .shadow(
            color: .black.opacity(0.15),
            radius: 12,
            x: 0,
            y: 8
        )
        .overlay(alignment: .topTrailing) {
            // Status indicator overlay
            if let userEntry = userEntry {
                statusIndicator(for: userEntry.readingStatus)
                    .padding(8)
            }
        }
        .overlay(alignment: .topLeading) {
            // Cultural diversity indicator
            if let primaryAuthor = work.primaryAuthor,
               primaryAuthor.representsMarginalizedVoices() {
                culturalDiversityBadge
                    .padding(8)
            }
        }
        .overlay(alignment: .bottom) {
            // Reading progress overlay for active books
            if let userEntry = userEntry,
               userEntry.readingStatus == .reading,
               userEntry.readingProgress > 0 {
                ProgressView(value: userEntry.readingProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .white.opacity(0.8)))
                    .scaleEffect(y: 1.5, anchor: .bottom)
                    .padding(10)
                    .background(.black.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    // MARK: - Refined Small Info Card

    private var smallInfoCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(work.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true) // Prevents text from truncating prematurely

            Text(work.authorNames)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            // Refined metadata row for status and format
            HStack {
                if let userEntry = userEntry {
                    infoCardStatus(for: userEntry.readingStatus)
                }
                
                Spacer()

                if let edition = primaryEdition {
                    // ✅ FIX: Use Image(systemName:) for proper icon display
                    Image(systemName: edition.format.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }

    // MARK: - Status Indicators (Using Shared Components)

    private func statusIndicator(for status: ReadingStatus) -> some View {
        StatusBadgeCircle(status: status)
    }
    
    // ✅ Compact status indicator for the info card
    private func infoCardStatus(for status: ReadingStatus) -> some View {
        StatusBadgeInline(status: status)
    }

    private var culturalDiversityBadge: some View {
        CulturalDiversityBadge(for: work.primaryAuthor)
    }

    // MARK: - Quick Actions

    private var quickActionsMenu: some View {
        Group {
            if let userEntry = userEntry {
                // Status change submenu
                Menu("Change Status", systemImage: "bookmark") {
                    ForEach(ReadingStatus.allCases.filter { $0 != userEntry.readingStatus }, id: \.self) { status in
                        Button(status.displayName, systemImage: status.systemImage) {
                            updateReadingStatus(status)
                        }
                    }
                }

                Divider()

                // Quick rating (if owned)
                if !userEntry.isWishlistItem {
                    Menu("Rate Book", systemImage: "star") {
                        ForEach(1...5, id: \.self) { rating in
                            Button("\(rating) Stars") {
                                setRating(Double(rating))
                            }
                        }
                        Button("Remove Rating") {
                            setRating(0)
                        }
                    }
                }

                Divider()

                Button("Remove from Library", systemImage: "trash", role: .destructive) {
                    removeFromLibrary()
                }
            }
            // ⚠️ REMOVED: Non-functional Add to Library/Wishlist buttons
            // These buttons had no ModelContext and couldn't persist changes
            // For full book details and persistence actions, navigate to WorkDetailView
        }
    }

    private var accessibilityDescription: String {
        BookCardAccessibility.buildDescription(work: work, userEntry: userEntry)
    }

    // MARK: - Actions (Using Shared Helpers)

    private func updateReadingStatus(_ status: ReadingStatus) {
        BookCardActions.updateReadingStatus(status, for: userEntry)
    }

    private func setRating(_ rating: Double) {
        BookCardActions.setRating(rating, for: userEntry)
    }

    // ⚠️ REMOVED: Non-functional addToLibrary() and addToWishlist() functions
    // These functions had no ModelContext and couldn't persist changes
    // For full book details and persistence actions, navigate to WorkDetailView
    // See ISSUE_DEAD_CODE_CARD_PERSISTENCE.md for context

    private func removeFromLibrary() {
        guard let userEntry = userEntry else { return }

        // ✅ FIXED: Use ModelContext.delete() instead of direct relationship mutation
        // Direct mutation of work.userLibraryEntries can crash outside of a transaction
        modelContext.delete(userEntry)

        BookCardActions.triggerNotificationFeedback(.warning)
    }
}

// MARK: - Performance Monitoring Tools

// MARK: - Quick Actions Sheet

@available(iOS 26.0, *)
struct QuickActionsSheet: View {
    let work: Work
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Work info header
                HStack(spacing: 16) {
                    #if os(iOS)
                    CachedAsyncImage(url: work.primaryEdition?.coverImageURL.flatMap(URL.init)) { image in
                        image
                            .resizable()
                            .aspectRatio(2/3, contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(.quaternary)
                    }
                    .frame(width: 60, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    #else
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 60, height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    #endif

                    VStack(alignment: .leading, spacing: 4) {
                        Text(work.title)
                            .font(.headline.bold())
                            .lineLimit(2)

                        Text(work.authorNames)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let year = work.firstPublicationYear {
                            Text("\(year)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                // Info text - actions require full detail view
                Text("Tap the book to view details and manage your library.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()

                Spacer()
            }
            .padding()
            .navigationTitle("Book Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview {
    @Previewable @State var container: ModelContainer = {
        let container = try! ModelContainer(for: Work.self, Author.self)
        let context = container.mainContext

        let author = Author(name: "Mark Twain")
        let work = Work(
            title: "The Adventures of Huckleberry Finn",
            originalLanguage: "English",
            firstPublicationYear: 1884
        )

        context.insert(author)
        context.insert(work)
        work.authors = [author]

        return container
    }()

    let work = try! container.mainContext.fetch(FetchDescriptor<Work>()).first!

    VStack {
        iOS26FloatingBookCard(work: work, namespace: Namespace().wrappedValue, uniqueID: nil)
            .frame(width: 160)

        Spacer()
    }
    .padding()
    .modelContainer(for: [Work.self, Edition.self, UserLibraryEntry.self, Author.self])
}