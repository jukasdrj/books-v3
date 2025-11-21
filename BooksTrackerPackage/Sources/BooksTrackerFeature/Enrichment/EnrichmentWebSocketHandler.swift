import Foundation

/// Handles WebSocket connection for enrichment progress updates
/// Migrated to unified WebSocket schema (TypedWebSocketMessage v1.0.0)
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

    /// Handle a received WebSocket message using unified schema
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        guard let data = message.data else { return }
        let decoder = JSONDecoder()

        // Decode unified TypedWebSocketMessage
        guard let typedMessage = try? decoder.decode(TypedWebSocketMessage.self, from: data) else {
            #if DEBUG
            print("Failed to decode TypedWebSocketMessage")
            #endif
            return
        }

        // Only handle batch_enrichment pipeline messages
        guard typedMessage.pipeline == .batchEnrichment else {
            #if DEBUG
            print("Ignoring non-batch-enrichment message: \(typedMessage.pipeline)")
            #endif
            return
        }

        switch typedMessage.payload {
        case .jobProgress(let progress):
            // Extract progress data
            let processedCount = progress.processedCount ?? 0
            let totalCount = Int(progress.progress * 100) // Approximate if needed
            let currentTitle = progress.currentItem ?? progress.status
            progressHandler(processedCount, totalCount, currentTitle)

        case .jobComplete(let complete):
            // v2.0 Migration: Fetch full enriched books via HTTP
            // WebSocket now only sends lightweight summary
            if case .batchEnrichment(let batchPayload) = complete {
                // Fetch full results from KV cache
                if let resourceId = batchPayload.summary.resourceId {
                    let jobId = resourceId.replacingOccurrences(of: "job-results:", with: "")

                    Task { @MainActor in
                        do {
                            // Fetch full enriched books via HTTP
                            let results = try await self.fetchEnrichmentResults(jobId: jobId)
                            self.completionHandler(results)
                        } catch {
                            #if DEBUG
                            print("❌ Failed to fetch enrichment results: \(error)")
                            #endif
                            // Call completion with empty array on error
                            self.completionHandler([])
                        }
                        self.disconnect()
                    }
                } else {
                    #if DEBUG
                    print("⚠️ No resourceId in completion payload - calling handler with empty results")
                    #endif
                    completionHandler([])
                    disconnect()
                }
            }

        case .error(let error):
            #if DEBUG
            print("WebSocket enrichment error: \(error.message)")
            #endif
            disconnect()

        default:
            // Ignore other message types (jobStarted, ping, pong)
            break
        }
    }

    /// Fetch full enrichment results from KV cache via HTTP GET
    /// v2.0 Migration: WebSocket sends lightweight summary, full results fetched on demand
    /// Results are cached for 24 hours after job completion
    private func fetchEnrichmentResults(jobId: String) async throws -> [EnrichedBookPayload] {
        let url = URL(string: "\(EnrichmentConfig.apiBaseURL)/v1/jobs/\(jobId)/results")!

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EnrichmentError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            // Decode ResponseEnvelope containing enriched books
            struct EnrichmentJobResults: Codable {
                let enrichedBooks: [EnrichedBookPayload]?
            }

            let envelope = try JSONDecoder().decode(ResponseEnvelope<EnrichmentJobResults>.self, from: data)

            guard let results = envelope.data, let books = results.enrichedBooks else {
                if let error = envelope.error {
                    throw EnrichmentError.apiError(error.message)
                }
                throw EnrichmentError.apiError("No enriched books in response")
            }

            return books

        case 404:
            // Results expired (> 24 hours old)
            throw EnrichmentError.apiError("Results expired (job older than 24 hours). Please re-run enrichment.")

        case 429:
            // Rate limited
            throw EnrichmentError.apiError("Rate limited. Please try again later.")

        default:
            throw EnrichmentError.httpError(httpResponse.statusCode)
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
