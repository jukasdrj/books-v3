import Foundation
import SwiftData
import SwiftUI

@Model
public final class UserLibraryEntry {
    var dateAdded: Date = Date()
    var readingStatus: ReadingStatus = ReadingStatus.toRead
    var currentPage: Int = 0
    var readingProgress: Double = 0.0 // 0.0 to 1.0
    var rating: Int? // 1-5 stars
    var personalRating: Double? // 0.0-5.0 for more granular ratings
    var notes: String?
    var tags: [String] = []

    // Reading tracking
    var dateStarted: Date?
    var dateCompleted: Date?
    var estimatedFinishDate: Date?

    // Metadata
    var lastModified: Date = Date()

    // Relationships (inverses defined on the "many" side: Work and Edition)
    var work: Work?

    // Nil for wishlist items (don't own yet)
    // Inverse defined on Edition side at line 43
    var edition: Edition?

    public init(
        readingStatus: ReadingStatus = ReadingStatus.toRead
    ) {
        self.readingStatus = readingStatus
        self.dateAdded = Date()
        self.lastModified = Date()
        // CRITICAL: work and edition MUST be set AFTER insert
        // Usage: let entry = UserLibraryEntry(); context.insert(entry); entry.work = work
    }

    /// Create wishlist entry (want to read but don't own)
    /// CRITICAL: Caller MUST have already inserted work into context
    public static func createWishlistEntry(for work: Work, context: ModelContext) -> UserLibraryEntry {
        let entry = UserLibraryEntry(readingStatus: .wishlist)
        context.insert(entry)  // Get permanent ID first
        entry.work = work      // Set relationship after insert
        return entry
    }

    /// Create owned entry (have specific edition)
    /// CRITICAL: Caller MUST have already inserted work and edition into context
    public static func createOwnedEntry(
        for work: Work,
        edition: Edition,
        status: ReadingStatus = .toRead,
        context: ModelContext
    ) -> UserLibraryEntry {
        let entry = UserLibraryEntry(readingStatus: status)
        context.insert(entry)  // Get permanent ID first
        entry.work = work      // Set relationships after insert
        entry.edition = edition
        return entry
    }

    // MARK: - Reading Progress Methods

    /// Update reading progress based on current page and edition page count
    func updateReadingProgress() {
        // Can't track progress for wishlist items (no edition)
        guard readingStatus != ReadingStatus.wishlist,
              let pageCount = edition?.pageCount,
              pageCount > 0 else {
            readingProgress = 0.0
            return
        }

        readingProgress = min(Double(currentPage) / Double(pageCount), 1.0)

        // Auto-complete if progress reaches 100%
        if readingProgress >= 1.0 && readingStatus != ReadingStatus.read {
            markAsCompleted()
        }
    }

    /// Mark the book as completed
    func markAsCompleted() {
        readingStatus = ReadingStatus.read
        readingProgress = 1.0
        if dateCompleted == nil {
            dateCompleted = Date()
        }
        if dateStarted == nil {
            dateStarted = Date()
        }
        if let pageCount = edition?.pageCount {
            currentPage = pageCount
        }
        touch()
    }

    /// Start reading the book (only if owned)
    func startReading() {
        guard readingStatus != ReadingStatus.wishlist, edition != nil else {
            // Can't start reading a wishlist item - need to acquire edition first
            return
        }

        if readingStatus == ReadingStatus.toRead {
            readingStatus = ReadingStatus.reading
            if dateStarted == nil {
                dateStarted = Date()
            }
            touch()
        }
    }

    /// Convert wishlist entry to owned entry
    func acquireEdition(_ edition: Edition, status: ReadingStatus = ReadingStatus.toRead) {
        guard readingStatus == ReadingStatus.wishlist else { return }

        self.edition = edition
        self.readingStatus = status
        touch()
    }

    /// Check if this is a wishlist entry
    var isWishlistItem: Bool {
        return readingStatus == ReadingStatus.wishlist && edition == nil
    }

    /// Check if user owns this entry
    var isOwned: Bool {
        return !isWishlistItem
    }

    /// Calculate reading pace (pages per day)
    var readingPace: Double? {
        guard let started = dateStarted,
              currentPage > 0,
              started < Date() else { return nil }

        let daysSinceStart = Calendar.current.dateComponents([.day], from: started, to: Date()).day ?? 1
        return Double(currentPage) / Double(max(daysSinceStart, 1))
    }

