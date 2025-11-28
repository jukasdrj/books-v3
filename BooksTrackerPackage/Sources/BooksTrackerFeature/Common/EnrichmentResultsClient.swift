import Foundation

/// Shared client for fetching enrichment results from the KV cache
/// Extracted from EnrichmentQueue and EnrichmentWebSocketHandler to eliminate code duplication
///
/// v2.0 Migration: WebSocket sends lightweight summary, full results fetched on demand
/// Results are cached for 24 hours after job completion
public enum EnrichmentResultsClient {
    
    /// Fetch full enrichment results from KV cache via HTTP GET
    /// - Parameter jobId: The enrichment job identifier
    /// - Returns: Array of enriched book payloads
    /// - Throws: EnrichmentError if request fails
    public static func fetchResults(jobId: String) async throws -> [EnrichedBookPayload] {
        let url = URL(string: "\(EnrichmentConfig.apiBaseURL)/v1/jobs/\(jobId)/results")!
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EnrichmentError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            // Decode ResponseEnvelope containing enriched books
            struct EnrichmentJobResults: Codable {
                let enrichedBooks: [EnrichedBookPayload]?
            }
            
            let envelope = try JSONDecoder().decode(ResponseEnvelope<EnrichmentJobResults>.self, from: data)
            
            guard let results = envelope.data, let books = results.enrichedBooks else {
                if let error = envelope.error {
                    throw EnrichmentError.apiError(error.message)
                }
                throw EnrichmentError.apiError("No enriched books in response")
            }
            
            return books
            
        case 404:
            // Results expired (> 24 hours old)
            throw EnrichmentError.apiError("Results expired (job older than 24 hours). Please re-run enrichment.")
            
        case 429:
            // Rate limited
            throw EnrichmentError.apiError("Rate limited. Please try again later.")
            
        default:
            throw EnrichmentError.httpError(httpResponse.statusCode)
        }
    }
}
