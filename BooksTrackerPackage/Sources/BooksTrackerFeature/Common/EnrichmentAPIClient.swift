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

    // MARK: - V2 Synchronous Enrichment

    /// Enrich a single book using V2 synchronous HTTP endpoint
    /// - Parameters:
    ///   - barcode: ISBN-10 or ISBN-13 barcode
    ///   - preferProvider: Optional provider preference ("google", "openlibrary", or "auto")
    /// - Returns: Enriched book data
    /// - Throws: EnrichmentV2Error for various failure cases
    /// - Note: This is a synchronous HTTP call, no WebSocket tracking needed
    func enrichBookV2(barcode: String, preferProvider: String? = "auto") async throws -> V2EnrichmentResponse {
        let url = EnrichmentConfig.enrichmentV2URL

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ios-v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")", forHTTPHeaderField: "X-Client-Version")
        request.timeoutInterval = 30  // 30 second timeout for sync enrichment

        // Generate idempotency key for safe retries
        let idempotencyKey = generateIdempotencyKey(for: barcode)

        let payload = V2EnrichmentRequest(
            barcode: barcode,
            preferProvider: preferProvider,
            idempotencyKey: idempotencyKey
        )
        request.httpBody = try JSONEncoder().encode(payload)

        #if DEBUG
        print("[EnrichmentAPIClient] 📤 V2 Enrichment request: \(barcode)")
        #endif

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EnrichmentV2Error.invalidResponse
        }

        #if DEBUG
        print("[EnrichmentAPIClient] ✅ V2 Enrichment HTTP \(httpResponse.statusCode)")
        #endif

        // Handle different status codes
        switch httpResponse.statusCode {
        case 200:
            // Success - decode enriched book data
            let decoder = JSONDecoder()
            return try decoder.decode(V2EnrichmentResponse.self, from: data)

        case 404:
            // Book not found in any provider
            let decoder = JSONDecoder()
            if let errorResponse = try? decoder.decode(V2EnrichmentErrorResponse.self, from: data) {
                throw EnrichmentV2Error.bookNotFound(
                    message: errorResponse.message,
                    providersChecked: errorResponse.providersChecked ?? []
                )
            }
            throw EnrichmentV2Error.bookNotFound(
                message: "No book data found for ISBN",
                providersChecked: []
            )

        case 429:
            // Rate limit exceeded
            let decoder = JSONDecoder()
            if let rateLimitError = try? decoder.decode(V2RateLimitErrorResponse.self, from: data) {
                throw EnrichmentV2Error.rateLimitExceeded(
                    retryAfter: rateLimitError.retryAfter ?? 3600,
                    message: rateLimitError.message
                )
            }
            throw EnrichmentV2Error.rateLimitExceeded(
                retryAfter: 3600,
                message: "Rate limit exceeded"
            )

        case 503:
            // Service unavailable - all providers down
            throw EnrichmentV2Error.serviceUnavailable(
                message: "Book metadata providers are currently unavailable"
            )

        case 400:
            // Invalid barcode format
            throw EnrichmentV2Error.invalidBarcode(barcode: barcode)

        default:
            // Other HTTP errors
            #if DEBUG
            if let responseString = String(data: data, encoding: .utf8) {
                print("🚨 V2 Enrichment error response: \(responseString)")
            }
            #endif
            throw EnrichmentV2Error.httpError(statusCode: httpResponse.statusCode)
        }
    }

    /// Generate idempotency key for a barcode to prevent duplicate enrichments
    /// Format: scan_YYYYMMDD_<barcode>_<timestamp>
    private func generateIdempotencyKey(for barcode: String) -> String {
        // Use ISO8601 date formatting (efficient, built-in)
        let dateString = ISO8601DateFormatter.string(
            from: Date(),
            timeZone: TimeZone.current,
            formatOptions: [.withYear, .withMonth, .withDay]
        ).replacingOccurrences(of: "-", with: "")  // Convert "2025-11-25" to "20251125"
        
        let timestamp = String(Int(Date().timeIntervalSince1970))
        return "scan_\(dateString)_\(barcode)_\(timestamp)"
    }
}

// MARK: - V2 Enrichment Errors

/// Errors specific to V2 synchronous enrichment
enum EnrichmentV2Error: Error, LocalizedError, Sendable {
    case bookNotFound(message: String, providersChecked: [String])
    case rateLimitExceeded(retryAfter: Int, message: String)
    case serviceUnavailable(message: String)
    case invalidBarcode(barcode: String)
    case invalidResponse
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .bookNotFound(let message, let providers):
            if providers.isEmpty {
                return message
            }
            return "\(message) (checked: \(providers.joined(separator: ", ")))"

        case .rateLimitExceeded(let retryAfter, let message):
            let minutes = retryAfter / 60
            if minutes > 0 {
                return "\(message). Please try again in \(minutes) minute\(minutes == 1 ? "" : "s")."
            }
            return "\(message). Please try again in \(retryAfter) seconds."

        case .serviceUnavailable(let message):
            return message

        case .invalidBarcode(let barcode):
            return "Invalid ISBN format: \(barcode)"

        case .invalidResponse:
            return "Invalid server response"

        case .httpError(let statusCode):
            return "Server error (HTTP \(statusCode))"
        }
    }
}
