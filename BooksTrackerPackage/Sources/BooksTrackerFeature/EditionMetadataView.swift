import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#endif

/// Edition Metadata Card - iOS 26 Liquid Glass Design
/// Displays core bibliographic information and user tracking data
@available(iOS 26.0, *)
struct EditionMetadataView: View {
    @Bindable var work: Work
    let edition: Edition
    @Binding var selectedAuthor: Author?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.iOS26ThemeStore) private var themeStore
    @State private var showingStatusPicker = false
    @State private var showingNotesEditor = false
    @FocusState private var isPageFieldFocused: Bool

    // User's library entry for this work (reactive to SwiftData changes)
    private var libraryEntry: UserLibraryEntry? {
        work.userLibraryEntries?.first
    }

    var body: some View {
        GlassEffectContainer(spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: - Core Metadata Section
                coreMetadataSection

                Divider()
                    .overlay(Color.secondary.opacity(0.3))

                // MARK: - User Tracking Section
                userTrackingSection

                // MARK: - Action Buttons
                actionButtonsSection
            }
            .padding(20)
        }
        .glassEffect(.regular, tint: themeStore.primaryColor.opacity(0.1))
        .onAppear {
            ensureLibraryEntry()
        }
    }

    // MARK: - Core Metadata Section

    private var coreMetadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Work Title
            Text(work.title)
                .font(.headline.bold())
                .foregroundStyle(.primary)
                .lineLimit(3)

            // Clickable Author Names
            if let authors = work.authors {
                ForEach(authors) { author in
                    Button {
                        selectedAuthor = author
                    } label: {
                        Text(author.name)
                            .font(.subheadline)
                            .foregroundStyle(themeStore.primaryColor)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Publisher and Year
            if let publisher = edition.publisher, !publisher.isEmpty {
                BookMetadataRow(icon: "building.2", text: publisher, style: .secondary)
            }

            if let year = edition.publicationDate?.prefix(4) {
                BookMetadataRow(icon: "calendar", text: String(year), style: .secondary)
            }

            // Page Count
            if let pageCount = edition.pageCount, pageCount > 0 {
                BookMetadataRow(icon: "book.pages", text: "\(pageCount) pages", style: .tertiary)
            }

            // Edition Format
            HStack(spacing: 8) {
                Image(systemName: edition.format.icon)
                    .foregroundColor(themeStore.primaryColor)

                Text(edition.format.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Genres
            if !work.subjectTags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Genres")
                        .font(.caption.bold())
                        .foregroundStyle(.primary)

                    GenreTagView(genres: work.subjectTags, maxVisible: 5)
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - User Tracking Section

    private var userTrackingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Reading Status
            readingStatusIndicator

            // User Rating (if book is owned)
            if libraryEntry?.isOwned == true {
                userRatingView
            }

            // Reading Progress (if currently reading)
            if libraryEntry?.readingStatus == .reading {
                readingProgressView
            }

            // Notes Field
            notesSection
        }
    }

    private var readingStatusIndicator: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reading Status")
                .font(.caption.bold())
                .foregroundStyle(.primary)

            Button(action: {
                showingStatusPicker.toggle()
                #if canImport(UIKit)
                triggerHaptic(.light)
                #endif
            }) {
                HStack(spacing: 12) {
                    Image(systemName: currentStatus.systemImage)
                        .foregroundColor(currentStatus.color)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(currentStatus.displayName)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)

                        Text(currentStatus.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(currentStatus.color.opacity(0.1))
                }
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showingStatusPicker) {
            ReadingStatusPicker(
                selectedStatus: Binding(
                    get: { currentStatus },
                    set: { newStatus in
                        updateReadingStatus(to: newStatus)
                    }
                )
            )
            .presentationDetents([.medium])
            .iOS26SheetGlass()
        }
    }

    private var userRatingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Rating")
                .font(.caption.bold())
                .foregroundStyle(.primary)

            StarRatingView(
                rating: Binding(
                    get: { libraryEntry?.personalRating ?? 0 },
                    set: { newRating in
                        guard let entry = libraryEntry else {
                            print("⚠️ Cannot set rating: libraryEntry is nil")
                            return
                        }
                        entry.personalRating = newRating
                        entry.touch()
                        saveContext()
                        print("✅ Rating set to \(newRating) for \(work.title)")
                    }
                )
            )
        }
    }

    private var readingProgressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reading Progress")
                .font(.caption.bold())
                .foregroundStyle(.primary)

            VStack(spacing: 8) {
                ProgressView(value: libraryEntry?.readingProgress ?? 0.0)
                    .tint(themeStore.primaryColor)

                HStack(spacing: 4) {
                    Text("Page")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Editable page number input
                    TextField("0", value: Binding(
                        get: { libraryEntry?.currentPage ?? 0 },
                        set: { newPage in
                            guard let entry = libraryEntry else { return }
                            // Validate against page count
                            if let pageCount = edition.pageCount {
                                entry.currentPage = min(newPage, pageCount)
                            } else {
                                entry.currentPage = newPage
                            }
                            // Auto-calculate progress
                            updateReadingProgress()
                            entry.touch()
                            saveContext()
                        }
                    ), format: .number)
                    #if canImport(UIKit)
                    .keyboardType(.numberPad)
                    #endif
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .multilineTextAlignment(.center)
                    .focused($isPageFieldFocused)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") {
                                isPageFieldFocused = false
                            }
                            .foregroundStyle(themeStore.primaryColor)
                            .font(.headline)
                        }
                    }

                    if let pageCount = edition.pageCount {
                        Text("of \(pageCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Progress percentage
                    if let progress = libraryEntry?.readingProgress {
                        Text("\(Int(progress * 100))%")
                            .font(.caption.bold())
                            .foregroundColor(themeStore.primaryColor)
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Notes")
                .font(.caption.bold())
                .foregroundStyle(.primary)

            Button(action: {
                showingNotesEditor.toggle()
            }) {
                Text(libraryEntry?.notes?.isEmpty == false ? libraryEntry!.notes! : "Add your thoughts...")
                    .font(.subheadline)
                    .foregroundColor(libraryEntry?.notes?.isEmpty == false ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    }
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showingNotesEditor) {
            NotesEditorView(
                notes: Binding(
                    get: { libraryEntry?.notes ?? "" },
                    set: { newNotes in
                        libraryEntry?.notes = newNotes.isEmpty ? nil : newNotes
                        libraryEntry?.touch()
                        saveContext()
                    }
                ),
                workTitle: work.title
            )
            .iOS26SheetGlass()
        }
    }

    // MARK: - Action Buttons

    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            // Delete button (always available)
            Button {
                deleteFromLibrary()
            } label: {
                HStack {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Remove from Library")
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.red)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helper Properties

    private var currentStatus: ReadingStatus {
        libraryEntry?.readingStatus ?? .wishlist
    }

    // MARK: - Setup and State Management

    private func ensureLibraryEntry() {
        // Create wishlist entry if none exists
        if libraryEntry == nil {
            let wishlistEntry = UserLibraryEntry.createWishlistEntry(for: work)
            modelContext.insert(wishlistEntry)
            saveContext()
        }
    }

    private func updateReadingStatus(to newStatus: ReadingStatus) {
        guard let entry = libraryEntry else { return }

        entry.readingStatus = newStatus
        entry.touch()

        // Handle status-specific logic
        switch newStatus {
        case .reading:
            if entry.dateStarted == nil {
                entry.dateStarted = Date()
            }
        case .read:
            entry.markAsCompleted()
        default:
            break
        }

        saveContext()
    }

    private func convertWishlistToOwned() {
        libraryEntry?.acquireEdition(edition, status: .toRead)
        saveContext()
    }

    private func startReading() {
        libraryEntry?.startReading()
        saveContext()
    }

    private func markAsCompleted() {
        libraryEntry?.markAsCompleted()
        saveContext()
    }

    private func updateReadingProgress() {
        guard let entry = libraryEntry, let pageCount = edition.pageCount, pageCount > 0 else { return }
        entry.readingProgress = Double(entry.currentPage) / Double(pageCount)
    }

    private func deleteFromLibrary() {
        guard let entry = libraryEntry else { return }

        // Delete the library entry
        modelContext.delete(entry)

        // If work has no more library entries, delete the work (and cascade to editions/authors)
        if work.userLibraryEntries?.isEmpty == true || work.userLibraryEntries == nil {
            modelContext.delete(work)
        }

        saveContext()
        #if canImport(UIKit)
        triggerHaptic(.medium)
        #endif
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            print("Failed to save context: \(error)")
        }
    }

    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if canImport(UIKit)
        let impactFeedback = UIImpactFeedbackGenerator(style: style)
        impactFeedback.impactOccurred()
        #endif
    }
}

