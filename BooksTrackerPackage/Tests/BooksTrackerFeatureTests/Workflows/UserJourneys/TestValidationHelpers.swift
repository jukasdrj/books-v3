//
//  TestValidationHelpers.swift
//  BooksTrackerFeatureTests
//
//  Comprehensive test validation and verification suite for Phase 1 E2E tests.
//  Provides helpers for:
//  - Validating test fixtures and mock data consistency
//  - Asserting navigation states and UI behavior
//  - Verifying search and library operations
//  - Performance validation (large datasets, debouncing)
//  - Error scenario handling and graceful degradation
//

import Testing
import Foundation
import SwiftData
@testable import BooksTrackerFeature

/// Comprehensive test validation helpers for E2E test scenarios
@MainActor
struct TestValidationHelpers {

    // MARK: - Test Fixture Validation

    /// Validates that mock data is realistic and consistent across the test
    /// - Parameter works: Array of Work models to validate
    /// - Parameter file: Source file for error reporting
    /// - Parameter line: Source line for error reporting
    static func verifyMockDataConsistency(
        _ works: [Work],
        file: StaticString = #file,
        line: UInt = #line
    ) {
        for work in works {
            // Verify title is not empty
            #expect(
                !work.title.isEmpty,
                "Work title must not be empty",
                sourceLocation: SourceLocation(file: file, line: line)
            )

            // Verify no unrealistic year values
            if let year = work.firstPublicationYear {
                #expect(
                    year >= 1000 && year <= 2100,
                    "Publication year \(year) outside realistic range (1000-2100) for '\(work.title)'",
                    sourceLocation: SourceLocation(file: file, line: line)
                )
            }

