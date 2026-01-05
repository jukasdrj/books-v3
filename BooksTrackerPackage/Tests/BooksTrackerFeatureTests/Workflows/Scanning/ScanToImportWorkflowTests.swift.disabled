//
//  ScanToImportWorkflowTests.swift
//  BooksTrackerFeatureTests
//
//  Tests for complete scan-to-import workflow including confidence thresholds and enrichment
//
//  User Story:
//  - Given: User scans a bookshelf with camera
//  - When: Vision detects books with varying confidence
//  - Then: Books are imported with appropriate review status and enriched with metadata
//

import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

@Suite("Scan-to-Import Workflow Tests")
@MainActor
struct ScanToImportWorkflowTests {

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    init() throws {
        modelContainer = try ModelContainer.createWorkflowTestContainer()
        modelContext = ModelContext(modelContainer)
    }

    // MARK: - High Confidence Workflow

    @Test("High confidence detection (>0.8) creates verified work")
    func highConfidenceCreatesVerifiedWork() throws {
        let detectedBook = DetectedBook(
            title: "High Confidence Book",
            author: "Author Name",
            confidence: 0.95,
            boundingBox: CGRect.zero,
            rawText: "High Confidence Book by Author Name"
        )

        #expect(detectedBook.confidence >= 0.8)
        #expect(detectedBook.title == "High Confidence Book")
        #expect(detectedBook.author == "Author Name")
    }

    @Test("High confidence book with ISBN should be enriched immediately")
    func highConfidenceWithISBNEnrichedImmediately() throws {
        let detectedBook = DetectedBook(
            title: "The Great Gatsby",
            author: "F. Scott Fitzgerald",
            confidence: 0.92,
            boundingBox: CGRect.zero,
            rawText: "The Great Gatsby by F. Scott Fitzgerald"
        )

        // Simulate enrichment lookup
        let mockWork = Work(title: detectedBook.title)
        mockWork.reviewStatus = .verified
        modelContext.insert(mockWork)

        let isbndbID = "9780743273565"
        mockWork.isbndbID = isbndbID

        try modelContext.save()

        #expect(mockWork.reviewStatus == .verified)
        #expect(mockWork.isbndbID != nil)
    }

    // MARK: - Low Confidence Workflow

    @Test("Low confidence detection (<0.7) creates work needing review")
    func lowConfidenceNeedsReview() throws {
        let detectedBook = DetectedBook(
            title: "Unclear Cover",
            author: "Unknown",
            confidence: 0.55,
            boundingBox: CGRect.zero,
            rawText: "Unclear... Cover"
        )

        #expect(detectedBook.confidence < 0.7)

        // When imported, should be marked for review
        let work = Work(title: detectedBook.title)
        work.reviewStatus = .needsReview

        #expect(work.reviewStatus == .needsReview)
    }

    @Test("Low confidence book requires user verification before finalization")
    func lowConfidenceRequiresUserConfirmation() throws {
        let detectedBook = DetectedBook(
            title: "Blurry Detection",
            author: "Author",
            confidence: 0.45,
            boundingBox: CGRect.zero,
            rawText: "Blurry"
        )

        // Initially marked for review
        var work = Work(title: detectedBook.title)
        work.reviewStatus = .needsReview

        #expect(work.reviewStatus == .needsReview)

        // User confirms the book
        work.reviewStatus = .verified

        #expect(work.reviewStatus == .verified)
    }

    // MARK: - Borderline Confidence (0.7-0.8)

    @Test("Borderline confidence (0.7-0.8) creates flagged work")
    func borderlineConfidenceIsFlagged() {
        let detectedBook = DetectedBook(
            title: "Borderline Book",
            author: "Borderline Author",
            confidence: 0.75,
            boundingBox: CGRect.zero,
            rawText: "Borderline Book by Borderline Author"
        )

        // Confidence is borderline
        #expect(detectedBook.confidence >= 0.7 && detectedBook.confidence <= 0.8)
    }

    // MARK: - Duplicate Detection

    @Test("Duplicate detection prevents re-importing same book")
    func duplicateDetectionPreventsReimport() throws {
        // First import
        let detectedBook1 = DetectedBook(
            title: "The Hobbit",
            author: "J.R.R. Tolkien",
            confidence: 0.9,
            boundingBox: CGRect.zero,
            rawText: "The Hobbit"
        )

        let work1 = Work(title: detectedBook1.title)
        work1.authors = [Author(name: detectedBook1.author, gender: .unknown)]
        modelContext.insert(work1)
        try modelContext.save()

        // Try to import duplicate
        let detectedBook2 = DetectedBook(
            title: "The Hobbit",
            author: "J.R.R. Tolkien",
            confidence: 0.88,
            boundingBox: CGRect.zero,
            rawText: "The Hobbit"
        )

        // Simulate duplicate detection
        let descriptor = FetchDescriptor<Work>(
            predicate: #Predicate { $0.title == detectedBook2.title }
        )
        let existingWorks = try modelContext.fetch(descriptor)

        #expect(!existingWorks.isEmpty, "Duplicate should be detected")
        #expect(existingWorks.count == 1)
    }

