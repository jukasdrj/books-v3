import Foundation
import SwiftUI

#if canImport(UIKit)

// MARK: - Detected Book Model

/// Represents a book detected from a bookshelf photo via Vision framework
/// This is temporary data before enrichment and SwiftData persistence
public struct DetectedBook: Identifiable, Sendable {
    public let id = UUID()

    /// Detected ISBN (13-digit or 10-digit)
    public var isbn: String?

    /// Detected book title
    public var title: String?

    /// Detected author name(s)
    public var author: String?

    /// Detected book format (hardcover, paperback, mass-market, or nil if unknown)
    public var format: EditionFormat?

    /// Confidence score from Vision API (0.0 - 1.0)
    public var confidence: Double

    /// Bounding box of detected spine in normalized coordinates (0.0 - 1.0)
    public var boundingBox: CGRect

    /// Raw OCR text extracted from spine
    public var rawText: String

    /// Detection status for user review
    public var status: DetectionStatus

    /// Path to original bookshelf scan image (temporary storage)
    /// Used for correction UI to show cropped spine image
    public var originalImagePath: String?

    // MARK: - Enrichment Storage

    /// Store enrichment DTOs from backend WebSocket
    /// Populated during bookshelf scan enrichment phase
    public var enrichmentWork: WorkDTO?
    public var enrichmentEditions: [EditionDTO]?
    public var enrichmentAuthors: [AuthorDTO]?

    /// Enrichment status from backend (API contract v3.1)
    /// Tracks the progress and result of backend enrichment operations
    public var enrichmentStatus: EnrichmentStatus?

    /// Retry delay in milliseconds (when enrichmentStatus == .circuitOpen)
    /// Indicates how long to wait before retrying enrichment
    public var retryAfterMs: Int?

    /// Confidence threshold for requiring human review
    /// Books below 0.60 (60%) confidence should be reviewed
    private static let reviewThreshold: Double = 0.60

    /// Whether this detection requires human review
    public var needsReview: Bool {
        return confidence < Self.reviewThreshold
    }

    public init(
        isbn: String? = nil,
        title: String? = nil,
        author: String? = nil,
        format: EditionFormat? = nil,
        confidence: Double,
        boundingBox: CGRect,
        rawText: String,
        status: DetectionStatus = .detected,
        originalImagePath: String? = nil
    ) {
        self.isbn = isbn
        self.title = title
        self.author = author
        self.format = format
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.rawText = rawText
        self.status = status
        self.originalImagePath = originalImagePath
        // Enrichment fields default to nil
        self.enrichmentWork = nil
        self.enrichmentEditions = nil
        self.enrichmentAuthors = nil
    }
}

// MARK: - Enrichment Status (API Contract v3.1)

/// Type-safe enrichment status values per API Contract v3.1 Section 7.6.1
///
/// This enum represents the possible states of book enrichment from the backend:
/// - `pending`: Enrichment is in progress
/// - `success`: Book was successfully enriched with metadata
/// - `notFound`: No matching book found in any provider
/// - `error`: Enrichment failed due to an error
/// - `circuitOpen`: Circuit breaker tripped, service temporarily unavailable
public enum EnrichmentStatus: String, CaseIterable, Codable, Sendable {
    case pending = "pending"
    case success = "success"
    case notFound = "not_found"
    case error = "error"
    case circuitOpen = "circuit_open"

    // MARK: - Display Properties

    /// Short display name for UI badges
    public var displayName: String {
        switch self {
        case .pending: return "Enriching..."
        case .success: return "Enriched"
        case .notFound: return "Not Found"
        case .error: return "Error"
        case .circuitOpen: return "Service Unavailable"
        }
    }

    /// User-friendly description for status messages
    public var displayDescription: String {
        switch self {
        case .pending:
            return "Enrichment pending..."
        case .success:
            return "Book enriched successfully"
        case .notFound:
            return "No match found - try manual search"
        case .error:
            return "Enrichment failed - tap to retry"
        case .circuitOpen:
            return "Service temporarily unavailable - will retry automatically"
        }
    }

