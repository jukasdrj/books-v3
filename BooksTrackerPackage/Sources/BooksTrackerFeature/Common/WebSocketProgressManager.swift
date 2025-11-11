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

/// Reconnection configuration with exponential backoff
public struct ReconnectionConfig: Sendable {
    let maxRetries: Int
    let initialDelay: TimeInterval       // Initial delay (1s)
    let maxDelay: TimeInterval          // Maximum delay (30s)
    let backoffMultiplier: Double       // Exponential multiplier (2.0)

    public static let `default` = ReconnectionConfig(
        maxRetries: 5,
        initialDelay: 1.0,
        maxDelay: 30.0,
        backoffMultiplier: 2.0
    )

    /// Calculate delay for a given attempt using exponential backoff
    func delay(for attempt: Int) -> TimeInterval {
        let exponentialDelay = initialDelay * pow(backoffMultiplier, Double(attempt))
        return min(exponentialDelay, maxDelay)
    }
}

/// Job state from Durable Object storage
/// Used for state sync after reconnection
struct JobState: Codable, Sendable {
    let pipeline: String
    let totalCount: Int
    let processedCount: Int
    let status: String          // "running", "complete", "failed"
    let startTime: Int64        // Milliseconds since epoch
    let version: Int
    let endTime: Int64?         // Optional: present when complete/failed
}

/// Manages WebSocket connections for real-time progress updates
/// Replaces polling-based progress tracking with server push notifications
///
/// CRITICAL: Uses WebSocket-first protocol to prevent race conditions
/// - Step 1: establishConnection() - Connect BEFORE job starts
/// - Step 2: configureForJob(jobId:) - Bind to specific job after connection ready
/// - Result: Server processes ONLY after WebSocket is listening
@MainActor
@Observable
public final class WebSocketProgressManager {

    // MARK: - Properties

    public private(set) var isConnected: Bool = false
    public private(set) var lastError: Error?

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var progressHandler: ((JobProgress) -> Void)?
    private var disconnectionHandler: ((Error) -> Void)?
    private var boundJobId: String?
    // NOTE: authToken now stored securely in Keychain (see KeychainHelper)

    // Reconnection state
    private var reconnectionConfig: ReconnectionConfig = .default
    private var reconnectionAttempt: Int = 0
    private var isReconnecting: Bool = false
    private var reconnectionTask: Task<Void, Never>?

    // Backend configuration
    // UNIFIED: All WebSocket progress tracking goes to api-worker (monolith architecture)
    private let connectionTimeout: TimeInterval = 10.0  // 10 seconds for initial handshake

    // MARK: - Public Methods

    public init() {}

    /// STEP 1: Establish WebSocket connection BEFORE job starts
    /// This prevents race condition where server processes before client listens
    ///
    /// - Parameters:
    ///   - jobId: Client-generated job identifier for WebSocket binding
    ///   - token: Optional authentication token for WebSocket connection
    /// - Returns: ConnectionToken proving connection is ready
    /// - Throws: URLError if connection fails or times out
    public func establishConnection(jobId: String, token: String? = nil) async throws -> ConnectionToken {
        guard webSocketTask == nil else {
            throw URLError(.badURL, userInfo: ["reason": "WebSocket already connected"])
        }

        // Store auth token securely in Keychain for reconnection
        if let token = token {
            try KeychainHelper.saveToken(token, for: jobId)
        }

        // Create connection endpoint with client-provided jobId and optional token
        let url: URL
        if let token = token {
            var components = URLComponents(string: "\(EnrichmentConfig.webSocketBaseURL)/ws/progress")!
            components.queryItems = [
                URLQueryItem(name: "jobId", value: jobId),
                URLQueryItem(name: "token", value: token)
            ]
            guard let urlWithToken = components.url else {
                throw URLError(.badURL, userInfo: ["reason": "Failed to construct WebSocket URL with token"])
            }
            url = urlWithToken
        } else {
            url = EnrichmentConfig.webSocketURL(jobId: jobId)
        }

        // Create URLSession with WebSocket configuration
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)

        // Start connection
        task.resume()

        // Wait for successful connection (by sending/receiving ping)
        try await WebSocketHelpers.waitForConnection(task, timeout: connectionTimeout)

        self.webSocketTask = task
        self.isConnected = true
        self.reconnectionAttempt = 0  // Reset reconnection counter on successful connection

        #if DEBUG
        print("🔌 WebSocket established (ready for job configuration)")
        #endif

