import Foundation

#if canImport(UIKit)
import UIKit

// MARK: - AI Service Errors

enum BookshelfAIError: Error, LocalizedError {
    case imageCompressionFailed
    case networkError(Error)
    case invalidResponse
    case serverError(Int, String)
    case rateLimitExceeded(retryAfter: Int) // New case for HTTP 429
    case decodingFailed(Error)
    case imageQualityRejected(String)
    case resultsExpired // NEW: For expired scan results (Issue #2)
    case apiError(code: String, message: String) // NEW: For generic API errors from ResponseEnvelope (Issue #3)

    var errorDescription: String? {
        switch self {
        case .imageCompressionFailed:
            return "Failed to compress image for upload"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Received invalid response from AI service"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .rateLimitExceeded(let retryAfter):
            return "Too many requests. Wait \(retryAfter)s before trying again."
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .imageQualityRejected(let reason):
            return "Image quality issue: \(reason)"
        case .resultsExpired:
            return "The scan results have expired. Please re-run the scan to get fresh results."
        case .apiError(let code, let message):
            return "API Error (\(code)): \(message)"
        }
    }
}

// MARK: - AI Response Models

public struct BookshelfAIResponse: Codable, Sendable {
    public let books: [AIDetectedBook]
    public let suggestions: [Suggestion]? // Optional for backward compatibility
    public let metadata: ImageMetadata?

    public struct AIDetectedBook: Codable, Sendable {
        public let title: String?
        public let author: String?
        public let boundingBox: BoundingBox
        public let confidence: Double?
        public let enrichmentStatus: String? // New field for enrichment status
        public let isbn: String?
        public let coverUrl: String?
        public let publisher: String?
        public let publicationYear: Int?

        public struct BoundingBox: Codable, Sendable {
            public let x1: Double
            public let y1: Double
            public let x2: Double
            public let y2: Double
        }
    }

    public struct Suggestion: Codable, Sendable, Identifiable {
        public let type: String
        public let severity: String
        public let message: String
        public let affectedCount: Int?

        public var id: String { type } // Identifiable for ForEach
    }

    public struct ImageMetadata: Codable, Sendable {
        public let imageQuality: String?
        public let lighting: String?
        public let sharpness: String?
        public let readableCount: Int?
    }
}

// MARK: - Bookshelf AI Service