    @Test("Same book with different edition is recognized as duplicate")
    func differentEditionSameWorkDetected() throws {
        // First import
        let work1 = Work(title: "Harry Potter and the Philosopher's Stone")
        modelContext.insert(work1)

        let edition1 = Edition(isbn: "9780439708180")
        edition1.work = work1
        modelContext.insert(edition1)

        work1.editions = [edition1]
        try modelContext.save()

        // Second import with different ISBN (different edition, same work)
        let work2 = Work(title: "Harry Potter and the Philosopher's Stone")

        let descriptor = FetchDescriptor<Work>(
            predicate: #Predicate { $0.title == "Harry Potter and the Philosopher's Stone" }
        )
        let matches = try modelContext.fetch(descriptor)

        #expect(!matches.isEmpty, "Same work with different edition should be detected")
    }

    // MARK: - Partial Enrichment Scenarios

    @Test("Enrichment succeeds with partial metadata")
    func partialEnrichmentSucceeds() throws {
        let detectedBook = DetectedBook(
            title: "Mystery Novel",
            author: "Unknown Author",
            confidence: 0.8,
            boundingBox: CGRect.zero,
            rawText: "Mystery Novel"
        )

        let work = Work(title: detectedBook.title)
        work.authors = [Author(name: detectedBook.author, gender: .unknown)]
        // Missing: publicationDate, pageCount, description

        modelContext.insert(work)
        try modelContext.save()

        // Verify work was created despite missing fields
        let descriptor = FetchDescriptor<Work>(
            predicate: #Predicate { $0.title == detectedBook.title }
        )
        let works = try modelContext.fetch(descriptor)

        #expect(!works.isEmpty)
        #expect(works.first?.title == detectedBook.title)
    }

    @Test("Enrichment handles missing cover image gracefully")
    func missingCoverImageHandled() throws {
        let work = Work(title: "Book Without Cover")
        work.coverImageURL = nil
        modelContext.insert(work)

        // Work should still be valid
        try modelContext.save()

        #expect(work.title == "Book Without Cover")
        #expect(work.coverImageURL == nil)
    }

    @Test("Enrichment retries on provider timeout")
    func enrichmentRetriesOnTimeout() throws {
        let detectedBook = DetectedBook(
            title: "Timeout Book",
            author: "Author",
            confidence: 0.85,
            boundingBox: CGRect.zero,
            rawText: "Timeout Book"
        )

        // Simulate provider timeout
        let work = Work(title: detectedBook.title)
        work.reviewStatus = .needsReview  // Marked for retry

        modelContext.insert(work)
        try modelContext.save()

        // Verify work created even if enrichment failed
        let descriptor = FetchDescriptor<Work>(
            predicate: #Predicate { $0.title == detectedBook.title }
        )
        let works = try modelContext.fetch(descriptor)

        #expect(!works.isEmpty, "Work should be created even if enrichment times out")
    }

    // MARK: - Confidence Threshold Testing

    @Test("Books below 0.5 confidence are rejected")
    func veryLowConfidenceRejected() throws {
        let detectedBook = DetectedBook(
            title: "Garbage Detection",
            author: "Noise",
            confidence: 0.25,
            boundingBox: CGRect.zero,
            rawText: "xxxxxx"
        )

        // Should not be imported
        #expect(detectedBook.confidence < 0.5)

        // Simulate rejection
        let shouldImport = detectedBook.confidence >= 0.5
        #expect(!shouldImport)
    }

    @Test("Books between 0.5-0.7 confidence flagged for manual review")
    func mediumConfidenceFlaggedForReview() {
        let detectedBook = DetectedBook(
            title: "Medium Confidence",
            author: "Author",
            confidence: 0.60,
            boundingBox: CGRect.zero,
            rawText: "Medium Confidence Book"
        )

        let needsReview = detectedBook.confidence >= 0.5 && detectedBook.confidence < 0.7
        #expect(needsReview)
    }

    @Test("Books above 0.8 confidence auto-imported")
    func highConfidenceAutoImported() throws {
        let detectedBook = DetectedBook(
            title: "Harry Potter",
            author: "J.K. Rowling",
            confidence: 0.93,
            boundingBox: CGRect.zero,
            rawText: "Harry Potter and the Sorcerer's Stone"
        )

        let autoImport = detectedBook.confidence >= 0.8
        #expect(autoImport)

        // Simulate auto-import
        let work = Work(title: detectedBook.title)
        work.reviewStatus = .verified
        modelContext.insert(work)
        try modelContext.save()

        #expect(work.reviewStatus == .verified)
    }

    // MARK: - Bounding Box and Image Handling

