import Testing
import Foundation
@testable import BooksTrackerFeature

// MARK: - SSE Client Tests

@Suite("SSEClient Tests")
struct SSEClientTests {

    // MARK: - Event Parsing Tests

    @Test("Parse queued event")
    func testParseQueuedEvent() async throws {
        var receivedQueued: SSEQueuedEvent?

        let client = SSEClient(
            baseURL: "https://test.example.com",
            onQueued: { event in receivedQueued = event },
            onStarted: { _ in },
            onProgress: { _ in },
            onComplete: { _ in },
            onError: { _ in }
        )

        // Simulate SSE event data
        let eventData = """
        event: queued
        data: {"status":"queued","job_id":"import_test123"}

        """

        await client.parseSSEEvents(eventData)

        #expect(receivedQueued != nil)
        #expect(receivedQueued?.status == "queued")
        #expect(receivedQueued?.jobId == "import_test123")
    }

    @Test("Parse started event")
    func testParseStartedEvent() async throws {
        var receivedStarted: SSEStartedEvent?

        let client = SSEClient(
            baseURL: "https://test.example.com",
            onQueued: { _ in },
            onStarted: { event in receivedStarted = event },
            onProgress: { _ in },
            onComplete: { _ in },
            onError: { _ in }
        )

        let eventData = """
        event: started
        data: {"status":"processing","total_rows":150,"started_at":"2025-11-26T10:00:00Z"}

        """

        await client.parseSSEEvents(eventData)

        #expect(receivedStarted != nil)
        #expect(receivedStarted?.status == "processing")
        #expect(receivedStarted?.totalRows == 150)
        #expect(receivedStarted?.startedAt == "2025-11-26T10:00:00Z")
    }

    @Test("Parse progress event")
    func testParseProgressEvent() async throws {
        var receivedProgress: SSEProgressEvent?

        let client = SSEClient(
            baseURL: "https://test.example.com",
            onQueued: { _ in },
            onStarted: { _ in },
            onProgress: { event in receivedProgress = event },
            onComplete: { _ in },
            onError: { _ in }
        )

        let eventData = """
        event: progress
        data: {"progress":0.5,"processed_rows":75,"successful_rows":72,"failed_rows":3}

        """

        await client.parseSSEEvents(eventData)

        #expect(receivedProgress != nil)
        #expect(receivedProgress?.progress == 0.5)
        #expect(receivedProgress?.processedRows == 75)
        #expect(receivedProgress?.successfulRows == 72)
        #expect(receivedProgress?.failedRows == 3)
    }

    @Test("Parse complete event")
    func testParseCompleteEvent() async throws {
        var receivedComplete: SSECompleteEvent?

        let client = SSEClient(
            baseURL: "https://test.example.com",
            onQueued: { _ in },
            onStarted: { _ in },
            onProgress: { _ in },
            onComplete: { event in receivedComplete = event },
            onError: { _ in }
        )

        let eventData = """
        event: complete
        data: {"status":"complete","progress":1.0,"result_summary":{"books_created":145,"books_updated":0,"duplicates_skipped":5,"enrichment_succeeded":140,"enrichment_failed":5,"errors":[]}}

        """

        await client.parseSSEEvents(eventData)

        #expect(receivedComplete != nil)
        #expect(receivedComplete?.status == "complete")
        #expect(receivedComplete?.progress == 1.0)
        #expect(receivedComplete?.resultSummary.booksCreated == 145)
        #expect(receivedComplete?.resultSummary.enrichmentSucceeded == 140)
    }

    @Test("Parse error event")
    func testParseErrorEvent() async throws {
        var receivedError: SSEClientError?

        let client = SSEClient(
            baseURL: "https://test.example.com",
            onQueued: { _ in },
            onStarted: { _ in },
            onProgress: { _ in },
            onComplete: { _ in },
            onError: { error in receivedError = error }
        )

        let eventData = """
        event: error
        data: {"status":"failed","error":"CSV parsing failed at row 42","processed_rows":41}

        """

        await client.parseSSEEvents(eventData)

        #expect(receivedError != nil)
        if case .serverError(let message) = receivedError {
            #expect(message == "CSV parsing failed at row 42")
        } else {
            Issue.record("Expected serverError, got \(String(describing: receivedError))")
        }
    }

