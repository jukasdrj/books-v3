import Foundation

/// Type of SSE job for routing unprefixed events correctly
public enum SSEJobType: Sendable {
    case enrichment      // Legacy enrichment (enrichment.progress, etc.)
    case csvImport       // CSV import (import.progress or unprefixed progress)
    case bookshelfScan   // V3 bookshelf scan (unprefixed progress/completed with results)
}

/// A client for connecting to Server-Sent Events (SSE) streams,
/// designed for real-time progress updates with reconnection logic.
///
/// Features:
/// - Actor-based concurrency for thread safety
/// - Exponential backoff with jitter for reconnection
/// - Proper SSE parsing (handles \r, \n, \r\n line endings)
/// - AsyncStream integration for Swift concurrency
/// - Automatic cleanup on stream termination
public actor SSEClient: NSObject { // NSObject required for URLSessionDelegate
    private let url: URL
    private let authToken: String
    private let jobType: SSEJobType
    private var urlSession: URLSession?
    private var dataTask: URLSessionDataTask?
    private var currentContinuation: AsyncStream<EnrichmentEvent>.Continuation?
    private var reconnectionTask: Task<Void, Never>?

    // Reconnection strategy
    private var currentBackoffDelay: TimeInterval = 1.0 // Initial delay
    private let maxBackoffDelay: TimeInterval = 60.0    // Max delay between reconnect attempts
    private let backoffFactor: Double = 2.0             // Factor to increase delay
    private let jitterFactor: Double = 0.2              // Add random jitter to avoid thundering herd
    private var isCurrentlyConnected: Bool = false      // Tracks logical connection state

    // Connection validation state - tracks whether we received a valid HTTP 200 response
    // This is critical for distinguishing between:
    // - Server rejection (401/403/500) before any data → should reconnect or fail
    // - Normal closure after receiving events → don't reconnect
    private var hasReceivedValidResponse: Bool = false
    private var lastHTTPStatusCode: Int?

    // Parsing state
    private var buffer = ""
    private var currentEventName: String?
    private var currentEventData: [String] = []

    // Static regex for line splitting - computed once, guaranteed valid pattern
    private static let lineSeparatorRegex: NSRegularExpression = {
        // Pattern is statically known to be valid; this only runs once at app launch
        guard let regex = try? NSRegularExpression(pattern: "\\r?\\n", options: []) else {
            fatalError("SSEClient: Invalid line separator regex pattern - this is a programmer error")
        }
        return regex
    }()

    /// Initializes the SSEClient.
    /// - Parameters:
    ///   - url: The URL of the SSE endpoint.
    ///   - authToken: The Bearer token for authentication.
    ///   - jobType: Type of job for routing unprefixed events (default: .enrichment for backward compatibility)
    public init(url: URL, authToken: String, jobType: SSEJobType = .enrichment) {
        self.url = url
        self.authToken = authToken
        self.jobType = jobType
        super.init() // Call NSObject initializer
    }

    /// Connects to the SSE stream and returns an `AsyncStream` of `EnrichmentEvent`s.
    /// The stream will automatically attempt to reconnect on failure.
    public func connect() -> AsyncStream<EnrichmentEvent> {
        return AsyncStream { continuation in
            self.currentContinuation = continuation
            // When the stream is terminated (e.g., consumer stops iterating),
            // ensure resources are cleaned up.
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { await self?.disconnect() }
            }
            // Start the initial connection attempt.
            // This happens in a Task to avoid blocking the caller of `connect()`.
            Task { self.startConnectionAttempt() }
        }
    }

    /// Initiates or reinitiates the connection to the SSE endpoint.
    private func startConnectionAttempt() {
        guard !isCurrentlyConnected else { return } // Prevent multiple simultaneous connections
        isCurrentlyConnected = true
        hasReceivedValidResponse = false // Reset for new connection attempt
        lastHTTPStatusCode = nil

        reconnectionTask?.cancel() // Cancel any pending reconnection task
        reconnectionTask = nil

        print("SSEClient: Attempting to connect to \(url)")

        // Invalidate and re-create URLSession for a clean slate, especially after errors.
        urlSession?.invalidateAndCancel()
        setupURLSession()
        setupDataTask()
        dataTask?.resume()

        currentBackoffDelay = 1.0 // Reset backoff delay on a new connection attempt
    }

    /// Configures `URLSession` with appropriate settings for SSE.
    private func setupURLSession() {
        let configuration = URLSessionConfiguration.default
        // SSE streams are long-lived; set timeouts to effectively infinite.
        configuration.timeoutIntervalForRequest = TimeInterval(INT_MAX)
        configuration.timeoutIntervalForResource = TimeInterval(INT_MAX)

        // Use a dedicated delegate queue for processing stream data to prevent blocking
        // the actor's default executor with potentially long parsing operations,
        // while still allowing delegate calls to interact with actor state.
        let delegateQueue = OperationQueue()
        delegateQueue.name = "net.bookstrack.sseclient.delegate"
        delegateQueue.maxConcurrentOperationCount = 1 // Process delegate calls sequentially
        urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
    }

    /// Prepares the `URLSessionDataTask` with required headers.
    private func setupDataTask() {
        var request = URLRequest(url: url)
        // Standard SSE headers
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        // Required for Cloudflare Workers SSE compatibility - prevents connection drops
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        dataTask = urlSession?.dataTask(with: request)
    }

    /// Disconnects the SSE client and cleans up resources.
    /// Guard against multiple simultaneous disconnect calls (can happen from multiple Task completions)
    public func disconnect() {
        // Guard against multiple disconnect calls racing
        guard isCurrentlyConnected || currentContinuation != nil else {
            return
        }
        print("SSEClient: Disconnecting from \(url)")
        dataTask?.cancel()
        dataTask = nil
        urlSession?.invalidateAndCancel() // Invalidate and release session resources
        urlSession = nil
        isCurrentlyConnected = false
        hasReceivedValidResponse = false
        lastHTTPStatusCode = nil
        reconnectionTask?.cancel() // Ensure no pending reconnection attempts
        reconnectionTask = nil
        currentContinuation?.finish() // Signal to the consumer that the stream has ended
        currentContinuation = nil
        // Reset parsing state
        buffer = ""
        currentEventName = nil
        currentEventData = []
    }

    /// Schedules a reconnection attempt with exponential backoff and jitter.
    private func scheduleReconnect() {
        // Only schedule a reconnect if not already connected and continuation is active.
        guard !isCurrentlyConnected, currentContinuation != nil else { return }

        reconnectionTask?.cancel() // Cancel any previous reconnection task

        let jitter = Double.random(in: -jitterFactor...jitterFactor) * currentBackoffDelay
        let delay = min(max(1.0, currentBackoffDelay + jitter), maxBackoffDelay)

        print("SSEClient: Scheduling reconnect in \(String(format: "%.2f", delay)) seconds.")

        reconnectionTask = Task {
            do {
                try await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else {
                    print("SSEClient: Reconnect task cancelled before attempt.")
                    return
                }
                print("SSEClient: Reconnecting to \(url)...")
                self.startConnectionAttempt()
                currentBackoffDelay = min(currentBackoffDelay * backoffFactor, maxBackoffDelay) // Increase delay for next time
            } catch is CancellationError {
                print("SSEClient: Reconnect task cancelled during sleep.")
            } catch {
                print("SSEClient: Unexpected error in reconnection task: \(error.localizedDescription)")
            }
        }
    }

    /// Handles connection errors or task completion, triggering a reconnection.
    private func handleConnectionTermination(error: Error?) {
        // Check if we're already disconnected (due to terminal event) - don't reconnect
        guard isCurrentlyConnected else {
            print("SSEClient: Connection already closed (normal termination), not reconnecting")
            return
        }

        // Enhanced error logging with NSError details for debugging
        let nsError = error as NSError?
        let errorCode = nsError?.code ?? 0
        let errorDomain = nsError?.domain ?? "none"
        let errorMessage = error?.localizedDescription ?? "No error (nil)"

        print("SSEClient: Connection to \(url) terminated")
        print("SSEClient: Error details - code: \(errorCode), domain: \(errorDomain), message: \(errorMessage)")
        print("SSEClient: State - hasReceivedValidResponse: \(hasReceivedValidResponse), lastHTTPStatusCode: \(lastHTTPStatusCode ?? -1)")

        // Determine if this is a normal closure vs an error requiring reconnection
        // CRITICAL FIX: Only treat as "normal closure" if:
        // 1. We already received a valid HTTP 200 response (hasReceivedValidResponse == true)
        // 2. AND the error is nil or -1005 (connection lost after streaming)
        //
        // Previously, nil error during INITIAL connection (before any response) was incorrectly
        // treated as "normal closure", hiding server rejections (401/403/500).
        let isStreamingPhaseError = error == nil || errorCode == -1005
        let isNormalClosure = hasReceivedValidResponse && isStreamingPhaseError

        if isNormalClosure {
            print("SSEClient: Normal stream closure detected (received valid response + clean EOF), not reconnecting")
            isCurrentlyConnected = false
            hasReceivedValidResponse = false
            lastHTTPStatusCode = nil
            dataTask?.cancel()
            dataTask = nil
            urlSession?.invalidateAndCancel()
            urlSession = nil
            return
        }

        // Connection failed before receiving valid response OR real error occurred
        // Build detailed error message for consumer
        var detailedError = errorMessage
        if !hasReceivedValidResponse {
            if let statusCode = lastHTTPStatusCode {
                detailedError = "Server returned HTTP \(statusCode)"
            } else {
                detailedError = "Connection failed before receiving server response. \(errorMessage)"
            }
        }

        print("SSEClient: Connection error - \(detailedError)")

        // Yield a failed event to the stream consumer
        currentContinuation?.yield(.failed(EnrichmentFailed(
            isbn: "unknown",
            status: "connection_failed",
            error: detailedError
        )))

        isCurrentlyConnected = false // Mark as disconnected
        hasReceivedValidResponse = false
        lastHTTPStatusCode = nil
        dataTask?.cancel() // Ensure task is cancelled
        dataTask = nil
        urlSession?.invalidateAndCancel() // Invalidate and recreate session for next attempt
        urlSession = nil

        // Attempt to reconnect if the stream is still active.
        scheduleReconnect()
    }

    /// Parses incoming raw data chunks from the SSE stream.
    /// This method is crucial for handling partial lines and multiple events in a single chunk.
    private func parse(data: Data) {
        guard let string = String(data: data, encoding: .utf8) else {
            print("SSEClient: Failed to decode incoming data as UTF-8.")
            return
        }
        buffer += string

        // Use a regex to robustly split by newlines (\r, \n, \r\n) while keeping empty lines.
        let lineSeparatorRegex = Self.lineSeparatorRegex
        var lastRange = NSRange(buffer.startIndex..<buffer.startIndex, in: buffer)
        var lines: [String] = []

        lineSeparatorRegex.enumerateMatches(in: buffer, options: [], range: NSRange(buffer.startIndex..<buffer.endIndex, in: buffer)) { match, _, _ in
            guard let match = match else { return }
            let lineRange = NSRange(location: lastRange.upperBound, length: match.range.lowerBound - lastRange.upperBound)
            if let range = Range(lineRange, in: buffer) {
                lines.append(String(buffer[range]))
            }
            lastRange = match.range
        }

        // Add any remaining text as the last line (if not newline-terminated)
        // Use proper String index conversion to handle multi-byte UTF-8 characters correctly
        if let remainingStart = Range(NSRange(location: lastRange.upperBound, length: 0), in: buffer)?.lowerBound,
           remainingStart < buffer.endIndex {
            buffer = String(buffer[remainingStart...])
        } else {
            buffer = "" // Buffer was fully processed
        }

        // Process the extracted lines
        for line in lines {
            if line.isEmpty { // An empty line signals the end of an event.
                processPendingEvent()
            } else if line.starts(with: "event:") {
                processPendingEvent() // Process previous event before starting a new one.
                currentEventName = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
            } else if line.starts(with: "data:") {
                let dataString = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                currentEventData.append(dataString)
            }
            // Add handling for 'id:' and 'retry:' fields if the API contract expands.
            // For now, these are implicitly ignored as per the request.
        }
    }

    /// Processes the accumulated `currentEventData` for the `currentEventName`.
    private func processPendingEvent() {
        guard let eventName = currentEventName, !currentEventData.isEmpty else {
            currentEventName = nil
            currentEventData = []
            return // No complete event to process
        }

        // According to SSE spec, multiple 'data:' lines are concatenated with a newline.
        let combinedData = currentEventData.joined(separator: "\n")
        print("SSEClient: Processing event: \(eventName), data: \(combinedData.prefix(100))...") // Log prefix to avoid flooding console

        do {
            let decoder = JSONDecoder()
            guard let jsonData = combinedData.data(using: .utf8) else {
                throw SSEError.decodingError("Cannot decode data as UTF-8")
            }

            switch eventName {
            // MARK: - Lifecycle Events (V3 - all job types)
            case "initialized":
                // Job initialized - yield for bookshelf scans, ignore for others
                if jobType == .bookshelfScan {
                    let initialized = try decoder.decode(V3ScanInitialized.self, from: jsonData)
                    currentContinuation?.yield(.v3ScanInitialized(initialized))
                }
                #if DEBUG
                print("SSEClient: Job initialized, waiting for progress events")
                #endif

            case "ping":
                // Keep-alive heartbeat - yield for bookshelf scans, ignore for others
                if jobType == .bookshelfScan {
                    let ping = try decoder.decode(V3Ping.self, from: jsonData)
                    currentContinuation?.yield(.v3Ping(ping))
                }
                // No action needed for other job types

            // MARK: - Prefixed Enrichment Events (Legacy)
            case "enrichment.progress":
                let progress = try decoder.decode(EnrichmentProgress.self, from: jsonData)
                currentContinuation?.yield(.progress(progress))

            case "enrichment.completed":
                let completed = try decoder.decode(EnrichmentCompleted.self, from: jsonData)
                currentContinuation?.yield(.completed(completed))
                Task { [weak self] in await self?.disconnect() }

            case "enrichment.failed":
                let failed = try decoder.decode(EnrichmentFailed.self, from: jsonData)
                currentContinuation?.yield(.failed(failed))
                Task { [weak self] in await self?.disconnect() }

            // MARK: - Unprefixed Progress Event (routed by job type)
            case "progress":
                switch jobType {
                case .bookshelfScan:
                    // V3 scan progress - decode with V3ScanProgress model
                    let scanProgress = try decoder.decode(V3ScanProgress.self, from: jsonData)
                    currentContinuation?.yield(.v3ScanProgress(scanProgress))
                case .csvImport:
                    // CSV import progress
                    let csvProgress = try decoder.decode(CSVImportProgress.self, from: jsonData)
                    currentContinuation?.yield(.csvImportProgress(csvProgress))
                case .enrichment:
                    // Legacy: try to decode as CSV import (backward compatibility)
                    let csvProgress = try decoder.decode(CSVImportProgress.self, from: jsonData)
                    currentContinuation?.yield(.csvImportProgress(csvProgress))
                }

            // MARK: - Unprefixed Completed Event (routed by job type)
            case "completed":
                switch jobType {
                case .bookshelfScan:
                    // V3 scan completed - decode with inline results
                    let scanCompleted = try decoder.decode(V3ScanCompleted.self, from: jsonData)
                    currentContinuation?.yield(.v3ScanCompleted(scanCompleted))
                    Task { [weak self] in await self?.disconnect() }
                case .csvImport:
                    // CSV import completed
                    let csvCompleted = try decoder.decode(CSVImportCompleted.self, from: jsonData)
                    currentContinuation?.yield(.csvImportCompleted(csvCompleted))
                    Task { [weak self] in await self?.disconnect() }
                case .enrichment:
                    // Legacy: try to decode as CSV import (backward compatibility)
                    let csvCompleted = try decoder.decode(CSVImportCompleted.self, from: jsonData)
                    currentContinuation?.yield(.csvImportCompleted(csvCompleted))
                    Task { [weak self] in await self?.disconnect() }
                }

            // MARK: - Failed Events (all variants)
            case "failed":
                switch jobType {
                case .bookshelfScan:
                    // V3 scan failed - decode with error object
                    let scanFailed = try decoder.decode(V3ScanFailed.self, from: jsonData)
                    currentContinuation?.yield(.v3ScanFailed(scanFailed))
                    Task { [weak self] in await self?.disconnect() }
                default:
                    // Generic failed event
                    let failed = try decoder.decode(EnrichmentFailed.self, from: jsonData)
                    currentContinuation?.yield(.failed(failed))
                    Task { [weak self] in await self?.disconnect() }
                }

            case "canceled", "cancelled":
                // Job was canceled by user or system - treat as failed
                let failed = EnrichmentFailed(
                    isbn: "unknown",
                    status: "canceled",
                    error: "Job was canceled"
                )
                currentContinuation?.yield(.failed(failed))
                Task { [weak self] in await self?.disconnect() }

            case "error":
                // Stream error event - treat as failed
                let errorMsg = try? decoder.decode([String: String].self, from: jsonData)
                let failed = EnrichmentFailed(
                    isbn: "unknown",
                    status: "error",
                    error: errorMsg?["message"] ?? "Stream error"
                )
                currentContinuation?.yield(.failed(failed))
                Task { [weak self] in await self?.disconnect() }

            // MARK: - PhotoScan SSE Events (API Contract v3.2 - prefixed variant)
            case "photoscan.progress":
                let progress = try decoder.decode(PhotoScanSSEProgress.self, from: jsonData)
                // Convert to EnrichmentEvent for compatibility with existing stream
                currentContinuation?.yield(.progress(EnrichmentProgress(
                    isbn: progress.jobId,
                    status: progress.status,
                    progress: Int(progress.progress * 100),
                    provider: "photoscan"
                )))

            case "photoscan.completed":
                let completed = try decoder.decode(PhotoScanSSECompleted.self, from: jsonData)
                currentContinuation?.yield(.completed(EnrichmentCompleted(
                    isbn: completed.jobId,
                    status: completed.status,
                    data: AnyCodable(["resultsUrl": completed.resultsUrl, "summary": [
                        "totalDetected": completed.summary.totalDetected,
                        "approved": completed.summary.approved,
                        "needsReview": completed.summary.needsReview,
                        "enrichedCount": completed.summary.enrichedCount,
                        "duration": completed.summary.duration
                    ]])
                )))
                Task { [weak self] in await self?.disconnect() }

            case "photoscan.failed":
                let failed = try decoder.decode(PhotoScanSSEFailed.self, from: jsonData)
                currentContinuation?.yield(.failed(EnrichmentFailed(
                    isbn: failed.jobId,
                    status: failed.status,
                    error: failed.error
                )))
                Task { [weak self] in await self?.disconnect() }

            // MARK: - CSV Import Prefixed Events
            case "import.progress":
                let progress = try decoder.decode(CSVImportProgress.self, from: jsonData)
                currentContinuation?.yield(.csvImportProgress(progress))

            case "import.completed":
                let completed = try decoder.decode(CSVImportCompleted.self, from: jsonData)
                currentContinuation?.yield(.csvImportCompleted(completed))
                Task { [weak self] in await self?.disconnect() }

            case "import.failed":
                let failed = try decoder.decode(CSVImportFailed.self, from: jsonData)
                currentContinuation?.yield(.csvImportFailed(failed))
                Task { [weak self] in await self?.disconnect() }

            default:
                print("SSEClient: Received unknown event type: \(eventName). Data: \(combinedData)")
            }
        } catch {
            print("SSEClient: Failed to decode event data for \(eventName): \(error.localizedDescription)")
            currentContinuation?.yield(.failed(EnrichmentFailed(
                isbn: "unknown",
                status: "parsing_failed",
                error: error.localizedDescription
            )))
        }

        // Reset state for the next event.
        currentEventName = nil
        currentEventData = []
    }
}

