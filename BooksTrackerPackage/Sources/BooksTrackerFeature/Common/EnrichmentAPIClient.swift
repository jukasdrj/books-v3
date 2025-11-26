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
    /// - Note: Supports automatic fallback from /v1/enrichment/batch → /api/enrichment/batch if canonical endpoint unavailable (404/405/426/501)
    func startEnrichment(jobId: String, books: [Book]) async throws -> EnrichmentResult {
        // Use canonical /v1 endpoint by default (Issue #425)
        // Legacy /api endpoint will be removed in backend v2.0 (January 2026)
        // Feature flag available to disable canonical endpoint if needed via FeatureFlags.disableCanonicalEnrichment
        let disableCanonical = FeatureFlags.shared.disableCanonicalEnrichment

        let primaryEndpoint = disableCanonical ? "/api/enrichment/batch" : "/v1/enrichment/batch"
        let fallbackEndpoint = "/api/enrichment/batch"

        do {
            return try await performEnrichment(endpoint: primaryEndpoint, jobId: jobId, books: books)
        } catch let error as NSError where !disableCanonical && shouldFallbackToLegacy(statusCode: error.code) {
            // Automatic fallback on endpoint-not-available errors (404, 405, 426, 501)
            #if DEBUG
            print("⚠️ [EnrichmentAPIClient] Canonical endpoint failed with \(error.code), falling back to legacy: \(fallbackEndpoint)")
            #endif

            // Log fallback metric for observability
            logFallbackMetric(fromEndpoint: primaryEndpoint, toEndpoint: fallbackEndpoint, reason: "\(error.code)")

            return try await performEnrichment(endpoint: fallbackEndpoint, jobId: jobId, books: books)
        }
    }

    /// Determines if error warrants fallback to legacy endpoint
    /// Fallback on: 404 (Not Found), 405 (Method Not Allowed), 426 (Upgrade Required), 501 (Not Implemented)
    /// Do NOT fallback on: 4xx client errors (400, 401, 403, 422) or 5xx server errors (to avoid duplicate jobs)
    private func shouldFallbackToLegacy(statusCode: Int) -> Bool {
        [404, 405, 426, 501].contains(statusCode)
    }

    /// Log fallback event for observability (sends to console in DEBUG, ready for analytics integration)
    private func logFallbackMetric(fromEndpoint: String, toEndpoint: String, reason: String) {
        #if DEBUG
        print("📊 [EnrichmentAPIClient] Fallback: \(fromEndpoint) → \(toEndpoint) (reason: \(reason))")
        #endif
        // TODO: Send to analytics/observability system (Firebase, Sentry, etc.)
        // Example: Analytics.log("enrichment_endpoint_fallback", parameters: ["from": fromEndpoint, "to": toEndpoint, "reason": reason])
    }

    /// Performs enrichment request to specified endpoint
    /// - Parameters:
    ///   - endpoint: API endpoint path (e.g., "/v1/enrichment/batch")
    ///   - jobId: Unique job identifier for WebSocket tracking
    ///   - books: Books to enrich
    /// - Returns: Enrichment result with job details
    private func performEnrichment(endpoint: String, jobId: String, books: [Book]) async throws -> EnrichmentResult {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ios-v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")", forHTTPHeaderField: "X-Client-Version")
        request.timeoutInterval = 30  // 30 second timeout for POST request

        let payload = BatchEnrichmentPayload(books: books, jobId: jobId)
        request.httpBody = try JSONEncoder().encode(payload)

        #if DEBUG
        print("[EnrichmentAPIClient] 📤 Sending POST to \(endpoint) (jobId: \(jobId), books: \(books.count))")
        #endif

        let (data, response) = try await URLSession.shared.data(for: request)

        #if DEBUG
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        print("[EnrichmentAPIClient] ✅ Received HTTP \(statusCode) response from \(endpoint)")
        #endif

        // CORS Detection (Issue #428)
        // NOTE: This detects backend-signaled CORS errors via X-Custom-Error header.
        // Real CORS errors (browser/OS blocks) result in status 0 or network errors
        // and cannot be reliably detected client-side. This is primarily for web builds
        // where backends can explicitly signal CORS policy violations.
        if let httpResponse = response as? HTTPURLResponse {
            if let customError = httpResponse.value(forHTTPHeaderField: "X-Custom-Error"),
               customError == "CORS_BLOCKED" {
                throw ApiErrorCode.corsBlocked.toNSError()
            }
        }

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 202 else {
            // Enhanced error logging for debugging enrichment failures
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            #if DEBUG
            print("🚨 Enrichment API error: HTTP \(statusCode) from \(endpoint)")
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

                // Use ApiErrorCode for structured error handling (Issue #429)
                if let errorCode = ApiErrorCode.from(code: apiError.code) {
                    // Extract details dictionary from AnyCodable wrapper
                    let details = apiError.details?.value as? [String: Any]

                    #if DEBUG
                    if apiError.details != nil && details == nil {
                        print("⚠️ [EnrichmentAPIClient] Failed to cast apiError.details to [String: Any], value: \(String(describing: apiError.details?.value))")
                    }
                    #endif

                    throw errorCode.toNSError(details: details)
                } else {
                    // Fallback for unknown error codes (preserve backend message)
                    let userInfo: [String: Any] = [
                        NSLocalizedDescriptionKey: apiError.message,
                        "errorCode": apiError.code ?? "UNKNOWN",
                        "details": apiError.details?.value ?? NSNull()
                    ]
                    throw NSError(domain: "com.bookstrack.api", code: statusCode, userInfo: userInfo)
                }
            }
            throw NSError(domain: "com.bookstrack.api", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Enrichment request failed"])
        }

        // Decode ResponseEnvelope and unwrap data
        let envelope = try JSONDecoder().decode(ResponseEnvelope<EnrichmentResult>.self, from: data)

        // Check for errors in envelope
        if let error = envelope.error {
            #if DEBUG
            print("🚨 Enrichment envelope error: \(error.message), Code: \(error.code ?? "UNKNOWN")")
            #endif

            // Use ApiErrorCode for structured error handling (Issue #429)
            if let errorCode = ApiErrorCode.from(code: error.code) {
                let details = error.details?.value as? [String: Any]

                #if DEBUG
                if error.details != nil && details == nil {
                    print("⚠️ [EnrichmentAPIClient] Failed to cast error.details to [String: Any], value: \(String(describing: error.details?.value))")
                }
                #endif

                throw errorCode.toNSError(details: details)
            } else {
                // Fallback for unknown error codes
                throw NSError(domain: "com.bookstrack.api", code: -1, userInfo: [NSLocalizedDescriptionKey: error.message])
            }
        }

        guard let result = envelope.data else {
            #if DEBUG
            print("🚨 Enrichment response missing data field from \(endpoint)")
            #endif
            throw URLError(.badServerResponse)
        }

        #if DEBUG
        print("✅ Enrichment job accepted by backend: \(result.totalCount) books queued for async processing")
        #endif

        return result
    }

    func enrichBookV2(barcode: String) async throws -> EnrichedBookDTO {
        let url = EnrichmentConfig.enrichBookV2URL
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let idempotencyKey = "scan_\(Date().timeIntervalSince1970)_\(UUID().uuidString)"
        let payload = EnrichBookV2Request(barcode: barcode, preferProvider: "auto", idempotencyKey: idempotencyKey)
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        switch httpResponse.statusCode {
        case 200:
            return try JSONDecoder().decode(EnrichedBookDTO.self, from: data)
        case 404:
            throw EnrichmentError.noMatchFound
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
            let retryAfterSeconds = Int(retryAfter ?? "0") ?? 0
            throw EnrichmentError.rateLimitExceeded(retryAfter: retryAfterSeconds)
        default:
            throw URLError(.badServerResponse)
        }
    }
}
