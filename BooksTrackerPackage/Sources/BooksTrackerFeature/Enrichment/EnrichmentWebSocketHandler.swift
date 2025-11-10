import Foundation

/// Handles WebSocket connection for enrichment progress updates
@MainActor
final class EnrichmentWebSocketHandler {
    private var webSocket: URLSessionWebSocketTask?
    private let jobId: String
    private let progressHandler: @MainActor (Int, Int, String) -> Void
    private let completionHandler: @MainActor ([EnrichedBookPayload]) -> Void
    private var isConnected = false

    init(
        jobId: String,
        progressHandler: @escaping @MainActor (Int, Int, String) -> Void,
        completionHandler: @escaping @MainActor ([EnrichedBookPayload]) -> Void
    ) {
        self.jobId = jobId
        self.progressHandler = progressHandler
        self.completionHandler = completionHandler
    }

    /// Connect to WebSocket and start listening for messages.
    func connect() async {
        guard let url = URL(string: "\(EnrichmentConfig.webSocketBaseURL)/ws/progress?jobId=\(jobId)") else { return }
        let session = URLSession(configuration: .default)
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()
        
        // ✅ CRITICAL: Wait for WebSocket handshake to complete
        // Prevents POSIX error 57 "Socket is not connected" when calling receive()
        if let webSocket = webSocket {
            do {
                try await WebSocketHelpers.waitForConnection(webSocket, timeout: 10.0)
                isConnected = true
                listenForMessages()
            } catch {
                #if DEBUG
                print("EnrichmentWebSocket connection failed: \(error)")
                #endif
                isConnected = false
            }
        }
    }

    /// Listen for incoming WebSocket messages.
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
                    print("WebSocket error: \(error)")
                    #endif
                    self.disconnect()
                }
            }
        }
    }

    /// Handle a received WebSocket message.
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        guard let data = message.data else { return }
        let decoder = JSONDecoder()

        guard let progressMessage = try? decoder.decode(EnrichmentProgressMessage.self, from: data) else { return }

        switch progressMessage {
        case .progress(let processedCount, let totalCount, let currentTitle):
            progressHandler(processedCount, totalCount, currentTitle)
        case .complete(let books):
            // Pass enriched books to completion handler
            completionHandler(books)
            disconnect()
        case .unknown:
            break
        }
    }

    /// Disconnect from the WebSocket.
    func disconnect() {
        guard isConnected else { return }
        isConnected = false
        webSocket?.cancel(with: .goingAway, reason: nil)
    }
}

private extension URLSessionWebSocketTask.Message {
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
