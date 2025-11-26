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

    public init(work: Work, edition: Edition) {
        self.work = work
        self.edition = edition
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.dtoMapper) private var dtoMapper
    @State private var showingStatusPicker = false
    @State private var showingNotesEditor = false
    @FocusState private var isPageFieldFocused: Bool

    // v2: Reading Session Timer State
    @State private var isSessionActive = false
    @State private var sessionStartTime: Date?
    @State private var currentSessionMinutes: Int = 0
    @State private var showEndSessionSheet = false
    @State private var endingPage: Int = 0
    @State private var showProfilingPrompt = false

    // User's library entry for this work (reactive to SwiftData changes)
    private var libraryEntry: UserLibraryEntry? {
        work.userLibraryEntries?.first
    }

    // Initialize session service
    private func getSessionService() -> ReadingSessionService {
        return ReadingSessionService(modelContext: modelContext)
    }

    var body: some View {
        GlassEffectContainer(spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: - Core Metadata Section
                coreMetadataSection

                Divider()
                    .overlay(Color.secondary.opacity(0.3))

                // MARK: - Diversity Metadata Section
                diversityMetadataSection

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
        .sheet(isPresented: $showProfilingPrompt) {
            ProgressiveProfilingPrompt(work: work, onComplete: {
                #if DEBUG
                print("✅ Progressive profiling completed")
                #endif
            })
            .presentationDetents([.large])
            .iOS26SheetGlass()
        }
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

            // Author Names (informational - interactive version in hero section)
            if let authors = work.authors {
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ForEach(authors) { author in
                        Text(author.name)
                            .font(.subheadline)
                            .foregroundStyle(themeStore.primaryColor)
                        
                        if author != authors.last {
                            Text("•")
                                .foregroundStyle(.secondary)
                        }
                    }
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

    // MARK: - Diversity Metadata Section

    private var diversityMetadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diversity Insights")
                .font(.caption.bold())
                .foregroundStyle(.primary)

            // Own Voices Toggle
            Toggle(isOn: Binding(
                get: { work.isOwnVoices ?? false },
                set: { newValue in
                    work.isOwnVoices = newValue
                    do {
                        try modelContext.save()
                        // Invalidate diversity stats cache
                        DiversityStats.invalidateCache()
                    } catch {
                        #if DEBUG
                        print("❌ Failed to save Own Voices flag: \(error)")
                        #endif
                    }
                }
            )) {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.shield.checkmark.fill")
                        .foregroundColor(themeStore.primaryColor)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Own Voices")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        
                        Text("Author's identity matches subject matter")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .tint(themeStore.primaryColor)

            // Accessibility Tags
            if !work.accessibilityTags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "accessibility")
                            .foregroundColor(themeStore.primaryColor)
                        
                        Text("Accessibility Features")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    
                    FlowLayout(spacing: 6) {
                        ForEach(work.accessibilityTags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background {
                                    Capsule()
                                        .fill(themeStore.primaryColor.opacity(0.15))
                                }
                                .foregroundStyle(themeStore.primaryColor)
                        }
                    }
                }
            }

            // Add Diversity Data Button
            Button(action: {
                showProfilingPrompt = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.caption)
                    
                    Text("Add Diversity Data")
                        .font(.caption)
                }
                .foregroundStyle(themeStore.primaryColor)
            }
            .buttonStyle(.plain)
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

                // v2: Reading Session Timer
                readingSessionTimerView
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
                            #if DEBUG
                            print("⚠️ Cannot set rating: libraryEntry is nil")
                            #endif
                            return
                        }
                        entry.personalRating = newRating
                        entry.touch()
                        saveContext()
                        #if DEBUG
                        print("✅ Rating set to \(newRating) for \(work.title)")
                        #endif
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

    private var readingSessionTimerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reading Session")
                .font(.caption.bold())
                .foregroundStyle(.primary)

            VStack(spacing: 12) {
                // Timer Display
                HStack(spacing: 12) {
                    Image(systemName: isSessionActive ? "timer.circle.fill" : "timer.circle")
                        .foregroundColor(isSessionActive ? themeStore.primaryColor : .secondary)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(isSessionActive ? "Session in Progress" : "No Active Session")
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)

                        if isSessionActive, let startTime = sessionStartTime {
                            Text(formatSessionDuration(startTime: startTime))
                                .font(.caption)
                                .foregroundColor(themeStore.primaryColor)
                        } else {
                            Text("Track your reading time")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding()
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSessionActive ? themeStore.primaryColor.opacity(0.1) : Color(uiColor: .systemBackground).opacity(0.7))
                }

                // Start/Stop Button
                Button(action: {
                    if isSessionActive {
                        showEndSessionSheet = true
                    } else {
                        startSession()
                    }
                }) {
                    HStack {
                        Image(systemName: isSessionActive ? "stop.circle.fill" : "play.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text(isSessionActive ? "End Session" : "Start Session")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isSessionActive ? Color.orange : themeStore.primaryColor)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showEndSessionSheet) {
            EndSessionSheet(
                workTitle: work.title,
                currentPage: libraryEntry?.currentPage ?? 0,
                pageCount: edition.pageCount ?? 0,
                endingPage: $endingPage,
                onSave: {
                    endSession()
                }
            )
            .presentationDetents([.medium])
            .iOS26SheetGlass()
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
                Text(libraryEntry?.notes?.isEmpty == false ? (libraryEntry?.notes ?? "") : "Add your thoughts...")
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
            // Note: Factory method handles insertion into context
            _ = UserLibraryEntry.createWishlistEntry(for: work, context: modelContext)
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
            modelContext.delete(work)  // Cache will auto-clean on next access
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
            #if DEBUG
            print("Failed to save context: \(error)")
            #endif
        }
    }

    // MARK: - Reading Session Methods

    private func startSession() {
        guard let entry = libraryEntry else { return }

        do {
            let service = getSessionService()
            try service.startSession(for: entry)
            isSessionActive = true
            sessionStartTime = Date()
            currentSessionMinutes = 0
            endingPage = entry.currentPage
            #if canImport(UIKit)
            triggerHaptic(.medium)
            #endif
        } catch {
            #if DEBUG
            print("❌ Failed to start session: \(error)")
            #endif
        }
    }

    private func endSession() {
        guard isSessionActive, let _ = libraryEntry else { return }

        // Helper to reset session state
        func resetSessionState() {
            isSessionActive = false
            sessionStartTime = nil
            showEndSessionSheet = false
        }

        do {
            let service = getSessionService()
            let session = try service.endSession(endPage: endingPage)

            // Reset session state
            resetSessionState()

            #if canImport(UIKit)
            triggerHaptic(.heavy)
            #endif

            // Show progressive profiling prompt if session >= 5 minutes
            if session.durationMinutes >= 5 {
                // Delay slightly for better UX (sheet after sheet)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    showProfilingPrompt = true
                }
            }
        } catch {
            resetSessionState()
            #if DEBUG
            print("❌ Failed to end session: \(error)")
            #endif
        }
    }

    private func formatSessionDuration(startTime: Date) -> String {
        let elapsed = Int(Date().timeIntervalSince(startTime))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func triggerHaptic(_ style: UIKit.UIImpactFeedbackGenerator.FeedbackStyle) {
        #if canImport(UIKit)
        let impactFeedback = UIKit.UIImpactFeedbackGenerator(style: style)
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

    private func triggerHaptic(_ style: UIKit.UIImpactFeedbackGenerator.FeedbackStyle) {
        #if canImport(UIKit)
        let impactFeedback = UIKit.UIImpactFeedbackGenerator(style: style)
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

// MARK: - End Session Sheet

struct EndSessionSheet: View {
    let workTitle: String
    let currentPage: Int
    let pageCount: Int
    @Binding var endingPage: Int
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.iOS26ThemeStore) private var themeStore
    @FocusState private var isPageFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)

                    Text("End Reading Session")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)

                    Text("Great job! Update your progress")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top)

                // Page Input
                VStack(alignment: .leading, spacing: 12) {
                    Text("What page did you reach?")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    HStack(spacing: 12) {
                        TextField("Page", value: $endingPage, format: .number)
                            #if canImport(UIKit)
                            .keyboardType(.numberPad)
                            #endif
                            .textFieldStyle(.roundedBorder)
                            .font(.title3)
                            .multilineTextAlignment(.center)
                            .focused($isPageFieldFocused)
                            .frame(maxWidth: 120)

                        if pageCount > 0 {
                            Text("of \(pageCount)")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }

                    // Validation hint
                    if endingPage < currentPage {
                        Label("Page number is less than your current page (\(currentPage))", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else if pageCount > 0 && endingPage > pageCount {
                        Label("Page number exceeds book length (\(pageCount))", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding()
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                }

                Spacer()

                // Save Button
                Button(action: {
                    // Clamp to valid range
                    if pageCount > 0 {
                        endingPage = min(max(endingPage, currentPage), pageCount)
                    }
                    onSave()
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Save Progress")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(themeStore.primaryColor)
                    }
                }
                .buttonStyle(.plain)
                .disabled(endingPage < currentPage)
            }
            .padding()
            .navigationTitle("End Session")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                isPageFieldFocused = true
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
        let edition = Edition(isbn: "9780123456789", publisher: "Sample Publisher", publicationDate: "2023", pageCount: 300)

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

    EditionMetadataView(work: Work(title: "Sample Book"), edition: Edition())
        .modelContainer(container)
        .environment(\.iOS26ThemeStore, themeStore)
        .padding()
        .themedBackground()
}