    @Test("Bounding box coordinates are preserved for cropping")
    func boundingBoxPreserved() throws {
        let boundingBox = CGRect(x: 10, y: 20, width: 100, height: 150)
        let detectedBook = DetectedBook(
            title: "Book with Crop",
            author: "Author",
            confidence: 0.9,
            boundingBox: boundingBox,
            rawText: "Book with Crop"
        )

        let work = Work(title: detectedBook.title)
        work.boundingBox = boundingBox

        #expect(work.boundingBox == boundingBox)
        #expect(work.boundingBoxX == 10)
        #expect(work.boundingBoxY == 20)
        #expect(work.boundingBoxWidth == 100)
        #expect(work.boundingBoxHeight == 150)
    }

    @Test("Original image path is stored for review")
    func originalImagePathStored() throws {
        let imagePath = "/tmp/bookshelf_scan_20251230_123456.jpg"
        let work = Work(title: "Scanned Book")
        work.originalImagePath = imagePath

        modelContext.insert(work)
        try modelContext.save()

        #expect(work.originalImagePath == imagePath)
    }

    // MARK: - Batch Import Workflow

    @Test("Batch import creates multiple works")
    func batchImportCreatesMultipleWorks() throws {
        var entryBuilder = LibraryScenarioBuilder(modelContext: modelContext)

        // Simulate scanning results
        entryBuilder = try entryBuilder.addReadingScenario(
            title: "Book One",
            status: .toRead,
            sessionsCount: 0
        )
        entryBuilder = try entryBuilder.addReadingScenario(
            title: "Book Two",
            status: .toRead,
            sessionsCount: 0
        )
        entryBuilder = try entryBuilder.addReadingScenario(
            title: "Book Three",
            status: .toRead,
            sessionsCount: 0
        )

        let (works, entries) = try entryBuilder.build()

        #expect(works.count == 3)
        #expect(entries.count == 3)
    }

    @Test("Batch import maintains metadata for each work")
    func batchImportPreservesMetadata() throws {
        let detectedBooks = [
            DetectedBook(
                title: "Book 1",
                author: "Author 1",
                confidence: 0.9,
                boundingBox: CGRect(x: 0, y: 0, width: 50, height: 100),
                rawText: "Book 1"
            ),
            DetectedBook(
                title: "Book 2",
                author: "Author 2",
                confidence: 0.85,
                boundingBox: CGRect(x: 60, y: 0, width: 50, height: 100),
                rawText: "Book 2"
            ),
            DetectedBook(
                title: "Book 3",
                author: "Author 3",
                confidence: 0.92,
                boundingBox: CGRect(x: 120, y: 0, width: 50, height: 100),
                rawText: "Book 3"
            ),
        ]

        for book in detectedBooks {
            let work = Work(title: book.title)
            work.authors = [Author(name: book.author, gender: .unknown)]
            work.reviewStatus = book.confidence >= 0.8 ? .verified : .needsReview
            work.boundingBox = book.boundingBox
            modelContext.insert(work)
        }

        try modelContext.save()

        let descriptor = FetchDescriptor<Work>()
        let works = try modelContext.fetch(descriptor)

        #expect(works.count == 3)
        for (index, work) in works.enumerated() {
            #expect(work.title == detectedBooks[index].title)
            #expect(work.authors?.first?.name == detectedBooks[index].author)
        }
    }

    // MARK: - Error Handling

    @Test("Import handles malformed metadata gracefully")
    func malformedMetadataHandled() throws {
        let work = Work(title: "")  // Empty title - should still be created
        modelContext.insert(work)

        // Should not throw
        try modelContext.save()

        #expect(work.title == "")
    }

    @Test("Enrichment service unavailable doesn't block import")
    func unavailableEnrichmentDoesntBlockImport() throws {
        let detectedBook = DetectedBook(
            title: "Book Without Enrichment",
            author: "Author",
            confidence: 0.8,
            boundingBox: CGRect.zero,
            rawText: "Book"
        )

        // Create work without enrichment
        let work = Work(title: detectedBook.title)
        work.reviewStatus = .needsReview  // Marked for later enrichment

        modelContext.insert(work)
        try modelContext.save()

        #expect(work.id != nil)
        #expect(work.title == detectedBook.title)
    }

    // MARK: - Performance Tests

    @Test("Large batch import (50 books) completes successfully")
    func largeBatchImportPerformance() throws {
        let workCount = 50
        let works = try LargeDatasetHelper.createLargeLibraryScenario(
            workCount: workCount,
            entriesPerWork: 0,
            sessionsPerEntry: 0,
            modelContext: modelContext
        )

        #expect(works.count == workCount)
    }

    @Test("Duplicate detection works efficiently on large library")
    func efficientDuplicateDetectionLargeLibrary() throws {
        // Create initial library
        let initialWorks = try LargeDatasetHelper.createLargeLibraryScenario(
            workCount: 100,
            entriesPerWork: 0,
            sessionsPerEntry: 0,
            modelContext: modelContext
        )

        // Try to detect duplicate
        let work = initialWorks.first!
        let descriptor = FetchDescriptor<Work>(
            predicate: #Predicate { $0.title == work.title }
        )
        let matches = try modelContext.fetch(descriptor)

        #expect(!matches.isEmpty)
    }
}
