import Testing
import Foundation
@testable import BooksTrackerFeature

/// Tests for SSEClient V3 event parsing and connection handling
///
/// These tests validate:
/// - V3 scan event parsing (initialized, progress, completed, failed)
/// - Ping/keep-alive handling
/// - Error event handling
/// - Job type routing for unprefixed events
@Suite("SSE Client V3 Tests")
struct SSEClientTests {

    // MARK: - V3 Scan Event Parsing Tests

    @Test("V3ScanInitialized parses correctly")
    func v3ScanInitialized_parsesCorrectly() throws {
        let json = """
        {
            "jobId": "scan_123",
            "status": "initialized",
            "progress": 0,
            "processedCount": 0,
            "totalCount": 5,
            "timestamp": "2025-01-15T10:30:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(V3ScanInitialized.self, from: data)

        #expect(event.jobId == "scan_123")
        #expect(event.status == "initialized")
        #expect(event.progress == 0)
        #expect(event.processedCount == 0)
        #expect(event.totalCount == 5)
        #expect(event.timestamp == "2025-01-15T10:30:00Z")
    }

    @Test("V3ScanProgress parses with all fields")
    func v3ScanProgress_parsesAllFields() throws {
        let json = """
        {
            "jobId": "scan_123",
            "status": "processing",
            "progress": 0.75,
            "processedCount": 15,
            "totalCount": 20,
            "message": "Processing image 15 of 20",
            "timestamp": "2025-01-15T10:32:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(V3ScanProgress.self, from: data)

        #expect(event.jobId == "scan_123")
        #expect(event.status == "processing")
        #expect(event.progress == 0.75)
        #expect(event.processedCount == 15)
        #expect(event.totalCount == 20)
        #expect(event.message == "Processing image 15 of 20")
        #expect(event.timestamp == "2025-01-15T10:32:00Z")
    }

    @Test("V3ScanProgress handles missing optional fields")
    func v3ScanProgress_handlesOptionalFields() throws {
        let json = """
        {
            "jobId": "scan_123",
            "status": "processing"
        }
        """

        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(V3ScanProgress.self, from: data)

        #expect(event.jobId == "scan_123")
        #expect(event.status == "processing")
        #expect(event.progress == nil)
        #expect(event.processedCount == nil)
        #expect(event.totalCount == nil)
        #expect(event.message == nil)
    }

    @Test("V3ScanCompleted parses with books array")
    func v3ScanCompleted_parsesWithBooks() throws {
        let json = """
        {
            "jobId": "scan_123",
            "status": "completed",
            "progress": 100,
            "processedCount": 5,
            "totalCount": 5,
            "completedAt": "2025-01-15T10:35:00Z",
            "books": [
                {
                    "isbn": "9780134685991",
                    "title": "Effective Java",
                    "author": "Joshua Bloch",
                    "confidence": 0.95,
                    "enrichmentStatus": "success"
                }
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(V3ScanCompleted.self, from: data)

        #expect(event.jobId == "scan_123")
        #expect(event.status == "completed")
        #expect(event.progress == 100)
        #expect(event.books.count == 1)
        #expect(event.books.first?.isbn == "9780134685991")
        #expect(event.books.first?.title == "Effective Java")
        #expect(event.books.first?.confidence == 0.95)
        #expect(event.books.first?.enrichmentStatus == "success")
        // Test convenience accessor
        #expect(event.results.count == 1)
    }

    @Test("V3ScanFailed parses error details")
    func v3ScanFailed_parsesErrorDetails() throws {
        let json = """
        {
            "jobId": "scan_123",
            "status": "failed",
            "error": {
                "code": "TIMEOUT",
                "message": "Job timed out after 300 seconds"
            }
        }
        """

        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(V3ScanFailed.self, from: data)

        #expect(event.jobId == "scan_123")
        #expect(event.status == "failed")
        #expect(event.error.code == "TIMEOUT")
        #expect(event.error.message == "Job timed out after 300 seconds")
    }

    @Test("V3ScanFailed handles optional timestamp")
    func v3ScanFailed_handlesOptionalTimestamp() throws {
        let json = """
        {
            "jobId": "scan_123",
            "status": "failed",
            "timestamp": "2025-01-15T10:35:00Z",
            "error": {
                "code": "INTERNAL_ERROR",
                "message": "Unexpected error"
            }
        }
        """

        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(V3ScanFailed.self, from: data)

        #expect(event.timestamp == "2025-01-15T10:35:00Z")
    }

    // MARK: - Ping Event Tests

    @Test("V3Ping parses correctly")
    func v3Ping_parsesCorrectly() throws {
        let json = """
        {
            "timestamp": "2025-01-15T10:30:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(V3Ping.self, from: data)

        #expect(event.timestamp == "2025-01-15T10:30:00Z")
    }

    // MARK: - Legacy Enrichment Event Tests

    @Test("EnrichmentProgress parses correctly")
    func enrichmentProgress_parsesCorrectly() throws {
        let json = """
        {
            "isbn": "9780134685991",
            "status": "processing",
            "progress": 50,
            "provider": "google-books"
        }
        """

        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(EnrichmentProgress.self, from: data)

        #expect(event.isbn == "9780134685991")
        #expect(event.status == "processing")
        #expect(event.progress == 50)
        #expect(event.provider == "google-books")
    }

    @Test("EnrichmentCompleted parses correctly")
    func enrichmentCompleted_parsesCorrectly() throws {
        let json = """
        {
            "isbn": "9780134685991",
            "status": "completed",
            "data": {
                "title": "Effective Java",
                "author": "Joshua Bloch"
            }
        }
        """

        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(EnrichmentCompleted.self, from: data)

        #expect(event.isbn == "9780134685991")
        #expect(event.status == "completed")
    }

    @Test("EnrichmentFailed parses correctly")
    func enrichmentFailed_parsesCorrectly() throws {
        let json = """
        {
            "isbn": "9780134685991",
            "status": "failed",
            "error": "Book not found in any provider"
        }
        """

        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(EnrichmentFailed.self, from: data)

        #expect(event.isbn == "9780134685991")
        #expect(event.status == "failed")
        #expect(event.error == "Book not found in any provider")
    }

    // MARK: - CSV Import Event Tests

    @Test("CSVImportProgress parses correctly")
    func csvImportProgress_parsesCorrectly() throws {
        let json = """
        {
            "jobId": "import_456",
            "status": "processing",
            "progress": 0.75,
            "processedCount": 75,
            "totalCount": 100
        }
        """

        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(CSVImportProgress.self, from: data)

        #expect(event.jobId == "import_456")
        #expect(event.status == "processing")
        #expect(event.progress == 0.75)
        #expect(event.processedCount == 75)
        #expect(event.totalCount == 100)
    }

    @Test("CSVImportCompleted parses correctly")
    func csvImportCompleted_parsesCorrectly() throws {
        let json = """
        {
            "jobId": "import_456",
            "status": "completed",
            "progress": 1.0,
            "processedCount": 100,
            "totalCount": 100
        }
        """

        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(CSVImportCompleted.self, from: data)

        #expect(event.jobId == "import_456")
        #expect(event.status == "completed")
        #expect(event.progress == 1.0)
        #expect(event.processedCount == 100)
        #expect(event.totalCount == 100)
    }

    @Test("CSVImportFailed parses correctly with full ErrorDetail")
    func csvImportFailed_parsesCorrectly_withFullErrorDetail() throws {
        let json = """
        {
            "jobId": "csv_job_abc",
            "status": "failed",
            "error": {
                "message": "CSV row 3 has an invalid ISBN '1234'.",
                "code": "INVALID_FORMAT",
                "retryable": false
            }
        }
        """
        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(CSVImportFailed.self, from: data)

        #expect(event.jobId == "csv_job_abc")
        #expect(event.status == "failed")
        #expect(event.error.message == "CSV row 3 has an invalid ISBN '1234'.")
        #expect(event.error.code == "INVALID_FORMAT")
        #expect(event.error.retryable == false)
    }

    @Test("CSVImportFailed parses correctly with minimal ErrorDetail")
    func csvImportFailed_parsesCorrectly_withMinimalErrorDetail() throws {
        let json = """
        {
            "jobId": "csv_job_def",
            "status": "failed",
            "error": {
                "message": "Internal server error during CSV processing."
            }
        }
        """
        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(CSVImportFailed.self, from: data)

        #expect(event.jobId == "csv_job_def")
        #expect(event.status == "failed")
        #expect(event.error.message == "Internal server error during CSV processing.")
        #expect(event.error.code == nil)
        #expect(event.error.retryable == nil)
    }

    // MARK: - EnrichmentEvent Enum Tests

    @Test("EnrichmentEvent equality works for V3 events")
    func enrichmentEvent_equalityWorksForV3() throws {
        let event1 = EnrichmentEvent.v3ScanProgress(V3ScanProgress(
            jobId: "scan_123",
            status: "processing",
            progress: 0.5,
            processedCount: 10,
            totalCount: 20,
            timestamp: nil,
            message: nil
        ))

        let event2 = EnrichmentEvent.v3ScanProgress(V3ScanProgress(
            jobId: "scan_123",
            status: "processing",
            progress: 0.5,
            processedCount: 10,
            totalCount: 20,
            timestamp: nil,
            message: nil
        ))

        #expect(event1 == event2)
    }

    @Test("EnrichmentEvent distinguishes different event types")
    func enrichmentEvent_distinguishesDifferentTypes() throws {
        let progressEvent = EnrichmentEvent.v3ScanProgress(V3ScanProgress(
            jobId: "scan_123",
            status: "processing"
        ))

        let completedEvent = EnrichmentEvent.v3ScanCompleted(V3ScanCompleted(
            jobId: "scan_123",
            status: "completed",
            books: []
        ))

        #expect(progressEvent != completedEvent)
    }

    // MARK: - SSEJobType Routing Tests

    @Test("SSEJobType has correct cases")
    func sseJobType_hasCorrectCases() {
        let enrichment = SSEJobType.enrichment
        let csvImport = SSEJobType.csvImport
        let bookshelfScan = SSEJobType.bookshelfScan

        // Verify all cases exist (compile-time check)
        #expect(enrichment == .enrichment)
        #expect(csvImport == .csvImport)
        #expect(bookshelfScan == .bookshelfScan)
    }

    // MARK: - V3ScanBookResult Tests

    @Test("V3ScanBookResult parses with all fields")
    func v3ScanBookResult_parsesAllFields() throws {
        let json = """
        {
            "isbn": "9780134685991",
            "title": "Effective Java",
            "author": "Joshua Bloch",
            "confidence": 0.95,
            "coverUrl": "https://covers.example.com/book.jpg",
            "enrichmentStatus": "success",
            "publisher": "Addison-Wesley",
            "publicationYear": 2018
        }
        """

        let data = json.data(using: .utf8)!
        let result = try JSONDecoder().decode(V3ScanBookResult.self, from: data)

        #expect(result.isbn == "9780134685991")
        #expect(result.title == "Effective Java")
        #expect(result.author == "Joshua Bloch")
        #expect(result.confidence == 0.95)
        #expect(result.coverUrl == "https://covers.example.com/book.jpg")
        #expect(result.enrichmentStatus == "success")
        #expect(result.publisher == "Addison-Wesley")
        #expect(result.publicationYear == 2018)
    }

    @Test("V3ScanBookResult handles optional fields")
    func v3ScanBookResult_handlesOptionalFields() throws {
        let json = """
        {
            "title": "Effective Java",
            "confidence": 0.8,
            "enrichmentStatus": "partial"
        }
        """

        let data = json.data(using: .utf8)!
        let result = try JSONDecoder().decode(V3ScanBookResult.self, from: data)

        #expect(result.isbn == nil)
        #expect(result.title == "Effective Java")
        #expect(result.author == nil)
        #expect(result.confidence == 0.8)
        #expect(result.coverUrl == nil)
        #expect(result.enrichmentStatus == "partial")
    }
}
