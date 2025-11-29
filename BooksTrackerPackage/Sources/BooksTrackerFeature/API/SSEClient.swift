import Foundation

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

    // Parsing state
    private var buffer = ""
    private var currentEventName: String?
    private var currentEventData: [String] = []

    /// Initializes the SSEClient.
    /// - Parameters:
    ///   - url: The URL of the SSE endpoint.
    ///   - authToken: The Bearer token for authentication.
    public init(url: URL, authToken: String) {
        self.url = url
        self.authToken = authToken
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
            Task { await self.startConnectionAttempt() }
        }
    }

    /// Initiates or reinitiates the connection to the SSE endpoint.
    private func startConnectionAttempt() {
        guard !isCurrentlyConnected else { return } // Prevent multiple simultaneous connections
        isCurrentlyConnected = true

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
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        dataTask = urlSession?.dataTask(with: request)
    }

    /// Disconnects the SSE client and cleans up resources.
    public func disconnect() {
        print("SSEClient: Disconnecting from \(url)")
        dataTask?.cancel()
        dataTask = nil
        urlSession?.invalidateAndCancel() // Invalidate and release session resources
        urlSession = nil
        isCurrentlyConnected = false
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
                await self.startConnectionAttempt()
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
        let errorMessage = error?.localizedDescription ?? "Unknown error"
        print("SSEClient: Connection to \(url) terminated with error: \(errorMessage)")

        // Yield a failed event to the stream consumer.
        // It's important to keep the stream alive for retries,
        // so we don't call `finish()` here unless it's a permanent disconnect.
        if let error = error {
            currentContinuation?.yield(.failed(EnrichmentFailed(
                isbn: "unknown",
                status: "connection_failed",
                error: errorMessage
            )))
        }

        isCurrentlyConnected = false // Mark as disconnected
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
        let lineSeparatorRegex = try! NSRegularExpression(pattern: "\\r?\\n", options: [])
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
        let remainingRange = NSRange(location: lastRange.upperBound, length: buffer.utf8.count - lastRange.upperBound)
        if let range = Range(remainingRange, in: buffer), !range.isEmpty {
            buffer = String(buffer[range])
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
            case "enrichment.progress":
                let progress = try decoder.decode(EnrichmentProgress.self, from: jsonData)
                currentContinuation?.yield(.progress(progress))
            case "enrichment.completed":
                let completed = try decoder.decode(EnrichmentCompleted.self, from: jsonData)
                currentContinuation?.yield(.completed(completed))
                // For completion events, we assume the stream should end.
                // Disconnect to clean up resources and terminate the AsyncStream.
                Task { await disconnect() }
            case "enrichment.failed":
                let failed = try decoder.decode(EnrichmentFailed.self, from: jsonData)
                currentContinuation?.yield(.failed(failed))
                // For failed events, we assume the stream should end.
                Task { await disconnect() }
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
