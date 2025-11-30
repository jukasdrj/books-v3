import Foundation

// MARK: - Retry Configuration

/// Configuration for retry behavior with exponential backoff
struct RetryConfiguration: Sendable {
    /// Maximum number of retry attempts (including the initial attempt)
    let maxAttempts: Int
    /// Initial delay before first retry (seconds)
    let initialDelay: TimeInterval
    /// Maximum delay between retries (seconds)
    let maxDelay: TimeInterval
    /// Multiplier for exponential backoff
    let backoffMultiplier: Double

    /// Default configuration: 3 attempts, 1s initial delay, 60s max, 2x backoff
    static let `default` = RetryConfiguration(
        maxAttempts: 3,
        initialDelay: 1.0,
        maxDelay: 60.0,
        backoffMultiplier: 2.0
    )

    /// Aggressive configuration: 5 attempts, 0.5s initial delay, 30s max, 1.5x backoff
    static let aggressive = RetryConfiguration(
        maxAttempts: 5,
        initialDelay: 0.5,
        maxDelay: 30.0,
        backoffMultiplier: 1.5
    )

    /// No retry configuration: single attempt only
    static let none = RetryConfiguration(
        maxAttempts: 1,
        initialDelay: 0,
        maxDelay: 0,
        backoffMultiplier: 1.0
    )
}

