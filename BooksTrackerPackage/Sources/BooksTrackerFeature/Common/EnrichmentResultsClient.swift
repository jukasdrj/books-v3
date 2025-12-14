import Foundation

/// Shared client for fetching enrichment results from the KV cache
/// Extracted from EnrichmentQueue and EnrichmentWebSocketHandler to eliminate code duplication
///
/// V3 Migration: SSE sends lightweight summary, full results fetched on demand
/// Results are cached for 24 hours after job completion
public enum EnrichmentResultsClient {

    /// Fetch full enrichment results from KV cache via HTTP GET
    /// - Parameter jobId: The enrichment job identifier
    /// - Returns: Array of enriched book payloads
    /// - Throws: EnrichmentError if request fails
    public static func fetchResults(jobId: String) async throws -> [EnrichedBookPayload] {
        let url = URL(string: "\(EnrichmentConfig.apiBaseURL)/v3/jobs/enrichment/\(jobId)/results")!

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
        // Dump raw JSON for debugging response format issues
        if let jsonString = String(data: data.prefix(2000), encoding: .utf8) {
            print("📄 [HTTP] Response preview (first 2000 chars):")
            print(jsonString)
        }
        #endif

        switch httpResponse.statusCode {
        case 200:
            return try decodeEnrichmentResults(from: data)

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

    /// Decode enrichment results using multiple format strategies
    /// V3 API may return different formats - try each until one succeeds
    private static func decodeEnrichmentResults(from data: Data) throws -> [EnrichedBookPayload] {
        let decoder = JSONDecoder()

        // Format 1: Standard ResponseEnvelope<{enrichedBooks: [...]}>
        struct EnrichmentJobResults: Codable {
            let enrichedBooks: [EnrichedBookPayload]?
        }

        // Format 2: V3 Direct response without metadata {success: true, data: {enrichedBooks: [...]}}
        struct V3EnrichmentResponse: Codable {
            let success: Bool
            let data: V3EnrichmentData?

            struct V3EnrichmentData: Codable {
                let enrichedBooks: [EnrichedBookPayload]?
            }
        }

        // Format 3: Simplified response with just data wrapper {data: {enrichedBooks: [...]}}
        struct SimpleEnrichmentResponse: Codable {
            let data: DataWrapper?

            struct DataWrapper: Codable {
                let enrichedBooks: [EnrichedBookPayload]?
            }
        }

        // Try Format 1: Full ResponseEnvelope
        do {
            let results = try data.decodeEnvelope(EnrichmentJobResults.self)
            #if DEBUG
            print("✅ [HTTP] Successfully decoded ResponseEnvelope (Format 1)")
            #endif

            guard let books = results.enrichedBooks else {
                throw EnrichmentError.apiError("No enriched books in response")
            }

            logDecodedBooks(books)
            return books

        } catch let envelopeError as ResponseEnvelopeError {
            #if DEBUG
            print("⚠️ [HTTP] Format 1 (ResponseEnvelope) failed, trying Format 2...")
            logResponseEnvelopeError(envelopeError)
            #endif

            // Try Format 2: V3 Direct response (no metadata)
            do {
                let v3Response = try decoder.decode(V3EnrichmentResponse.self, from: data)
                #if DEBUG
                print("✅ [HTTP] Successfully decoded V3EnrichmentResponse (Format 2)")
                #endif

                guard v3Response.success, let books = v3Response.data?.enrichedBooks else {
                    throw EnrichmentError.apiError("No enriched books in V3 response")
                }

                logDecodedBooks(books)
                return books

            } catch {
                #if DEBUG
                print("⚠️ [HTTP] Format 2 (V3) failed, trying Format 3...")
                print("  - Error: \(error)")
                #endif

                // Try Format 3: Simple wrapper
                do {
                    let simpleResponse = try decoder.decode(SimpleEnrichmentResponse.self, from: data)
                    #if DEBUG
                    print("✅ [HTTP] Successfully decoded SimpleEnrichmentResponse (Format 3)")
                    #endif

                    guard let books = simpleResponse.data?.enrichedBooks else {
                        throw EnrichmentError.apiError("No enriched books in simple response")
                    }

                    logDecodedBooks(books)
                    return books

                } catch {
                    #if DEBUG
                    print("❌ [HTTP] All decode formats failed")
                    print("  - Format 3 error: \(error)")
                    #endif

                    // Re-throw the original envelope error with detailed info
                    throw mapEnvelopeError(envelopeError)
                }
            }
        }
    }

    /// Log decoded books for debugging
    private static func logDecodedBooks(_ books: [EnrichedBookPayload]) {
        #if DEBUG
        print("✅ [HTTP] Decoded \(books.count) enriched books")
        for (index, book) in books.prefix(3).enumerated() {
            print("📚 [HTTP] Book \(index + 1): '\(book.title)'")
            print("  - success: \(book.success)")
            print("  - enriched: \(book.enriched != nil)")
            if let enriched = book.enriched {
                print("  - work.coverImageURL: \(enriched.work.coverImageURL ?? "nil")")
                print("  - edition?.coverImageURL: \(enriched.edition?.coverImageURL ?? "nil")")
                print("  - edition?.isbn: \(enriched.edition?.isbn ?? "nil")")
            }
        }
        if books.count > 3 {
            print("  ... and \(books.count - 3) more books")
        }
        #endif
    }

    /// Log ResponseEnvelopeError details for debugging
    private static func logResponseEnvelopeError(_ error: ResponseEnvelopeError) {
        #if DEBUG
        print("❌ [HTTP] ResponseEnvelopeError: \(error)")
        switch error {
        case .apiError(let code, let message, let details):
            print("  - Type: apiError")
            print("  - Code: \(code ?? "nil")")
            print("  - Message: \(message)")
            print("  - Details: \(String(describing: details))")
        case .missingData:
            print("  - Type: missingData (envelope decoded but data field was nil)")
        case .decodingFailed(let decodingError):
            print("  - Type: decodingFailed")
            print("  - Underlying error: \(decodingError)")
            if let decodingErr = decodingError as? DecodingError {
                switch decodingErr {
                case .keyNotFound(let key, let context):
                    print("  - Missing key: '\(key.stringValue)' at path: \(context.codingPath.map(\.stringValue).joined(separator: "."))")
                case .typeMismatch(let type, let context):
                    print("  - Type mismatch: expected \(type) at path: \(context.codingPath.map(\.stringValue).joined(separator: "."))")
                case .valueNotFound(let type, let context):
                    print("  - Value not found: \(type) at path: \(context.codingPath.map(\.stringValue).joined(separator: "."))")
                case .dataCorrupted(let context):
                    print("  - Data corrupted at path: \(context.codingPath.map(\.stringValue).joined(separator: "."))")
                @unknown default:
                    print("  - Unknown decoding error")
                }
            }
        }
        #endif
    }

    /// Map ResponseEnvelopeError to EnrichmentError
    private static func mapEnvelopeError(_ error: ResponseEnvelopeError) -> EnrichmentError {
        switch error {
        case .apiError(_, let message, _):
            return EnrichmentError.apiError(message)
        case .missingData:
            return EnrichmentError.apiError("No enriched books in response")
        case .decodingFailed(let decodingError):
            return EnrichmentError.apiError("Failed to decode results: \(decodingError.localizedDescription)")
        }
    }
}