    // MARK: - Event ID Handling Tests

    @Test("Store last event ID for reconnection")
    func testLastEventIdStorage() async throws {
        let client = SSEClient(
            baseURL: "https://test.example.com",
            onQueued: { _ in },
            onStarted: { _ in },
            onProgress: { _ in },
            onComplete: { _ in },
            onError: { _ in }
        )

        let eventData = """
        id: event-12345
        event: progress
        data: {"progress":0.5,"processed_rows":75,"successful_rows":72,"failed_rows":3}

        """

        await client.parseSSEEvents(eventData)

        // Verify lastEventId is stored (internal state)
        // In real implementation, we'd verify this in reconnection logic
    }

    // MARK: - Multi-line Data Tests

    @Test("Parse multi-line data in single event")
    func testMultiLineData() async throws {
        var receivedComplete: SSECompleteEvent?

        let client = SSEClient(
            baseURL: "https://test.example.com",
            onQueued: { _ in },
            onStarted: { _ in },
            onProgress: { _ in },
            onComplete: { event in receivedComplete = event },
            onError: { _ in }
        )

        // Some SSE servers split long JSON across multiple data: lines
        let eventData = """
        event: complete
        data: {"status":"complete","progress":1.0,
        data: "result_summary":{"books_created":145,"books_updated":0,
        data: "duplicates_skipped":5,"enrichment_succeeded":140,"enrichment_failed":5,"errors":[]}}

        """

        await client.parseSSEEvents(eventData)

        #expect(receivedComplete != nil)
        #expect(receivedComplete?.status == "complete")
        #expect(receivedComplete?.resultSummary.booksCreated == 145)
    }

    // MARK: - Comment Line Tests

    @Test("Ignore comment lines")
    func testIgnoreComments() async throws {
        var eventCount = 0

        let client = SSEClient(
            baseURL: "https://test.example.com",
            onQueued: { _ in eventCount += 1 },
            onStarted: { _ in },
            onProgress: { _ in },
            onComplete: { _ in },
            onError: { _ in }
        )

        let eventData = """
        : This is a comment line
        : Another comment
        event: queued
        data: {"status":"queued","job_id":"import_test123"}

        """

        await client.parseSSEEvents(eventData)

        #expect(eventCount == 1) // Only one event should be processed
    }

    // MARK: - Buffer Handling Tests

    @Test("Handle incomplete events in buffer")
    func testBufferHandling() async throws {
        var receivedProgress = 0

        let client = SSEClient(
            baseURL: "https://test.example.com",
            onQueued: { _ in },
            onStarted: { _ in },
            onProgress: { _ in receivedProgress += 1 },
            onComplete: { _ in },
            onError: { _ in }
        )

        // First chunk (incomplete)
        let chunk1 = """
        event: progress
        data: {"progress":0.5,"processed_rows":75,"successful_rows":72
        """

        await client.parseSSEEvents(chunk1)
        #expect(receivedProgress == 0) // Event not complete yet

        // Second chunk (completes the event)
        let chunk2 = """
        ,"failed_rows":3}

        """

        await client.parseSSEEvents(chunk2)
        #expect(receivedProgress == 1) // Event should now be processed
    }

    // MARK: - Multiple Events Tests

    @Test("Parse multiple events in single chunk")
    func testMultipleEvents() async throws {
        var queuedCount = 0
        var progressCount = 0

        let client = SSEClient(
            baseURL: "https://test.example.com",
            onQueued: { _ in queuedCount += 1 },
            onStarted: { _ in },
            onProgress: { _ in progressCount += 1 },
            onComplete: { _ in },
            onError: { _ in }
        )

        let eventData = """
        event: queued
        data: {"status":"queued","job_id":"import_test123"}

        event: progress
        data: {"progress":0.1,"processed_rows":15,"successful_rows":14,"failed_rows":1}

        event: progress
        data: {"progress":0.5,"processed_rows":75,"successful_rows":72,"failed_rows":3}

        """

        await client.parseSSEEvents(eventData)

        #expect(queuedCount == 1)
        #expect(progressCount == 2)
    }

