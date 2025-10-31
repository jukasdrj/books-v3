import SwiftUI
import SwiftData

#if canImport(UIKit)

// MARK: - Scan Results View

/// Review and confirm detected books before adding to library
@MainActor
public struct ScanResultsView: View {
    let scanResult: ScanResult?
    let modelContext: ModelContext
    let onDismiss: () -> Void

    @Environment(\.iOS26ThemeStore) private var themeStore
    @State private var resultsModel: ScanResultsModel
    @State private var dismissedSuggestionTypes: Set<String> = []
    @State private var showPhoto = false

    public init(
        scanResult: ScanResult?,
        modelContext: ModelContext,
        onDismiss: @escaping () -> Void
    ) {
        self.scanResult = scanResult
        self.modelContext = modelContext
        self.onDismiss = onDismiss
        self._resultsModel = State(initialValue: ScanResultsModel(scanResult: scanResult))
    }

    private var activeSuggestions: [SuggestionViewModel] {
        (scanResult?.suggestions ?? []).filter { suggestion in
            !dismissedSuggestionTypes.contains(suggestion.type)
        }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                themeStore.backgroundGradient
                    .ignoresSafeArea()

                if let result = scanResult {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Summary card
                            summaryCard(result: result)

                            // Suggestions banner (NEW - between summary and books)
                            suggestionsBanner()

                            // Detected books list
                            detectedBooksList

                            // Add all button
                            if !resultsModel.detectedBooks.isEmpty {
                                addAllButton
                            }

                            // Bottom spacer
                            Color.clear.frame(height: 40)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                    }
                } else {
                    emptyStateView
                }
            }
            .navigationTitle("Scan Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if let image = scanResult?.capturedImage, !resultsModel.detectedBooks.isEmpty {
                        Button(action: { showPhoto = true }) {
                            Image(systemName: "photo.on.rectangle")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
            .sheet(isPresented: $showPhoto) {
                if let image = scanResult?.capturedImage, let books = scanResult?.detectedBooks {
                    BoundingBoxOverlayView(image: image, detectedBooks: books)
                }
            }
            .task {
                await resultsModel.performDuplicateCheck(modelContext: modelContext)
            }
        }
    }

    // MARK: - Summary Card

    private func summaryCard(result: ScanResult) -> some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scan Complete")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Processed in \(String(format: "%.1f", result.totalProcessingTime))s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.green)
            }

            Divider()

            // Statistics
            HStack(spacing: 20) {
                statBadge(
                    value: "\(result.statistics.totalDetected)",
                    label: "Detected",
                    color: .blue
                )

                statBadge(
                    value: "\(result.statistics.withISBN)",
                    label: "With ISBN",
                    color: .green
                )

                statBadge(
                    value: "\(result.statistics.needsReview)",
                    label: "Uncertain",
                    color: .orange
                )
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        }
    }

    private func statBadge(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(color)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Suggestions Banner

    @ViewBuilder
    private func suggestionsBanner() -> some View {
        if !activeSuggestions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(themeStore.primaryColor)
                    Text("Suggestions")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                }

                // Suggestion rows
                ForEach(Array(activeSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 36)
                    }
                    suggestionRow(suggestion)
                }
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(themeStore.primaryColor.opacity(0.3), lineWidth: 1)
                    }
            }
        }
    }

    private func suggestionRow(_ suggestion: SuggestionViewModel) -> some View {
        HStack(spacing: 12) {
            // Severity icon
            Image(systemName: suggestion.iconName)
                .font(.body)
                .foregroundStyle(colorForSeverity(suggestion.severity))
                .frame(width: 24)

            // Message
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let count = suggestion.affectedCount {
                    Text("\(count) book\(count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Dismiss button ("Got it" pattern)
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    _ = dismissedSuggestionTypes.insert(suggestion.type)
                }
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(themeStore.primaryColor.opacity(0.6))
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark \(suggestion.type.replacingOccurrences(of: "_", with: " ")) as understood")
        }
        .padding(.vertical, 8)
    }

    private func colorForSeverity(_ severity: String) -> Color {
        switch severity {
        case "high": return .red
        case "medium": return .orange
        default: return themeStore.primaryColor
        }
    }

    // MARK: - Detected Books List

    private var detectedBooksList: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Detected Books")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(resultsModel.detectedBooks.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(resultsModel.detectedBooks) { book in
                DetectedBookRow(
                    detectedBook: book,
                    onSearch: {
                        await resultsModel.searchBook(book, modelContext: modelContext)
                    },
                    onToggle: {
                        resultsModel.toggleBookSelection(book)
                    }
                )
            }
        }
    }

    // MARK: - Add All Button

    private var addAllButton: some View {
        Button {
            Task {
                await resultsModel.addAllToLibrary(modelContext: modelContext)
                onDismiss()
            }
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)

                Text("Add \(resultsModel.selectedCount) to Library")
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(themeStore.primaryColor.gradient)
            }
        }
        .disabled(resultsModel.selectedCount == 0 || resultsModel.isAdding)
        .opacity((resultsModel.selectedCount == 0 || resultsModel.isAdding) ? 0.5 : 1.0)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No Results")
                .font(.title2.bold())
                .foregroundStyle(.primary)

            Text("No books were detected in the selected photos")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Detected Book Row

