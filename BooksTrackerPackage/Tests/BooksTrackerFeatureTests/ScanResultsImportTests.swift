//
//  ScanResultsImportTests.swift
//  BooksTrackerFeatureTests
//
//  Tests for scan results import logic with review status
//

import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

@Suite("Scan Results Import Tests")
@MainActor
struct ScanResultsImportTests {

    @Test func importSetsCorrectReviewStatus() async throws {
        // Create in-memory model context
        let container = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        // Create high and low confidence books
        let highConfidenceBook = DetectedBook(
            title: "High Confidence",
            author: "Author",
            confidence: 0.95,
            boundingBox: CGRect.zero,
            rawText: "High Confidence by Author"
        )

        let lowConfidenceBook = DetectedBook(
            title: "Low Confidence",
            author: "Author",
            confidence: 0.40,
            boundingBox: CGRect.zero,
            rawText: "Low Confidence by Author"
        )

        // Create scan result
        let scanResult = ScanResult(
            detectedBooks: [highConfidenceBook, lowConfidenceBook],
            totalProcessingTime: 1.0
        )

        // Create model and import
        let resultsModel = ScanResultsModel(scanResult: scanResult)

        // Mark both as confirmed (simulate user accepting them)
        resultsModel.detectedBooks[0].status = .confirmed
        resultsModel.detectedBooks[1].status = .confirmed

        // Import books
        let enrichmentQueue = EnrichmentQueue()
        await resultsModel.addAllToLibrary(modelContext: context, enrichmentQueue: enrichmentQueue)

        // Fetch works from context
        let descriptor = FetchDescriptor<Work>()
        let works = try context.fetch(descriptor)

        // Verify high confidence book has .verified status
        let highWork = works.first { $0.title == "High Confidence" }
        #expect(highWork != nil, "High confidence book should be imported")
        #expect(highWork?.reviewStatus == .verified, "High confidence book should have .verified status")

        // Verify low confidence book has .needsReview status
        let lowWork = works.first { $0.title == "Low Confidence" }
        #expect(lowWork != nil, "Low confidence book should be imported")
        #expect(lowWork?.reviewStatus == .needsReview, "Low confidence book should have .needsReview status")
    }

    @Test func importStoresOriginalImagePathAndBoundingBox() async throws {
        // Create in-memory model context
        let container = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        // Create detected book with image metadata
        let testImagePath = "/tmp/test_scan_123.jpg"
        let testBoundingBox = CGRect(x: 10, y: 20, width: 100, height: 200)

        var detectedBook = DetectedBook(
            title: "Test Book",
            author: "Test Author",
            confidence: 0.85,
            boundingBox: testBoundingBox,
            rawText: "Test Book by Test Author"
        )
        detectedBook.originalImagePath = testImagePath

        // Create scan result
        let scanResult = ScanResult(
            detectedBooks: [detectedBook],
            totalProcessingTime: 1.0
        )

        // Create model and import
        let resultsModel = ScanResultsModel(scanResult: scanResult)
        resultsModel.detectedBooks[0].status = .confirmed

        // Import books
        let enrichmentQueue = EnrichmentQueue()
        await resultsModel.addAllToLibrary(modelContext: context, enrichmentQueue: enrichmentQueue)

        // Fetch works from context
        let descriptor = FetchDescriptor<Work>()
        let works = try context.fetch(descriptor)

        // Verify image metadata stored
        let work = works.first { $0.title == "Test Book" }
        #expect(work != nil, "Book should be imported")
        #expect(work?.originalImagePath == testImagePath, "Original image path should be stored")
        #expect(work?.boundingBox == testBoundingBox, "Bounding box should be stored")
    }
}