    // MARK: - Error Handling Tests

    @Test("Handle invalid JSON data")
    func testInvalidJSON() async throws {
        var receivedError: SSEClientError?

        let client = SSEClient(
            baseURL: "https://test.example.com",
            onQueued: { _ in },
            onStarted: { _ in },
            onProgress: { _ in },
            onComplete: { _ in },
            onError: { error in receivedError = error }
        )

        let eventData = """
        event: progress
        data: {invalid json here}

        """

        await client.parseSSEEvents(eventData)

        #expect(receivedError != nil)
        if case .eventParsingFailed = receivedError {
            // Expected error type
        } else {
            Issue.record("Expected eventParsingFailed, got \(String(describing: receivedError))")
        }
    }

    // MARK: - Retry Directive Tests

    @Test("Parse retry directive")
    func testRetryDirective() async throws {
        let client = SSEClient(
            baseURL: "https://test.example.com",
            onQueued: { _ in },
            onStarted: { _ in },
            onProgress: { _ in },
            onComplete: { _ in },
            onError: { _ in }
        )

        let eventData = """
        retry: 5000
        event: progress
        data: {"progress":0.5,"processed_rows":75,"successful_rows":72,"failed_rows":3}

        """

        // Should parse without error and log retry value
        await client.parseSSEEvents(eventData)
    }
}

// MARK: - SSE Models Tests

@Suite("SSE Models Tests")
struct SSEModelsTests {

    @Test("SSEProgressEvent decoding")
    func testProgressEventDecoding() throws {
        let json = """
        {
            "progress": 0.75,
            "processed_rows": 112,
            "successful_rows": 110,
            "failed_rows": 2
        }
        """

        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(SSEProgressEvent.self, from: data)

        #expect(event.progress == 0.75)
        #expect(event.processedRows == 112)
        #expect(event.successfulRows == 110)
        #expect(event.failedRows == 2)
    }

    @Test("SSECompleteEvent decoding")
    func testCompleteEventDecoding() throws {
        let json = """
        {
            "status": "complete",
            "progress": 1.0,
            "result_summary": {
                "books_created": 145,
                "books_updated": 5,
                "duplicates_skipped": 10,
                "enrichment_succeeded": 140,
                "enrichment_failed": 5,
                "errors": [
                    {"row": 42, "isbn": "invalid", "error": "Invalid ISBN format"}
                ]
            }
        }
        """

        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(SSECompleteEvent.self, from: data)

        #expect(event.status == "complete")
        #expect(event.progress == 1.0)
        #expect(event.resultSummary.booksCreated == 145)
        #expect(event.resultSummary.enrichmentSucceeded == 140)
        #expect(event.resultSummary.errors?.count == 1)
        #expect(event.resultSummary.errors?.first?.row == 42)
    }

    @Test("SSEStartedEvent decoding")
    func testStartedEventDecoding() throws {
        let json = """
        {
            "status": "processing",
            "total_rows": 200,
            "started_at": "2025-11-26T10:30:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(SSEStartedEvent.self, from: data)

        #expect(event.status == "processing")
        #expect(event.totalRows == 200)
        #expect(event.startedAt == "2025-11-26T10:30:00Z")
    }

    @Test("SSEErrorEvent decoding")
    func testErrorEventDecoding() throws {
        let json = """
        {
            "status": "failed",
            "error": "Network timeout during enrichment",
            "processed_rows": 50
        }
        """

        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(SSEErrorEvent.self, from: data)

        #expect(event.status == "failed")
        #expect(event.error == "Network timeout during enrichment")
        #expect(event.processedRows == 50)
    }

    @Test("SSEQueuedEvent decoding")
    func testQueuedEventDecoding() throws {
        let json = """
        {
            "status": "queued",
            "job_id": "import_abc123def456"
        }
        """

        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(SSEQueuedEvent.self, from: data)

        #expect(event.status == "queued")
        #expect(event.jobId == "import_abc123def456")
    }
}
