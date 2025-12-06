import Foundation

extension BooksTrackAPI {
    /// Enriches a single book by barcode.
    func enrichBook(barcode: String, idempotencyKey: String? = nil) async throws -> EnrichedBookDTO {
        let url = baseURL.appendingPathComponent("/v3/books/enrich")

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

}
