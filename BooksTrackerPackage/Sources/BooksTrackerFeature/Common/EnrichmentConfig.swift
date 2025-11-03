import Foundation

/// Centralized configuration for enrichment API endpoints
enum EnrichmentConfig {
    /// Base URL for the Cloudflare Worker API
    static let baseURL = "https://api-worker.jukasdrj.workers.dev"

    /// WebSocket base URL for the Cloudflare Worker
    static let webSocketBaseURL = "wss://api-worker.jukasdrj.workers.dev"
}
