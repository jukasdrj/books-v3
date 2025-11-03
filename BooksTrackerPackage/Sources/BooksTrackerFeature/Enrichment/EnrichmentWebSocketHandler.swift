import Foundation

/// Handles WebSocket connection for enrichment progress updates
@MainActor
final class EnrichmentWebSocketHandler {
    private var webSocket: URLSessionWebSocketTask?
    private let jobId: String
    private let progressHandler: @MainActor (Int, Int, String) -> Void
    private var isConnected = false

    init(jobId: String, progressHandler: @escaping @MainActor (Int, Int, String) -> Void) {
        self.jobId = jobId
        self.progressHandler = progressHandler
    }

    /// Connect to WebSocket and start listening for messages.
    func connect() {
        guard let url = URL(string: "\(EnrichmentConfig.webSocketBaseURL)/ws/progress?jobId=\(jobId)") else { return }
        let session = URLSession(configuration: .default)
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()
        isConnected = true
        listenForMessages()
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
                    print("WebSocket error: \(error)")
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
        case .complete:
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
