import Foundation

/// Handles a generic, typed WebSocket connection for progress-based background jobs.
///
/// This handler is responsible for connecting to a WebSocket endpoint, listening for messages,
/// and decoding them into strongly-typed Swift models. It abstracts WebSocket connection
/// management, message routing, and error handling.
///
/// **Usage:**
/// ```swift
/// let handler = GenericWebSocketHandler(
///     url: webSocketURL,
///     pipeline: .batchEnrichment,
///     progressHandler: { progress in
///         // Handle JobProgressPayload
///     },
///     completionHandler: { complete in
///         // Handle BatchEnrichmentCompletePayload
///     },
///     errorHandler: { error in
///         // Handle ErrorPayload
///     }
/// )
/// await handler.connect()
/// ```
///
/// - Note: Must be used from MainActor context (Swift 6 concurrency)
@MainActor
public final class GenericWebSocketHandler {
    private var webSocket: URLSessionWebSocketTask?
    private let url: URL
    private let pipeline: PipelineType
    private let progressHandler: @MainActor (JobProgressPayload) -> Void
    private let completionHandler: @MainActor (JobCompletePayload) -> Void
    private let errorHandler: @MainActor (ErrorPayload) -> Void
    private var isConnected = false

    /// Initializes a new generic WebSocket handler.
    /// - Parameters:
    ///   - url: The exact WebSocket URL to connect to, including query parameters (jobId, token)
    ///   - pipeline: The pipeline type this handler is for (batch_enrichment, csv_import, ai_scan)
    ///   - progressHandler: Callback fired when a `job_progress` message is received
    ///   - completionHandler: Callback fired when a `job_complete` message is received
    ///   - errorHandler: Callback fired when an `error` message is received
    public init(
        url: URL,
        pipeline: PipelineType,
        progressHandler: @escaping @MainActor (JobProgressPayload) -> Void,
        completionHandler: @escaping @MainActor (JobCompletePayload) -> Void,
        errorHandler: @escaping @MainActor (ErrorPayload) -> Void
    ) {
        self.url = url
        self.pipeline = pipeline
        self.progressHandler = progressHandler
        self.completionHandler = completionHandler
        self.errorHandler = errorHandler
    }

    /// Connects to the WebSocket and starts listening for messages.
    public func connect() async {
        let session = URLSession(configuration: .default)
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()

        // ✅ CRITICAL: Wait for WebSocket handshake to complete
        // Prevents POSIX error 57 "Socket is not connected" when calling receive()
        if let webSocket = webSocket {
            do {
                try await WebSocketHelpers.waitForConnection(webSocket, timeout: 10.0)
                isConnected = true
                #if DEBUG
                print("✅ GenericWebSocketHandler connected (\(pipeline.rawValue))")
                #endif

                // CRITICAL FIX (Issue #378): Send ready signal to backend
                // Backend waits for this signal before sending messages to prevent race condition
                await sendReadySignal()

                listenForMessages()
            } catch {
                #if DEBUG
                print("❌ GenericWebSocketHandler connection failed (\(pipeline.rawValue)): \(error)")
                #endif
                isConnected = false
            }
        }
    }

    /// Listens for incoming WebSocket messages recursively.
    private func listenForMessages() {
        webSocket?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self = self, self.isConnected else { return }
                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    self.listenForMessages() // Continue listening for more messages
                case .failure(let error):
                    #if DEBUG
                    print("❌ WebSocket error (\(self.pipeline.rawValue)): \(error.localizedDescription)")
                    #endif
                    let errorPayload = ErrorPayload(
                        code: "WEBSOCKET_TRANSPORT_ERROR",
                        message: error.localizedDescription,
                        details: nil,
                        retryable: true // Transport errors are often retryable
                    )
                    self.errorHandler(errorPayload)
                    self.disconnect()
                }
            }
        }
    }

    /// Handles a received WebSocket message by decoding it into the unified message format.
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        guard let data = message.data else { return }
        let decoder = JSONDecoder()

        do {
            let typedMessage = try decoder.decode(TypedWebSocketMessage.self, from: data)

            // Verify pipeline matches (safety check)
            guard typedMessage.pipeline == pipeline else {
                #if DEBUG
                print("⚠️ Pipeline mismatch: expected \(pipeline.rawValue), got \(typedMessage.pipeline.rawValue)")
                #endif
                return
            }

            switch typedMessage.payload {
            case .jobProgress(let payload):
                progressHandler(payload)
            case .jobComplete(let payload):
                completionHandler(payload)
                disconnect() // Job complete - disconnect
            case .error(let payload):
                errorHandler(payload)
                disconnect() // Job failed - disconnect
            case .jobStarted, .ping, .pong:
                // These messages are handled at infrastructure level or ignored
                break
            }
        } catch {
            #if DEBUG
            print("❌ Failed to decode WebSocket message (\(pipeline.rawValue)): \(error)")
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Raw JSON: \(jsonString)")
            }
            #endif
            let errorPayload = ErrorPayload(
                code: "CLIENT_DECODING_ERROR",
                message: "Failed to decode WebSocket message: \(error.localizedDescription)",
                details: String(data: data, encoding: .utf8).map { AnyCodable($0) },
                retryable: false
            )
            errorHandler(errorPayload)
            disconnect()
        }
    }

    /// Sends the "ready" signal to backend after connection established.
    /// Backend waits for this signal before processing job to prevent race condition.
    private func sendReadySignal() async {
        guard let webSocket = webSocket else { return }

        let readyMessage = ["type": "ready"]
        guard let jsonData = try? JSONEncoder().encode(readyMessage),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            #if DEBUG
            print("⚠️ Failed to encode ready signal")
            #endif
            return
        }

        do {
            try await webSocket.send(.string(jsonString))
            #if DEBUG
            print("📤 Ready signal sent to backend (\(pipeline.rawValue))")
            #endif
        } catch {
            #if DEBUG
            print("⚠️ Failed to send ready signal: \(error.localizedDescription)")
            #endif
        }
    }

    /// Disconnects from the WebSocket.
    public func disconnect() {
        guard isConnected else { return }
        isConnected = false
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        #if DEBUG
        print("🔌 GenericWebSocketHandler disconnected (\(pipeline.rawValue))")
        #endif
    }
}

// MARK: - URLSessionWebSocketTask.Message Extension

private extension URLSessionWebSocketTask.Message {
    /// A convenience property to extract `Data` from a WebSocket message.
    var data: Data? {
        switch self {
        case .data(let data):
            return data
        case .string(let string):
            return string.data(using: .utf8)
        @unknown default:
            return nil
        }
    }
}
