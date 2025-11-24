import SwiftData
import Foundation

/// Service responsible for managing reading sessions, including starting/ending sessions,
/// tracking active sessions in-memory, persisting completed sessions, and handling
/// enrichment prompt logic. All operations run on @MainActor since ModelContext requires it.
@MainActor
public class ReadingSessionService {

    private let modelContext: ModelContext
    private var activeSession: ReadingSession?
    private var activeEntry: UserLibraryEntry?

    /// Initializes the service with the required ModelContext for persistence.
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Starts a new reading session for the given library entry.
    /// - Throws: `SessionError.alreadyActive` if a session is already active.
    public func startSession(for entry: UserLibraryEntry) throws {
        guard activeSession == nil else {
            throw SessionError.alreadyActive
        }

        let newSession = ReadingSession(
            date: Date(),
            durationMinutes: 0,
            startPage: entry.currentPage,
            endPage: 0
        )

        newSession.workUUID = entry.work?.uuid

        activeSession = newSession
        activeEntry = entry // Keep reference to update currentPage on end
    }

    /// Ends the active reading session, persists it, and updates the entry's current page.
    /// - Parameter endPage: The page reached at session end.
    /// - Returns: The completed and persisted ReadingSession.
    /// - Throws: `SessionError.noActiveSession` if no session is active.
    public func endSession(endPage: Int) throws -> ReadingSession {
        guard let session = activeSession else {
            throw SessionError.noActiveSession
        }

        let endDate = Date()
        let duration = endDate.timeIntervalSince(session.date)
        let durationMinutes = Int(duration / 60.0)

        session.endPage = endPage
        session.durationMinutes = durationMinutes

        // Insert session into context for persistence
        modelContext.insert(session)

        // Update entry's current page
        if let entry = activeEntry {
            entry.currentPage = endPage
            entry.updateReadingProgress()
            entry.touch()
        }

        try modelContext.save()

        // Clear active session
        activeSession = nil
        activeEntry = nil

        return session
    }

    /// Returns `true` if an active session is currently tracked.
    public func isSessionActive() -> Bool {
        return activeSession != nil
    }

    /// Returns the currently active session, if any.
    public func getCurrentSession() -> ReadingSession? {
        return activeSession
    }

    /// Determines if an enrichment prompt should be shown for the given session.
    /// - Parameter session: The completed session to check.
    /// - Returns: `true` if prompt should be shown (not previously shown and >= 5 minutes).
    public func shouldShowEnrichmentPrompt(for session: ReadingSession) async throws -> Bool {
        return !session.enrichmentPromptShown && session.durationMinutes >= 5
    }

    /// Records that the enrichment prompt was shown for the session.
    /// - Parameter session: The session to update.
    public func recordEnrichmentShown(for session: ReadingSession) async throws {
        session.enrichmentPromptShown = true
        try modelContext.save()
    }

    /// Records that enrichment was completed for the session.
    /// - Parameter session: The session to update.
    public func recordEnrichmentCompleted(for session: ReadingSession) async throws {
        session.enrichmentCompleted = true
        try modelContext.save()
    }
}

/// Errors specific to reading session management.
public enum SessionError: Error, LocalizedError {
    case alreadyActive
    case noActiveSession

    public var errorDescription: String? {
        switch self {
        case .alreadyActive:
            return "Cannot start a new session while one is already active."
        case .noActiveSession:
            return "No active session found to end."
        }
    }
}
