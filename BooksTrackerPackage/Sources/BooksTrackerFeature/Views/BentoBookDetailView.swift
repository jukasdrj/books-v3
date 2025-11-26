import SwiftUI
import SwiftData

/// Bento Book Detail View - Modular dashboard layout for book metadata
/// Replaces the traditional vertical list with an engaging grid layout
@available(iOS 26.0, *)
public struct BentoBookDetailView: View {
    @Bindable var work: Work
    let edition: Edition
    
    @Environment(\.iOS26ThemeStore) private var themeStore
    
    public init(work: Work, edition: Edition) {
        self.work = work
        self.edition = edition
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Floating pills ribbon
                FloatingPillsView(work: work, edition: edition)
                
                // Bento Grid with 4 modules
                BentoGridView {
                    // Top row: Reading Progress (wide) and Habits (compact)
                    BentoModule(title: "Reading Progress", icon: "book.pages", span: .wide) {
                        ReadingProgressModule(work: work, edition: edition)
                    }
                    
                    BentoModule(title: "Reading Habits", icon: "chart.line.uptrend.xyaxis", span: .single) {
                        ReadingHabitsModule(work: work)
                    }
                    
                    // Bottom row: Diversity (wide) and Annotations (compact)
                    BentoModule(title: "Diversity & Representation", icon: "globe", span: .wide) {
                        DiversityPreviewModule(work: work)
                    }
                    
                    BentoModule(title: "Your Thoughts", icon: "star", span: .single) {
                        AnnotationsModule(work: work)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview("Bento Book Detail View") {
    @Previewable @State var container: ModelContainer = {
        let container = try! ModelContainer(for: Work.self, Edition.self, UserLibraryEntry.self, Author.self, ReadingSession.self)
        let context = container.mainContext
        
        // Create sample data
        let author = Author(name: "Chimamanda Ngozi Adichie")
        let work = Work(title: "Half of a Yellow Sun")
        let edition = Edition(
            isbn: "9780123456789",
            publisher: "Anchor Books",
            publicationDate: "2007",
            pageCount: 435,
            format: .paperback
        )
        let entry = UserLibraryEntry(readingStatus: .reading)
        
        // Insert all models first
        context.insert(author)
        context.insert(work)
        context.insert(edition)
        context.insert(entry)
        
        // Set relationships after insert
        author.culturalRegion = .africa
        author.gender = .female
        work.authors = [author]
        work.originalLanguage = "English"
        edition.work = work
        entry.work = work
        entry.edition = edition
        entry.currentPage = 150
        entry.readingProgress = 0.34
        entry.personalRating = 4.5
        entry.notes = "A powerful story about the Biafran War with beautiful prose..."
        
        // Add reading sessions
        let session1 = ReadingSession(
            date: Calendar.current.date(byAdding: .day, value: -2, to: Date())!,
            durationMinutes: 45,
            startPage: 0,
            endPage: 50
        )
        let session2 = ReadingSession(
            date: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
            durationMinutes: 60,
            startPage: 50,
            endPage: 100
        )
        let session3 = ReadingSession(
            date: Date(),
            durationMinutes: 30,
            startPage: 100,
            endPage: 150
        )
        
        context.insert(session1)
        context.insert(session2)
        context.insert(session3)
        
        session1.entry = entry
        session2.entry = entry
        session3.entry = entry
        
        return container
    }()
    
    let work = try! container.mainContext.fetch(FetchDescriptor<Work>()).first!
    let edition = try! container.mainContext.fetch(FetchDescriptor<Edition>()).first!
    let themeStore = BooksTrackerFeature.iOS26ThemeStore()
    
    NavigationStack {
        BentoBookDetailView(work: work, edition: edition)
            .navigationTitle(work.title)
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }
    .modelContainer(container)
    .environment(\.iOS26ThemeStore, themeStore)
    .themedBackground()
}
