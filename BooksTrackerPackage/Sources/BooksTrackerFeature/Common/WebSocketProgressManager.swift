import Foundation

/// WebSocket-specific errors
enum WebSocketError: Error, LocalizedError {
    case notConnected
    case encodingFailed
    case decodingFailed
    case connectionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "WebSocket not connected"
        case .encodingFailed: return "Failed to encode message"
        case .decodingFailed: return "Failed to decode message"
        case .connectionFailed(let error): return "Connection failed: \(error.localizedDescription)"
        }
    }
}

/// Connection token proving WebSocket is ready for job binding
/// Issued after initial handshake, before jobId configuration
public struct ConnectionToken: Sendable {
    let connectionId: String
    let createdAt: Date

    var isExpired: Bool {
        Date().timeIntervalSince(createdAt) > 30  // 30 second validity window
    }
}

/// Manages WebSocket connections for real-time progress updates
/// Replaces polling-based progress tracking with server push notifications
///
/// CRITICAL: Uses WebSocket-first protocol to prevent race conditions
/// - Step 1: establishConnection() - Connect BEFORE job starts
/// - Step 2: configureForJob(jobId:) - Bind to specific job after connection ready
/// - Result: Server processes ONLY after WebSocket is listening
@MainActor
public final class WebSocketProgressManager: ObservableObject {

    // MARK: - Properties

    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var lastError: Error?

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var progressHandler: ((JobProgress) -> Void)?
    private var disconnectionHandler: ((Error) -> Void)?
    private var boundJobId: String?

    // Backend configuration
    // UNIFIED: All WebSocket progress tracking goes to api-worker (monolith architecture)
    private let baseURL = "wss://api-worker.jukasdrj.workers.dev"
    private let connectionTimeout: TimeInterval = 10.0  // 10 seconds for initial handshake
    private let readySignalEndpoint = "https://api-worker.jukasdrj.workers.dev"

    // MARK: - Public Methods

    public init() {}

    /// STEP 1: Establish WebSocket connection BEFORE job starts
    /// This prevents race condition where server processes before client listens
    ///
    /// - Parameter jobId: Client-generated job identifier for WebSocket binding
    /// - Returns: ConnectionToken proving connection is ready
    /// - Throws: URLError if connection fails or times out
    public func establishConnection(jobId: String) async throws -> ConnectionToken {
        guard webSocketTask == nil else {
            throw URLError(.badURL, userInfo: ["reason": "WebSocket already connected"])
        }

        // Create connection endpoint with client-provided jobId
        guard let url = URL(string: "\(baseURL)/ws/progress?jobId=\(jobId)") else {
            throw URLError(.badURL)
        }

        // Create URLSession with WebSocket configuration
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)

        // Start connection
        task.resume()

        // Wait for successful connection (by sending/receiving ping)
        try await waitForConnection(task, timeout: connectionTimeout)

        self.webSocketTask = task
        self.isConnected = true

        print("🔌 WebSocket established (ready for job configuration)")

        // Start receiving messages in background
        await startReceiving()

        // Return token proving connection is ready
        let token = ConnectionToken(
            connectionId: UUID().uuidString,
            createdAt: Date()
        )

