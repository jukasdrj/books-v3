import SwiftUI
import SwiftData

/// Reading Habits & Pace Module - Glanceable metrics
/// Top-right module in Bento Grid (compact layout)
@available(iOS 26.0, *)
public struct ReadingHabitsModule: View {
    @Bindable var work: Work
    
    @Environment(\.iOS26ThemeStore) private var themeStore
    
    private var libraryEntry: UserLibraryEntry? {
        work.userLibraryEntries?.first
    }
    
    public init(work: Work) {
        self.work = work
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let entry = libraryEntry, !entry.readingSessions.isEmpty {
                // Average reading pace
                if let pace = entry.averageReadingPace {
                    HStack(spacing: 8) {
                        Image(systemName: "speedometer")
                            .foregroundStyle(themeStore.primaryColor)
                            .font(.title3)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: "%.0f pgs/hr", pace))
                                .font(.headline.bold())
                                .foregroundStyle(.primary)
                            
                            Text("Avg. Pace")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // Reading streak
                if let streak = calculateReadingStreak(sessions: entry.readingSessions) {
                    HStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                            .font(.title3)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(streak) Day\(streak == 1 ? "" : "s")")
                                .font(.headline.bold())
                                .foregroundStyle(.primary)
                            
                            Text("Streak")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // Total reading time
                if entry.totalReadingMinutes > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .foregroundStyle(themeStore.secondaryColor)
                            .font(.title3)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formatReadingTime(entry.totalReadingMinutes))
                                .font(.headline.bold())
                                .foregroundStyle(.primary)
                            
                            Text("Total Time")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                // No reading data yet
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    
                    Text("No reading data yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Text("Start a session to see stats")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
    }
    
    // MARK: - Calculations
    
    /// Calculate reading streak (consecutive days with sessions)
    private func calculateReadingStreak(sessions: [ReadingSession]) -> Int? {
        guard !sessions.isEmpty else { return nil }
        
        // Sort sessions by date (newest first)
        let sortedSessions = sessions.sorted { $0.date > $1.date }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Check if there's a session today or yesterday
        guard let mostRecentDate = sortedSessions.first?.date,
              let daysSinceRecent = calendar.dateComponents([.day], from: calendar.startOfDay(for: mostRecentDate), to: today).day,
              daysSinceRecent <= 1 else {
            return nil // Streak is broken if no session in last 2 days
        }
        
        // Count consecutive days
        var streak = 0
        var currentDay = today
        
        for session in sortedSessions {
            let sessionDay = calendar.startOfDay(for: session.date)
            
            if calendar.isDate(sessionDay, inSameDayAs: currentDay) {
                // Same day - count it if we haven't already
                if sessionDay == currentDay {
                    streak += 1
                    // Move to previous day
                    currentDay = calendar.date(byAdding: .day, value: -1, to: currentDay) ?? currentDay
                }
            } else if let dayDiff = calendar.dateComponents([.day], from: sessionDay, to: currentDay).day,
                      dayDiff == 1 {
                // Previous day - continue streak
                streak += 1
                currentDay = calendar.date(byAdding: .day, value: -1, to: currentDay) ?? currentDay
            } else {
                // Gap in days - streak is broken
                break
            }
        }
        
        return streak > 0 ? streak : nil
    }
    
    /// Format reading time in human-readable format
    private func formatReadingTime(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 {
                return "\(hours) hr"
            } else {
                return "\(hours)h \(mins)m"
            }
        }
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview("Reading Habits") {
    @Previewable @State var container: ModelContainer = {
        let container = try! ModelContainer(for: Work.self, Edition.self, UserLibraryEntry.self, ReadingSession.self)
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
        
        // Add some reading sessions
        let session1 = ReadingSession(
            date: Calendar.current.date(byAdding: .day, value: -2, to: Date())!,
            durationMinutes: 45,
            startPage: 0,
            endPage: 30
        )
        let session2 = ReadingSession(
            date: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
            durationMinutes: 60,
            startPage: 30,
            endPage: 70
        )
        let session3 = ReadingSession(
            date: Date(),
            durationMinutes: 30,
            startPage: 70,
            endPage: 90
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
    let themeStore = BooksTrackerFeature.iOS26ThemeStore()
    
    BentoModule(title: "Reading Habits", icon: "chart.line.uptrend.xyaxis") {
        ReadingHabitsModule(work: work)
    }
    .modelContainer(container)
    .environment(\.iOS26ThemeStore, themeStore)
    .padding()
    .themedBackground()
}
