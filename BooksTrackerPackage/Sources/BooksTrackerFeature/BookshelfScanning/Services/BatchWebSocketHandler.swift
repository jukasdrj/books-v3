import Foundation

#if os(iOS)

/// Handles WebSocket connection for batch scan progress updates
/// Actor-isolated for thread-safe WebSocket operations
actor BatchWebSocketHandler {
    private var webSocket: URLSessionWebSocketTask?
    private let jobId: String
    private let onProgress: @MainActor (BatchProgress) -> Void
    private var isConnected = false

    init(jobId: String, onProgress: @MainActor @escaping (BatchProgress) -> Void) {
        self.jobId = jobId
        self.onProgress = onProgress
    }

    /// Connect to WebSocket and start listening
    func connect() async throws {
        let wsURL = EnrichmentConfig.webSocketURL(jobId: jobId)

        let session = URLSession(configuration: .default)
        webSocket = session.webSocketTask(with: wsURL)
        webSocket?.resume()
        
        // ✅ CRITICAL: Wait for WebSocket handshake to complete
        // Prevents POSIX error 57 "Socket is not connected" when calling receive()
        if let webSocket = webSocket {
            try await WebSocketHelpers.waitForConnection(webSocket, timeout: 10.0)
        }
        
        isConnected = true

        print("[BatchWebSocket] Connected for job \(jobId)")

        // Start listening for messages
        await listenForMessages()
    }

    /// Listen for incoming WebSocket messages
    private func listenForMessages() async {
        guard let webSocket else { return }

        do {
            while isConnected {
                let message = try await webSocket.receive()

                switch message {
                case .string(let text):
                    await handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await handleMessage(text)
                    }
                @unknown default:
                    break
                }
            }
        } catch {
            print("[BatchWebSocket] Error: \(error)")
            isConnected = false
        }
    }

    /// Parse and handle incoming message
    private func handleMessage(_ text: String) async {
        guard let data = text.data(using: .utf8) else { return }

        let decoder = JSONDecoder()

        // Try to decode as generic message to determine type
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = json["type"] as? String {

            switch type {
            case "batch-init":
                if let initMsg = try? decoder.decode(BatchWebSocketMessage.BatchInitMessage.self, from: data) {
                    await processInit(initMsg)
                }

            case "batch-progress":
                if let progressMsg = try? decoder.decode(BatchWebSocketMessage.BatchProgressMessage.self, from: data) {
                    await processProgressUpdate(progressMsg)
                }

            case "batch-complete":
                if let completeMsg = try? decoder.decode(BatchWebSocketMessage.BatchCompleteMessage.self, from: data) {
                    await processCompletion(completeMsg)
                }

            default:
                print("[BatchWebSocket] Unknown message type: \(type)")
            }
        }
    }

    /// Handle batch initialization message
    private func processInit(_ message: BatchWebSocketMessage.BatchInitMessage) async {
        print("[BatchWebSocket] Batch initialized: \(message.totalPhotos) photos")
    }

    /// Update batch progress on main thread
    private func processProgressUpdate(_ message: BatchWebSocketMessage.BatchProgressMessage) async {
        // Extract values before crossing actor boundary
        let currentPhoto = message.currentPhoto
        let totalPhotos = message.totalPhotos
        let totalBooksFound = message.totalBooksFound

        await MainActor.run {
            print("[BatchWebSocket] Progress: Photo \(currentPhoto + 1)/\(totalPhotos) - \(totalBooksFound) books")
            // The callback will update the BatchProgress object
            // UI observes the BatchProgress via @Observable
        }
    }

    /// Handle batch completion
    private func processCompletion(_ message: BatchWebSocketMessage.BatchCompleteMessage) async {
        // Extract values before crossing actor boundary
        let totalBooks = message.totalBooks

        await MainActor.run {
            print("[BatchWebSocket] Batch complete: \(totalBooks) books found")
        }

        disconnect()
    }

    /// Close WebSocket connection
    func disconnect() {
        guard isConnected else { return }

        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        isConnected = false

        print("[BatchWebSocket] Disconnected for job \(jobId)")
    }
}

#endif // os(iOS)
