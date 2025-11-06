import Foundation

/// API client for triggering backend enrichment jobs
actor EnrichmentAPIClient {

    private let baseURL = EnrichmentConfig.baseURL

    struct EnrichmentResult: Codable, Sendable {
        let success: Bool
        let processedCount: Int
        let totalCount: Int
    }

    /// Start enrichment job on backend
    /// Backend will push progress updates via WebSocket
    /// - Parameter jobId: Unique job identifier for WebSocket tracking
    /// - Returns: Enrichment result with final counts
    func startEnrichment(jobId: String, books: [Book]) async throws -> EnrichmentResult {
        guard let url = URL(string: "\(baseURL)/api/enrichment/batch") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = BatchEnrichmentPayload(books: books, jobId: jobId)

        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 202 else {
            // Enhanced error logging for debugging enrichment failures
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("🚨 Enrichment API error: HTTP \(statusCode)")
            
            #if DEBUG
            if let responseString = String(data: data, encoding: .utf8) {
                print("🚨 Response body: \(responseString)")
            }
            #endif
            
            // Try to decode error response to extract error code
            // Backend returns ResponseEnvelope for both success and error cases
            if let errorEnvelope = try? JSONDecoder().decode(ResponseEnvelope<EnrichmentResult>.self, from: data),
               let apiError = errorEnvelope.error {
                print("🚨 API Error: \(apiError.message), Code: \(apiError.code ?? "UNKNOWN")")
                // Preserve error code in NSError userInfo
                let userInfo: [String: Any] = [
                    NSLocalizedDescriptionKey: apiError.message,
                    "errorCode": apiError.code ?? "UNKNOWN",
                    "details": apiError.details?.value ?? NSNull()
                ]
                throw NSError(domain: "EnrichmentAPIClient", code: statusCode, userInfo: userInfo)
            }
            throw URLError(.badServerResponse)
        }

        // Decode ResponseEnvelope and unwrap data
        let envelope = try JSONDecoder().decode(ResponseEnvelope<EnrichmentResult>.self, from: data)

        // Check for errors in envelope
        if let error = envelope.error {
            print("🚨 Enrichment envelope error: \(error.message), Code: \(error.code ?? "UNKNOWN")")
            throw NSError(domain: "EnrichmentAPIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: error.message])
        }

        guard let result = envelope.data else {
            print("🚨 Enrichment response missing data field")
            throw URLError(.badServerResponse)
        }

        #if DEBUG
        print("✅ Enrichment job accepted by backend: \(result.totalCount) books queued for async processing")
        #endif

        return result
    }
}
