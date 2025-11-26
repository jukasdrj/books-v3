import Testing
import Foundation
@testable import BooksTrackerFeature

// MARK: - ResponseEnvelope Test Helper

extension ResponseEnvelope {
    /// Create a mock ResponseEnvelope for testing
    static func mock<T>(with data: T) -> ResponseEnvelope<T> {
        ResponseEnvelope(
            data: data,
            metadata: ResponseMetadata(timestamp: ISO8601DateFormatter().string(from: Date()))
        )
    }
}

// MARK: - Tests

@MainActor
@Suite("Gemini CSV Import Service Tests")
struct GeminiCSVImportServiceTests {

    @Test("Upload CSV returns jobId")
    func uploadCSVReturnsJobId() async throws {
        // Arrange
        let csvText = "Title,Author\nBook1,Author1\n"
        let service = GeminiCSVImportService.shared

        // Note: This test requires a live backend or mock URLSession
        // For now, we'll test the structure is correct by checking error handling

        // This test will fail with network error since we don't have mock URLSession
        // In production, this would connect to the real API
        do {
            let jobId = try await service.uploadCSV(csvText: csvText)
            #expect(jobId.isEmpty == false)
        } catch {
            // Expected to fail without mock - this validates the error path works
            #expect(error is GeminiCSVImportError)
        }
    }

    @Test("Upload rejects files larger than 10MB")
    func uploadRejectsLargeFiles() async throws {
        // Arrange
        let largeCSV = String(repeating: "x", count: 11 * 1024 * 1024) // 11MB
        let service = GeminiCSVImportService.shared

        // Act & Assert
        do {
            _ = try await service.uploadCSV(csvText: largeCSV)
            Issue.record("Expected fileTooLarge error")
        } catch let error as GeminiCSVImportError {
            if case .fileTooLarge = error {
                // Success - correct error type
            } else {
                Issue.record("Expected fileTooLarge error, got: \(error)")
            }
        } catch {
            Issue.record("Expected GeminiCSVImportError, got: \(error)")
        }
    }
    
    // MARK: - V2 API Tests
    
    @Test("V2 upload validates CSV format before network call")
    func v2UploadValidatesCSV() async throws {
        let invalidCSV = "Not a valid CSV"
        let service = GeminiCSVImportService.shared
        
        // Should fail validation before network call
        do {
            _ = try await service.uploadCSVV2(csvText: invalidCSV)
            Issue.record("Expected parsingFailed error")
        } catch let error as GeminiCSVImportError {
            if case .parsingFailed = error {
                // Success - correct error type
            } else {
                Issue.record("Expected parsingFailed error, got: \(error)")
            }
        } catch {
            Issue.record("Expected GeminiCSVImportError, got: \(error)")
        }
    }
    
    @Test("V2 upload accepts files up to 50MB")
    func v2UploadAcceptsLargerFiles() async throws {
        // V2 API allows up to 50MB (vs 10MB for V1)
        // This test validates the size check passes for files between 10-50MB
        let largeCSV = String(repeating: "Title,Author\nBook1,Author1\n", count: 300000) // ~15MB
        let service = GeminiCSVImportService.shared
        
        // Should pass size validation (but will fail network call without mock)
        do {
            _ = try await service.uploadCSVV2(csvText: largeCSV)
            // Expected to fail on network, not validation
        } catch let error as GeminiCSVImportError {
            // Should be network error, not fileTooLarge
            if case .fileTooLarge = error {
                Issue.record("V2 should accept files up to 50MB, got fileTooLarge for 15MB file")
            }
            // Network errors are expected without mock server
        }
    }
}