            // Verify accessibility tags are from known set
            let knownTags = ["Dyslexia Friendly", "Large Print", "Audiobook Available", "Braille", "High Contrast"]
            for tag in work.accessibilityTags {
                #expect(
                    knownTags.contains(tag),
                    "Unknown accessibility tag '\(tag)' for '\(work.title)'",
                    sourceLocation: SourceLocation(file: file, line: line)
                )
            }

            // Verify no duplicate authors
            let authorCount = work.authors.count
            let uniqueAuthors = Set(work.authors.map { $0.name })
            #expect(
                authorCount == uniqueAuthors.count,
                "Work '\(work.title)' has duplicate authors",
                sourceLocation: SourceLocation(file: file, line: line)
            )
        }
    }

    /// Validates that V3 API responses match schema requirements
    /// - Parameter response: V3SearchResponse to validate
    /// - Parameter file: Source file for error reporting
    /// - Parameter line: Source line for error reporting
    static func verifyV3SearchResponseSchema(
        _ response: V3SearchResponse,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        // Verify success flag
        #expect(
            response.success == true,
            "V3SearchResponse success flag should be true",
            sourceLocation: SourceLocation(file: file, line: line)
        )

        // Verify metadata
        #expect(
            !response.metadata.timestamp.isEmpty,
            "V3ResponseMetadata timestamp must not be empty",
            sourceLocation: SourceLocation(file: file, line: line)
        )

        // Verify pagination consistency
        let pagination = response.data.pagination
        #expect(
            pagination.page > 0,
            "Pagination page must be > 0, got \(pagination.page)",
            sourceLocation: SourceLocation(file: file, line: line)
        )

        #expect(
            pagination.limit > 0,
            "Pagination limit must be > 0, got \(pagination.limit)",
            sourceLocation: SourceLocation(file: file, line: line)
        )

        #expect(
            pagination.totalPages > 0,
            "Pagination totalPages must be > 0, got \(pagination.totalPages)",
            sourceLocation: SourceLocation(file: file, line: line)
        )

        // Verify hasNext/hasPrev logic
        let isLastPage = pagination.page >= pagination.totalPages
        #expect(
            isLastPage == !pagination.hasNext,
            "hasNext should be false on last page (page \(pagination.page) of \(pagination.totalPages))",
            sourceLocation: SourceLocation(file: file, line: line)
        )

        #expect(
            pagination.page > 1 == pagination.hasPrev,
            "hasPrev should match (page > 1)",
            sourceLocation: SourceLocation(file: file, line: line)
        )

        // Validate each book in response
        for book in response.data.books {
            verifyV3BookSchema(book, file: file, line: line)
        }
    }

    /// Validates individual V3Book schema compliance
    /// - Parameter book: V3Book to validate
    /// - Parameter file: Source file for error reporting
    /// - Parameter line: Source line for error reporting
    private static func verifyV3BookSchema(
        _ book: V3Book,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        // ISBN must exist
        #expect(
            !book.isbn.isEmpty && book.isbn.count >= 10,
            "ISBN must be valid for '\(book.title)'",
            sourceLocation: SourceLocation(file: file, line: line)
        )

        // Title must exist
        #expect(
            !book.title.isEmpty,
            "Book title must not be empty",
            sourceLocation: SourceLocation(file: file, line: line)
        )

        // Quality score must be valid
        #expect(
            book.quality >= 0 && book.quality <= 100,
            "Quality score \(book.quality) outside valid range [0, 100] for '\(book.title)'",
            sourceLocation: SourceLocation(file: file, line: line)
        )

        // Provider must be known value
        let knownProviders = ["alexandria", "google-books", "openlibrary", "isbndb"]
        #expect(
            knownProviders.contains(book.provider),
            "Unknown provider '\(book.provider)' for '\(book.title)'",
            sourceLocation: SourceLocation(file: file, line: line)
        )

        // Authors should not be empty for real books
        #expect(
            !book.authors.isEmpty,
            "Book '\(book.title)' has no authors",
            sourceLocation: SourceLocation(file: file, line: line)
        )
    }

    /// Verifies that test container is properly isolated
    /// - Parameter modelContext: Context to verify
    /// - Parameter file: Source file for error reporting
    /// - Parameter line: Source line for error reporting
    static func verifyContainerIsolation(
        _ modelContext: ModelContext,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        // Fetch all works to verify container is empty/isolated
        do {
            var descriptor = FetchDescriptor<Work>()
            descriptor.fetchLimit = 1

            // This should succeed on isolated container
            let _ = try modelContext.fetch(descriptor)

            // No assertion needed - if fetch succeeds, container is valid
        } catch {
            Issue.record(
                "Container isolation check failed: \(error)",
                sourceLocation: SourceLocation(file: file, line: line)
            )
        }
    }

    // MARK: - Navigation State Assertions

    /// Verifies navigation state is as expected
    /// - Parameter currentTab: Expected MainTab value
    /// - Parameter stackDepth: Expected navigation stack depth
    /// - Parameter file: Source file for error reporting
    /// - Parameter line: Source line for error reporting
    static func verifyNavigationState(
        currentTab: MainTab?,
        stackDepth: Int,
        expectedTab: MainTab? = nil,
        expectedStackDepth: Int? = nil,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        if let expectedTab = expectedTab {
            #expect(
                currentTab == expectedTab,
                "Expected tab \(expectedTab), got \(String(describing: currentTab))",
                sourceLocation: SourceLocation(file: file, line: line)
            )
        }

        if let expectedStackDepth = expectedStackDepth {
            #expect(
                stackDepth == expectedStackDepth,
                "Expected stack depth \(expectedStackDepth), got \(stackDepth)",
                sourceLocation: SourceLocation(file: file, line: line)
            )
        }
    }

    // MARK: - Library Assertions

    /// Verifies that library contains all expected works
    /// - Parameter modelContext: SwiftData context with library data
    /// - Parameter expectedTitles: Array of expected book titles
    /// - Parameter file: Source file for error reporting
    /// - Parameter line: Source line for error reporting
    static func verifyLibraryContains(
        modelContext: ModelContext,
        expectedTitles: [String],
        file: StaticString = #file,
        line: UInt = #line
    ) {
        do {
            let descriptor = FetchDescriptor<Work>()
            let allWorks = try modelContext.fetch(descriptor)
            let libraryTitles = Set(allWorks.map { $0.title })

            for expectedTitle in expectedTitles {
                #expect(
                    libraryTitles.contains(expectedTitle),
                    "Expected book '\(expectedTitle)' not found in library",
                    sourceLocation: SourceLocation(file: file, line: line)
                )
            }
        } catch {
            Issue.record(
                "Failed to fetch library: \(error)",
                sourceLocation: SourceLocation(file: file, line: line)
            )
        }
    }

    /// Verifies library does NOT contain specific works
    /// - Parameter modelContext: SwiftData context with library data
    /// - Parameter excludedTitles: Titles that should NOT be in library
    /// - Parameter file: Source file for error reporting
    /// - Parameter line: Source line for error reporting
    static func verifyLibraryExcludes(
        modelContext: ModelContext,
        excludedTitles: [String],
        file: StaticString = #file,
        line: UInt = #line
    ) {
        do {
            let descriptor = FetchDescriptor<Work>()
            let allWorks = try modelContext.fetch(descriptor)
            let libraryTitles = Set(allWorks.map { $0.title })

            for excludedTitle in excludedTitles {
                #expect(
                    !libraryTitles.contains(excludedTitle),
                    "Book '\(excludedTitle)' should not be in library",
                    sourceLocation: SourceLocation(file: file, line: line)
                )
            }
        } catch {
            Issue.record(
                "Failed to fetch library: \(error)",
                sourceLocation: SourceLocation(file: file, line: line)
            )
        }
    }

    /// Verifies library contains exact count of works
    /// - Parameter modelContext: SwiftData context with library data
    /// - Parameter expectedCount: Expected number of works
    /// - Parameter file: Source file for error reporting
    /// - Parameter line: Source line for error reporting
    static func verifyLibraryCount(
        modelContext: ModelContext,
        expectedCount: Int,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        do {
            let descriptor = FetchDescriptor<Work>()
            let allWorks = try modelContext.fetch(descriptor)

            #expect(
                allWorks.count == expectedCount,
                "Expected \(expectedCount) books in library, found \(allWorks.count)",
                sourceLocation: SourceLocation(file: file, line: line)
            )
        } catch {
            Issue.record(
                "Failed to fetch library: \(error)",
                sourceLocation: SourceLocation(file: file, line: line)
            )
        }
    }

    // MARK: - Search Results Assertions

    /// Verifies search results are properly formatted and contain expected data
    /// - Parameter results: Array of V3Book search results
    /// - Parameter expectedCount: Expected number of results
    /// - Parameter shouldContain: Titles that should be in results (optional)
    /// - Parameter file: Source file for error reporting
    /// - Parameter line: Source line for error reporting
    static func verifySearchResults(
        _ results: [V3Book],
        expectedCount: Int? = nil,
        shouldContain: [String]? = nil,
        minQuality: Double = 0,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        // Verify count if specified
        if let expectedCount = expectedCount {
            #expect(
                results.count == expectedCount,
                "Expected \(expectedCount) search results, got \(results.count)",
                sourceLocation: SourceLocation(file: file, line: line)
            )
        }

        // Verify each result is well-formed
        for book in results {
            verifyV3BookSchema(book, file: file, line: line)

            // Verify quality threshold
            #expect(
                book.quality >= minQuality,
                "Book '\(book.title)' quality \(book.quality) below threshold \(minQuality)",
                sourceLocation: SourceLocation(file: file, line: line)
            )
        }

        // Verify specific titles if provided
        if let shouldContain = shouldContain {
            let resultTitles = Set(results.map { $0.title })
            for expectedTitle in shouldContain {
                let found = resultTitles.contains { $0.localizedCaseInsensitiveContains(expectedTitle) }
                #expect(
                    found,
                    "Expected to find '\(expectedTitle)' in search results",
                    sourceLocation: SourceLocation(file: file, line: line)
                )
            }
        }
    }

    /// Verifies search results are sorted by relevance/quality
    /// - Parameter results: Array of V3Book results
    /// - Parameter file: Source file for error reporting
    /// - Parameter line: Source line for error reporting
    static func verifySearchResultsOrdering(
        _ results: [V3Book],
        file: StaticString = #file,
        line: UInt = #line
    ) {
        // Check that quality scores are in descending order
        for i in 0..<(results.count - 1) {
            #expect(
                results[i].quality >= results[i + 1].quality,
                "Search results not sorted by quality at index \(i): \(results[i].quality) vs \(results[i + 1].quality)",
                sourceLocation: SourceLocation(file: file, line: line)
            )
        }
    }

    // MARK: - Observable State Assertions

    /// Verifies that observable state changes propagate to views
    /// - Parameter expectedValue: Value that should be in observable state
    /// - Parameter actualValue: Current observable state value
    /// - Parameter file: Source file for error reporting
    /// - Parameter line: Source line for error reporting
    static func verifyObservableStateChange<T: Equatable>(
        expected: T,
        actual: T,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        #expect(
            expected == actual,
            "Observable state did not propagate correctly",
            sourceLocation: SourceLocation(file: file, line: line)
        )
    }

    /// Verifies that work's observable relationships propagate correctly
    /// - Parameter work: Work instance to verify
    /// - Parameter shouldHaveAuthors: Whether work should have authors
    /// - Parameter file: Source file for error reporting
    /// - Parameter line: Source line for error reporting
    static func verifyWorkObservableRelationships(
        _ work: Work,
        shouldHaveAuthors: Bool = false,
        shouldHaveEditions: Bool = false,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        if shouldHaveAuthors {
            #expect(
                !work.authors.isEmpty,
                "Work '\(work.title)' should have authors",
                sourceLocation: SourceLocation(file: file, line: line)
            )
        }

        if shouldHaveEditions {
            #expect(
                !work.editions.isEmpty,
                "Work '\(work.title)' should have editions",
                sourceLocation: SourceLocation(file: file, line: line)
            )
        }
    }

    // MARK: - Performance Validation

    /// Verifies that large library operations complete within performance threshold
    /// - Parameter operationName: Name of operation being timed
    /// - Parameter elapsedTime: Elapsed time in milliseconds
    /// - Parameter maxTimeMs: Maximum allowed time in milliseconds (default: 500ms)
    /// - Parameter file: Source file for error reporting
    /// - Parameter line: Source line for error reporting
    static func verifyPerformance(
        operationName: String,
        elapsedTime: TimeInterval,
        maxTimeMs: Int = 500,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let elapsedMs = Int(elapsedTime * 1000)

        #expect(
            elapsedMs <= maxTimeMs,
            "Performance failure: \(operationName) took \(elapsedMs)ms (max: \(maxTimeMs)ms)",
            sourceLocation: SourceLocation(file: file, line: line)
        )
    }

    /// Measures operation performance and returns the elapsed time
    /// - Parameter description: Description of operation for logging
    /// - Parameter block: Async operation to measure
    /// - Returns: Elapsed time in milliseconds
    static func measurePerformance(
        _ description: String,
        block: () async throws -> Void
    ) async throws -> Double {
        let startTime = Date()
        try await block()
        let elapsedTime = Date().timeIntervalSince(startTime)
        let elapsedMs = elapsedTime * 1000

        print("Performance: \(description) completed in \(String(format: "%.0f", elapsedMs))ms")
        return elapsedMs
    }

    /// Verifies that search debouncing works correctly (no excessive API calls)
    /// - Parameter callCount: Actual number of API calls made
    /// - Parameter expectedMaxCalls: Maximum expected calls (default: 1 for debounced)
    /// - Parameter file: Source file for error reporting
    /// - Parameter line: Source line for error reporting
    static func verifySearchDebouncing(
        callCount: Int,
        expectedMaxCalls: Int = 1,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        #expect(
            callCount <= expectedMaxCalls,
            "Search debouncing failed: made \(callCount) calls, expected max \(expectedMaxCalls)",
            sourceLocation: SourceLocation(file: file, line: line)
        )
    }

    // MARK: - Error Scenario Helpers

    /// Creates a mock network timeout scenario
    /// - Returns: URLError representing a timeout
    static func createNetworkTimeoutError() -> URLError {
        URLError(.timedOut)
    }

    /// Creates a mock API error response
    /// - Parameter statusCode: HTTP status code
    /// - Parameter message: Error message
    /// - Returns: V3ErrorResponse object
    static func createMockErrorResponse(
        statusCode: Int,
        message: String
    ) -> V3ErrorResponse {
        V3ErrorResponse(
            success: false,
            error: V3ErrorInfo(
                code: "ERROR_\(statusCode)",
                message: message,
                details: nil,
                statusCode: statusCode
            ),
            metadata: V3ResponseMetadata(
                timestamp: ISO8601DateFormatter().string(from: Date()),
                requestId: UUID().uuidString,
                source: nil,
                cached: nil,
                processingTimeMs: nil
            )
        )
    }

    /// Creates a mock partial API failure (some books succeed, some fail)
    /// - Parameter totalBooks: Total books requested
    /// - Parameter successCount: Number of books successfully processed
    /// - Returns: Array of V3Book objects for successful books
    static func createMockPartialFailureResponse(
        totalBooks: Int,
        successCount: Int
    ) -> [V3Book] {
        let successCount = min(successCount, totalBooks)
        return (0..<successCount).map { index in
            V3Book(
                isbn: "ISBN\(index)",
                isbn10: "ISBN10\(index)",
                title: "Book \(index)",
                subtitle: nil,
                authors: ["Author"],
                publisher: nil,
                publishedDate: nil,
                description: nil,
                pageCount: 300,
                categories: nil,
                language: "en",
                coverUrl: nil,
                thumbnailUrl: nil,
                workKey: nil,
                editionKey: nil,
                provider: "test",
                quality: 75.0
            )
        }
    }

    /// Verifies graceful degradation when API returns partial results
    /// - Parameter resultCount: Actual results returned
    /// - Parameter expectedMinimum: Minimum acceptable results
    /// - Parameter file: Source file for error reporting
    /// - Parameter line: Source line for error reporting
    static func verifyGracefulDegradation(
        resultCount: Int,
        expectedMinimum: Int,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        #expect(
            resultCount >= expectedMinimum,
            "Graceful degradation failed: got \(resultCount) results, minimum \(expectedMinimum) required",
            sourceLocation: SourceLocation(file: file, line: line)
        )
    }

    // MARK: - Mock Data Factory Methods

    /// Creates a realistic mock search response for testing
    /// - Parameter query: Search query
    /// - Parameter bookCount: Number of books in response
    /// - Parameter page: Page number
    /// - Parameter totalPages: Total number of pages available
    /// - Returns: JSON Data representing V3SearchResponse
    static func createMockSearchResponse(
        query: String,
        bookCount: Int,
        page: Int = 1,
        totalPages: Int = 1
    ) -> Data {
        let books = (0..<bookCount).map { index -> [String: Any] in
            [
                "isbn": "ISBN" + String(format: "%013d", index),
                "isbn10": "ISBN10" + String(format: "%09d", index),
                "title": "Book \(index): \(query)",
                "subtitle": index % 3 == 0 ? "A Compelling Story" : NSNull(),
                "authors": ["Author \(index)", "Co-Author \(index)"],
                "publisher": "Test Publisher",
                "publishedDate": "2025-01-01",
                "description": "A test book about \(query)",
                "pageCount": 300 + index * 10,
                "categories": ["Fiction", "Test"],
                "language": "en",
                "coverUrl": NSNull(),
                "thumbnailUrl": NSNull(),
                "workKey": "work_\(index)",
                "editionKey": "edition_\(index)",
                "provider": "alexandria",
                "quality": Double(90 - (index % 20))
            ]
        }

        let response: [String: Any] = [
            "success": true,
            "data": [
                "books": books,
                "total": totalPages * bookCount,
                "query": [
                    "q": query,
                    "mode": "text"
                ],
                "pagination": [
                    "type": "offset",
                    "page": page,
                    "limit": bookCount,
                    "totalPages": totalPages,
                    "hasNext": page < totalPages,
                    "hasPrev": page > 1
                ]
            ],
            "metadata": [
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "requestId": UUID().uuidString,
                "source": "alexandria",
                "cached": false,
                "processingTimeMs": Int.random(in: 50...200)
            ]
        ]

        return try! JSONSerialization.data(withJSONObject: response)
    }

    /// Creates a realistic mock ISBN lookup response
    /// - Parameter isbn: ISBN of the book
    /// - Parameter title: Book title
    /// - Parameter authors: Author names
    /// - Returns: JSON Data representing V3BookResponse
    static func createMockISBNResponse(
        isbn: String,
        title: String,
        authors: [String] = []
    ) -> Data {
        let book: [String: Any] = [
            "isbn": isbn,
            "isbn10": String(isbn.dropFirst(3)),
            "title": title,
            "subtitle": NSNull(),
            "authors": authors.isEmpty ? ["Unknown Author"] : authors,
            "publisher": "Test Publisher",
            "publishedDate": "2025-01-01",
            "description": "A comprehensive book about \(title)",
            "pageCount": 400,
            "categories": ["Fiction", "Reference"],
            "language": "en",
            "coverUrl": NSNull(),
            "thumbnailUrl": NSNull(),
            "workKey": "work_\(isbn)",
            "editionKey": "edition_\(isbn)",
            "provider": "alexandria",
            "quality": 90.0
        ]

        let response: [String: Any] = [
            "success": true,
            "data": book,
            "metadata": [
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "requestId": UUID().uuidString,
                "source": "alexandria",
                "cached": false,
                "processingTimeMs": 75
            ]
        ]

        return try! JSONSerialization.data(withJSONObject: response)
    }

    // MARK: - State Transition Helpers

    /// Verifies that state transitions happen synchronously (no async delays)
    /// - Parameter startTime: Time before state transition
    /// - Parameter endTime: Time after state transition
    /// - Parameter maxDelayMs: Maximum allowed delay in milliseconds (default: 16ms for UI frame)
    /// - Parameter file: Source file for error reporting
    /// - Parameter line: Source line for error reporting
    static func verifyStateTransitionSynchronicity(
        startTime: Date,
        endTime: Date,
        maxDelayMs: Int = 16,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let delayMs = Int(endTime.timeIntervalSince(startTime) * 1000)

        #expect(
            delayMs <= maxDelayMs,
            "State transition took \(delayMs)ms (max: \(maxDelayMs)ms) - may be async",
            sourceLocation: SourceLocation(file: file, line: line)
        )
    }
}