/// API client for triggering backend enrichment jobs
actor EnrichmentAPIClient {

    private let baseURL = EnrichmentConfig.baseURL

    struct EnrichmentResult: Codable, Sendable {
        let success: Bool
        let processedCount: Int
        let totalCount: Int
        let authToken: String  // Auth token for WebSocket connection (canonical)

        @available(*, deprecated, message: "Use authToken instead. Removal: March 1, 2026")
        let token: String?  // Deprecated field, backward compatibility only

        // Custom decoding to handle both authToken and token fields
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            success = try container.decode(Bool.self, forKey: .success)
            processedCount = try container.decode(Int.self, forKey: .processedCount)
            totalCount = try container.decode(Int.self, forKey: .totalCount)

            // Prefer authToken, fallback to token for legacy responses
            let decodedAuthToken = try? container.decode(String.self, forKey: .authToken)
            let decodedToken = try? container.decode(String.self, forKey: .token)

            if let authTokenValue = decodedAuthToken {
                authToken = authTokenValue
                token = decodedToken  // Optional, may be present
            } else if let tokenValue = decodedToken {
                // Legacy response - only has token field
                authToken = tokenValue
                token = tokenValue
            } else {
                throw DecodingError.keyNotFound(
                    CodingKeys.authToken,
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Expected authToken or token field"
                    )
                )
            }
        }

        private enum CodingKeys: String, CodingKey {
            case success, processedCount, totalCount, authToken, token
        }
    }

    /// Start enrichment job on backend with automatic retry for retryable errors
    /// Backend will push progress updates via WebSocket
    /// - Parameters:
    ///   - jobId: Unique job identifier for WebSocket tracking
    ///   - books: Books to enrich
    ///   - retryConfig: Retry configuration (default: .default)
    /// - Returns: Enrichment result with final counts
    /// - Note: Supports automatic fallback from /v1/enrichment/batch → /api/enrichment/batch if canonical endpoint unavailable (404/405/426/501)
    func startEnrichment(jobId: String, books: [Book], retryConfig: RetryConfiguration = .default) async throws -> EnrichmentResult {
        // Use canonical /v1 endpoint by default (Issue #425)
        // Legacy /api endpoint will be removed in backend v2.0 (January 2026)
        // Feature flag available to disable canonical endpoint if needed via FeatureFlags.disableCanonicalEnrichment
        let disableCanonical = await FeatureFlags.shared.disableCanonicalEnrichment

        let primaryEndpoint = disableCanonical ? "/api/enrichment/batch" : "/v1/enrichment/batch"
        let fallbackEndpoint = "/api/enrichment/batch"

        // Wrap with retry logic - each retry attempt includes fallback logic
        return try await retryWithBackoff(config: retryConfig) { [self] in
            do {
                return try await self.performEnrichment(endpoint: primaryEndpoint, jobId: jobId, books: books)
            } catch let error as NSError where !disableCanonical && Self.shouldFallbackToLegacy(statusCode: error.code) {
                // Automatic fallback on endpoint-not-available errors (404, 405, 426, 501)
                #if DEBUG
                print("⚠️ [EnrichmentAPIClient] Canonical endpoint failed with \(error.code), falling back to legacy: \(fallbackEndpoint)")
                #endif

                // Log fallback metric for observability
                Self.logFallbackMetric(fromEndpoint: primaryEndpoint, toEndpoint: fallbackEndpoint, reason: "\(error.code)")

                return try await self.performEnrichment(endpoint: fallbackEndpoint, jobId: jobId, books: books)
            }
        }
    }

    /// Determines if error warrants fallback to legacy endpoint
    /// Fallback on: 404 (Not Found), 405 (Method Not Allowed), 426 (Upgrade Required), 501 (Not Implemented)
    /// Do NOT fallback on: 4xx client errors (400, 401, 403, 422) or 5xx server errors (to avoid duplicate jobs)
    private static func shouldFallbackToLegacy(statusCode: Int) -> Bool {
        [404, 405, 426, 501].contains(statusCode)
    }

    /// Log fallback event for observability (sends to console in DEBUG, ready for analytics integration)
    private static func logFallbackMetric(fromEndpoint: String, toEndpoint: String, reason: String) {
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

    // MARK: - Job Cancellation (API v3.1)

    struct JobCancellationResponse: Codable, Sendable {
        let jobId: String
        let status: String
        let message: String
        let cleanup: CleanupDetails

        struct CleanupDetails: Codable, Sendable {
            let r2ObjectsDeleted: Int
            let kvCacheCleared: Bool
        }
    }

    /// Cancel an enrichment job and cleanup R2 images/KV cache (API v3.2)
    /// - Parameters:
    ///   - jobId: The unique job identifier to cancel
    ///   - authToken: Bearer token from job creation (required as of API v3.2)
    /// - Returns: Job cancellation response with cleanup details
    /// - Note: Idempotent - calling DELETE on completed jobs returns success
    func cancelJob(jobId: String, authToken: String) async throws -> JobCancellationResponse {
        guard let url = URL(string: "\(baseURL)/v1/jobs/\(jobId)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("ios-v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")", forHTTPHeaderField: "X-Client-Version")
        request.timeoutInterval = 15  // 15 second timeout for DELETE request

        #if DEBUG
        print("[EnrichmentAPIClient] 🗑️ Sending DELETE to /v1/jobs/\(jobId)")
        #endif

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        // Handle authentication errors (API v3.2 requirement)
        if httpResponse.statusCode == 401 {
            #if DEBUG
            print("🚨 Job cancellation unauthorized: Invalid or expired token")
            #endif
            throw NSError(domain: "com.bookstrack.api", code: 401, userInfo: [NSLocalizedDescriptionKey: "Authentication failed: Invalid or expired token"])
        }

        guard httpResponse.statusCode == 200 else {
            #if DEBUG
            print("🚨 Job cancellation failed: HTTP \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("🚨 Response body: \(responseString)")
            }
            #endif
            throw NSError(domain: "com.bookstrack.api", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Job cancellation failed"])
        }

        // Decode ResponseEnvelope and unwrap data
        let envelope = try JSONDecoder().decode(ResponseEnvelope<JobCancellationResponse>.self, from: data)

        guard let result = envelope.data else {
            #if DEBUG
            print("🚨 Job cancellation response missing data field")
            #endif
            throw URLError(.badServerResponse)
        }

        #if DEBUG
        print("✅ Job \(jobId) canceled successfully: \(result.cleanup.r2ObjectsDeleted) R2 objects deleted")
        #endif

        return result
    }

    // MARK: - Retry Logic with Exponential Backoff

    /// Retry wrapper with exponential backoff for retryable errors
    /// - Parameters:
    ///   - config: Retry configuration
    ///   - operation: Async operation to retry
    /// - Returns: Result of successful operation
    /// - Throws: Error if all retries exhausted or non-retryable error
    private func retryWithBackoff<T: Sendable>(
        config: RetryConfiguration,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        var attempt = 0
        var lastError: Error?

        while attempt < config.maxAttempts {
            do {
                return try await operation()
            } catch let error as EnrichmentError {
                lastError = error

                // Determine if error is retryable and get delay
                let (retryable, delay) = getRetryInfo(for: error, config: config, attempt: attempt)

                if !retryable {
                    throw error
                }

                attempt += 1
                if attempt >= config.maxAttempts {
                    throw error
                }

                #if DEBUG
                print("⚠️ Retryable error (attempt \(attempt)/\(config.maxAttempts)), retrying in \(String(format: "%.1f", delay))s: \(error.localizedDescription)")
                #endif

                try await Task.sleep(for: .seconds(delay))
            } catch let error as URLError where error.code == .timedOut || error.code == .networkConnectionLost || error.code == .notConnectedToInternet {
                // Network errors are retryable with exponential backoff
                lastError = error

                // Calculate delay BEFORE incrementing attempt (consistent with EnrichmentError handling)
                let delay = min(
                    config.initialDelay * pow(config.backoffMultiplier, Double(attempt)),
                    config.maxDelay
                )

                attempt += 1
                if attempt >= config.maxAttempts {
                    throw error
                }

                #if DEBUG
                print("⚠️ Network error (attempt \(attempt)/\(config.maxAttempts)), retrying in \(String(format: "%.1f", delay))s: \(error.localizedDescription)")
                #endif

                try await Task.sleep(for: .seconds(delay))
            } catch {
                // Non-retryable error - fail immediately
                throw error
            }
        }

        throw lastError ?? EnrichmentError.apiError("Max retries exceeded")
    }

    /// Determines if an error is retryable and calculates delay
    /// - Parameters:
    ///   - error: The EnrichmentError to evaluate
    ///   - config: Retry configuration for backoff calculation
    ///   - attempt: Current attempt number (0-indexed)
    /// - Returns: Tuple of (isRetryable, delayInSeconds)
    private func getRetryInfo(
        for error: EnrichmentError,
        config: RetryConfiguration,
        attempt: Int
    ) -> (retryable: Bool, delay: TimeInterval) {
        switch error {
        case .rateLimitExceeded(let retryAfter):
            // Use server-provided retry-after, capped at maxDelay
            let delay = min(TimeInterval(retryAfter), config.maxDelay)
            return (true, delay)

        case .circuitOpen(_, let retryAfterMs):
            // Use circuit breaker cooldown from server, capped at maxDelay
            let delay = min(TimeInterval(retryAfterMs) / 1000.0, config.maxDelay)
            return (true, delay)

        case .httpError(let statusCode) where statusCode >= 500:
            // Server errors are retryable with exponential backoff
            let delay = min(
                config.initialDelay * pow(config.backoffMultiplier, Double(attempt)),
                config.maxDelay
            )
            return (true, delay)

        default:
            // Not retryable - noMatchFound, apiError, invalidQuery, etc.
            return (false, 0)
        }
    }

    // MARK: - V2 Sync Enrichment API

    /// Enriches a book using the V2 sync API with automatic retry for retryable errors.
    /// - Parameters:
    ///   - barcode: The ISBN or barcode to enrich
    ///   - idempotencyKey: Optional stable key for retry safety. If nil, generates one based on barcode.
    ///   - preferProvider: Provider preference hint (default: "auto")
    ///   - retryConfig: Retry configuration (default: .default)
    /// - Returns: Enriched book data from the API
    /// - Throws: EnrichmentError for API-specific errors, URLError for network issues
    func enrichBookV2(
        barcode: String,
        idempotencyKey: String? = nil,
        preferProvider: String = "auto",
        retryConfig: RetryConfiguration = .default
    ) async throws -> EnrichedBookDTO {
        // Use provided idempotency key or generate a stable one based on barcode
        // This ensures retries use the same key, preserving idempotency semantics
        let key = idempotencyKey ?? "scan_\(barcode)"

        return try await retryWithBackoff(config: retryConfig) { [self] in
            try await self.performEnrichBookV2(
                barcode: barcode,
                idempotencyKey: key,
                preferProvider: preferProvider
            )
        }
    }

    /// Internal implementation of enrichBookV2 without retry wrapper
    /// - Parameters:
    ///   - barcode: The ISBN or barcode to enrich
    ///   - idempotencyKey: Stable key for retry safety
    ///   - preferProvider: Provider preference hint
    /// - Returns: Enriched book data from the API
    private func performEnrichBookV2(
        barcode: String,
        idempotencyKey: String,
        preferProvider: String
    ) async throws -> EnrichedBookDTO {
        let url = EnrichmentConfig.enrichBookV2URL
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = EnrichBookV2Request(barcode: barcode, preferProvider: preferProvider, idempotencyKey: idempotencyKey)
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
            // Use conservative default of 5 seconds to prevent busy-wait loops
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
            let retryAfterSeconds = Int(retryAfter ?? "5") ?? 5
            throw EnrichmentError.rateLimitExceeded(retryAfter: retryAfterSeconds)
        case 503:
            // Service unavailable - parse structured error response
            do {
                let errorResponse = try JSONDecoder().decode(ErrorResponseDTO.self, from: data)
                if errorResponse.error.code == "CIRCUIT_OPEN" {
                    let provider = errorResponse.error.provider ?? "unknown"
                    let retryAfterMs = errorResponse.error.retryAfterMs ?? 60000
                    #if DEBUG
                    print("⚠️ Circuit breaker open for provider '\(provider)', retry in \(retryAfterMs)ms: \(errorResponse.error.message)")
                    #endif
                    throw EnrichmentError.circuitOpen(provider: provider, retryAfterMs: retryAfterMs)
                }
                // Handle other 503 errors with structured message
                throw EnrichmentError.apiError(errorResponse.error.message)
            } catch let decodingError as DecodingError {
                // Fallback if error response doesn't match expected format
                #if DEBUG
                print("⚠️ Failed to decode 503 error response: \(decodingError)")
                #endif
            }
            throw URLError(.badServerResponse)
        default:
            throw URLError(.badServerResponse)
        }
    }
}
