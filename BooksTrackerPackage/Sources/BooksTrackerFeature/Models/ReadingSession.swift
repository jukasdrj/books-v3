import Foundation
import SwiftData

/// Represents a single reading session with timer tracking and progressive profiling integration
///
/// # Usage with @Bindable
///
/// ```swift
/// struct SessionTimerView: View {
///     @Bindable var session: ReadingSession
///
///     var body: some View {
///         Text("\(session.durationMinutes) minutes")
///     }
/// }
/// ```
@Model
public final class ReadingSession {
    /// Date/time when reading session started
    public var date: Date

    /// Duration of reading session in minutes
    public var durationMinutes: Int

    /// Page number when session started
    public var startPage: Int

    /// Page number when session ended
    public var endPage: Int

    // MARK: - Progressive Profiling Integration

    /// Whether enrichment prompt was shown after this session
    public var enrichmentPromptShown: Bool

    /// Whether user completed enrichment prompt (answered questions)
    public var enrichmentCompleted: Bool

    // MARK: - Relationships

    /// Relationship to UserLibraryEntry (inverse defined on UserLibraryEntry.readingSessions)
    public var entry: UserLibraryEntry?

    /// Denormalized work UUID for efficient bulk queries (stable across CloudKit sync)
    public var workUUID: UUID?

    // MARK: - Computed Properties

    /// Number of pages read during this session
    public var pagesRead: Int {
        max(0, endPage - startPage)
    }

    /// Reading pace in pages per hour (nil if duration is 0)
    public var readingPace: Double? {
        guard durationMinutes > 0 else { return nil }
        return Double(pagesRead) / Double(durationMinutes) * 60.0 // pages/hour
    }

    // MARK: - Initializer

    public init(
        date: Date = Date(),
        durationMinutes: Int = 0,
        startPage: Int = 0,
        endPage: Int = 0,
        enrichmentPromptShown: Bool = false,
        enrichmentCompleted: Bool = false
    ) {
        self.date = date
        self.durationMinutes = durationMinutes
        self.startPage = startPage
        self.endPage = endPage
        self.enrichmentPromptShown = enrichmentPromptShown
        self.enrichmentCompleted = enrichmentCompleted
    }
}