/// Service for communicating with Cloudflare bookshelf-ai-worker.
/// Actor-isolated for thread-safe network operations.
actor BookshelfAIService {
    // MARK: - Configuration

    private let endpoint = EnrichmentConfig.scanBookshelfURL
    private let timeout: TimeInterval = EnrichmentConfig.sseTimeout
    private let maxImageSize: Int = 10_000_000 // 10MB max (matches worker limit)

    // MARK: - Singleton

    static let shared = BookshelfAIService()

    private init() {}

    // MARK: - Provider Selection

    /// Read user-selected AI provider from UserDefaults
    /// UserDefaults is thread-safe, safe to call from actor context
    private func getSelectedProvider() -> AIProvider {
        let raw = UserDefaults.standard.string(forKey: "aiProvider") ?? "gemini-flash"
        return AIProvider(rawValue: raw) ?? .geminiFlash
    }

    // MARK: - Public API

    /// Process bookshelf image and return detected books with suggestions.
    /// - Parameter image: UIImage to process (will be compressed)
    /// - Returns: Tuple of (detected books, suggestions for improvement)
    func processBookshelfImage(_ image: UIImage) async throws -> ([DetectedBook], [SuggestionViewModel]) {
        // Step 1: Compress image to acceptable size
        guard let imageData = compressImage(image, maxSizeBytes: maxImageSize) else {
            throw BookshelfAIError.imageCompressionFailed
        }

        // Step 2: Upload to Cloudflare Worker
        let response = try await uploadImage(imageData)

        // Step 3: Check image quality metadata
        if let metadata = response.metadata, let quality = metadata.imageQuality {
            if quality.lowercased().contains("poor") || quality.lowercased().contains("reject") {
                throw BookshelfAIError.imageQualityRejected(quality)
            }
        }

        // Step 4: Convert AI response to DetectedBook models
        let detectedBooks = response.books.compactMap { aiBook in
            convertToDetectedBook(aiBook)
        }

        // Step 5: Generate suggestions (AI-first, client fallback)
        let suggestions = SuggestionGenerator.generateSuggestions(from: response)

        // Return both books and suggestions
        return (detectedBooks, suggestions)
    }

    // MARK: - Progress Tracking

    /// Process bookshelf image with WebSocket real-time progress tracking.
    /// CRITICAL: Uses WebSocket-first protocol to prevent race conditions
    ///
    /// Flow:
    /// 1. Connect WebSocket BEFORE uploading image
    /// Process bookshelf image using WebSocket for real-time progress
    /// - Parameters:
    ///   - image: UIImage to process
    ///   - jobId: Pre-generated job identifier
    ///   - provider: AI provider (Gemini or Cloudflare)
    ///   - progressHandler: Closure for progress updates
    /// - Returns: Tuple of detected books and suggestions
    /// - Throws: BookshelfAIError for failures
    internal func processViaWebSocket(
        image: UIImage,
        jobId: String,
        provider: AIProvider,
        progressHandler: @MainActor @escaping (Double, String) -> Void
    ) async throws(BookshelfAIError) -> ([DetectedBook], [SuggestionViewModel]) {
        // STEP 1: Compress image
        let config = provider.preprocessingConfig
        let processedImage = image.resizeForAI(maxDimension: config.maxDimension)

        guard let imageData = compressImageAdaptive(processedImage, maxSizeBytes: maxImageSize) else {
            throw .imageCompressionFailed
        }

        // STEP 2: Upload image and get auth token
        let scanResponse: ScanJobResponse
        do {
            scanResponse = try await startScanJob(imageData, provider: provider, jobId: jobId)
            #if DEBUG
            print("✅ Image uploaded with jobId: \(jobId), token: \(scanResponse.authToken.prefix(8))...")
            #endif
        } catch {
            throw .networkError(error)
        }

        // STEP 3: Connect WebSocket with authentication token
        let wsManager = await WebSocketProgressManager()
        do {
            _ = try await wsManager.establishConnection(jobId: jobId, token: scanResponse.authToken)
            try await wsManager.configureForJob(jobId: jobId)

            // NEW: Send ready signal to server
            try await wsManager.sendReadySignal()

            #if DEBUG
            print("✅ WebSocket connected with authentication and ready signal sent for job \(jobId)")
            #endif
        } catch {
            throw .networkError(error)
        }

        // STEP 4: Listen for progress updates
        let result: Result<([DetectedBook], [SuggestionViewModel]), BookshelfAIError> = await withCheckedContinuation { continuation in
            // Track if continuation has been resumed to prevent double-resume
            var continuationResumed = false

            Task { @MainActor in
                // Set disconnection handler to resume continuation if WebSocket drops
                wsManager.setDisconnectionHandler { error in
                    guard !continuationResumed else { return }
                    continuationResumed = true
                    #if DEBUG
                    print("⚠️ WebSocket disconnected unexpectedly, resuming continuation with error")
                    #endif
                    continuation.resume(returning: .failure(.networkError(error)))
                }

                wsManager.setProgressHandler { jobProgress in
                    // Skip keep-alive pings
                    guard jobProgress.keepAlive != true else {
                        #if DEBUG
                        print("🔁 Keep-alive ping received (skipping UI update)")
                        #endif
                        return
                    }

                    progressHandler(jobProgress.fractionCompleted, jobProgress.currentStatus)

                    // Check for completion via scanResult presence (set by WebSocketProgressManager on job_complete)
                    if let scanResult = jobProgress.scanResult {
                        guard !continuationResumed else { return }
                        continuationResumed = true

                        #if DEBUG
                        print("✅ Scan complete with \(scanResult.totalDetected) books (\(scanResult.approved) approved, \(scanResult.needsReview) review)")
                        #endif
                        wsManager.disconnect()

                        // Convert scan result to detected books
                        let detectedBooks = scanResult.books.compactMap { bookPayload in
                            self.convertPayloadToDetectedBook(bookPayload)
                        }

                        // Generate suggestions (using metadata from scan result)
                        let suggestions = self.generateSuggestionsFromPayload(scanResult)

                        continuation.resume(returning: .success((detectedBooks, suggestions)))
                    }

                    // Check for error or failure
                    let status = jobProgress.currentStatus.lowercased()
                    if status.contains("error") || status.contains("fail") {
                        guard !continuationResumed else { return }
                        continuationResumed = true
                        wsManager.disconnect()
                        continuation.resume(returning: .failure(.serverError(500, "Job failed: \(jobProgress.currentStatus)")))
                    }
                }
            }
        }

        // Unwrap result
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }

    // MARK: - SSE Processing (API Contract v3.2)

    /// Process bookshelf image using SSE for real-time progress (API Contract v3.2)
    /// - Parameters:
    ///   - image: UIImage to process
    ///   - jobId: Pre-generated job identifier
    ///   - provider: AI provider
    ///   - progressHandler: Closure for progress updates
    /// - Returns: Tuple of detected books and suggestions
    internal func processViaSSE(
        image: UIImage,
        jobId: String,
        provider: AIProvider,
        progressHandler: @MainActor @escaping (Double, String) -> Void
    ) async throws(BookshelfAIError) -> ([DetectedBook], [SuggestionViewModel]) {
        // STEP 1: Compress image
        let config = provider.preprocessingConfig
        let processedImage = image.resizeForAI(maxDimension: config.maxDimension)

        guard let imageData = compressImageAdaptive(processedImage, maxSizeBytes: maxImageSize) else {
            throw .imageCompressionFailed
        }

        // STEP 2: Upload image and get SSE URL
        let scanResponse: ScanJobResponse
        do {
            scanResponse = try await startScanJob(imageData, provider: provider, jobId: jobId)
            #if DEBUG
            print("SSE: Image uploaded with jobId: \(jobId)")
            #endif
        } catch {
            throw .networkError(error)
        }

        // STEP 3: Check for SSE URL (V2 endpoint)
        guard let sseUrlPath = scanResponse.sseUrl else {
            throw .serverError(501, "SSE URL not provided - backend may not support SSE yet")
        }

        // Construct full SSE URL
        guard let sseUrl = URL(string: "\(EnrichmentConfig.apiBaseURL)\(sseUrlPath)") else {
            throw .invalidResponse
        }

        // STEP 4: Connect to SSE stream
        let sseClient = SSEClient(url: sseUrl, authToken: scanResponse.authToken)
        let eventStream = await sseClient.connect()

        #if DEBUG
        print("SSE: Connected for job \(jobId)")
        #endif

        // STEP 5: Process SSE events
        var resultsUrl: String?

        for await event in eventStream {
            switch event {
            case .progress(let progress):
                let fraction = Double(progress.progress) / 100.0
                await progressHandler(fraction, progress.status)

            case .completed(let completed):
                // Extract results URL from data
                if let data = completed.data.value as? [String: Any],
                   let url = data["resultsUrl"] as? String {
                    resultsUrl = url
                }
                // Break out of the stream loop
                break

            case .failed(let failed):
                throw .serverError(500, "SSE job failed: \(failed.error)")
            }
        }

        // STEP 6: Fetch full results from resultsUrl
        guard let url = resultsUrl else {
            throw .invalidResponse
        }

        let scanResult: ScanResultPayload
        do {
            scanResult = try await fetchScanResults(url: url)
        } catch let error as BookshelfAIError {
            throw error
        } catch {
            throw .networkError(error)
        }

        // Convert to DetectedBooks
        let finalBooks = scanResult.books.compactMap { bookPayload in
            convertPayloadToDetectedBook(bookPayload)
        }

        let finalSuggestions = generateSuggestionsFromPayload(scanResult)

        return (finalBooks, finalSuggestions)
    }

    /// Process bookshelf image with real-time progress tracking.
    /// Strategy: SSE-first (API v3.2), WebSocket fallback (legacy)
    ///
    /// - Parameters:
    ///   - image: UIImage to process
    ///   - progressHandler: Closure to handle progress updates (called on MainActor)
    /// - Returns: Tuple of processed image, detected books, and suggestions
    /// - Throws: BookshelfAIError for image compression, network, or processing errors
    func processBookshelfImageWithProgress(
        _ image: UIImage,
        progressHandler: @MainActor @escaping (Double, String) -> Void
    ) async throws -> (UIImage, [DetectedBook], [SuggestionViewModel]) {
        let provider = getSelectedProvider()
        let jobId = UUID().uuidString

        #if DEBUG
        print("[Analytics] bookshelf_scan_started - provider: \(provider.rawValue), scan_id: \(jobId)")
        #endif

        // Check feature flag for SSE (API Contract v3.2)
        let useSSE = await FeatureFlags.shared.enablePhotoScanSSE

        if useSSE {
            // Try SSE first (API Contract v3.2)
            do {
                #if DEBUG
                print("SSE: Attempting connection for job \(jobId)")
                #endif

                let result = try await processViaSSE(
                    image: image,
                    jobId: jobId,
                    provider: provider,
                    progressHandler: progressHandler
                )

                #if DEBUG
                print("SSE: Scan completed successfully")
                print("[Analytics] bookshelf_scan_completed - provider: \(provider.rawValue), books_detected: \(result.0.count), scan_id: \(jobId), success: true, strategy: sse")
                #endif

                return (image, result.0, result.1)

            } catch {
                #if DEBUG
                print("SSE: Failed, falling back to WebSocket: \(error)")
                #endif
                // Fall through to WebSocket
            }
        }

        // WebSocket fallback (or primary if SSE disabled)
        do {
            #if DEBUG
            print("WebSocket: Attempting connection for job \(jobId)")
            #endif

            let result = try await processViaWebSocket(
                image: image,
                jobId: jobId,
                provider: provider,
                progressHandler: progressHandler
            )

            #if DEBUG
            print("WebSocket: Scan completed successfully")
            print("[Analytics] bookshelf_scan_completed - provider: \(provider.rawValue), books_detected: \(result.0.count), scan_id: \(jobId), success: true, strategy: websocket")
            #endif

            return (image, result.0, result.1)

        } catch {
            #if DEBUG
            print("Scan failed: \(error)")
            print("[Analytics] bookshelf_scan_failed - provider: \(provider.rawValue), scan_id: \(jobId), error: \(error)")
            #endif
            throw error
        }
    }

    /// Process bookshelf image with WebSocket real-time progress tracking.
    /// DEPRECATED: Use processBookshelfImageWithProgress for SSE-first strategy.
    @available(*, deprecated, message: "Use processBookshelfImageWithProgress for SSE-first strategy")
    func processBookshelfImageWithWebSocket(
        _ image: UIImage,
        progressHandler: @MainActor @escaping (Double, String) -> Void
    ) async throws -> (UIImage, [DetectedBook], [SuggestionViewModel]) {
        // Delegate to new method for backward compatibility
        try await processBookshelfImageWithProgress(image, progressHandler: progressHandler)
    }

    // MARK: - Private Methods

    /// Parse retry-after from JSON response body (fallback when header missing)
    /// - Parameter data: Response body data
    /// - Returns: Retry-after seconds if found in response body
    private func parseRetryAfterFromBody(_ data: Data) -> Int? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let details = error["details"] as? [String: Any] else {
            return nil
        }
        
        // Try to extract retryAfter from details (can be Int, Double, or String)
        if let retryAfter = details["retryAfter"] as? Int {
            return retryAfter
        } else if let retryAfterDouble = details["retryAfter"] as? Double {
            return Int(round(retryAfterDouble))
        } else if let retryAfter = details["retryAfter"] as? String,
                  let seconds = Int(retryAfter) {
            return seconds
        }
        
        return nil
    }

    /// Upload compressed image data to Cloudflare Worker.
    private func uploadImage(_ imageData: Data) async throws -> BookshelfAIResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        request.httpBody = imageData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw BookshelfAIError.invalidResponse
            }

            // Check HTTP status
            guard (200...299).contains(httpResponse.statusCode) else {
                // Handle 429 Rate Limit separately (GitHub Issue #426)
                if httpResponse.statusCode == 429 {
                    // Parse Retry-After header (seconds)
                    let retryAfter: Int
                    if let retryAfterHeader = httpResponse.value(forHTTPHeaderField: "Retry-After"),
                       let seconds = Int(retryAfterHeader) {
                        retryAfter = seconds
                        #if DEBUG
                        print("⏱️ Rate limit: using Retry-After header value: \(seconds)s")
                        #endif
                    } else if let bodyValue = parseRetryAfterFromBody(data) {
                        // Fallback: try to parse from response body
                        retryAfter = bodyValue
                        #if DEBUG
                        print("⏱️ Rate limit: using body retryAfter value: \(bodyValue)s")
                        #endif
                    } else {
                        // Final fallback: 60s default (Issue #6 - verify backend alignment)
                        retryAfter = 60
                        #if DEBUG
                        print("⚠️ Rate limit fallback: using default 60s (verify backend rate limit config)")
                        #endif
                    }
                    throw BookshelfAIError.rateLimitExceeded(retryAfter: retryAfter)
                }
                
                // Other server errors
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw BookshelfAIError.serverError(httpResponse.statusCode, errorMessage)
            }

            // Decode JSON response
            let decoder = JSONDecoder()
            return try decoder.decode(BookshelfAIResponse.self, from: data)

        } catch let error as BookshelfAIError {
            throw error
        } catch let error as DecodingError {
            throw BookshelfAIError.decodingFailed(error)
        } catch {
            throw BookshelfAIError.networkError(error)
        }
    }

    /// Compress UIImage with adaptive cascade algorithm
    /// Guarantees <10MB output by cascading through resolution levels
    ///
    /// Strategy: Try multiple resolution + quality combinations
    /// - 1920px @ [0.9, 0.85, 0.8, 0.75, 0.7]
    /// - 1280px @ [0.85, 0.8, 0.75, 0.7, 0.6]
    /// - 960px @ [0.8, 0.75, 0.7, 0.6, 0.5]
    /// - 800px @ [0.7, 0.6, 0.5, 0.4]
    ///
    /// Each resolution reduction = ~50% size reduction,
    /// guarantees success without quality degradation
    ///
    /// - Parameter image: UIImage to compress
    /// - Parameter maxSizeBytes: Maximum output size (10MB)
    /// - Returns: Compressed JPEG data, or nil if truly impossible
    nonisolated private func compressImageAdaptive(_ image: UIImage, maxSizeBytes: Int) -> Data? {
        let compressionService = ImageCompressionService()
        return compressionService.compress(image, maxSizeBytes: maxSizeBytes)
    }

    /// Legacy compression method (for backward compatibility)
    /// Deprecated: Use compressImageAdaptive() instead
    nonisolated private func compressImage(_ image: UIImage, maxSizeBytes: Int) -> Data? {
        let compressionService = ImageCompressionService()
        return compressionService.compress(image, maxSizeBytes: maxSizeBytes)
    }

    /// Convert AI response book to DetectedBook model.
    nonisolated internal func convertToDetectedBook(_ aiBook: BookshelfAIResponse.AIDetectedBook) -> DetectedBook? {
        // Calculate CGRect from normalized coordinates
        let boundingBox = CGRect(
            x: aiBook.boundingBox.x1,
            y: aiBook.boundingBox.y1,
            width: aiBook.boundingBox.x2 - aiBook.boundingBox.x1,
            height: aiBook.boundingBox.y2 - aiBook.boundingBox.y1
        )

        // Determine initial status from enrichment data
        let status: DetectionStatus
        switch aiBook.enrichmentStatus?.uppercased() {
        case "ENRICHED", "FOUND":
            status = .detected
        case "UNCERTAIN", "NEEDS_REVIEW":
            status = .uncertain
        case "REJECTED":
            status = .rejected
        default:
            // Fallback for nil or unknown status
            if aiBook.title == nil || aiBook.author == nil {
                status = .uncertain
            } else {
                status = .detected
            }
        }

        // Use the direct confidence score from the API
        let confidence = aiBook.confidence ?? 0.5

        // Generate raw text from available data
        let rawText = [aiBook.title, aiBook.author]
            .compactMap { $0 }
            .joined(separator: " by ")

        return DetectedBook(
            isbn: aiBook.isbn,
            title: aiBook.title,
            author: aiBook.author,
            confidence: confidence,
            boundingBox: boundingBox,
            rawText: rawText.isEmpty ? "Unreadable spine" : rawText,
            status: status
        )
    }

    /// Convert WebSocket payload book to DetectedBook model.
    nonisolated internal func convertPayloadToDetectedBook(_ bookPayload: ScanResultPayload.BookPayload) -> DetectedBook? {
        // Calculate CGRect from normalized coordinates
        let boundingBox = CGRect(
            x: bookPayload.boundingBox.x1,
            y: bookPayload.boundingBox.y1,
            width: bookPayload.boundingBox.x2 - bookPayload.boundingBox.x1,
            height: bookPayload.boundingBox.y2 - bookPayload.boundingBox.y1
        )

        // Determine status from enrichment
        let status: DetectionStatus
        if let enrichment = bookPayload.enrichment {
            switch enrichment.status.uppercased() {
            case "SUCCESS":
                status = .detected
            case "NOT_FOUND", "ERROR":
                status = .uncertain
            default:
                status = bookPayload.confidence >= 0.7 ? .detected : .uncertain
            }
        } else {
            status = bookPayload.confidence >= 0.7 ? .detected : .uncertain
        }

        // Generate raw text
        let rawText = "\(bookPayload.title) by \(bookPayload.author)"

        // Map format string to EditionFormat enum
        let format: EditionFormat? = {
            guard let formatString = bookPayload.format?.lowercased() else { return nil }
            switch formatString {
            case "hardcover":
                return .hardcover
            case "paperback":
                return .paperback
            case "mass-market":
                return .massMarket
            case "unknown":
                return nil  // Unknown format = nil
            default:
                return nil
            }
        }()

        var detectedBook = DetectedBook(
            isbn: bookPayload.isbn,
            title: bookPayload.title,
            author: bookPayload.author,
            format: format,  // NEW: Format from Gemini
            confidence: bookPayload.confidence,
            boundingBox: boundingBox,
            rawText: rawText,
            status: status
        )

        // Attach enrichment data if available and successful
        if let enrichment = bookPayload.enrichment,
           enrichment.status.uppercased() == "SUCCESS",
           let work = enrichment.work,
           let editions = enrichment.editions,
           let authors = enrichment.authors,
           !editions.isEmpty,
           !authors.isEmpty {

            detectedBook.enrichmentWork = work
            detectedBook.enrichmentEditions = editions
            detectedBook.enrichmentAuthors = authors

            #if DEBUG
            print("✅ Enrichment data attached to DetectedBook: \(work.title)")
            #endif
        } else {
            #if DEBUG
            print("⚠️ No enrichment data available for DetectedBook: \(bookPayload.title)")
            #endif
        }

        return detectedBook
    }

    /// Generate suggestions from scan result payload
    nonisolated internal func generateSuggestionsFromPayload(_ scanResult: ScanResultPayload) -> [SuggestionViewModel] {
        var suggestions: [SuggestionViewModel] = []

        // Low confidence warning
        if scanResult.needsReview > 0 {
            suggestions.append(SuggestionViewModel(
                type: "low_confidence",
                severity: "warning",
                affectedCount: scanResult.needsReview
            ))
        }

        // No enrichment found
        let unenriched = scanResult.totalDetected - scanResult.metadata.enrichedCount
        if unenriched > 0 {
            suggestions.append(SuggestionViewModel(
                type: "no_enrichment",
                severity: "info",
                affectedCount: unenriched
            ))
        }

        return suggestions
    }

    // MARK: - Progress Tracking Methods (Swift 6.2 Task Pattern)

    private func startScanJob(_ imageData: Data, provider: AIProvider, jobId: String) async throws -> ScanJobResponse {
        // Construct URL with jobId query parameter (provider always Gemini)
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "jobId", value: jobId)
            // Provider param removed - backend defaults to gemini-flash
        ]

        guard let urlWithParams = components.url else {
            throw BookshelfAIError.invalidResponse
        }

        var request = URLRequest(url: urlWithParams)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = imageData
        request.timeoutInterval = timeout // Use same timeout as uploadImage (70s for AI + enrichment)

        // DIAGNOSTIC: Log outgoing request details
        #if DEBUG
        print("[Diagnostic iOS Layer] === Outgoing Request for job \(jobId) ===")
        #endif
        #if DEBUG
        print("[Diagnostic iOS Layer] Provider: Gemini 2.0 Flash (optimized)")
        #endif
        #if DEBUG
        print("[Diagnostic iOS Layer] Full URL: \(urlWithParams.absoluteString)")
        #endif
        #if DEBUG
        print("[Diagnostic iOS Layer] Query items: \(components.queryItems ?? [])")
        #endif

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 202 else {
            throw BookshelfAIError.invalidResponse
        }

        return try JSONDecoder().decode(ScanJobResponse.self, from: data)
    }

    /// Calculate expected progress based on elapsed time and stages
    nonisolated func calculateExpectedProgress(
        elapsed: Int,
        stages: [ScanJobResponse.StageMetadata]
    ) -> Double {
        var cumulativeTime = 0

        for (index, stage) in stages.enumerated() {
            cumulativeTime += stage.typicalDuration

            if elapsed < cumulativeTime {
                let stageElapsed = elapsed - (cumulativeTime - stage.typicalDuration)
                let stageProgress = Double(stageElapsed) / Double(stage.typicalDuration)

                let previousProgress = index > 0 ? stages[index - 1].progress : 0.0
                let currentStageRange = stage.progress - previousProgress

                return min(1.0, previousProgress + (stageProgress * currentStageRange))
            }
        }

        return stages.last?.progress ?? 1.0
    }

    /// Poll job status from server (DEPRECATED - WebSocket-only now)
    /// This method is retained for backward compatibility but should not be used.
    /// All progress updates come via WebSocket on /ws/progress endpoint.
    @available(*, deprecated, message: "Polling removed - use WebSocket for all progress updates")
    func pollJobStatus(jobId: String) async throws -> JobStatusResponse {
        // Polling endpoints no longer exist on api-worker
        // This is kept for compilation but will always fail
        throw BookshelfAIError.serverError(410, "Polling endpoints removed - use WebSocket")
    }

    // MARK: - Batch Scanning

    /// Submit batch of photos for processing
    public func submitBatch(jobId: String, photos: [CapturedPhoto]) async throws -> BatchSubmissionResponse {
        let batchRequest = try await createBatchRequest(jobId: jobId, photos: photos)

        let endpoint = EnrichmentConfig.scanBookshelfBatchURL

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120.0 // 2 minutes for upload

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(batchRequest)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BookshelfAIError.invalidResponse
        }

        guard httpResponse.statusCode == 202 else { // Accepted
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw BookshelfAIError.serverError(httpResponse.statusCode, errorMessage)
        }

        let decoder = JSONDecoder()
        let submissionResponse = try decoder.decode(BatchSubmissionResponse.self, from: data)

        return submissionResponse
    }

    // MARK: - Response Envelope Helper

    /// Generic helper to unwrap ResponseEnvelope and handle common API errors.
    /// This eliminates duplication in `fetchJobResults` and `fetchScanResults`.
    /// (Issue #3 - Eliminate ResponseEnvelope unwrapping duplication)
    private func unwrapEnvelope<T: Codable>(_ data: Data) throws -> T {
        let decoder = JSONDecoder()
        do {
            let envelope = try decoder.decode(ResponseEnvelope<T>.self, from: data)

            guard let result = envelope.data else {
                if let error = envelope.error {
                    // Map API error info to BookshelfAIError for consistency
                    throw BookshelfAIError.apiError(code: error.code ?? "UNKNOWN", message: error.message)
                }
                // If data is nil and no specific error, throw a generic "NO_DATA" error
                throw BookshelfAIError.apiError(code: "NO_DATA", message: "Missing results data")
            }

            return result
        } catch let error as DecodingError {
            // Catch decoding errors specifically and wrap them
            throw BookshelfAIError.decodingFailed(error)
        } catch let error as BookshelfAIError {
            // Re-throw BookshelfAIError if it was already thrown by the helper
            throw error
        } catch {
            // Catch any other unexpected errors
            throw BookshelfAIError.networkError(error)
        }
    }

    public func fetchScanResults(url: String) async throws -> ScanResultPayload {
        guard let fullURL = URL(string: "\(EnrichmentConfig.apiBaseURL)\(url)") else {
            throw BookshelfAIError.invalidResponse
        }

        let (data, response) = try await URLSession.shared.data(from: fullURL)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BookshelfAIError.invalidResponse
        }

        // Handle non-2xx responses
        guard (200...299).contains(httpResponse.statusCode) else {
            // 404 indicates expired results
            if httpResponse.statusCode == 404 {
                throw BookshelfAIError.resultsExpired
            }
            throw BookshelfAIError.invalidResponse
        }

        // Unwrap ResponseEnvelope using helper
        let results: ScanResultPayload = try unwrapEnvelope(data)

        // Validate expiresAt field (Issue #2 - Missing expiresAt validation)
        // According to v2.4 API contract, results have a 24-hour TTL
        if let expiresAtString = results.expiresAt {
            let formatter = ISO8601DateFormatter()
            // Ensure formatter can handle fractional seconds if present
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let expiryDate = formatter.date(from: expiresAtString) {
                if expiryDate < Date() {
                    // Results are expired client-side
                    throw BookshelfAIError.resultsExpired
                }
            } else {
                // Log if expiresAt string is malformed
                #if DEBUG
                print("⚠️ Failed to parse expiresAt date: \(expiresAtString)")
                #endif
            }
        }

        return results
    }

    /// Fetch full job results from KV cache via HTTP GET
    /// v2.0 Migration: WebSocket sends lightweight summary, full results fetched on demand
    /// Results are cached for 24 hours after job completion
    public func fetchJobResults(jobId: String) async throws -> ScanResultPayload {
        let url = URL(string: "\(EnrichmentConfig.apiBaseURL)/v1/jobs/\(jobId)/results")!

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BookshelfAIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            // Unwrap ResponseEnvelope using helper
            let results: ScanResultPayload = try unwrapEnvelope(data)

            // Validate expiresAt field (Issue #2 - Missing expiresAt validation)
            // According to v2.4 API contract, results have a 24-hour TTL
            if let expiresAtString = results.expiresAt {
                let formatter = ISO8601DateFormatter()
                // Ensure formatter can handle fractional seconds if present
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let expiryDate = formatter.date(from: expiresAtString) {
                    if expiryDate < Date() {
                        // Results are expired client-side
                        throw BookshelfAIError.resultsExpired
                    }
                } else {
                    // Log if expiresAt string is malformed
                    #if DEBUG
                    print("⚠️ Failed to parse expiresAt date: \(expiresAtString)")
                    #endif
                }
            }

            return results

        case 404:
            // Results expired (> 24 hours old) or not found
            throw BookshelfAIError.resultsExpired

        case 429:
            // Rate limited - attempt to parse retryAfter from body
            let retryAfter = parseRetryAfterFromBody(data) ?? 60
            throw BookshelfAIError.rateLimitExceeded(retryAfter: retryAfter)

        default:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw BookshelfAIError.serverError(httpResponse.statusCode, errorMessage)
        }
    }

    /// Create batch request payload with compressed images
    internal func createBatchRequest(jobId: String, photos: [CapturedPhoto]) async throws -> BatchScanRequest {
        var images: [BatchScanRequest.ImageData] = []

        for (index, photo) in photos.enumerated() {
            // Compress image
            let compressed = try await compressImage(photo.image, maxSizeKB: 500)

            guard let jpegData = compressed.jpegData(compressionQuality: 0.9) else {
                throw BookshelfAIError.imageCompressionFailed
            }

            let base64 = jpegData.base64EncodedString()

            images.append(BatchScanRequest.ImageData(index: index, data: base64))
        }

        return BatchScanRequest(jobId: jobId, images: images)
    }

    /// Compress image to target size (reuse existing logic)
    public func compressImage(_ image: UIImage, maxSizeKB: Int) async throws -> UIImage {
        let maxBytes = maxSizeKB * 1024
        let targetSize = CGSize(width: 3072, height: 3072)

        // Resize to target dimensions
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        // Compress with quality adjustment to hit target size
        var compression: CGFloat = 0.9
        var imageData = resized.jpegData(compressionQuality: compression)

        while let data = imageData, data.count > maxBytes && compression > 0.5 {
            compression -= 0.1
            imageData = resized.jpegData(compressionQuality: compression)
        }

        guard let finalData = imageData, let finalImage = UIImage(data: finalData) else {
            throw BookshelfAIError.imageCompressionFailed
        }

        return finalImage
    }
}

// MARK: - Batch Response Models

/// Response from batch submission endpoint
public struct BatchSubmissionResponse: Codable, Sendable {
    public let jobId: String
    public let totalPhotos: Int
    public let status: String
}

// MARK: - UIImage Extensions

extension UIImage {
    /// Resize image for AI processing without upscaling
    func resizeForAI(maxDimension: CGFloat) -> UIImage {
        let scale = maxDimension / max(size.width, size.height)
        if scale >= 1 { return self } // Don't upscale

        let newSize = CGSize(
            width: size.width * scale,
            height: size.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

#endif  // canImport(UIKit)