        return token
    }

    /// STEP 2: Configure established WebSocket for specific job
    /// Called after receiving jobId from server
    ///
    /// - Parameter jobId: Job identifier from POST /scan response
    /// - Throws: URLError if jobId is invalid or connection was lost
    public func configureForJob(jobId: String) async throws {
        guard webSocketTask != nil else {
            throw URLError(.badURL, userInfo: ["reason": "WebSocket not connected. Call establishConnection() first"])
        }

        guard !jobId.isEmpty else {
            throw URLError(.badURL, userInfo: ["reason": "Invalid jobId"])
        }

        self.boundJobId = jobId

        print("🔌 WebSocket configured for job: \(jobId)")

        // NOTE: Ready signal is now sent explicitly via sendReadySignal()
        // This gives caller control over when to signal readiness to server
    }

    /// Set progress handler for already-connected WebSocket
    /// Use this after calling establishConnection() + configureForJob()
    ///
    /// - Parameter handler: Callback for progress updates (called on MainActor)
    public func setProgressHandler(_ handler: @escaping (JobProgress) -> Void) {
        self.progressHandler = handler
    }

    /// Set disconnection handler to be notified when WebSocket connection drops
    /// Used to resume continuations when network errors occur
    ///
    /// - Parameter handler: Callback for disconnection events (called on MainActor)
    public func setDisconnectionHandler(_ handler: @escaping (Error) -> Void) {
        self.disconnectionHandler = handler
    }

    /// Connect to WebSocket for a specific job (backward compatible)
    /// This is now equivalent to: establishConnection(jobId) + configureForJob(jobId)
    ///
    /// - Parameters:
    ///   - jobId: Unique job identifier
    ///   - progressHandler: Callback for progress updates (called on MainActor)
    public func connect(
        jobId: String,
        progressHandler: @escaping (JobProgress) -> Void
    ) async {
        do {
            // Use new two-step protocol with client-generated jobId
            _ = try await establishConnection(jobId: jobId)
            try await configureForJob(jobId: jobId)

            // Set progress handler after connection is fully configured
            self.progressHandler = progressHandler
        } catch {
            self.lastError = error
            print("❌ Failed to connect: \(error)")
        }
    }

    /// Disconnect WebSocket
    public func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        isConnected = false
        progressHandler = nil
        disconnectionHandler = nil
        boundJobId = nil

        print("🔌 WebSocket disconnected")
    }

    // MARK: - Private Methods

    /// Wait for WebSocket connection to be established
    /// Uses exponential backoff to verify connection is working
    private func waitForConnection(_ task: URLSessionWebSocketTask, timeout: TimeInterval) async throws {
        let startTime = Date()

        // Try a few ping/pong cycles to confirm connection
        var attempts = 0
        let maxAttempts = 5

        while attempts < maxAttempts {
            if Date().timeIntervalSince(startTime) > timeout {
                throw URLError(.timedOut)
            }

            do {
                // Send ping message to confirm connection is working
                try await task.send(.string("PING"))

                // Wait for any response (with timeout)
                _ = Task {
                    try await task.receive()
                }

                try await Task.sleep(for: .milliseconds(100 * (attempts + 1)))

                attempts += 1
            } catch {
                throw error
            }
        }

        print("✅ WebSocket connection verified after \(attempts) attempts")
    }

    /// Send ready signal to server via WebSocket message
    /// This prevents race condition where server processes before client is listening
    /// Server waits for this signal before starting background processing
    ///
    /// - Throws: WebSocketError if connection not established or encoding fails
    @MainActor
    public func sendReadySignal() async throws {
        guard let webSocketTask = webSocketTask else {
            throw WebSocketError.notConnected
        }

        // Create ready message
        let readyMessage: [String: Any] = [
            "type": "ready",
            "timestamp": Date().timeIntervalSince1970 * 1000 // Unix timestamp in ms
        ]

        guard let messageData = try? JSONSerialization.data(withJSONObject: readyMessage),
              let messageString = String(data: messageData, encoding: .utf8) else {
            throw WebSocketError.encodingFailed
        }

        // Send ready signal to server
        let message = URLSessionWebSocketTask.Message.string(messageString)
        try await webSocketTask.send(message)

        print("✅ Sent ready signal to server")

        // Wait for ready_ack (optional, for confirmation)
        // The server will send { "type": "ready_ack", "timestamp": ... }
    }

    /// Start receiving WebSocket messages
    private func startReceiving() async {
        receiveTask = Task { @MainActor in
            while !Task.isCancelled, let webSocketTask = webSocketTask {
                do {
                    let message = try await webSocketTask.receive()
                    await handleMessage(message)
                } catch {
                    print("⚠️ WebSocket receive error: \(error)")
                    self.lastError = error

                    // Notify continuation before disconnecting
                    disconnectionHandler?(error)

                    self.disconnect()
                    break
                }
            }
        }
    }

    /// Handle incoming WebSocket message
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) async {
        switch message {
        case .string(let text):
            // Skip PING/PONG messages used for connection verification
            if text != "PING" && text != "PONG" {
                await parseProgressUpdate(text)
            }

        case .data(let data):
            if let text = String(data: data, encoding: .utf8),
               text != "PING" && text != "PONG" {
                await parseProgressUpdate(text)
            }

        @unknown default:
            print("⚠️ Unknown WebSocket message type")
        }
    }

    /// Parse JSON progress update
    private func parseProgressUpdate(_ json: String) async {
        guard let data = json.data(using: .utf8) else { return }

        do {
            let decoder = JSONDecoder()
            let message = try decoder.decode(WebSocketMessage.self, from: data)

            // Convert to JobProgress, preserving keepAlive flag and scan result
            let progress = JobProgress(
                totalItems: message.data.totalItems,
                processedItems: message.data.processedItems,
                currentStatus: message.data.currentStatus,
                keepAlive: message.data.keepAlive,  // Pass through keepAlive flag
                scanResult: message.data.result.map { scanData in
                    // Convert ScanResultData to ScanResultPayload
                    ScanResultPayload(
                        totalDetected: scanData.totalDetected,
                        approved: scanData.approved,
                        needsReview: scanData.needsReview,
                        books: scanData.books.map { book in
                            ScanResultPayload.BookPayload(
                                title: book.title,
                                author: book.author,
                                isbn: book.isbn,
                                format: book.format,  // NEW: Format from Gemini
                                confidence: book.confidence,
                                boundingBox: ScanResultPayload.BookPayload.BoundingBoxPayload(
                                    x1: book.boundingBox.x1,
                                    y1: book.boundingBox.y1,
                                    x2: book.boundingBox.x2,
                                    y2: book.boundingBox.y2
                                ),
                                enrichment: book.enrichment.map { enr in
                                    ScanResultPayload.BookPayload.EnrichmentPayload(
                                        status: enr.status,
                                        apiData: enr.apiData.map { api in
                                            ScanResultPayload.BookPayload.EnrichmentPayload.APIDataPayload(
                                                title: api.title,
                                                authors: api.authors,
                                                isbn: api.isbn,
                                                coverUrl: api.coverUrl,
                                                publisher: api.publisher,
                                                publicationYear: api.publicationYear
                                            )
                                        },
                                        provider: enr.provider,
                                        cachedResult: enr.cachedResult
                                    )
                                }
                            )
                        },
                        metadata: ScanResultPayload.ScanMetadataPayload(
                            processingTime: scanData.metadata.processingTime,
                            enrichedCount: scanData.metadata.enrichedCount,
                            timestamp: scanData.metadata.timestamp,
                            modelUsed: scanData.metadata.modelUsed
                        )
                    )
                }
            )

            // Call progress handler on MainActor
            await MainActor.run {
                progressHandler?(progress)
            }

        } catch {
            print("⚠️ Failed to parse progress update: \(error)")
        }
    }
}

