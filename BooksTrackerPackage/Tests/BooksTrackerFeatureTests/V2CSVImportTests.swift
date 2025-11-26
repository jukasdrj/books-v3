import Testing
import Foundation
@testable import BooksTrackerFeature

@MainActor
@Suite("V2 CSV Import Service Tests")
struct V2CSVImportServiceTests {
    
    @Test("V2 response models decode correctly")
    func v2ResponseDecoding() throws {
        let json = """
        {
            "job_id": "import_test123",
            "status": "queued",
            "created_at": "2025-11-26T00:00:00Z",
            "sse_url": "/api/v2/imports/import_test123/stream",
            "status_url": "/api/v2/imports/import_test123",
            "estimated_rows": 100
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let response = try decoder.decode(V2CSVImportResponse.self, from: data)
        
        #expect(response.jobId == "import_test123")
        #expect(response.status == "queued")
        #expect(response.sseUrl == "/api/v2/imports/import_test123/stream")
        #expect(response.estimatedRows == 100)
    }
    
    @Test("V2 status response decoding - processing")
    func v2StatusProcessingDecoding() throws {
        let json = """
        {
            "job_id": "import_test123",
            "status": "processing",
            "progress": 0.5,
            "total_rows": 100,
            "processed_rows": 50,
            "successful_rows": 48,
            "failed_rows": 2,
            "created_at": "2025-11-26T00:00:00Z",
            "started_at": "2025-11-26T00:01:00Z"
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let status = try decoder.decode(V2CSVImportStatus.self, from: data)
        
        #expect(status.jobId == "import_test123")
        #expect(status.status == "processing")
        #expect(status.progress == 0.5)
        #expect(status.totalRows == 100)
        #expect(status.processedRows == 50)
        #expect(status.successfulRows == 48)
        #expect(status.failedRows == 2)
    }
    
    @Test("V2 status response decoding - complete with summary")
    func v2StatusCompleteDecoding() throws {
        let json = """
        {
            "job_id": "import_test123",
            "status": "complete",
            "progress": 1.0,
            "total_rows": 100,
            "processed_rows": 100,
            "successful_rows": 95,
            "failed_rows": 5,
            "created_at": "2025-11-26T00:00:00Z",
            "started_at": "2025-11-26T00:01:00Z",
            "completed_at": "2025-11-26T00:05:00Z",
            "result_summary": {
                "books_created": 90,
                "books_updated": 5,
                "duplicates_skipped": 5,
                "enrichment_succeeded": 92,
                "enrichment_failed": 3,
                "errors": [
                    {
                        "row": 42,
                        "isbn": "invalid",
                        "error": "Invalid ISBN format"
                    }
                ]
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let status = try decoder.decode(V2CSVImportStatus.self, from: data)
        
        #expect(status.status == "complete")
        #expect(status.progress == 1.0)
        #expect(status.resultSummary?.booksCreated == 90)
        #expect(status.resultSummary?.booksUpdated == 5)
        #expect(status.resultSummary?.duplicatesSkipped == 5)
        #expect(status.resultSummary?.enrichmentSucceeded == 92)
        #expect(status.resultSummary?.enrichmentFailed == 3)
        #expect(status.resultSummary?.errors?.count == 1)
        #expect(status.resultSummary?.errors?.first?.row == 42)
    }
    
    @Test("V2 SSE event data decoding - started")
    func v2SSEStartedEventDecoding() throws {
        let json = """
        {
            "status": "processing",
            "total_rows": 150,
            "started_at": "2025-11-26T00:01:00Z"
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let eventData = try decoder.decode(V2SSEEventData.self, from: data)
        
        #expect(eventData.status == "processing")
        #expect(eventData.totalRows == 150)
        #expect(eventData.startedAt == "2025-11-26T00:01:00Z")
    }
    
    @Test("V2 SSE event data decoding - progress")
    func v2SSEProgressEventDecoding() throws {
        let json = """
        {
            "progress": 0.5,
            "processed_rows": 75,
            "successful_rows": 72,
            "failed_rows": 3
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let eventData = try decoder.decode(V2SSEEventData.self, from: data)
        
        #expect(eventData.progress == 0.5)
        #expect(eventData.processedRows == 75)
        #expect(eventData.successfulRows == 72)
        #expect(eventData.failedRows == 3)
    }
    
    @Test("V2 SSE event data decoding - complete")
    func v2SSECompleteEventDecoding() throws {
        let json = """
        {
            "status": "complete",
            "progress": 1.0,
            "result_summary": {
                "books_created": 145,
                "books_updated": 0,
                "duplicates_skipped": 5,
                "enrichment_succeeded": 140,
                "enrichment_failed": 5
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let eventData = try decoder.decode(V2SSEEventData.self, from: data)
        
        #expect(eventData.status == "complete")
        #expect(eventData.progress == 1.0)
        #expect(eventData.resultSummary?.booksCreated == 145)
        #expect(eventData.resultSummary?.enrichmentSucceeded == 140)
    }
    
    @Test("V2 SSE event data decoding - error")
    func v2SSEErrorEventDecoding() throws {
        let json = """
        {
            "status": "failed",
            "error": "CSV parsing failed at row 42",
            "processed_rows": 41
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let eventData = try decoder.decode(V2SSEEventData.self, from: data)
        
        #expect(eventData.status == "failed")
        #expect(eventData.error == "CSV parsing failed at row 42")
        #expect(eventData.processedRows == 41)
    }
    
    @Test("Feature flag defaults to V1")
    func featureFlagDefaultsToV1() {
        // Reset to defaults
        FeatureFlags.shared.resetToDefaults()
        
        // V2 CSV import should be disabled by default
        #expect(FeatureFlags.shared.useV2CSVImport == false)
    }
    
    @Test("Feature flag can be toggled")
    func featureFlagCanBeToggled() {
        // Enable V2
        FeatureFlags.shared.useV2CSVImport = true
        #expect(FeatureFlags.shared.useV2CSVImport == true)
        
        // Disable V2
        FeatureFlags.shared.useV2CSVImport = false
        #expect(FeatureFlags.shared.useV2CSVImport == false)
        
        // Reset to defaults
        FeatureFlags.shared.resetToDefaults()
        #expect(FeatureFlags.shared.useV2CSVImport == false)
    }
}
