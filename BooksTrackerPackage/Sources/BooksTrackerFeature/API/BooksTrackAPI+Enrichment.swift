import Foundation

extension BooksTrackAPI {
    /// Enriches a single book by barcode.
    func enrichBook(barcode: String, idempotencyKey: String? = nil) async throws -> EnrichedBookDTO {
        let url = baseURL.appendingPathComponent("/api/v2/books/enrich")

        // Idempotency key generation: scan_{barcode} default
        let finalIdempotencyKey = idempotencyKey ?? "scan_\(barcode)"

        var requestBody: [String: Any] = ["barcode": barcode]
        requestBody["idempotencyKey"] = finalIdempotencyKey

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

        var request = makeRequest(url: url, method: "POST", body: jsonData)
        request.timeoutInterval = 30.0 // 30s timeout for POST

        let (data, _) = try await performRequest(request: request)
        return try decodeEnvelope(EnrichedBookDTO.self, from: data)
    }

    /// Enriches a batch of books by barcodes, with fallback logic.
    func enrichBatch(barcodes: [String]) async throws -> (jobId: String, authToken: String) {
        let initialPath = "/api/batch-enrich"
        let fallbackPath = "/api/enrichment/batch"

        let requestBody: [String: Any] = ["barcodes": barcodes]
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

        // Attempt primary endpoint
        do {
            let initialURL = baseURL.appendingPathComponent(initialPath)
            var request = makeRequest(url: initialURL, method: "POST", body: jsonData)
            request.timeoutInterval = 30.0 // 30s timeout for POST

            let (data, _) = try await performRequest(request: request)
            let response = try decodeEnvelope(JobInitiationResponse.self, from: data)
            return (jobId: response.jobId, authToken: response.authToken)
        } catch let error as APIError {
            // Check for fallback-triggering errors (404, 405, 426, 501)
            // Note: validateResponse will throw HTTPError(404) etc.
            let shouldFallback: Bool
            switch error {
            case .httpError(let statusCode):
                shouldFallback = [404, 405, 426, 501].contains(statusCode)
            default:
                shouldFallback = false
            }

            guard shouldFallback else {
                throw error // Not a fallback-triggering error, re-throw
            }

            // Fallback to secondary endpoint
            let fallbackURL = baseURL.appendingPathComponent(fallbackPath)
            var fallbackRequest = makeRequest(url: fallbackURL, method: "POST", body: jsonData)
            fallbackRequest.timeoutInterval = 30.0 // 30s timeout for POST

            let (data, _) = try await performRequest(request: fallbackRequest)
            let response = try decodeEnvelope(JobInitiationResponse.self, from: data)
            return (jobId: response.jobId, authToken: response.authToken)
        }
    }

    /// Cancels an enrichment job.
    func cancelJob(jobId: String, authToken: String) async throws -> JobCancellationResponse {
        let url = baseURL.appendingPathComponent("/v1/jobs/\(jobId)")

        var request = makeRequest(url: url, method: "DELETE")
        request.addValue(authToken, forHTTPHeaderField: "X-Auth-Token") // Assuming auth token header
        request.timeoutInterval = 15.0 // 15s timeout for DELETE

        let (data, _) = try await performRequest(request: request)
        return try decodeEnvelope(JobCancellationResponse.self, from: data)
    }
}
