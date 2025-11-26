import Foundation

/// Centralized configuration for enrichment API endpoints
/// All API URLs should be accessed through this enum to ensure consistency and ease of maintenance
enum EnrichmentConfig {
    /// Base URL for the Cloudflare Worker API (Custom Domain)
    static let baseURL = "https://api.oooefam.net"

    /// WebSocket base URL for the Cloudflare Worker (Custom Domain)
    static let apiBaseURL = "https://api.oooefam.net"
    static let webSocketBaseURL = "wss://api.oooefam.net"

    // MARK: - Search Endpoints

    /// Search books by title
    static var searchTitleURL: URL {
        URL(string: "\(baseURL)/search/title")!
    }

    /// Search books by ISBN
    static var searchISBNURL: URL {
        URL(string: "\(baseURL)/search/isbn")!
    }

    /// Advanced search (title + author)
    static var searchAdvancedURL: URL {
        URL(string: "\(baseURL)/search/advanced")!
    }

    // MARK: - Enrichment Endpoints

    /// Start batch enrichment job
    /// ⚠️ DEPRECATED: /api/enrichment/start is scheduled for removal in backend v2.0 (Jan 2026)
    /// TODO: GitHub Issue - Migrate to canonical /v1/enrichment/batch endpoint
    /// See: https://github.com/jukasdrj/bookstrack-backend for deprecation timeline
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

    // MARK: - CSV Import Endpoints

    /// AI-powered CSV import with Gemini
    static var csvImportURL: URL {
        URL(string: "\(baseURL)/api/import/csv-gemini")!
    }

    // MARK: - WebSocket Endpoints

    /// WebSocket progress tracking for background jobs (v2.4 - Secure Auth)
    ///
    /// ⚠️ SECURITY (Issue #163): Token authentication now uses Sec-WebSocket-Protocol header
    /// instead of query parameters to prevent token leakage in server logs.
    ///
    /// **NEW (Secure) - Recommended:**
    /// ```swift
    /// let url = EnrichmentConfig.webSocketURL(jobId: jobId)
    /// var request = URLRequest(url: url)
    /// request.setValue("bookstrack-auth.\(token)", forHTTPHeaderField: "Sec-WebSocket-Protocol")
    /// let webSocket = URLSession.shared.webSocketTask(with: request)
    /// ```
    ///
    /// - Parameter jobId: The unique job identifier
    /// - Returns: WebSocket URL for the specified job (WITHOUT token in query params)
    static func webSocketURL(jobId: String) -> URL {
        URL(string: "\(webSocketBaseURL)/ws/progress?jobId=\(jobId)")!
    }

    // MARK: - Health Check

    /// Health check endpoint
    static var healthCheckURL: URL {
        URL(string: "\(baseURL)/health")!
    }

    // MARK: - Timeout Configuration

    /// WebSocket connection timeout for background jobs
    /// - AI processing (Gemini): 25-40s
    /// - Enrichment: 5-10s
    /// - Network buffer: ~20s
    /// - Total: 70s recommended for most networks
    static let webSocketTimeout: TimeInterval = 70.0

    /// Slow network timeout (2x standard)
    /// For users on slower connections or high-latency networks
    static let webSocketTimeoutSlow: TimeInterval = 140.0
}
