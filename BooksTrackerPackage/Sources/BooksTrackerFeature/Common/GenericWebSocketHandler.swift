import Foundation
import os.log

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
    private let logger = Logger(subsystem: "com.oooefam.booksV3", category: "WebSocket")
    private var webSocket: URLSessionWebSocketTask?
    private let url: URL
    private let pipeline: PipelineType
    private let progressHandler: @MainActor (JobProgressPayload) -> Void
    private let completionHandler: @MainActor (JobCompletePayload) -> Void
    private let errorHandler: @MainActor (ErrorPayload) -> Void
    private var isConnected = false
    private var shouldContinueListening = true

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
    /// Implements automatic retry with exponential backoff for transient failures.
    public func connect() async {
        var attempts = 0
        let maxRetries = 3
        
        while attempts < maxRetries {
            let session = URLSession(configuration: .default)
            webSocket = session.webSocketTask(with: url)
            webSocket?.resume()

            // ✅ CRITICAL: Wait for WebSocket handshake to complete
            // Prevents POSIX error 57 "Socket is not connected" when calling receive()
            if let webSocket = webSocket {
                do {
                    try await WebSocketHelpers.waitForConnection(webSocket, timeout: 10.0)
                    isConnected = true
                    shouldContinueListening = true
                    logger.debug("✅ GenericWebSocketHandler connected (\(self.pipeline.rawValue))")

                    // CRITICAL FIX (Issue #378): Send ready signal to backend
                    // Backend waits for this signal before sending messages to prevent race condition
                    try await sendReadySignal()

                    listenForMessages()
                    return // Success - exit retry loop
                } catch {
                    attempts += 1
                    logger.error("❌ GenericWebSocketHandler connection failed (\(self.pipeline.rawValue)), attempt \(attempts)/\(maxRetries): \(error.localizedDescription)")
                    
                    // Clean up failed connection
                    webSocket.cancel(with: .abnormalClosure, reason: nil)
                    self.webSocket = nil
                    
                    if attempts < maxRetries {
                        // Exponential backoff: 1s, 2s, 4s
                        let delay = pow(2.0, Double(attempts))
                        logger.debug("⏳ Retrying in \(delay) seconds...")
                        try? await Task.sleep(for: .seconds(delay))
                    } else {
                        // Final failure - notify error handler
                        isConnected = false
                        shouldContinueListening = false
                        let errorPayload = ErrorPayload(
                            code: "WEBSOCKET_CONNECTION_FAILED",
                            message: "Failed to connect after \(maxRetries) attempts: \(error.localizedDescription)",
                            details: nil,
                            retryable: true
                        )
                        errorHandler(errorPayload)
                    }
                }
            }
        }
    }

    /// Listens for incoming WebSocket messages recursively.
    private func listenForMessages() {
        // Check if we should stop listening (job completed or error occurred)
        guard shouldContinueListening, isConnected else {
            logger.debug("🛑 Stopped listening for messages (\(self.pipeline.rawValue))")
            return
        }

        webSocket?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                // Double-check we should still be listening
                guard self.shouldContinueListening, self.isConnected else { return }

                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    // Only continue listening if still connected
                    if self.shouldContinueListening && self.isConnected {
                        self.listenForMessages()
                    }
                case .failure(let error):
                    // Check if this is a normal disconnect (Code 57 after job complete)
                    let nsError = error as NSError
                    if nsError.domain == NSPOSIXErrorDomain && nsError.code == 57 {
                        // Socket closed gracefully after job completion - not an error
                        self.logger.debug("✅ WebSocket closed gracefully (\(self.pipeline.rawValue))")
                        return
                    }

                    // Actual error - report it
                    // Stop listening before handling transport error (prevents race condition)
                    shouldContinueListening = false
                    self.logger.error("❌ WebSocket error (\(self.pipeline.rawValue)): \(error.localizedDescription)")
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
                logger.warning("⚠️ Pipeline mismatch: expected \(self.pipeline.rawValue), got \(typedMessage.pipeline.rawValue)")
                return
            }

            switch typedMessage.payload {
            case .jobProgress(let payload):
                progressHandler(payload)
            case .reconnected(let payload):
                progressHandler(payload.toJobProgressPayload())
            case .jobComplete(let payload):
                // CRITICAL: Stop listening BEFORE calling handler and disconnect
                // This prevents "Socket is not connected" error (POSIX 57)
                shouldContinueListening = false
                logger.debug("✅ Job complete, stopping message loop (\(self.pipeline.rawValue))")
                completionHandler(payload)
                disconnect()
            case .error(let payload):
                // Stop listening before handling error
                shouldContinueListening = false
                logger.warning("⚠️ Job error, stopping message loop (\(self.pipeline.rawValue))")
                errorHandler(payload)
                disconnect()
            case .readyAck, .jobStarted, .ping, .pong:
                // These messages are handled at infrastructure level or ignored
                // readyAck: Backend acknowledgment of client ready signal (no action needed)
                // jobStarted: Optional pre-processing notification (no action needed)
                // ping/pong: Keep-alive messages (no action needed)
                break
            }
        } catch {
            logger.error("❌ Failed to decode WebSocket message (\(self.pipeline.rawValue)): \(error.localizedDescription)")
            if let jsonString = String(data: data, encoding: .utf8) {
                logger.debug("Raw JSON: \(jsonString)")
            }

            // Stop listening before handling decoding error
            shouldContinueListening = false
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
    /// - Throws: Error if encoding or sending fails
    private func sendReadySignal() async throws {
        guard let webSocket = webSocket else { return }

        let readyMessage = ["type": "ready"]
        let jsonData = try JSONEncoder().encode(readyMessage)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            struct InvalidStringDataError: Error, LocalizedError {
                var errorDescription: String? = "Failed to convert ready signal JSON data to string."
            }
            throw InvalidStringDataError()
        }

        try await webSocket.send(.string(jsonString))
        logger.debug("📤 Ready signal sent to backend (\(self.pipeline.rawValue))")
    }

    /// Disconnects from the WebSocket.
    public func disconnect() {
        guard isConnected else { return }

        // Stop listening first
        shouldContinueListening = false
        isConnected = false

        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        logger.debug("🔌 GenericWebSocketHandler disconnected (\(self.pipeline.rawValue))")
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