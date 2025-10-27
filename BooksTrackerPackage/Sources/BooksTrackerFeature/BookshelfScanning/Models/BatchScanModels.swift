import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Captured Photo

/// Represents a captured photo in a batch scan session
@MainActor
public struct CapturedPhoto: Identifiable {
    public let id: UUID
    #if canImport(UIKit)
    public let image: UIImage
    #endif
    public let timestamp: Date

    /// Maximum photos allowed per batch
    public static let maxPhotosPerBatch = 5

    #if canImport(UIKit)
    public init(image: UIImage) {
        self.id = UUID()
        self.image = image
        self.timestamp = Date()
    }
    #endif
}

// MARK: - Photo Status

/// Status of an individual photo in batch processing
public enum PhotoStatus: String, Codable, Sendable {
    case queued
    case processing
    case complete
    case error
}

// MARK: - Photo Progress

/// Progress information for a single photo in a batch
public struct PhotoProgress: Identifiable, Sendable {
    public let index: Int
    public var status: PhotoStatus
    public var progress: Double?
    public var booksFound: [AIDetectedBook]?
    public var error: String?

    public var id: Int { index }

    public init(index: Int) {
        self.index = index
        self.status = .queued
    }
}

// MARK: - Batch Progress

/// Overall progress for a batch scan job
@available(iOS 26.0, macOS 14.0, *)
@Observable
@MainActor
public final class BatchProgress {
    public let jobId: String
    public let totalPhotos: Int
    public var photos: [PhotoProgress]
    public var overallStatus: String
    public var totalBooksFound: Int
    public var currentPhotoIndex: Int?

    public init(jobId: String, totalPhotos: Int) {
        self.jobId = jobId
        self.totalPhotos = totalPhotos
        self.photos = (0..<totalPhotos).map { PhotoProgress(index: $0) }
        self.overallStatus = "queued"
        self.totalBooksFound = 0
    }

    /// Update status for a specific photo
    public func updatePhoto(
        index: Int,
        status: PhotoStatus,
        booksFound: [AIDetectedBook]? = nil,
        error: String? = nil
    ) {
        guard index < photos.count else { return }

        photos[index].status = status

        if let booksFound {
            photos[index].booksFound = booksFound
            recalculateTotalBooks()
        }

        if let error {
            photos[index].error = error
        }

        if status == .processing {
            currentPhotoIndex = index
        }
    }

    /// Mark batch as complete
    public func complete(totalBooks: Int) {
        self.overallStatus = "complete"
        self.totalBooksFound = totalBooks
        self.currentPhotoIndex = nil
    }

    /// Check if all photos are complete
    public var isComplete: Bool {
        photos.allSatisfy { $0.status == .complete || $0.status == .error }
    }

    /// Count successful photos
    public var successCount: Int {
        photos.filter { $0.status == .complete }.count
    }

    /// Count failed photos
    public var errorCount: Int {
        photos.filter { $0.status == .error }.count
    }

    private func recalculateTotalBooks() {
        totalBooksFound = photos.compactMap { $0.booksFound?.count }.reduce(0, +)
    }
}

// MARK: - Batch Request

/// Request payload for batch scan endpoint
public struct BatchScanRequest: Codable, Sendable {
    public let jobId: String
    public let images: [ImageData]

    public struct ImageData: Codable, Sendable {
        public let index: Int
        public let data: String // Base64 encoded

        public init(index: Int, data: String) {
            self.index = index
            self.data = data
        }
    }

    public init(jobId: String, images: [ImageData]) {
        self.jobId = jobId
        self.images = images
    }
}

// MARK: - Batch WebSocket Messages

/// WebSocket message types for batch scanning
public enum BatchWebSocketMessage: Codable {
    case batchInit(BatchInitMessage)
    case batchProgress(BatchProgressMessage)
    case batchComplete(BatchCompleteMessage)

    public struct BatchInitMessage: Codable {
        public let type: String
        public let jobId: String
        public let totalPhotos: Int
        public let status: String

        public init(type: String, jobId: String, totalPhotos: Int, status: String) {
            self.type = type
            self.jobId = jobId
            self.totalPhotos = totalPhotos
            self.status = status
        }
    }

    public struct BatchProgressMessage: Codable {
        public let type: String
        public let jobId: String
        public let currentPhoto: Int
        public let totalPhotos: Int
        public let photoStatus: String
        public let booksFound: Int
        public let totalBooksFound: Int
        public let photos: [PhotoProgressData]

        public struct PhotoProgressData: Codable {
            public let index: Int
            public let status: String
            public let booksFound: Int?
            public let error: String?

            public init(index: Int, status: String, booksFound: Int? = nil, error: String? = nil) {
                self.index = index
                self.status = status
                self.booksFound = booksFound
                self.error = error
            }
        }

        public init(type: String, jobId: String, currentPhoto: Int, totalPhotos: Int, photoStatus: String, booksFound: Int, totalBooksFound: Int, photos: [PhotoProgressData]) {
            self.type = type
            self.jobId = jobId
            self.currentPhoto = currentPhoto
            self.totalPhotos = totalPhotos
            self.photoStatus = photoStatus
            self.booksFound = booksFound
            self.totalBooksFound = totalBooksFound
            self.photos = photos
        }
    }

    public struct BatchCompleteMessage: Codable {
        public let type: String
        public let jobId: String
        public let totalBooks: Int
        public let photoResults: [PhotoResult]
        public let books: [AIDetectedBook]

        public struct PhotoResult: Codable {
            public let index: Int
            public let status: String
            public let booksFound: Int?
            public let error: String?

            public init(index: Int, status: String, booksFound: Int? = nil, error: String? = nil) {
                self.index = index
                self.status = status
                self.booksFound = booksFound
                self.error = error
            }
        }

        public init(type: String, jobId: String, totalBooks: Int, photoResults: [PhotoResult], books: [AIDetectedBook]) {
            self.type = type
            self.jobId = jobId
            self.totalBooks = totalBooks
            self.photoResults = photoResults
            self.books = books
        }
    }
}

// MARK: - AIDetectedBook

/// AI-detected book from backend (for batch complete message)
public struct AIDetectedBook: Codable, Sendable {
    public let title: String
    public let author: String?
    public let isbn: String?
    public let confidence: Double

    public init(title: String, author: String? = nil, isbn: String? = nil, confidence: Double) {
        self.title = title
        self.author = author
        self.isbn = isbn
        self.confidence = confidence
    }
}
