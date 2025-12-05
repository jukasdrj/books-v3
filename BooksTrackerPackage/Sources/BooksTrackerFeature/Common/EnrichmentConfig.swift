import Foundation

/// Centralized configuration for enrichment API endpoints
/// All API URLs should be accessed through this enum to ensure consistency and ease of maintenance
enum EnrichmentConfig {
    /// Base URL for the Cloudflare Worker API (Custom Domain)
    static let baseURL = "https://api.oooefam.net"

    /// API base URL for the Cloudflare Worker (Custom Domain)
    static let apiBaseURL = "https://api.oooefam.net"

    /// WebSocket base URL for the Cloudflare Worker (Custom Domain)
    /// ⚠️ DEPRECATED: Used by legacy bookshelf scanning. Will be removed when bookshelf scanning migrates to SSE.
    static let webSocketBaseURL = "wss://api.oooefam.net"

    // MARK: - Search Endpoints (V3 API)

    /// Search books by query (V3 unified search)
    /// Endpoint: GET /v3/books/search?q={query}&limit=20
    /// Replaces: /v1/search/title
    static var searchURL: URL {
        URL(string: "\(baseURL)/v3/books/search")!
    }

    /// Get book by ISBN (V3 API)
    /// Endpoint: GET /v3/books/{isbn}
    /// Replaces: /v1/search/isbn
    static func bookByISBNURL(isbn: String) -> URL {
        URL(string: "\(baseURL)/v3/books/\(isbn)")!
    }

    // MARK: - Legacy Search Endpoints (DEPRECATED - V1 Sunset March 1, 2026)

    /// Search books by title (DEPRECATED)
    /// ⚠️ Use searchURL with V3 API instead
    @available(*, deprecated, message: "Use searchURL with V3 API - V1 sunsets March 1, 2026")
    static var searchTitleURL: URL {
        URL(string: "\(baseURL)/v1/search/title")!
    }

    /// Search books by ISBN (DEPRECATED)
    /// ⚠️ Use bookByISBNURL(isbn:) with V3 API instead
    @available(*, deprecated, message: "Use bookByISBNURL(isbn:) with V3 API - V1 sunsets March 1, 2026")
    static var searchISBNURL: URL {
        URL(string: "\(baseURL)/v1/search/isbn")!
    }

    /// Advanced search (title + author) (DEPRECATED)
    /// ⚠️ Use searchURL with combined query in V3 API instead
    @available(*, deprecated, message: "Use searchURL with combined query in V3 API - V1 sunsets March 1, 2026")
    static var searchAdvancedURL: URL {
        URL(string: "\(baseURL)/v1/search/advanced")!
    }

    // MARK: - Enrichment Endpoints

    /// Start batch enrichment job (Legacy endpoint)
    /// ⚠️ DEPRECATED: This endpoint is scheduled for removal in backend v2.0 (Jan 2026)
    /// ✅ Migration complete: EnrichmentAPIClient now uses /v3/books/enrich as primary endpoint
    /// This URL is kept for emergency fallback only (controlled via FeatureFlags.disableCanonicalEnrichment)
    /// V1 endpoints sunset: March 1, 2026
    /// See: docs/V1_SUNSET_PLAN.md and docs/FRONTEND_INTEGRATION.md
    static var enrichmentStartURL: URL {
        URL(string: "\(baseURL)/api/enrichment/start")!
    }

    /// Cancel enrichment job
    static var enrichmentCancelURL: URL {
        URL(string: "\(baseURL)/api/enrichment/cancel")!
    }

    /// Synchronous V2 book enrichment
    static var enrichBookV2URL: URL {
        URL(string: "\(baseURL)/api/v2/books/enrich")!
    }

    // MARK: - Bookshelf Scanning Endpoints

    /// AI-powered bookshelf scanning
    static var scanBookshelfURL: URL {
        URL(string: "\(baseURL)/api/scan-bookshelf")!
    }

    /// Batch bookshelf scanning
    static var scanBookshelfBatchURL: URL {
        URL(string: "\(baseURL)/api/scan-bookshelf/batch")!
    }

    /// Cancel bookshelf scan job
    static var scanCancelURL: URL {
        URL(string: "\(baseURL)/api/scan-bookshelf/cancel")!
    }

    // MARK: - Workflow Import Endpoints

    /// Create a new import workflow
    static var workflowCreateURL: URL {
        URL(string: "\(baseURL)/v2/import/workflow")!
    }

    /// Get workflow status by ID
    /// - Parameter workflowId: The workflow ID to check
    /// - Returns: URL for the workflow status endpoint
    static func workflowStatusURL(workflowId: String) -> URL {
        URL(string: "\(baseURL)/v2/import/workflow/\(workflowId)")!
    }

    // MARK: - WebSocket Endpoints (Legacy - Bookshelf Scanning Only)

    /// WebSocket progress tracking for background jobs
    /// ⚠️ DEPRECATED: Only used by bookshelf scanning. CSV import uses SSE.
    /// TODO: Migrate bookshelf scanning to SSE and remove this method.
    /// - Parameter jobId: The unique job identifier
    /// - Returns: WebSocket URL for the specified job
    static func webSocketURL(jobId: String) -> URL {
        URL(string: "\(webSocketBaseURL)/ws/progress?jobId=\(jobId)")!
    }

    // MARK: - Health Check

    /// Health check endpoint
    static var healthCheckURL: URL {
        URL(string: "\(baseURL)/health")!
    }

    // MARK: - Timeout Configuration

    /// SSE connection timeout for background jobs
    /// - AI processing (Gemini): 25-40s
    /// - Enrichment: 5-10s
    /// - Network buffer: ~20s
    /// - Total: 70s recommended for most networks
    static let sseTimeout: TimeInterval = 70.0

    /// Slow network timeout (2x standard)
    /// For users on slower connections or high-latency networks
    static let sseTimeoutSlow: TimeInterval = 140.0
}
