import Foundation

/// Generic SSE response handler for any SSE endpoint
/// Provides AsyncThrowingStream of SSEEvent for consumers to decode
///
/// Features:
/// - URLSessionDataDelegate for incremental data processing
/// - Line-by-line SSE parsing (handles multi-line data fields)
/// - Last-Event-ID support for stream resumption
/// - Exponential backoff reconnection
/// - Content-Type validation
/// - Thread-safe state management via serial queue
public final class SSEResponseHandler: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let url: URL
    private let session: URLSession
    private var dataTask: URLSessionDataTask?
    private var continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation?

    private var currentBuffer = ""
    private var lastEventID: String?
    private var retryInterval: TimeInterval = 3.0 // Default retry interval

    // For exponential backoff reconnection
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private let baseReconnectDelay: TimeInterval = 1.0 // 1 second base delay

    /// Serial queue for thread-safe access to mutable state
    /// All access to currentBuffer, continuation, reconnectAttempts, etc. must go through this queue
    private let stateQueue = DispatchQueue(label: "net.bookstrack.sse-state-queue")

    public init(url: URL, lastEventID: String? = nil) {
        self.url = url
        self.lastEventID = lastEventID
        // A dedicated operation queue ensures delegate callbacks are not on the main thread
        let delegateQueue = OperationQueue()
        delegateQueue.name = "net.bookstrack.sse-delegate-queue"
        self.session = URLSession(configuration: .default, delegate: nil, delegateQueue: delegateQueue)
        super.init()
    }

    deinit {
        // Invalidate the session to clean up resources, especially the delegate reference
        session.invalidateAndCancel()
    }

    public func start() -> AsyncThrowingStream<SSEEvent, Error> {
        return AsyncThrowingStream { [weak self] continuation in
            guard let self = self else {
                continuation.finish(throwing: SSEError.streamCancelled)
                return
            }
            self.stateQueue.sync {
                self.continuation = continuation
            }
            self.connect()

            // Handle cancellation
            continuation.onTermination = { @Sendable [weak self] _ in
                self?.cancel()
            }
        }
    }

    private func connect() {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData // Always get fresh data

        let eventID = stateQueue.sync { lastEventID }
        if let eventID = eventID {
            request.setValue(eventID, forHTTPHeaderField: "Last-Event-ID")
        }

        stateQueue.sync {
            dataTask?.cancel() // Cancel any previous task before starting a new one
            dataTask = session.dataTask(with: request)
            dataTask?.resume()
        }
    }

    public func cancel() {
        stateQueue.sync {
            dataTask?.cancel()
            dataTask = nil
            continuation?.finish() // Explicitly finish the stream
            continuation = nil
        }
    }

    // MARK: - URLSessionDataDelegate

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let httpResponse = response as? HTTPURLResponse else {
            stateQueue.sync { continuation?.finish(throwing: SSEError.connectionFailed("Invalid response type")) }
            completionHandler(.cancel)
            return
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            stateQueue.sync { continuation?.finish(throwing: SSEError.httpError(statusCode: httpResponse.statusCode)) }
            completionHandler(.cancel)
            return
        }

        guard let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
              contentType.lowercased().hasPrefix("text/event-stream") else {
            stateQueue.sync { continuation?.finish(throwing: SSEError.invalidContentType) }
            completionHandler(.cancel)
            return
        }

        stateQueue.sync { reconnectAttempts = 0 } // Reset reconnect attempts on successful connection
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        stateQueue.sync {
            currentBuffer.append(chunk)
        }
        processBuffer()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error as NSError?, error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled {
            // Task was cancelled, either by us or the system. No need to reconnect.
            stateQueue.sync { continuation?.finish() }
            return
        }

        let (currentReconnectAttempts, maxAttempts) = stateQueue.sync { (reconnectAttempts, maxReconnectAttempts) }

        if let error = error {
            stateQueue.sync { continuation?.finish(throwing: SSEError.connectionFailed(error.localizedDescription)) }
        } else {
            // Stream completed normally (server closed connection without error),
            // if host exists, it implies an unexpected close which might warrant reconnect.
            // If the server explicitly completes the stream without error, we finish.
            // Standard SSE behavior means client should reconnect unless `retry: 0` is sent.
            // For now, if no error and URL is present, attempt reconnect.
            if url.host != nil && currentReconnectAttempts < maxAttempts { // Reconnect if server closes without explicit completion
                attemptReconnect()
                return
            }
            stateQueue.sync { continuation?.finish() }
        }

        if currentReconnectAttempts >= maxAttempts {
            stateQueue.sync { continuation?.finish(throwing: SSEError.connectionFailed("Max reconnection attempts reached")) }
        }
    }

    private func attemptReconnect() {
        let (currentAttempts, maxAttempts, delay) = stateQueue.sync { () -> (Int, Int, TimeInterval) in
            let current = reconnectAttempts
            let delay = baseReconnectDelay * pow(2.0, Double(current))
            reconnectAttempts += 1
            return (current, maxReconnectAttempts, delay)
        }

        guard currentAttempts < maxAttempts else {
            stateQueue.sync { continuation?.finish(throwing: SSEError.connectionFailed("Max reconnection attempts reached")) }
            return
        }

        Task {
            try? await Task.sleep(for: .seconds(delay))
            self.connect()
        }
    }

    // MARK: - SSE Parsing Logic

    private var eventLineBuffer = [String: String]() // To build up event fields for the current event

    private func processBuffer() {
        stateQueue.sync {
            let lines = currentBuffer.components(separatedBy: .newlines)
            currentBuffer = lines.last ?? "" // Keep the last partial line

            for i in 0..<lines.count - 1 { // Process all but the last (potentially partial) line
                let line = lines[i]
                if line.isEmpty { // An empty line signifies the end of an event
                    if let event = parseEventFromLineBuffer() {
                        continuation?.yield(event)
                        lastEventID = event.id ?? lastEventID // Update last event ID
                        retryInterval = event.retry ?? retryInterval // Update retry interval if provided
                    }
                    clearLineBuffer()
                } else if line.starts(with: ":") {
                    // Ignore comment lines
                    continue
                } else {
                    appendLineToBuffer(line)
                }
            }
        }
    }

    /// Must be called from within stateQueue.sync
    private func appendLineToBuffer(_ line: String) {
        if let colonIndex = line.firstIndex(of: ":") {
            let field = String(line[..<colonIndex])
            var value = String(line[line.index(after: colonIndex)...])
            if value.starts(with: " ") { // Strip leading space if present
                value.removeFirst()
            }
            // For "data" fields, append if already present, otherwise set.
            // For other fields, overwrite.
            if field == "data", var existingData = eventLineBuffer[field] {
                existingData.append("\n\(value)")
                eventLineBuffer[field] = existingData
            } else {
                eventLineBuffer[field] = value
            }
        } else {
            // Line contains no colon, treat as data line.
            if var existingData = eventLineBuffer["data"] {
                existingData.append("\n\(line)")
                eventLineBuffer["data"] = existingData
            } else {
                eventLineBuffer["data"] = line
            }
        }
    }

    /// Must be called from within stateQueue.sync
    private func parseEventFromLineBuffer() -> SSEEvent? {
        guard !eventLineBuffer.isEmpty else { return nil }

        let id = eventLineBuffer["id"]
        let event = eventLineBuffer["event"]
        let data = eventLineBuffer["data"]
        let retry: TimeInterval? = eventLineBuffer["retry"].flatMap(Double.init)

        return SSEEvent(id: id, event: event, data: data, retry: retry)
    }

    /// Must be called from within stateQueue.sync
    private func clearLineBuffer() {
        eventLineBuffer.removeAll()
    }
}