        // Start receiving messages in background
        await startReceiving()

        // Return token proving connection is ready
        let connectionToken = ConnectionToken(
            connectionId: UUID().uuidString,
            createdAt: Date()
        )

        return connectionToken
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

        #if DEBUG
        print("🔌 WebSocket configured for job: \(jobId)")
        #endif

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
            #if DEBUG
            print("❌ Failed to connect: \(error)")
            #endif
        }
    }

    /// Attempt to reconnect with exponential backoff
    /// Called automatically when connection drops unexpectedly
    private func attemptReconnection() async {
        guard !isReconnecting else {
            #if DEBUG
            print("⚠️ Reconnection already in progress")
            #endif
            return
        }

        guard let jobId = boundJobId else {
            #if DEBUG
            print("❌ Cannot reconnect: missing jobId")
            #endif
            return
        }

        // Retrieve token from Keychain
        let token: String?
        do {
            token = try KeychainHelper.getToken(for: jobId)
        } catch {
            #if DEBUG
            print("❌ Cannot reconnect: failed to retrieve token from Keychain: \(error)")
            #endif
            return
        }

        guard token != nil else {
            #if DEBUG
            print("❌ Cannot reconnect: no token found in Keychain")
            #endif
            return
        }

        isReconnecting = true

        while reconnectionAttempt < reconnectionConfig.maxRetries {
            let delay = reconnectionConfig.delay(for: reconnectionAttempt)
            reconnectionAttempt += 1

            #if DEBUG
            print("🔄 Reconnection attempt \(reconnectionAttempt)/\(reconnectionConfig.maxRetries) after \(delay)s")
            #endif

            // Wait with exponential backoff
            try? await Task.sleep(for: .seconds(delay))

            // Check if we've been cancelled
            guard !Task.isCancelled else {
                #if DEBUG
                print("⚠️ Reconnection cancelled")
                #endif
                break
            }

            // Attempt reconnection
            do {
                // Clean up old connection
                webSocketTask?.cancel(with: .goingAway, reason: nil)
                webSocketTask = nil
                receiveTask?.cancel()
                receiveTask = nil

                // Try to reconnect (token already in Keychain)
                _ = try await establishConnection(jobId: jobId, token: token!)

                // If successful, sync state from server
                await syncStateAfterReconnection()

                #if DEBUG
                print("✅ Reconnection successful after \(reconnectionAttempt) attempts")
                #endif

                isReconnecting = false
                return

            } catch {
                #if DEBUG
                print("❌ Reconnection attempt \(reconnectionAttempt) failed: \(error)")
                #endif
                lastError = error
            }
        }

        // Exhausted all retries
        isReconnecting = false
        #if DEBUG
        print("❌ Reconnection failed after \(reconnectionConfig.maxRetries) attempts")
        #endif

        // Notify disconnection handler
        if let handler = disconnectionHandler {
            let error = URLError(.networkConnectionLost, userInfo: ["reason": "Reconnection failed"])
            handler(error)
        }
    }

    /// Sync state from server after reconnection
    /// Fetches latest job state to avoid missing progress updates
    /// Retries up to 3 times with exponential backoff on failure
    private func syncStateAfterReconnection() async {
        guard let jobId = boundJobId else {
            #if DEBUG
            print("⚠️ Cannot sync state: missing jobId")
            #endif
            return
        }

        // Retrieve token from Keychain
        let token: String
        do {
            guard let retrievedToken = try KeychainHelper.getToken(for: jobId) else {
                #if DEBUG
                print("⚠️ Cannot sync state: no token found in Keychain")
                #endif
                return
            }
            token = retrievedToken
        } catch {
            #if DEBUG
            print("⚠️ Cannot sync state: Keychain error: \(error)")
            #endif
            return
        }

        // Retry with exponential backoff (3 attempts: 1s, 2s, 4s)
        let maxRetries = 3
        for attempt in 1...maxRetries {
            do {
                // Call backend to get current job state
                let stateURL = URL(string: "\(EnrichmentConfig.apiBaseURL)/api/job-state/\(jobId)")!
                var request = URLRequest(url: stateURL)
                request.httpMethod = "GET"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.timeoutInterval = 10.0  // 10 second timeout

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }

                // Handle non-200 responses
                guard httpResponse.statusCode == 200 else {
                    if httpResponse.statusCode >= 500 && attempt < maxRetries {
                        // Server error - retry
                        let delay = pow(2.0, Double(attempt))
                        #if DEBUG
                        print("⚠️ State sync failed (HTTP \(httpResponse.statusCode)), retrying in \(delay)s...")
                        #endif
                        try await Task.sleep(for: .seconds(delay))
                        continue
                    } else {
                        // Client error or final attempt - don't retry
                        #if DEBUG
                        print("⚠️ State sync failed: HTTP \(httpResponse.statusCode)")
                        #endif
                        return
                    }
                }

                // Parse state response
                let decoder = JSONDecoder()
                let jobState = try decoder.decode(JobState.self, from: data)

                #if DEBUG
                print("✅ State synced: \(jobState.status) - \(jobState.processedCount)/\(jobState.totalCount)")
                #endif

                // If we have a progress handler, synthesize a progress update
                if let handler = progressHandler {
                    let progress = JobProgress(
                        totalItems: jobState.totalCount,
                        processedItems: jobState.processedCount,
                        currentStatus: "Reconnected - resuming at \(jobState.processedCount)/\(jobState.totalCount)",
                        keepAlive: false,
                        scanResult: nil
                    )
                    handler(progress)
                }

                // Success - exit retry loop
                return

            } catch {
                if attempt < maxRetries {
                    // Retry with exponential backoff
                    let delay = pow(2.0, Double(attempt))
                    #if DEBUG
                    print("⚠️ State sync attempt \(attempt) failed: \(error). Retrying in \(delay)s...")
                    #endif
                    try? await Task.sleep(for: .seconds(delay))
                } else {
                    // Final attempt failed
                    #if DEBUG
                    print("❌ State sync failed after \(maxRetries) attempts: \(error)")
                    #endif

                    // Notify user of sync failure
                    if let handler = progressHandler {
                        let progress = JobProgress(
                            totalItems: 0,
                            processedItems: 0,
                            currentStatus: "Reconnected - state sync failed, progress may be inaccurate",
                            keepAlive: false,
                            scanResult: nil
                        )
                        handler(progress)
                    }
                }
            }
        }
    }

    /// Disconnect WebSocket
    public func disconnect() {
        // Cancel any ongoing reconnection attempts
        reconnectionTask?.cancel()
        reconnectionTask = nil
        isReconnecting = false

        receiveTask?.cancel()
        receiveTask = nil

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        isConnected = false
        progressHandler = nil
        disconnectionHandler = nil

        // Clean up token from Keychain
        if let jobId = boundJobId {
            KeychainHelper.deleteToken(for: jobId)
        }

        boundJobId = nil
        reconnectionAttempt = 0

        #if DEBUG
        print("🔌 WebSocket disconnected")
        #endif
    }

    // MARK: - Private Methods

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

        #if DEBUG
        print("✅ Sent ready signal to server")
        #endif

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
                    #if DEBUG
                    print("⚠️ WebSocket receive error: \(error)")
                    #endif
                    self.lastError = error

                    // Mark as disconnected
                    self.isConnected = false

                    // Attempt automatic reconnection if we have jobId and token in Keychain
                    if let jobId = boundJobId,
                       let _ = try? KeychainHelper.getToken(for: jobId) {
                        #if DEBUG
                        print("🔄 Connection lost - attempting reconnection...")
                        #endif

                        // Spawn reconnection task (don't await to avoid blocking)
                        reconnectionTask = Task {
                            await self.attemptReconnection()
                        }

                        return  // Exit receive loop - reconnection will start a new one
                    } else {
                        // No reconnection info - notify and disconnect
                        disconnectionHandler?(error)
                        self.disconnect()
                    }

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
            #if DEBUG
            print("⚠️ Unknown WebSocket message type")
            #endif
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
                        books: (scanData.books ?? []).map { book in
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
                                        work: enr.work,
                                        editions: enr.editions,
                                        authors: enr.authors,
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
            #if DEBUG
            print("⚠️ Failed to parse progress update: \(error)")
            #endif
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
    let books: [BookData]?  // Optional - may be missing in error/cancellation messages
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
            let work: WorkDTO?
            let editions: [EditionDTO]?
            let authors: [AuthorDTO]?
            let provider: String?
            let cachedResult: Bool?
        }
    }

    struct ScanMetadata: Codable, Sendable {
        let processingTime: Int
        let enrichedCount: Int
        let timestamp: String
        let modelUsed: String
    }
}
