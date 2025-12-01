import Foundation

/// Shared client for fetching enrichment results from the KV cache
/// Extracted from EnrichmentQueue and EnrichmentWebSocketHandler to eliminate code duplication
///
/// V2 Migration: SSE sends lightweight summary, full results fetched on demand
/// Results are cached for 24 hours after job completion
public enum EnrichmentResultsClient {

    /// Fetch full enrichment results from KV cache via HTTP GET
    /// - Parameter jobId: The enrichment job identifier
    /// - Returns: Array of enriched book payloads
    /// - Throws: EnrichmentError if request fails
    public static func fetchResults(jobId: String) async throws -> [EnrichedBookPayload] {
        let url = URL(string: "\(EnrichmentConfig.apiBaseURL)/api/v2/imports/\(jobId)/results")!

        #if DEBUG
        print("🌐 [HTTP] Fetching enrichment results from: \(url.absoluteString)")
        #endif

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EnrichmentError.invalidResponse
        }

        #if DEBUG
        print("📡 [HTTP] Response status: \(httpResponse.statusCode)")
        print("📦 [HTTP] Response size: \(data.count) bytes")
        #endif

        switch httpResponse.statusCode {
        case 200:
            // Decode ResponseEnvelope containing enriched books
            struct EnrichmentJobResults: Codable {
                let enrichedBooks: [EnrichedBookPayload]?
            }

            do {
                let results = try data.decodeEnvelope(EnrichmentJobResults.self)

                guard let books = results.enrichedBooks else {
                    throw EnrichmentError.apiError("No enriched books in response")
                }

                #if DEBUG
                print("✅ [HTTP] Decoded \(books.count) enriched books")
                // Sample first book's cover data
                if let firstBook = books.first {
                    print("📚 [HTTP] First book: '\(firstBook.title)'")
                    print("  - success: \(firstBook.success)")
                    print("  - enriched: \(firstBook.enriched != nil)")
                    print("  - work.coverImageURL: \(firstBook.enriched?.work.coverImageURL ?? "nil")")
                    print("  - edition?.coverImageURL: \(firstBook.enriched?.edition?.coverImageURL ?? "nil")")
                }
                #endif

                return books

            } catch let error as ResponseEnvelopeError {
                // Map ResponseEnvelopeError to EnrichmentError
                switch error {
                case .apiError(_, let message, _):
                    throw EnrichmentError.apiError(message)
                case .missingData:
                    throw EnrichmentError.apiError("No enriched books in response")
                case .decodingFailed(let decodingError):
                    throw EnrichmentError.apiError("Failed to decode results: \(decodingError.localizedDescription)")
                }
            }
            
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