    /// Estimate finish date based on current pace and remaining pages
    func calculateEstimatedFinishDate() {
        guard let pageCount = edition?.pageCount,
              let pace = readingPace,
              pace > 0,
              currentPage < pageCount else {
            estimatedFinishDate = nil
            return
        }

        let remainingPages = pageCount - currentPage
        let daysToFinish = Double(remainingPages) / pace
        estimatedFinishDate = Calendar.current.date(byAdding: .day, value: Int(ceil(daysToFinish)), to: Date())
    }

    /// Update last modified timestamp
    func touch() {
        lastModified = Date()
    }

    // MARK: - Validation

    /// Validate rating is within acceptable range
    func validateRating() -> Bool {
        guard let rating = rating else { return true }
        return (1...5).contains(rating)
    }

    /// Validate notes length
    func validateNotes() -> Bool {
        guard let notes = notes else { return true }
        return notes.count <= 2000
    }
}

// MARK: - Reading Status Enum
public enum ReadingStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case wishlist = "Wishlist"     // Want to have/read but don't own
    case toRead = "TBR"            // Have it and want to read in the future
    case reading = "Reading"       // Currently reading
    case read = "Read"             // Finished reading
    case onHold = "On Hold"        // Started but paused
    case dnf = "DNF"               // Did not finish

    public var id: Self { self }

    var displayName: String {
        switch self {
        case .wishlist: return "Wishlist"
        case .toRead: return "To Read"
        case .reading: return "Reading"
        case .read: return "Read"
        case .onHold: return "On Hold"
        case .dnf: return "Did Not Finish"
        }
    }

    var description: String {
        switch self {
        case .wishlist: return "Want to have or read, but don't have"
        case .toRead: return "Have it and want to read in the future"
        case .reading: return "Currently reading"
        case .read: return "Finished reading"
        case .onHold: return "Started reading but paused"
        case .dnf: return "Started but did not finish"
        }
    }

    var systemImage: String {
        switch self {
        case .toRead: return "book"
        case .reading: return "book.pages"
        case .read: return "checkmark.circle.fill"
        case .onHold: return "pause.circle"
        case .dnf: return "xmark.circle"
        case .wishlist: return "heart"
        }
    }

    var color: Color {
        switch self {
        case .toRead: return Color.blue
        case .reading: return Color.orange
        case .read: return Color.green
        case .onHold: return Color.yellow
        case .dnf: return Color.red
        case .wishlist: return Color.pink
        }
    }

    // MARK: - String Parsing for CSV Import

    /// Parse reading status from common CSV export formats
    /// Supports Goodreads, LibraryThing, StoryGraph, and custom formats
    public static func from(string: String?) -> ReadingStatus? {
        guard let string = string?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return nil
        }

        guard !string.isEmpty else { return nil }

        // Direct matches
        switch string {
        // Wishlist variants
        case "wishlist", "want to read", "to-read", "want", "planned":
            return .wishlist

        // To Read variants (owned but not started)
        case "tbr", "to read", "owned", "unread", "on shelf", "to-be-read":
            return .toRead

        // Currently Reading variants
        case "reading", "currently reading", "in progress", "started", "current":
            return .reading

        // Read/Finished variants
        case "read", "finished", "completed", "done":
            return .read

        // On Hold variants
        case "on hold", "on-hold", "paused", "suspended":
            return .onHold

        // DNF variants
        case "dnf", "did not finish", "abandoned", "quit", "stopped":
            return .dnf

        default:
            break
        }

        // Partial matches for common patterns
        if string.contains("wish") || string.contains("want") {
            return .wishlist
        }

        if string.contains("reading") || string.contains("current") {
            return .reading
        }

        if string.contains("read") || string.contains("finish") || string.contains("complete") {
            return .read
        }

        if string.contains("hold") || string.contains("pause") {
            return .onHold
        }

        if string.contains("dnf") || string.contains("abandon") {
            return .dnf
        }

        if string.contains("tbr") || string.contains("owned") {
            return .toRead
        }

        // Unable to determine - return nil
        return nil
    }
}

