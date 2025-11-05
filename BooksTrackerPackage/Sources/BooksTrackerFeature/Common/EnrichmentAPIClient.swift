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
            // Try to decode error response to extract error code
            if let errorResponse = try? JSONDecoder().decode(ApiResponse<EnrichmentResult>.self, from: data),
               case .failure(let apiError, _) = errorResponse {
                // Preserve error code in NSError userInfo
                let userInfo: [String: Any] = [
                    NSLocalizedDescriptionKey: apiError.message,
                    "errorCode": apiError.code?.rawValue ?? "UNKNOWN",
                    "details": apiError.details?.value ?? NSNull()
                ]
                throw NSError(domain: "EnrichmentAPIClient", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: userInfo)
            }
            throw URLError(.badServerResponse)
        }

        // Decode ResponseEnvelope and unwrap data
        let envelope = try JSONDecoder().decode(ResponseEnvelope<EnrichmentResult>.self, from: data)

        // Check for errors in envelope
        if let error = envelope.error {
            throw NSError(domain: "EnrichmentAPIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: error.message])
        }

        guard let result = envelope.data else {
            throw URLError(.badServerResponse)
        }

        return result
    }
}