// MARK: - Star Rating View

struct StarRatingView: View {
    @Binding var rating: Double
    @Environment(\.iOS26ThemeStore) private var themeStore

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { star in
                Button(action: {
                    rating = Double(star)
                    #if canImport(UIKit)
                    triggerHaptic(.light)
                    #endif
                }) {
                    Image(systemName: star <= Int(rating) ? "star.fill" : "star")
                        .foregroundColor(star <= Int(rating) ? .yellow : .secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            if rating > 0 {
                Text("\(Int(rating))/5")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
    }

    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if canImport(UIKit)
        let impactFeedback = UIImpactFeedbackGenerator(style: style)
        impactFeedback.impactOccurred()
        #endif
    }
}

// MARK: - Reading Status Picker

struct ReadingStatusPicker: View {
    @Binding var selectedStatus: ReadingStatus
    @Environment(\.dismiss) private var dismiss
    @Environment(\.iOS26ThemeStore) private var themeStore

    var body: some View {
        NavigationStack {
            List(ReadingStatus.allCases, id: \.self) { status in
                Button(action: {
                    selectedStatus = status
                    dismiss()
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: status.systemImage)
                            .foregroundColor(status.color)
                            .font(.title3)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(status.displayName)
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)

                            Text(status.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if status == selectedStatus {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                                .font(.caption.bold())
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Reading Status")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Notes Editor View

struct NotesEditorView: View {
    @Binding var notes: String
    let workTitle: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.iOS26ThemeStore) private var themeStore
    @FocusState private var isTextEditorFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Notes for \(workTitle)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top)

                TextEditor(text: $notes)
                    .focused($isTextEditorFocused)
                    .font(.body)
                    .padding()
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    }
                    .overlay {
                        if notes.isEmpty {
                            VStack {
                                HStack {
                                    Text("Add your thoughts...")
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, 20)
                                        .padding(.top, 8)
                                    Spacer()
                                }
                                Spacer()
                            }
                        }
                    }

                Spacer()
            }
            .padding()
            .navigationTitle("Notes")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .automatic) {
                    Button("Save") {
                        dismiss()
                    }
                    .bold()
                }
            }
            .onAppear {
                isTextEditorFocused = true
            }
        }
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview {
    @Previewable @State var container: ModelContainer = {
        let container = try! ModelContainer(for: Work.self, Edition.self, UserLibraryEntry.self, Author.self)
        let context = container.mainContext

        // Sample data - follow insert-before-relate pattern
        let author = Author(name: "Sample Author")
        let work = Work(title: "Sample Book Title")
        let edition = Edition(isbn: "9780123456789", publisher: "Sample Publisher", publicationDate: "2023", pageCount: 300, work: nil)

        // Insert to get permanent IDs
        context.insert(author)
        context.insert(work)
        context.insert(edition)

        // Set relationships after insert
        work.authors = [author]
        edition.work = work

        return container
    }()
    
    @Previewable @State var selectedAuthor: Author?

    let themeStore = BooksTrackerFeature.iOS26ThemeStore()

    return EditionMetadataView(work: Work(title: "Sample Book"), edition: Edition(), selectedAuthor: $selectedAuthor)
        .modelContainer(container)
        .environment(\.iOS26ThemeStore, themeStore)
        .padding()
        .themedBackground()
}