// MARK: - URLSessionDataDelegate Extension

extension SSEClient: URLSessionDataDelegate {
    /// Called when the initial HTTP response is received - CRITICAL for validating SSE connection.
    /// This method allows us to inspect the HTTP status code BEFORE any data arrives.
    /// Without this, server rejections (401/403/500) would silently close the connection
    /// and be misinterpreted as "normal closure".
    nonisolated public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse else {
            print("SSEClient: Received non-HTTP response, cancelling")
            completionHandler(.cancel)
            return
        }

        let statusCode = httpResponse.statusCode
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"

        print("SSEClient: Received HTTP response - status: \(statusCode), content-type: \(contentType)")

        // Update actor state with response info
        Task {
            await self.handleInitialResponse(statusCode: statusCode, contentType: contentType)
        }

        // Validate HTTP 200 OK for SSE streams
        // Accept 200 (standard) or 201/202 (some backends return these for created streams)
        if (200...202).contains(statusCode) {
            // Validate Content-Type is text/event-stream (allow charset suffix)
            if contentType.hasPrefix("text/event-stream") {
                print("SSEClient: ✅ Valid SSE response, proceeding with stream")
                completionHandler(.allow)
            } else {
                // Some backends may not set correct content-type but still stream SSE
                // Log warning but allow - we'll fail on parsing if it's not SSE
                print("SSEClient: ⚠️ Unexpected content-type '\(contentType)', allowing but may fail on parse")
                completionHandler(.allow)
            }
        } else {
            // Server rejected the request - log details and cancel
            print("SSEClient: ❌ Server returned HTTP \(statusCode) - rejecting connection")

            // Common status codes:
            // 401 - Unauthorized (auth token invalid/expired)
            // 403 - Forbidden (token valid but not authorized for this resource)
            // 404 - Not Found (job doesn't exist or expired)
            // 500/502/503 - Server error

            completionHandler(.cancel)
        }
    }

    /// Actor-isolated method to update state from response delegate
    private func handleInitialResponse(statusCode: Int, contentType: String) {
        lastHTTPStatusCode = statusCode
        // Only mark as valid if we got 200-202 with event-stream content type
        if (200...202).contains(statusCode) && contentType.hasPrefix("text/event-stream") {
            hasReceivedValidResponse = true
            print("SSEClient: Connection validated - ready for events")
        } else if (200...202).contains(statusCode) {
            // Allow non-standard content-type but log warning
            hasReceivedValidResponse = true
            print("SSEClient: Connection allowed with non-standard content-type")
        }
        // For non-2xx status, hasReceivedValidResponse remains false
    }

    /// Called when data is received for the data task.
    /// This method is `nonisolated` because `URLSession` calls its delegate on the specified delegate queue,
    /// which is outside the actor's isolation. We immediately hop back to the actor's isolation.
    nonisolated public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task { await self.parse(data: data) }
    }

    /// Called when the data task completes, either successfully or with an error.
    /// This method is `nonisolated`. Hop back to the actor to handle state changes and reconnection logic.
    nonisolated public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { await self.handleConnectionTermination(error: error) }
    }

    /// Optional: Called when the URLSession is about to use the credential.
    /// Useful if authentication challenges are involved, but for simple Bearer token, headers are sufficient.
    nonisolated public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Default handling (usually means not authenticated or invalid cert)
        completionHandler(.performDefaultHandling, nil)
    }
}
