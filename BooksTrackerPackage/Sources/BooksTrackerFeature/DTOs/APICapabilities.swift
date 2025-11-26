import Foundation

/// API Capabilities Response (v2.7.0+)
///
/// Feature discovery endpoint response from `/api/v2/capabilities`.
/// Allows clients to detect server capabilities at runtime and enable/disable features accordingly.
///
/// **Backend Endpoint:** `GET /api/v2/capabilities`
///
/// **Use Cases:**
/// - Feature Flags: Enable/disable UI based on backend capabilities
/// - Rate Limit Display: Show user their limits before they hit them
/// - Version Checking: Detect API version for compatibility
/// - Graceful Degradation: Fall back to V1 if V2 features unavailable
///
/// **Contract:** Mirrors backend response in `docs/API_CONTRACT.md` (Section 6.5.5)
public struct APICapabilities: Codable, Sendable {
    /// Feature availability flags
    public let features: Features
    
    /// Rate limits and resource constraints
    public let limits: Limits
    
    /// Infrastructure availability (optional, may not be present in all responses)
    public let infrastructure: Infrastructure?
    
    /// Backend API version (semantic versioning)
    public let version: String
    
    /// When this capability snapshot was fetched (client-side tracking)
    /// Not part of API response - added by client for cache management
    public var fetchedAt: Date?
    
    // MARK: - Nested Types
    
    /// Feature availability flags
    public struct Features: Codable, Sendable {
        /// Semantic search using vector embeddings (AI-powered)
        public let semanticSearch: Bool
        
        /// Similar books recommendation based on ISBN
        public let similarBooks: Bool
        
        /// AI-curated weekly book recommendations
        public let weeklyRecommendations: Bool
        
        /// Server-Sent Events (SSE) for progress streaming
        public let sseStreaming: Bool
        
        /// Batch enrichment support
        public let batchEnrichment: Bool
        
        /// CSV import support
        public let csvImport: Bool
        
        enum CodingKeys: String, CodingKey {
            case semanticSearch = "semantic_search"
            case similarBooks = "similar_books"
            case weeklyRecommendations = "weekly_recommendations"
            case sseStreaming = "sse_streaming"
            case batchEnrichment = "batch_enrichment"
            case csvImport = "csv_import"
        }
    }
    
    /// Rate limits and resource constraints
    public struct Limits: Codable, Sendable {
        /// Semantic search rate limit (requests per minute)
        /// Default: 5 req/min (AI compute intensive)
        public let semanticSearchRpm: Int
        
        /// Text search rate limit (requests per minute)
        /// Default: 100 req/min (standard)
        public let textSearchRpm: Int
        
        /// Maximum rows allowed in CSV import
        /// Default: 500 rows
        public let csvMaxRows: Int
        
        /// Maximum photos in batch upload
        /// Default: 5 photos
        public let batchMaxPhotos: Int
        
        enum CodingKeys: String, CodingKey {
            case semanticSearchRpm = "semantic_search_rpm"
            case textSearchRpm = "text_search_rpm"
            case csvMaxRows = "csv_max_rows"
            case batchMaxPhotos = "batch_max_photos"
        }
    }
    
    /// Infrastructure availability (backend services status)
    public struct Infrastructure: Codable, Sendable {
        /// Cloudflare Vectorize availability (for semantic search)
        public let vectorizeAvailable: Bool
        
        /// Workers AI availability (for embeddings generation)
        public let workersAiAvailable: Bool
        
        /// D1 database availability
        public let d1Available: Bool
        
        enum CodingKeys: String, CodingKey {
            case vectorizeAvailable = "vectorize_available"
            case workersAiAvailable = "workers_ai_available"
            case d1Available = "d1_available"
        }
    }
}

// MARK: - Convenience Extensions

extension APICapabilities {
    /// Check if a specific feature is available
    public func isFeatureAvailable(_ feature: Feature) -> Bool {
        switch feature {
        case .semanticSearch:
            return features.semanticSearch
        case .similarBooks:
            return features.similarBooks
        case .weeklyRecommendations:
            return features.weeklyRecommendations
        case .sseStreaming:
            return features.sseStreaming
        case .batchEnrichment:
            return features.batchEnrichment
        case .csvImport:
            return features.csvImport
        }
    }
    
    /// Feature enumeration for type-safe feature checking
    public enum Feature {
        case semanticSearch
        case similarBooks
        case weeklyRecommendations
        case sseStreaming
        case batchEnrichment
        case csvImport
    }
}

// MARK: - Default Capabilities (Fallback)

extension APICapabilities {
    /// Default capabilities used as fallback when endpoint is unavailable
    /// Assumes V1 API capabilities only (no AI features)
    public static var defaultV1: APICapabilities {
        APICapabilities(
            features: Features(
                semanticSearch: false,
                similarBooks: false,
                weeklyRecommendations: false,
                sseStreaming: false,
                batchEnrichment: true,
                csvImport: true
            ),
            limits: Limits(
                semanticSearchRpm: 0,
                textSearchRpm: 100,
                csvMaxRows: 500,
                batchMaxPhotos: 5
            ),
            infrastructure: nil,
            version: "1.0.0",
            fetchedAt: Date()
        )
    }
}
