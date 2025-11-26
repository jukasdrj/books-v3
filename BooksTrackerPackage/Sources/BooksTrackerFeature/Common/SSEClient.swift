import Foundation

/// Represents a single event from a Server-Sent Events stream.
public struct SSEEvent: Sendable, Equatable {
    public var id: String?
    public var event: String?
    public var data: String?
    public var retry: Int?
}

/// An actor that connects to a Server-Sent Events (SSE) stream and provides an `AsyncThrowingStream` of events.
@available(iOS 15.0, *)
public actor SSEClient {
    private var urlRequest: URLRequest
    private var lastEventID: String?
    private var urlSession: URLSession?
    private var sessionDelegate: SSEUrlSessionDelegate?

    /// Initializes a new SSE client.
    /// - Parameters:
    ///   - urlRequest: The URL request to connect to the SSE stream. Must have `Accept: text/event-stream` header.
    ///   - lastEventID: The ID of the last event received, for reconnection.
    public init(urlRequest: URLRequest, lastEventID: String? = nil) {
        var request = urlRequest
        if request.value(forHTTPHeaderField: "Accept") == nil {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        self.urlRequest = request
        self.lastEventID = lastEventID
    }

    /// Connects to the SSE stream and returns an async stream of events.
    public func connect() -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let delegate = SSEUrlSessionDelegate(continuation: continuation)
            self.sessionDelegate = delegate

            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            self.urlSession = session

            if let lastEventID = self.lastEventID {
                self.urlRequest.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID")
            }

            let task = session.dataTask(with: self.urlRequest)
            task.resume()

            continuation.onTermination = { @Sendable _ in
                task.cancel()
                session.invalidateAndCancel()
            }
        }
    }

    /// Disconnects the client from the SSE stream.
    public func disconnect() {
        urlSession?.invalidateAndCancel()
        urlSession = nil
        sessionDelegate = nil
    }
}

/// A URLSession delegate that handles the SSE stream and parses events.
private class SSEUrlSessionDelegate: NSObject, URLSessionDataDelegate {
    private let continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation
    private var receivedData = Data()
    private var currentEvent = SSEEvent()

    init(continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation) {
        self.continuation = continuation
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            completionHandler(.cancel)
            continuation.finish(throwing: GeminiCSVImportError.invalidResponse)
            return
        }
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        receivedData.append(data)
        // Process lines as they are received
        while let lineRange = receivedData.range(of: Data("\n".utf8)) {
            var lineData = receivedData.subdata(in: 0..<lineRange.lowerBound)
            receivedData.removeSubrange(0..<lineRange.upperBound)

            // Handle \r\n line endings
            if !lineData.isEmpty && lineData.last == 13 { // 13 is the ASCII value for carriage return
                lineData.removeLast()
            }

            if let line = String(data: lineData, encoding: .utf8) {
                parseAndYield(line: line)
            }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            continuation.finish(throwing: error)
        } else {
            // If there's remaining data, process it
            if !receivedData.isEmpty, let line = String(data: receivedData, encoding: .utf8) {
                parseAndYield(line: line)
            }
            continuation.finish()
        }
    }

    private func parseAndYield(line: String) {
        if line.isEmpty {
            // An empty line dispatches the event
            if currentEvent.data != nil || currentEvent.event != nil || currentEvent.id != nil {
                 continuation.yield(currentEvent)
            }
            currentEvent = SSEEvent()
            return
        }

        let components = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let field = components.first else { return }
        let value = components.count > 1 ? components[1] : ""

        switch field {
        case "event":
            currentEvent.event = value
        case "data":
            if currentEvent.data == nil {
                currentEvent.data = value
            } else {
                currentEvent.data?.append("\n" + value)
            }
        case "id":
            currentEvent.id = value
        case "retry":
            if let retryInt = Int(value) {
                 currentEvent.retry = retryInt
            }
        default:
            // Ignore comments and other fields
            break
        }
    }
}
