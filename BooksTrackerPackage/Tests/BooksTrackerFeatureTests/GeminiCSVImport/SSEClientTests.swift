import Testing
import Foundation
@testable import BooksTrackerFeature

// MARK: - SSE Client Tests (V2 API)

@Suite("SSEClient Tests - V2 API")
struct SSEClientTests {

    // MARK: - Event Parsing Tests

    @Test("Parse initialized event")
    func testParseInitializedEvent() async throws {
        var receivedInitialized: SSEInitializedEvent?

        let client = SSEClient(
            baseURL: "https://test.example.com",
            onInitialized: { event in receivedInitialized = event },
            onProcessing: { _ in },
            onCompleted: { _ in },
            onFailed: { _ in },
            onError: { _ in },
            onTimeout: { _ in }
        )

        // Simulate SSE event data
        let eventData = """
        event: initialized
        id: 1732713000123-initial
        data: {"jobId":"import_test123","status":"initialized","progress":0,"processedCount":0,"totalCount":100}

        """

        await client.parseSSEEvents(eventData)

        #expect(receivedInitialized != nil)
        #expect(receivedInitialized?.jobId == "import_test123")
        #expect(receivedInitialized?.status == "initialized")
        #expect(receivedInitialized?.progress == 0.0)
        #expect(receivedInitialized?.processedCount == 0)
        #expect(receivedInitialized?.totalCount == 100)
    }

    @Test("Parse processing event")
    func testParseProcessingEvent() async throws {
        var receivedProcessing: SSEProgressEvent?

        let client = SSEClient(
            baseURL: "https://test.example.com",
            onInitialized: { _ in },
            onProcessing: { event in receivedProcessing = event },
            onCompleted: { _ in },
            onFailed: { _ in },
            onError: { _ in },
            onTimeout: { _ in }
        )

        let eventData = """
        event: processing
        id: 1732713002456-progress
        data: {"jobId":"import_test123","status":"processing","progress":0.5,"processedCount":50,"totalCount":100}

        """

        await client.parseSSEEvents(eventData)

        #expect(receivedProcessing != nil)
        #expect(receivedProcessing?.jobId == "import_test123")
        #expect(receivedProcessing?.status == "processing")
        #expect(receivedProcessing?.progress == 0.5)
        #expect(receivedProcessing?.processedCount == 50)
        #expect(receivedProcessing?.totalCount == 100)
    }

    @Test("Parse completed event")
    func testParseCompletedEvent() async throws {
        var receivedCompleted: SSECompleteEvent?

        let client = SSEClient(
            baseURL: "https://test.example.com",
            onInitialized: { _ in },
            onProcessing: { _ in },
            onCompleted: { event in receivedCompleted = event },
            onFailed: { _ in },
            onError: { _ in },
            onTimeout: { _ in }
        )

        let eventData = """
        event: completed
        id: 1732713010789-final
        data: {"jobId":"import_test123","status":"completed","progress":1.0,"processedCount":100,"totalCount":100,"completedAt":"2025-11-27T10:30:10Z"}

        """

        await client.parseSSEEvents(eventData)

        #expect(receivedCompleted != nil)
        #expect(receivedCompleted?.jobId == "import_test123")
        #expect(receivedCompleted?.status == "completed")
        #expect(receivedCompleted?.progress == 1.0)
        #expect(receivedCompleted?.processedCount == 100)
        #expect(receivedCompleted?.totalCount == 100)
        #expect(receivedCompleted?.completedAt == "2025-11-27T10:30:10Z")
    }

    @Test("Parse failed event")
    func testParseFailedEvent() async throws {
        var receivedFailed: SSEErrorEvent?

        let client = SSEClient(
            baseURL: "https://test.example.com",
            onInitialized: { _ in },
            onProcessing: { _ in },
            onCompleted: { _ in },
            onFailed: { event in receivedFailed = event },
            onError: { _ in },
            onTimeout: { _ in }
        )

        let eventData = """
        event: failed
        data: {"jobId":"import_test123","status":"failed","error":"parsing_error","message":"Invalid CSV format"}

        """

        await client.parseSSEEvents(eventData)

        #expect(receivedFailed != nil)
        #expect(receivedFailed?.jobId == "import_test123")
        #expect(receivedFailed?.status == "failed")
        #expect(receivedFailed?.error == "parsing_error")
        #expect(receivedFailed?.message == "Invalid CSV format")
    }

