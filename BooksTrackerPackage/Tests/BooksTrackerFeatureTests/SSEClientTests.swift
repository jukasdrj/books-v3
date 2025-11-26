import Testing
import Foundation
@testable import BooksTrackerFeature

@Suite("SSE Client Tests")
struct SSEClientTests {
    
    // MARK: - Event Parsing Tests
    
    @Test("Parse SSE progress event")
    func parseProgressEvent() async throws {
        let sseData = """
        event: progress
        data: {"progress": 0.5, "processed_rows": 75, "successful_rows": 72, "failed_rows": 3}
        id: evt-123
        
        """
        
        // Create a mock SSE client and test event parsing
        // Note: Since SSEClient is an actor with private methods, we test via public API
        // This test validates the data models can be decoded correctly
        
        let jsonData = """
        {"progress": 0.5, "processed_rows": 75, "successful_rows": 72, "failed_rows": 3}
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let event = try decoder.decode(SSEProgressEvent.self, from: jsonData)
        
        #expect(event.progress == 0.5)
        #expect(event.processedRows == 75)
        #expect(event.successfulRows == 72)
        #expect(event.failedRows == 3)
    }
    
    @Test("Parse SSE complete event")
    func parseCompleteEvent() async throws {
        let jsonData = """
        {
            "status": "complete",
            "progress": 1.0,
            "result_summary": {
                "books_created": 145,
                "books_updated": 0,
                "duplicates_skipped": 5,
                "enrichment_succeeded": 140,
                "enrichment_failed": 5,
                "errors": [
                    {
                        "row": 42,
                        "isbn": "invalid",
                        "error": "Invalid ISBN format"
                    }
                ]
            }
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let result = try decoder.decode(SSEImportResult.self, from: jsonData)
        
        #expect(result.status == "complete")
        #expect(result.progress == 1.0)
        #expect(result.resultSummary?.booksCreated == 145)
        #expect(result.resultSummary?.errors?.count == 1)
        #expect(result.resultSummary?.errors?.first?.row == 42)
    }
    
    @Test("Parse SSE started event")
    func parseStartedEvent() async throws {
        let jsonData = """
        {
            "status": "processing",
            "total_rows": 150,
            "started_at": "2025-01-22T10:30:05Z"
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let event = try decoder.decode(SSEStartedEvent.self, from: jsonData)
        
        #expect(event.status == "processing")
        #expect(event.totalRows == 150)
        #expect(event.startedAt == "2025-01-22T10:30:05Z")
    }
    
    // MARK: - SSE Error Tests
    
    @Test("SSE error descriptions are informative")
    func sseErrorDescriptions() {
        let error1 = SSEError.connectionFailed(URLError(.notConnectedToInternet))
        #expect(error1.localizedDescription.contains("connection failed"))
        
        let error2 = SSEError.reconnectionFailed(3)
        #expect(error2.localizedDescription.contains("3 attempts"))
        
        let error3 = SSEError.jobFailed("CSV parsing error")
        #expect(error3.localizedDescription.contains("CSV parsing error"))
    }
    
    @Test("SSE event type enum values")
    func sseEventTypes() {
        #expect(SSEEventType.progress.rawValue == "progress")
        #expect(SSEEventType.complete.rawValue == "complete")
        #expect(SSEEventType.error.rawValue == "error")
        #expect(SSEEventType.started.rawValue == "started")
        #expect(SSEEventType.queued.rawValue == "queued")
    }
    
    // MARK: - V2 API Model Tests
    
    @Test("V2 import response decoding")
    func v2ImportResponseDecoding() async throws {
        let jsonData = """
        {
            "job_id": "import_abc123def456",
            "status": "queued",
            "created_at": "2025-01-22T10:30:00Z",
            "sse_url": "/api/v2/imports/import_abc123def456/stream",
            "status_url": "/api/v2/imports/import_abc123def456",
            "file_size_bytes": 15234,
            "estimated_rows": 150
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let response = try decoder.decode(V2ImportResponse.self, from: jsonData)
        
        #expect(response.jobId == "import_abc123def456")
        #expect(response.status == "queued")
        #expect(response.sseUrl == "/api/v2/imports/import_abc123def456/stream")
        #expect(response.estimatedRows == 150)
    }
    
    @Test("V2 import status decoding - processing")
    func v2ImportStatusProcessing() async throws {
        let jsonData = """
        {
            "job_id": "import_abc123def456",
            "status": "processing",
            "progress": 0.67,
            "total_rows": 150,
            "processed_rows": 100,
            "successful_rows": 95,
            "failed_rows": 5,
            "created_at": "2025-01-22T10:30:00Z",
            "started_at": "2025-01-22T10:30:05Z",
            "completed_at": null,
            "error": null,
            "result_summary": null
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let status = try decoder.decode(V2ImportStatus.self, from: jsonData)
        
        #expect(status.jobId == "import_abc123def456")
        #expect(status.status == "processing")
        #expect(status.progress == 0.67)
        #expect(status.processedRows == 100)
        #expect(status.successfulRows == 95)
        #expect(status.failedRows == 5)
    }
    
    @Test("V2 import status decoding - complete")
    func v2ImportStatusComplete() async throws {
        let jsonData = """
        {
            "job_id": "import_abc123def456",
            "status": "complete",
            "progress": 1.0,
            "total_rows": 150,
            "processed_rows": 150,
            "successful_rows": 145,
            "failed_rows": 5,
            "created_at": "2025-01-22T10:30:00Z",
            "started_at": "2025-01-22T10:30:05Z",
            "completed_at": "2025-01-22T10:35:12Z",
            "error": null,
            "result_summary": {
                "books_created": 120,
                "books_updated": 25,
                "duplicates_skipped": 5,
                "enrichment_succeeded": 140,
                "enrichment_failed": 5,
                "errors": []
            }
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let status = try decoder.decode(V2ImportStatus.self, from: jsonData)
        
        #expect(status.status == "complete")
        #expect(status.progress == 1.0)
        #expect(status.resultSummary?.booksCreated == 120)
        #expect(status.resultSummary?.booksUpdated == 25)
    }
    
    // MARK: - Integration Tests
    
    @Test("SSEClient initializes with correct configuration")
    func sseClientInitialization() async {
        let client = SSEClient(baseURL: "https://test.example.com")
        let isConnected = await client.getConnectionState()
        #expect(isConnected == false)
    }
    
    @Test("SSEClient disconnect clears state")
    func sseClientDisconnect() async {
        let client = SSEClient(baseURL: "https://test.example.com")
        await client.disconnect()
        let isConnected = await client.getConnectionState()
        #expect(isConnected == false)
    }
}