struct DetectedBookRow: View {
    let detectedBook: DetectedBook
    let onSearch: () async -> Void
    let onToggle: () -> Void

    @Environment(\.iOS26ThemeStore) private var themeStore
    @State private var isSearching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                // Status icon
                Image(systemName: detectedBook.status.systemImage)
                    .font(.title3)
                    .foregroundStyle(detectedBook.status.color)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    // Title
                    if let title = detectedBook.title {
                        Text(title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                    }

                    // Author
                    if let author = detectedBook.author {
                        Text("by \(author)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // ISBN
                    if let isbn = detectedBook.isbn {
                        HStack(spacing: 4) {
                            Image(systemName: "barcode")
                                .font(.caption2)
                            Text(isbn)
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }

                    // Confidence
                    HStack(spacing: 4) {
                        Text("Confidence:")
                        Text("\(Int(detectedBook.confidence * 100))%")
                            .fontWeight(.medium)
                    }
                    .font(.caption2)
                    .foregroundStyle(detectedBook.confidence >= 0.7 ? .green : .orange)
                }

                Spacer()

                // Selection toggle
                Button {
                    onToggle()
                } label: {
                    Image(systemName: detectedBook.status == .confirmed ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(detectedBook.status == .confirmed ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }

            // Action buttons
            HStack(spacing: 12) {
                // Search button
                Button {
                    Task {
                        isSearching = true
                        await onSearch()
                        isSearching = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isSearching {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                        Text("Search Matches")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        Capsule()
                            .fill(themeStore.primaryColor)
                    }
                }
                .disabled(isSearching)

                // Status badge
                Text(detectedBook.status.displayName)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule()
                            .fill(detectedBook.status.color.opacity(0.2))
                    }
                    .foregroundStyle(detectedBook.status.color)
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            detectedBook.status == .alreadyInLibrary ? Color.orange.opacity(0.5) :
                            detectedBook.status == .confirmed ? Color.green.opacity(0.3) :
                            Color.clear,
                            lineWidth: 2
                        )
                }
        }
    }
}

// MARK: - Scan Results Model

@MainActor
@Observable
class ScanResultsModel {
    var detectedBooks: [DetectedBook]
    var isAdding = false
    var selectedCount: Int {
        detectedBooks.filter { $0.status == .confirmed }.count
    }

    init(scanResult: ScanResult?) {
        self.detectedBooks = scanResult?.detectedBooks ?? []
    }

    // MARK: - Duplicate Detection

    func performDuplicateCheck(modelContext: ModelContext) async {
        for index in detectedBooks.indices {
            let book = detectedBooks[index]

            // Check if already in library
            if await isDuplicate(book, in: modelContext) {
                detectedBooks[index].status = .alreadyInLibrary
            } else if book.confidence >= 0.7 && (book.isbn != nil || (book.title != nil && book.author != nil)) {
                // Auto-select high-confidence books
                detectedBooks[index].status = .confirmed
            }
        }
    }

    private func isDuplicate(_ detectedBook: DetectedBook, in modelContext: ModelContext) async -> Bool {
        // ISBN-first strategy
        if let isbn = detectedBook.isbn, !isbn.isEmpty {
            let descriptor = FetchDescriptor<Edition>(
                predicate: #Predicate<Edition> { edition in
                    edition.isbn == isbn
                }
            )
            if let editions = try? modelContext.fetch(descriptor), !editions.isEmpty {
                return true
            }
        }

        // Title + Author fallback
        if let title = detectedBook.title, let author = detectedBook.author {
            let titleLower = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let authorLower = author.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

            let descriptor = FetchDescriptor<Work>()
            if let allWorks = try? modelContext.fetch(descriptor) {
                return allWorks.contains { work in
                    guard work.userLibraryEntries?.isEmpty == false else { return false }
                    let workTitle = work.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    let workAuthor = work.authorNames.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    return workTitle == titleLower && workAuthor == authorLower
                }
            }
        }

        return false
    }

    // MARK: - Book Search Integration

    @MainActor
    func searchBook(_ detectedBook: DetectedBook, modelContext: ModelContext) async {
        // TODO: Phase 1E - Integrate with BookSearchAPIService
        // For now, just mark as confirmed if not duplicate
        if detectedBook.status != .alreadyInLibrary {
            if let index = detectedBooks.firstIndex(where: { $0.id == detectedBook.id }) {
                detectedBooks[index].status = .confirmed
            }
        }
    }

    func toggleBookSelection(_ detectedBook: DetectedBook) {
        guard let index = detectedBooks.firstIndex(where: { $0.id == detectedBook.id }) else { return }

        // Can't toggle books already in library
        if detectedBooks[index].status == .alreadyInLibrary {
            return
        }

        // Toggle between confirmed and detected
        detectedBooks[index].status = detectedBooks[index].status == .confirmed ? .detected : .confirmed
    }

    // MARK: - Add to Library

    @MainActor
    func addAllToLibrary(modelContext: ModelContext) async {
        isAdding = true

        let confirmedBooks = detectedBooks.filter { $0.status == .confirmed }
        var addedWorks: [Work] = []

        for detectedBook in confirmedBooks {
            // 1. Create Work FIRST (no relationships yet)
            let work = Work(
                title: detectedBook.title ?? "Unknown Title",
                originalLanguage: "English",
                firstPublicationYear: nil
            )

            // Set review status based on confidence threshold (0.60)
            work.reviewStatus = detectedBook.needsReview ? ReviewStatus.needsReview : ReviewStatus.verified

            // Store original image path and bounding box for correction UI
            work.originalImagePath = detectedBook.originalImagePath
            work.boundingBox = detectedBook.boundingBox

            // 2. INSERT Work IMMEDIATELY (gets permanent ID)
            modelContext.insert(work)
            addedWorks.append(work)

            // 3. Create and insert Author BEFORE setting relationship
            if let authorName = detectedBook.author {
                let author = Author(name: authorName)
                modelContext.insert(author)  // ✅ Insert BEFORE relating
                work.authors = [author]      // ✅ Safe - both have permanent IDs
            }

            // 4. Create edition if ISBN available
            if let isbn = detectedBook.isbn {
                let edition = Edition(
                    isbn: isbn,
                    publisher: nil,
                    publicationDate: nil,
                    pageCount: nil,
                    format: .paperback
                    // work parameter removed - set after insert
                )
                modelContext.insert(edition)  // ✅ Insert BEFORE relating

                // ✅ Safe - both have permanent IDs
                edition.work = work
                work.editions = [edition]

                // Create library entry (owned)
                let libraryEntry = UserLibraryEntry.createOwnedEntry(
                    for: work,
                    edition: edition,
                    status: .toRead,
                    context: modelContext
                )
                // Note: libraryEntry already inserted by factory method

            } else {
                // Create wishlist entry (no edition)
                let libraryEntry = UserLibraryEntry.createWishlistEntry(for: work, context: modelContext)
                // Note: libraryEntry already inserted by factory method
            }
        }

        // Save context FIRST to convert temporary IDs to permanent IDs
        do {
            try modelContext.save()

            // Capture permanent IDs AFTER save
            let addedWorkIDs = addedWorks.map { $0.persistentModelID }

            // Enqueue works for background enrichment
            if !addedWorkIDs.isEmpty {
                EnrichmentQueue.shared.enqueueBatch(addedWorkIDs)
                print("📚 Queued \(addedWorkIDs.count) books from scan for background enrichment")

                // Delay enrichment to allow SwiftData to fully persist newly created works
                // Swift 6.2: Use Task.sleep instead of DispatchQueue.asyncAfter for better actor isolation
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    EnrichmentQueue.shared.startProcessing(in: modelContext) { _, _, _ in
                        // Silent background processing - progress shown via EnrichmentProgressBanner
                    }
                }
            }

        } catch {
            print("Failed to save books: \(error)")
        }

        isAdding = false
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview {
    let mockResult = ScanResult(
        detectedBooks: [
            DetectedBook(
                isbn: "9780062073488",
                title: "Murder on the Orient Express",
                author: "Agatha Christie",
                confidence: 0.95,
                boundingBox: CGRect(x: 0, y: 0, width: 0.1, height: 0.3),
                rawText: "Murder on the Orient Express Agatha Christie",
                status: .detected
            ),
            DetectedBook(
                isbn: nil,
                title: "The Great Gatsby",
                author: "F. Scott Fitzgerald",
                confidence: 0.65,
                boundingBox: CGRect(x: 0.1, y: 0, width: 0.1, height: 0.3),
                rawText: "The Great Gatsby F. Scott Fitzgerald",
                status: .uncertain
            )
        ],
        totalProcessingTime: 2.5
    )

    let container = try! ModelContainer(for: Work.self, Edition.self, UserLibraryEntry.self, Author.self)

    ScanResultsView(
        scanResult: mockResult,
        modelContext: container.mainContext,
        onDismiss: {}
    )
    .environment(BooksTrackerFeature.iOS26ThemeStore())
}

#endif  // canImport(UIKit)