    @Test("Parse error event")
    func testParseErrorEvent() async throws {
        var receivedError: SSEClientError?

        let client = SSEClient(
            baseURL: "https://test.example.com",
            onInitialized: { _ in },
            onProcessing: { _ in },
            onCompleted: { _ in },
            onFailed: { _ in },
            onError: { error in receivedError = error },
            onTimeout: { _ in }
        )

        let eventData = """
        event: error
        data: {"error":"stream_error","message":"An error occurred while streaming progress"}

        """

        await client.parseSSEEvents(eventData)

        #expect(receivedError != nil)
        if case .serverError(let message) = receivedError {
            #expect(message == "An error occurred while streaming progress")
        } else {
            Issue.record("Expected serverError, got \(String(describing: receivedError))")
        }
    }

    @Test("Parse timeout event")
    func testParseTimeoutEvent() async throws {
        var receivedTimeout: SSETimeoutEvent?

        let client = SSEClient(
            baseURL: "https://test.example.com",
            onInitialized: { _ in },
            onProcessing: { _ in },
            onCompleted: { _ in },
            onFailed: { _ in },
            onError: { _ in },
            onTimeout: { event in receivedTimeout = event }
        )

        let eventData = """
        event: timeout
        data: {"error":"stream_timeout","message":"No progress for 5 minutes","jobId":"import_test123","lastStatus":"processing","lastProgress":0.75}

        """

        await client.parseSSEEvents(eventData)

        #expect(receivedTimeout != nil)
        #expect(receivedTimeout?.error == "stream_timeout")
        #expect(receivedTimeout?.message == "No progress for 5 minutes")
        #expect(receivedTimeout?.jobId == "import_test123")
        #expect(receivedTimeout?.lastStatus == "processing")
        #expect(receivedTimeout?.lastProgress == 0.75)
    }

    // MARK: - Reconnection Tests

    @Test("Parse event with Last-Event-ID")
    func testParseEventWithLastEventID() async throws {
        var receivedProcessing: SSEProgressEvent?
        var lastEventId: String?

        let client = SSEClient(
            baseURL: "https://test.example.com",
            onInitialized: { _ in },
            onProcessing: { event in receivedProcessing = event },
            onCompleted: { _ in },
            onFailed: { _ in },
            onError: { _ in },
            onTimeout: { _ in }
        )

        let eventData = """
        event: processing
        id: 1732713002456-progress
        data: {"jobId":"import_test123","status":"processing","progress":0.5,"processedCount":50,"totalCount":100}

        """

        await client.parseSSEEvents(eventData)

        // Client should store the event ID internally for reconnection
        #expect(receivedProcessing != nil)
    }

    // MARK: - Multiple Events

    @Test("Parse multiple events in sequence")
    func testParseMultipleEvents() async throws {
        var events: [String] = []

        let client = SSEClient(
            baseURL: "https://test.example.com",
            onInitialized: { _ in events.append("initialized") },
            onProcessing: { _ in events.append("processing") },
            onCompleted: { _ in events.append("completed") },
            onFailed: { _ in events.append("failed") },
            onError: { _ in events.append("error") },
            onTimeout: { _ in events.append("timeout") }
        )

        let eventData = """
        event: initialized
        id: 1732713000123-initial
        data: {"jobId":"import_test123","status":"initialized","progress":0,"processedCount":0,"totalCount":100}

        event: processing
        id: 1732713002456-progress
        data: {"jobId":"import_test123","status":"processing","progress":0.5,"processedCount":50,"totalCount":100}

        event: completed
        id: 1732713010789-final
        data: {"jobId":"import_test123","status":"completed","progress":1.0,"processedCount":100,"totalCount":100,"completedAt":"2025-11-27T10:30:10Z"}

        """

        await client.parseSSEEvents(eventData)

        #expect(events == ["initialized", "processing", "completed"])
    }

    // MARK: - Heartbeat Handling

    @Test("Ignore heartbeat comments")
    func testIgnoreHeartbeatComments() async throws {
        var receivedProcessing: SSEProgressEvent?

        let client = SSEClient(
            baseURL: "https://test.example.com",
            onInitialized: { _ in },
            onProcessing: { event in receivedProcessing = event },
            onCompleted: { _ in },
            onFailed: { _ in },
            onError: { _ in },
            onTimeout: { _ in }
        )

        let eventData = """
        : heartbeat

        event: processing
        id: 1732713002456-progress
        data: {"jobId":"import_test123","status":"processing","progress":0.5,"processedCount":50,"totalCount":100}

        : heartbeat

        """

        await client.parseSSEEvents(eventData)

        // Heartbeat comments should be ignored, only processing event should be parsed
        #expect(receivedProcessing != nil)
    }
}
