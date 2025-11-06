import Foundation

// MARK: - WebSocket Message Types

/// WebSocket message structure for CSV import progress tracking
/// Matches backend message format from progress-socket.js
public struct WebSocketMessage: Codable {
    public let type: String
    public let jobId: String?
    public let timestamp: Double?
    public let data: MessageData?
    
    public struct MessageData: Codable {
        // Progress message fields
        public let progress: Double?
        public let status: String?
        public let keepAlive: Bool?
        
        // Complete message fields
        public let books: [GeminiCSVImportJob.ParsedBook]?
        public let errors: [GeminiCSVImportJob.ImportError]?
        public let successRate: String?
        
        // Error message fields
        public let error: String?
        public let fallbackAvailable: Bool?
        public let suggestion: String?
        
        public init(
            progress: Double? = nil,
            status: String? = nil,
            keepAlive: Bool? = nil,
            books: [GeminiCSVImportJob.ParsedBook]? = nil,
            errors: [GeminiCSVImportJob.ImportError]? = nil,
            successRate: String? = nil,
            error: String? = nil,
            fallbackAvailable: Bool? = nil,
            suggestion: String? = nil
        ) {
            self.progress = progress
            self.status = status
            self.keepAlive = keepAlive
            self.books = books
            self.errors = errors
            self.successRate = successRate
            self.error = error
            self.fallbackAvailable = fallbackAvailable
            self.suggestion = suggestion
        }
    }
}
