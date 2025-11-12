import Foundation

/// API client for triggering backend enrichment jobs
actor EnrichmentAPIClient {

    private let baseURL = EnrichmentConfig.baseURL

    struct EnrichmentResult: Codable, Sendable {
        let success: Bool
        let processedCount: Int
        let totalCount: Int
        let token: String  // Auth token for WebSocket connection
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
        request.timeoutInterval = 30  // 30 second timeout for POST request

        let payload = BatchEnrichmentPayload(books: books, jobId: jobId)

        request.httpBody = try JSONEncoder().encode(payload)

        #if DEBUG
        print("[EnrichmentAPIClient] 📤 Sending POST to /api/enrichment/batch (jobId: \(jobId), books: \(books.count))")
        #endif

        let (data, response) = try await URLSession.shared.data(for: request)

        #if DEBUG
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        print("[EnrichmentAPIClient] ✅ Received HTTP \(statusCode) response")
        #endif

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 202 else {
            // Enhanced error logging for debugging enrichment failures
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            #if DEBUG
            print("🚨 Enrichment API error: HTTP \(statusCode)")
            #endif
            
            #if DEBUG
            if let responseString = String(data: data, encoding: .utf8) {
                print("🚨 Response body: \(responseString)")
            }
            #endif
            
            // Try to decode error response to extract error code
            // Backend returns ResponseEnvelope for both success and error cases
            if let errorEnvelope = try? JSONDecoder().decode(ResponseEnvelope<EnrichmentResult>.self, from: data),
               let apiError = errorEnvelope.error {
                #if DEBUG
                print("🚨 API Error: \(apiError.message), Code: \(apiError.code ?? "UNKNOWN")")
                #endif
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
            #if DEBUG
            print("🚨 Enrichment envelope error: \(error.message), Code: \(error.code ?? "UNKNOWN")")
            #endif
            throw NSError(domain: "EnrichmentAPIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: error.message])
        }

        guard let result = envelope.data else {
            #if DEBUG
            print("🚨 Enrichment response missing data field")
            #endif
            throw URLError(.badServerResponse)
        }

        #if DEBUG
        print("✅ Enrichment job accepted by backend: \(result.totalCount) books queued for async processing")
        #endif

        return result
    }
}
