import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#endif

/// Annotations & Rating Module - User profile and notes
/// Bottom-right module in Bento Grid (compact layout)
@available(iOS 26.0, *)
public struct AnnotationsModule: View {
    @Bindable var work: Work
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.iOS26ThemeStore) private var themeStore
    @State private var showingNotesEditor = false
    
    private var libraryEntry: UserLibraryEntry? {
        work.userLibraryEntries?.first
    }
    
    public init(work: Work) {
        self.work = work
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // User rating
            if let entry = libraryEntry, entry.isOwned {
                // Rating stars
                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { star in
                        Button(action: {
                            updateRating(to: Double(star))
                        }) {
                            Image(systemName: star <= Int(entry.personalRating ?? 0) ? "star.fill" : "star")
                                .foregroundColor(star <= Int(entry.personalRating ?? 0) ? .yellow : .secondary)
                                .font(.body)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                if let rating = entry.personalRating, rating > 0 {
                    Text("\(String(format: "%.1f", rating))/5")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Notes link
            Button(action: {
                showingNotesEditor = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: hasNotes ? "note.text" : "note.text.badge.plus")
                        .foregroundStyle(hasNotes ? themeStore.primaryColor : .secondary)
                        .font(.title3)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hasNotes ? "Your Notes" : "Add Notes")
                            .font(.caption.bold())
                            .foregroundStyle(.primary)
                        
                        if hasNotes, let preview = notesPreview {
                            Text(preview)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        } else {
                            Text("Tap to write")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(hasNotes ? themeStore.primaryColor.opacity(0.08) : Color(uiColor: .systemBackground).opacity(0.5))
            }
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
    
    private var hasNotes: Bool {
        guard let notes = libraryEntry?.notes else { return false }
        return !notes.isEmpty
    }
    
    private var notesPreview: String? {
        guard let notes = libraryEntry?.notes, !notes.isEmpty else { return nil }
        return String(notes.prefix(50))
    }
    
    private func updateRating(to newRating: Double) {
        guard let entry = libraryEntry else { return }
        entry.personalRating = newRating
        entry.touch()
        saveContext()
        #if canImport(UIKit)
        triggerHaptic(.light)
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
    
    private func triggerHaptic(_ style: UIKit.UIImpactFeedbackGenerator.FeedbackStyle) {
        #if canImport(UIKit)
        let impactFeedback = UIKit.UIImpactFeedbackGenerator(style: style)
        impactFeedback.impactOccurred()
        #endif
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview("Annotations Module") {
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
        let entry = UserLibraryEntry(readingStatus: .read)
        
        context.insert(work)
        context.insert(edition)
        context.insert(entry)
        
        edition.work = work
        entry.work = work
        entry.edition = edition
        entry.personalRating = 4.5
        entry.notes = "This is a wonderful book with great insights about..."
        
        return container
    }()
    
    let work = try! container.mainContext.fetch(FetchDescriptor<Work>()).first!
    let themeStore = BooksTrackerFeature.iOS26ThemeStore()
    
    BentoModule(title: "Your Thoughts", icon: "star") {
        AnnotationsModule(work: work)
    }
    .modelContainer(container)
    .environment(\.iOS26ThemeStore, themeStore)
    .padding()
    .themedBackground()
}
