import SwiftUI
import SwiftData

/// Adaptive book card that changes layout based on available space
/// Provides multiple display modes from compact to detailed
@available(iOS 26.0, *)
struct iOS26AdaptiveBookCard: View {
    let work: Work
    let displayMode: AdaptiveDisplayMode

    @Environment(\.iOS26ThemeStore) private var themeStore
    @State private var cardSize: CGSize = .zero
    @State private var showingQuickActions = false

    // Current user's library entry for this work
    private var userEntry: UserLibraryEntry? {
        work.userLibraryEntries?.first
    }

    // Primary edition for display
    private var primaryEdition: Edition? {
        userEntry?.edition ?? work.availableEditions.first
    }

    init(work: Work, displayMode: AdaptiveDisplayMode = .automatic) {
        self.work = work
        self.displayMode = displayMode
    }

    var body: some View {
        GeometryReader { geometry in
            adaptiveContent(for: geometry.size)
                .onAppear {
                    cardSize = geometry.size
                }
                .onChange(of: geometry.size) { _, newSize in
                    cardSize = newSize
                }
        }
        .aspectRatio(cardAspectRatio, contentMode: .fit)
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
            } else {
                Button("Add to Library") {
                    addToLibrary()
                }
                Button("Add to Wishlist") {
                    addToWishlist()
                }
            }
        }
    }

    // MARK: - Adaptive Content

    @ViewBuilder
    private func adaptiveContent(for size: CGSize) -> some View {
        let resolvedMode = resolveDisplayMode(for: size)

        switch resolvedMode {
        case .automatic:
            standardCard // Fallback, though this shouldn't happen
        case .compact:
            compactCard
        case .standard:
            standardCard
        case .detailed:
            detailedCard
        case .hero:
            heroCard
        }
    }

    private func resolveDisplayMode(for size: CGSize) -> AdaptiveDisplayMode {
        if displayMode != .automatic {
            return displayMode
        }

        // Auto-determine based on available space
        let area = size.width * size.height
        let width = size.width

        if area > 50000 || width > 300 {
            return .hero
        } else if area > 25000 || width > 200 {
            return .detailed
        } else if area > 15000 || width > 150 {
            return .standard
        } else {
            return .compact
        }
    }

    // MARK: - Card Variants

    private var compactCard: some View {
        VStack(spacing: 8) {
            // Compact cover with minimal details
            coverImage
                .frame(height: 120)
                .glassEffect(.subtle, tint: themeStore.primaryColor.opacity(0.1))

            VStack(spacing: 4) {
                Text(work.title)
                    .font(.caption.bold())
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                if let userEntry = userEntry {
                    statusIndicator(for: userEntry.readingStatus, style: .minimal)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var standardCard: some View {
        VStack(spacing: 12) {
            // Standard floating cover
            ZStack {
                coverImage
                    .frame(height: 180)
                    .glassEffect(.regular, tint: themeStore.primaryColor.opacity(0.1))

                // Overlay indicators
                cardOverlays
            }

            // Info section
            VStack(alignment: .leading, spacing: 6) {
                Text(work.title)
                    .font(.subheadline.bold())
                    .lineLimit(2)

                authorNavigationButton(font: .caption, lineLimit: 1)

                if let userEntry = userEntry {
                    statusIndicator(for: userEntry.readingStatus, style: .standard)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onLongPressGesture {
            showingQuickActions = true
            triggerHapticFeedback()
        }
    }

    private var detailedCard: some View {
        VStack(spacing: 16) {
            // Large cover with enhanced effects
            ZStack {
                coverImage
                    .frame(height: 220)
                    .glassEffect(.prominent, tint: themeStore.primaryColor.opacity(0.15))
                    .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)

                cardOverlays
            }

            // Detailed info section
            VStack(alignment: .leading, spacing: 8) {
                Text(work.title)
                    .font(.headline.bold())
                    .lineLimit(2)

                authorNavigationButton(font: .subheadline, lineLimit: 1)

                if let year = work.firstPublicationYear {
                    BookMetadataRow(icon: "calendar", text: "\(year)", style: .secondary)
                }

                HStack {
                    if let userEntry = userEntry {
                        statusIndicator(for: userEntry.readingStatus, style: .detailed)
                    }

                    Spacer()

                    if let edition = primaryEdition {
                        Label(edition.format.displayName, systemImage: edition.format.icon)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if !work.subjectTags.isEmpty {
                    GenreTagView(genres: work.subjectTags, maxVisible: 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onLongPressGesture {
            showingQuickActions = true
            triggerHapticFeedback()
        }
    }

    private var heroCard: some View {
        VStack(spacing: 20) {
            // Hero cover with premium effects
            ZStack {
                coverImage
                    .frame(height: 280)
                    .glassEffect(.prominent, tint: themeStore.primaryColor.opacity(0.2))
                    .shadow(color: themeStore.primaryColor.opacity(0.3), radius: 20, x: 0, y: 12)
                    .overlay {
                        // Premium glass reflection
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.3), location: 0),
                                .init(color: .clear, location: 0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                        .blendMode(.overlay)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                cardOverlays
            }

            // Premium info section
            VStack(alignment: .leading, spacing: 12) {
                Text(work.title)
                    .font(.title3.bold())
                    .lineLimit(3)

                authorNavigationButton(font: .body, lineLimit: 2)

                HStack(spacing: 12) {
                    if let year = work.firstPublicationYear {
                        BookMetadataRow(icon: "calendar", text: "\(year)", style: .secondary)
                    }

                    if let edition = primaryEdition {
                        Label(edition.format.displayName, systemImage: edition.format.icon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !work.subjectTags.isEmpty {
                    GenreTagView(genres: work.subjectTags, maxVisible: 2)
                }

                if let userEntry = userEntry {
                    statusIndicator(for: userEntry.readingStatus, style: .premium)
                } else {
                    // Add to library button
                    Button("Add to Library") {
                        addToLibrary()
                    }
                    .buttonStyle(.glassProminent)
                    .tint(themeStore.primaryColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onLongPressGesture {
            showingQuickActions = true
            triggerHapticFeedback()
        }
    }

    // MARK: - Shared Components

    private var coverImage: some View {
        CachedAsyncImage(url: primaryEdition?.coverImageURL.flatMap(URL.init)) { image in
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
                    VStack(spacing: 8) {
                        Image(systemName: "book.closed")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.8))

                        Text(work.title)
                            .font(.caption.bold())
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.black.opacity(0.4)) // ✅ WCAG AA: Dark scrim for contrast on light gradients
                            )
                    }
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var cardOverlays: some View {
        VStack {
            HStack {
                // Cultural diversity indicator
                if let primaryAuthor = work.primaryAuthor,
                   primaryAuthor.representsMarginalizedVoices() {
                    culturalDiversityBadge
                }

                Spacer()

                // Status indicator
                if let userEntry = userEntry {
                    statusBadge(for: userEntry.readingStatus)
                }
            }

            Spacer()

            // Reading progress
            if let userEntry = userEntry,
               userEntry.readingStatus == .reading,
               userEntry.readingProgress > 0 {
                readingProgressBar(userEntry.readingProgress)
            }
        }
        .padding(12)
    }

    private var culturalDiversityBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "globe.americas.fill")
                .font(.caption2)
                .foregroundColor(.white)

            if let region = work.primaryAuthor?.culturalRegion {
                Text(region.emoji)
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
        .glassEffect(.subtle, tint: .white.opacity(0.2))
    }

    private func statusBadge(for status: ReadingStatus) -> some View {
        Circle()
            .fill(status.color)
            .frame(width: 20, height: 20)
            .overlay {
                Image(systemName: status.systemImage)
                    .font(.caption2.bold())
                    .foregroundColor(.white)
            }
            .glassEffect(.subtle, interactive: true)
    }

    private func readingProgressBar(_ progress: Double) -> some View {
        ProgressView(value: progress)
            .progressViewStyle(LinearProgressViewStyle(tint: .white))
            .scaleEffect(y: 1.5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 3))
    }

    /// Reusable author navigation button with consistent behavior
    /// - Parameters:
    ///   - font: Text font for author name
    ///   - lineLimit: Max lines for author name
    @ViewBuilder
    private func authorNavigationButton(font: Font, lineLimit: Int) -> some View {
        Button {
            NotificationCoordinator.postSearchForAuthor(authorName: work.primaryAuthorName)
        } label: {
            HStack(spacing: 4) {
                Text(work.authorNames)
                    .font(font)
                    .foregroundStyle(.secondary)
                    .lineLimit(lineLimit)

                Image(systemName: "chevron.forward")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Status Indicators

    private func statusIndicator(for status: ReadingStatus, style: StatusIndicatorStyle) -> some View {
        Group {
            switch style {
            case .minimal:
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)

            case .standard:
                Label(status.displayName, systemImage: status.systemImage)
                    .font(.caption2)
                    .foregroundColor(status.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(status.color.opacity(0.15), in: Capsule())

            case .detailed:
                HStack(spacing: 6) {
                    Image(systemName: status.systemImage)
                        .font(.caption)
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(status.color, in: Circle())

                    Text(status.displayName)
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                }

            case .premium:
                Button(status.displayName) {
                    // Quick status change
                }
                .buttonStyle(.glass)
                .tint(status.color)
            }
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
            } else {
                Button("Add to Library", systemImage: "plus.circle") {
                    addToLibrary()
                }

                Button("Add to Wishlist", systemImage: "heart") {
                    addToWishlist()
                }
            }

            Button("View Details", systemImage: "info.circle") {
                // Navigate to detail view
            }
        }
    }

    // MARK: - Helper Properties

    private var accessibilityDescription: String {
        var description = "Book: \(work.title) by \(work.authorNames)"
        if let userEntry = userEntry {
            description += ", Status: \(userEntry.readingStatus.displayName)"
            if userEntry.readingStatus == .reading && userEntry.readingProgress > 0 {
                description += ", Progress: \(Int(userEntry.readingProgress * 100))%"
            }
        }
        return description
    }

    private var cardAspectRatio: CGFloat {
        let resolvedMode = resolveDisplayMode(for: cardSize)

        switch resolvedMode {
        case .automatic: return 0.65   // Fallback to standard
        case .compact: return 0.75     // More vertical
        case .standard: return 0.65    // Standard book card ratio
        case .detailed: return 0.6     // More space for details
        case .hero: return 0.55        // Premium spacing
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

    // TODO: Fix non-functional buttons (see .github/ISSUE_DEAD_CODE_CARD_PERSISTENCE.md)
    // These functions create entries but have no modelContext to save them
    private func addToLibrary() {
        // DISABLED: No modelContext available in this view
        // See GitHub issue for proper implementation
        print("⚠️ addToLibrary() called but not implemented - no persistence")
    }

    private func addToWishlist() {
        // DISABLED: No modelContext available in this view
        // See GitHub issue for proper implementation
        print("⚠️ addToWishlist() called but not implemented - no persistence")
    }

    private func removeFromLibrary() {
        guard userEntry != nil else { return }
        // Remove from SwiftData context
    }
}

// MARK: - Supporting Types

enum AdaptiveDisplayMode: String, CaseIterable {
    case automatic = "automatic"
    case compact = "compact"
    case standard = "standard"
    case detailed = "detailed"
    case hero = "hero"

    var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .compact: return "Compact"
        case .standard: return "Standard"
        case .detailed: return "Detailed"
        case .hero: return "Hero"
        }
    }
}

enum StatusIndicatorStyle {
    case minimal
    case standard
    case detailed
    case premium
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview {
    @Previewable @State var container: ModelContainer = {
        let container = try! ModelContainer(for: Work.self, Author.self)
        let context = container.mainContext

        let author = Author(name: "Taylor Jenkins Reid")
        let work = Work(
            title: "The Seven Husbands of Evelyn Hugo",
            originalLanguage: "English",
            firstPublicationYear: 2017
        )

        context.insert(author)
        context.insert(work)
        work.authors = [author]

        return container
    }()

    let sampleWork = try! container.mainContext.fetch(FetchDescriptor<Work>()).first!

    ScrollView {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 20) {
            ForEach(AdaptiveDisplayMode.allCases.dropFirst(), id: \.self) { mode in
                VStack {
                    Text(mode.displayName)
                        .font(.caption.bold())

                    iOS26AdaptiveBookCard(work: sampleWork, displayMode: mode)
                        .frame(height: 300)
                }
            }
        }
        .padding()
    }
    .themedBackground()
    .modelContainer(for: [Work.self, Edition.self, UserLibraryEntry.self, Author.self])
    .iOS26ThemeStore(BooksTrackerFeature.iOS26ThemeStore())
}