    /// Color for status indicators
    public var color: Color {
        switch self {
        case .pending: return .blue
        case .success: return .green
        case .notFound: return .orange
        case .error: return .red
        case .circuitOpen: return .yellow
        }
    }

    /// SF Symbol name for status icons
    public var systemImage: String {
        switch self {
        case .pending: return "arrow.clockwise.circle"
        case .success: return "checkmark.circle.fill"
        case .notFound: return "questionmark.circle"
        case .error: return "xmark.circle"
        case .circuitOpen: return "exclamationmark.triangle"
        }
    }

    // MARK: - Status Behavior Properties

    /// Whether this status allows automatic retry
    ///
    /// Retryable statuses:
    /// - `pending`: May need retry if enrichment times out
    /// - `error`: Transient failures can be retried
    /// - `circuitOpen`: Will auto-retry after cooldown period
    public var isRetryable: Bool {
        switch self {
        case .pending, .error, .circuitOpen:
            return true
        case .success, .notFound:
            return false
        }
    }

    /// Whether this status requires manual user intervention
    ///
    /// Statuses requiring manual review:
    /// - `notFound`: User may need to search manually or correct metadata
    /// - `error`: User may need to retry or investigate
    public var requiresManualReview: Bool {
        switch self {
        case .notFound, .error:
            return true
        case .pending, .success, .circuitOpen:
            return false
        }
    }
}

// MARK: - Detection Status

public enum DetectionStatus: String, CaseIterable, Sendable {
    case detected = "Detected"
    case confirmed = "Confirmed"
    case alreadyInLibrary = "Already in Library"
    case uncertain = "Needs Review"
    case rejected = "Rejected"

    var displayName: String { rawValue }

    var color: Color {
        switch self {
        case .detected: return .blue
        case .confirmed: return .green
        case .alreadyInLibrary: return .orange
        case .uncertain: return .yellow
        case .rejected: return .red
        }
    }

    var systemImage: String {
        switch self {
        case .detected: return "book.closed"
        case .confirmed: return "checkmark.circle.fill"
        case .alreadyInLibrary: return "books.vertical.fill"
        case .uncertain: return "questionmark.circle"
        case .rejected: return "xmark.circle"
        }
    }
}

// MARK: - Scan Result Summary

/// Summary of a bookshelf scan session
public struct ScanResult: Sendable {
    public let sessionId = UUID()
    public let scanDate = Date()
    #if canImport(UIKit)
    public var capturedImage: UIImage?
    #endif
    public var detectedBooks: [DetectedBook]
    public var totalProcessingTime: TimeInterval
    public var suggestions: [SuggestionViewModel]

    public init(
        capturedImage: UIImage? = nil,
        detectedBooks: [DetectedBook],
        totalProcessingTime: TimeInterval,
        suggestions: [SuggestionViewModel] = []
    ) {
        self.capturedImage = capturedImage
        self.detectedBooks = detectedBooks
        self.totalProcessingTime = totalProcessingTime
        self.suggestions = suggestions
    }

    /// Statistics for user feedback
    public var statistics: ScanStatistics {
        ScanStatistics(
            totalDetected: detectedBooks.count,
            withISBN: detectedBooks.filter { $0.isbn != nil }.count,
            highConfidence: detectedBooks.filter { $0.confidence >= 0.7 }.count,
            needsReview: detectedBooks.filter { $0.confidence < 0.5 }.count
        )
    }
}

public struct ScanStatistics: Sendable {
    public let totalDetected: Int
    public let withISBN: Int
    public let highConfidence: Int
    public let needsReview: Int

    public init(totalDetected: Int, withISBN: Int, highConfidence: Int, needsReview: Int) {
        self.totalDetected = totalDetected
        self.withISBN = withISBN
        self.highConfidence = highConfidence
        self.needsReview = needsReview
    }
}

#endif  // canImport(UIKit)