// MARK: - Message Models

/// WebSocket message structure (matches backend)
struct WebSocketMessage: Codable, Sendable {
    let type: String
    let jobId: String
    let timestamp: Int64
    let data: ProgressData
}

struct ProgressData: Codable, Sendable {
    let progress: Double
    let processedItems: Int
    let totalItems: Int
    let currentStatus: String
    let currentWorkId: String?
    let error: String?
    let keepAlive: Bool?  // Optional: true for keep-alive pings, nil for normal updates
    let result: ScanResultData?  // Optional: present in final completion message
}

/// Scan result embedded in final WebSocket message
struct ScanResultData: Codable, Sendable {
    let totalDetected: Int
    let approved: Int
    let needsReview: Int
    let books: [BookData]
    let metadata: ScanMetadata

    struct BookData: Codable, Sendable {
        let title: String
        let author: String
        let isbn: String?
        let format: String?  // Format detected by Gemini: "hardcover", "paperback", "mass-market", "unknown"
        let confidence: Double
        let boundingBox: BoundingBox
        let enrichment: Enrichment?

        struct BoundingBox: Codable, Sendable {
            let x1: Double
            let y1: Double
            let x2: Double
            let y2: Double
        }

        struct Enrichment: Codable, Sendable {
            let status: String
            let apiData: APIData?
            let provider: String?
            let cachedResult: Bool?

            struct APIData: Codable, Sendable {
                let title: String?
                let authors: [String]?
                let isbn: String?
                let coverUrl: String?
                let publisher: String?
                let publicationYear: Int?
            }
        }
    }

    struct ScanMetadata: Codable, Sendable {
        let processingTime: Int
        let enrichedCount: Int
        let timestamp: String
        let modelUsed: String
    }
}
