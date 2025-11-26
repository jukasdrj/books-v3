import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#endif

/// Reading Progress Module - Large progress bar with timer controls
/// Top-left module in Bento Grid (wide layout)
@available(iOS 26.0, *)
public struct ReadingProgressModule: View {
    @Bindable var work: Work
    let edition: Edition
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.iOS26ThemeStore) private var themeStore
    
    // Reading session timer state
    @State private var isSessionActive = false
    @State private var sessionStartTime: Date?
    @State private var currentSessionMinutes: Int = 0
    @State private var showEndSessionSheet = false
    @State private var endingPage: Int = 0
    @State private var showProfilingPrompt = false
    
    private var libraryEntry: UserLibraryEntry? {
        work.userLibraryEntries?.first
    }
    
    private func getSessionService() -> ReadingSessionService {
        return ReadingSessionService(modelContext: modelContext)
    }
    
    public init(work: Work, edition: Edition) {
        self.work = work
        self.edition = edition
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Progress bar
            if let entry = libraryEntry, entry.readingStatus == .reading {
                VStack(spacing: 8) {
                    ProgressView(value: entry.readingProgress)
                        .tint(themeStore.primaryColor)
                        .frame(height: 8)
                    
                    HStack {
                        Text("Page \(entry.currentPage)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        if let pageCount = edition.pageCount {
                            Text("of \(pageCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Text("\(Int(entry.readingProgress * 100))%")
                            .font(.caption.bold())
                            .foregroundStyle(themeStore.primaryColor)
                    }
                }
                
                // Timer display
                HStack(spacing: 12) {
                    Image(systemName: isSessionActive ? "timer.circle.fill" : "timer.circle")
                        .foregroundColor(isSessionActive ? themeStore.primaryColor : .secondary)
                        .font(.title3)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isSessionActive ? "Session in Progress" : "No Active Session")
                            .font(.caption.bold())
                            .foregroundStyle(.primary)
                        
                        if isSessionActive, let startTime = sessionStartTime {
                            Text(formatSessionDuration(startTime: startTime))
                                .font(.caption2)
                                .foregroundColor(themeStore.primaryColor)
                        } else {
                            Text("Track your reading time")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                }
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSessionActive ? themeStore.primaryColor.opacity(0.1) : Color(uiColor: .systemBackground).opacity(0.5))
                }
                
                // Start/Stop button
                Button(action: {
                    if isSessionActive {
                        showEndSessionSheet = true
                    } else {
                        startSession()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: isSessionActive ? "stop.circle.fill" : "play.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text(isSessionActive ? "End Session" : "Start Session")
                            .font(.caption.bold())
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSessionActive ? Color.orange : themeStore.primaryColor)
                    }
                }
                .buttonStyle(.plain)
            } else {
                // Not currently reading
                VStack(spacing: 8) {
                    Image(systemName: "book.closed")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
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
        .sheet(isPresented: $showProfilingPrompt) {
            ProgressiveProfilingPrompt(work: work, onComplete: {
                #if DEBUG
                print("✅ Progressive profiling completed")
                #endif
            })
            .presentationDetents([.large])
            .iOS26SheetGlass()
        }
    }
    
    private var statusMessage: String {
        guard let entry = libraryEntry else {
            return "Add to library to track progress"
        }
        
        switch entry.readingStatus {
        case .wishlist:
            return "On your wishlist"
        case .toRead:
            return "Ready to start reading"
        case .read:
            return "Completed! ✓"
        case .onHold:
            return "Paused"
        case .dnf:
            return "Did not finish"
        case .reading:
            return "Start reading to track progress"
        }
    }
    
    // MARK: - Session Management
    
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
        
        func resetSessionState() {
            isSessionActive = false
            sessionStartTime = nil
            showEndSessionSheet = false
        }
        
        do {
            let service = getSessionService()
            let session = try service.endSession(endPage: endingPage)
            
            resetSessionState()
            
            #if canImport(UIKit)
            triggerHaptic(.heavy)
            #endif
            
            // Show progressive profiling prompt if session >= 5 minutes
            if session.durationMinutes >= 5 {
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

// MARK: - Preview

@available(iOS 26.0, *)
#Preview("Reading Progress") {
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
        entry.currentPage = 120
        entry.readingProgress = 0.34
        
        return container
    }()
    
    let work = try! container.mainContext.fetch(FetchDescriptor<Work>()).first!
    let edition = try! container.mainContext.fetch(FetchDescriptor<Edition>()).first!
    let themeStore = BooksTrackerFeature.iOS26ThemeStore()
    
    BentoModule(title: "Reading Progress", icon: "book.pages") {
        ReadingProgressModule(work: work, edition: edition)
    }
    .modelContainer(container)
    .environment(\.iOS26ThemeStore, themeStore)
    .padding()
    .themedBackground()
}
