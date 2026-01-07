import Foundation

/// Centralized configuration for enrichment API endpoints
/// All API URLs should be accessed through this enum to ensure consistency and ease of maintenance
enum EnrichmentConfig {
    /// Base URL for the Cloudflare Worker API (Custom Domain)
    static let baseURL = "https://api.oooefam.net"

    /// API base URL for the Cloudflare Worker (Custom Domain)
    static let apiBaseURL = "https://api.oooefam.net"

    /// WebSocket base URL for the Cloudflare Worker (Custom Domain)
    /// ⚠️ DEPRECATED: WebSocket is **V1/V2 legacy only**. V3 uses SSE exclusively.
    ///   - V3 endpoints: GET /v3/jobs/{type}/{jobId}/stream (SSE)
    ///   - V1/V2 legacy: GET /ws/progress?jobId=xxx (WebSocket)
    ///   - Used only as automatic fallback when V3 SSE fails
    /// - Note: **Removal: 90 days after V3 GA** (V1/V2 sunset)
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

    /// Start batch enrichment job (Legacy endpoint - DEPRECATED)
    /// ⚠️ DEPRECATED: V1 endpoints sunset March 1, 2026
    /// ✅ Use /v3/books/enrich instead
    /// This URL is kept for emergency fallback only (controlled via FeatureFlags.disableCanonicalEnrichment)
    /// See: docs/V1_SUNSET_PLAN.md and docs/FRONTEND_INTEGRATION.md
    @available(*, deprecated, message: "Use V3 enrichment endpoint - V1 sunsets March 1, 2026")
    static var enrichmentStartURL: URL {
        URL(string: "\(baseURL)/api/enrichment/start")!
    }

    /// Cancel enrichment job (Legacy endpoint - DEPRECATED)
    /// ⚠️ DEPRECATED: V1 endpoints sunset March 1, 2026
    static var enrichmentCancelURL: URL {
        URL(string: "\(baseURL)/api/enrichment/cancel")!
    }

    /// V3 book enrichment endpoint
    /// Endpoint: POST /v3/books/enrich
    static var enrichBookURL: URL {
        URL(string: "\(baseURL)/v3/books/enrich")!
    }

    // MARK: - Bookshelf Scanning Endpoints (V3 API)

    /// AI-powered bookshelf scanning (V3 API)
    /// Endpoint: POST /v3/jobs/scans
    /// Returns: {jobId, status, streamUrl}
    /// Replaces: /api/scan-bookshelf (legacy V1/V2)
    static var scanBookshelfURL: URL {
        URL(string: "\(baseURL)/v3/jobs/scans")!
    }

    /// Cancel bookshelf scan job (V3 API)
    /// Endpoint: DELETE /v3/jobs/scans/{jobId}
    static func scanCancelURL(jobId: String) -> URL {
        URL(string: "\(baseURL)/v3/jobs/scans/\(jobId)")!
    }

    /// Legacy V1/V2 scan endpoint (DEPRECATED)
    /// ⚠️ Use scanBookshelfURL with V3 API instead
    @available(*, deprecated, message: "Use scanBookshelfURL with V3 API - V1/V2 sunsets Q3 2026")
    static var legacyScanBookshelfURL: URL {
        URL(string: "\(baseURL)/api/scan-bookshelf")!
    }

    // MARK: - Workflow Import Endpoints (V2 EXPERIMENTAL - Sunset TBD)

    /// Create a new import workflow (V2 Experimental)
    /// ⚠️ EXPERIMENTAL: V2 workflow import is a P2 feature with limited adoption.
    ///   - Controlled by FeatureFlags.enableWorkflowImport
    ///   - No V3 equivalent planned; evaluate adoption before sunset decision
    ///   - Tech Debt: Define migration path or removal timeline by Q2 2026
    /// - Returns: URL for the workflow creation endpoint
    static var workflowCreateURL: URL {
        URL(string: "\(baseURL)/v2/import/workflow")!
    }

    /// Get workflow status by ID (V2 Experimental)
    /// ⚠️ EXPERIMENTAL: Part of V2 workflow import feature
    /// - Parameter workflowId: The workflow ID to check
    /// - Returns: URL for the workflow status endpoint
    static func workflowStatusURL(workflowId: String) -> URL {
        URL(string: "\(baseURL)/v2/import/workflow/\(workflowId)")!
    }

    // MARK: - WebSocket Endpoints (V1/V2 LEGACY - Automatic Fallback Only)

    /// WebSocket progress tracking for background jobs
    /// ⚠️ DEPRECATED: WebSocket is **V1/V2 legacy only**. V3 uses SSE exclusively.
    ///   - V3 endpoints: `GET /v3/jobs/{type}/{jobId}/stream` (SSE)
    ///   - V1/V2 legacy: `GET /ws/progress?jobId=xxx` (WebSocket)
    ///   - Used only as automatic fallback when V3 SSE connection fails
    ///   - All V3 jobs (scans, imports, enrichment) use SSE, not WebSocket
    /// - Parameter jobId: The unique job identifier
    /// - Returns: WebSocket URL for the specified job
    /// - Note: **Removal: 90 days after V3 GA** (V1/V2 sunset)
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
