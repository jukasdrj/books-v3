import Foundation

/// WebSocket-specific errors
enum WebSocketError: Error, LocalizedError {
    case notConnected
    case encodingFailed
    case decodingFailed
    case connectionFailed(Error)
    case authenticationFailed
    case connectionLimitExceeded

    var errorDescription: String? {
        switch self {
        case .notConnected: return "WebSocket not connected"
        case .encodingFailed: return "Failed to encode message"
        case .decodingFailed: return "Failed to decode message"
        case .connectionFailed(let error): return "Connection failed: \(error.localizedDescription)"
        case .authenticationFailed: return "Authentication failed"
        case .connectionLimitExceeded: return "Too many connections to this job. Close existing connections before reconnecting."
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
public final class WebSocketProgressManager: NSObject, @preconcurrency URLSessionWebSocketDelegate, @preconcurrency URLSessionTaskDelegate {

    // MARK: - Properties

    public private(set) var isConnected: Bool = false
    public private(set) var lastError: Error?

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession!
    private var connectionContinuation: CheckedContinuation<ConnectionToken, Error>?
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

    override public init() {
        super.init()

        // FIX (Issue #227): Enforce HTTP/1.1 for WebSocket handshake compatibility with iOS/backend.
        // iOS defaults to HTTP/2 for HTTPS, which is incompatible with RFC 6455 WebSocket upgrade.
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 1
        config.timeoutIntervalForRequest = connectionTimeout // Use defined timeout (10.0s)

        self.session = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
    }

    /// STEP 1: Establish WebSocket connection BEFORE job starts
    /// This prevents race condition where server processes before client listens
    ///
    /// - Parameters:
    ///   - jobId: Client-generated job identifier for WebSocket binding
    ///   - token: Optional authentication token for WebSocket connection
    ///   - reconnect: Set to true when reconnecting to existing job (enables state sync)
    /// - Returns: ConnectionToken proving connection is ready
    /// - Throws: URLError if connection fails or times out
    public func establishConnection(jobId: String, token: String? = nil, reconnect: Bool = false) async throws -> ConnectionToken {
        guard webSocketTask == nil else {
            throw URLError(.badURL, userInfo: ["reason": "WebSocket already connected"])
        }

        // Store auth token securely in Keychain for reconnection
        if let token = token {
            try KeychainHelper.saveToken(token, for: jobId)
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Create connection endpoint with client-provided jobId (token goes in header for security)
            // Add reconnect=true parameter for state sync on reconnection (v2.4 API contract)
            var urlString = "\(EnrichmentConfig.webSocketBaseURL)/ws/progress?jobId=\(jobId)"
            if reconnect {
                urlString += "&reconnect=true"
            }
            let url = URL(string: urlString)!

            self.connectionContinuation = continuation

            // FIX (Issue #227): Configure URLRequest for HTTP/1.1 WebSocket upgrade.
            var request = URLRequest(url: url)
            request.assumesHTTP3Capable = false // Forces HTTP/1.1 negotiation (disables HTTP/2 and HTTP/3)
            request.setValue("websocket", forHTTPHeaderField: "Upgrade")
            request.setValue("Upgrade", forHTTPHeaderField: "Connection")

            // SECURITY: Add token securely via Sec-WebSocket-Protocol header (matches GenericWebSocketHandler pattern)
            // This prevents token leakage in server logs, proxies, or error reports
            if let token = token {
                request.setValue("bookstrack-auth.\(token)", forHTTPHeaderField: "Sec-WebSocket-Protocol")
            }

            let task = self.session.webSocketTask(with: request)
            self.webSocketTask = task
            task.resume()
        }
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
                // Pass reconnect=true to enable backend state sync (v2.4 API contract)
                _ = try await establishConnection(jobId: jobId, token: token!, reconnect: true)

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
                    // The didCloseWith delegate method will handle closures.
                    // We just need to break the loop.
                    #if DEBUG
                    print("⚠️ WebSocket receive error, loop ending: \(error)")
                    #endif
                    self.lastError = error
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

    /// Parse JSON progress update (unified schema)
    private func parseProgressUpdate(_ json: String) async {
        guard let data = json.data(using: .utf8) else { return }

        do {
            let decoder = JSONDecoder()
            // Use unified WebSocket schema (Phase 1 #363)
            let message = try decoder.decode(TypedWebSocketMessage.self, from: data)

            // Verify this is for ai_scan pipeline
            guard message.pipeline == .aiScan else {
                #if DEBUG
                print("⚠️ Ignoring message for different pipeline: \(message.pipeline)")
                #endif
                return
            }

            switch message.payload {
            case .jobProgress(let progressPayload):
                // Convert to legacy JobProgress format for compatibility
                let progress = JobProgress(
                    totalItems: 1, // AI scan is single-item
                    processedItems: progressPayload.progress >= 1.0 ? 1 : 0,
                    currentStatus: progressPayload.status,
                    keepAlive: progressPayload.keepAlive,
                    scanResult: nil  // Only in completion
                )

                await MainActor.run {
                    progressHandler?(progress)
                }

            case .jobComplete(let completePayload):
                // Extract AI scan-specific completion data
                guard case .aiScan(let aiPayload) = completePayload else {
                    #if DEBUG
                    print("❌ Wrong completion payload type for ai_scan")
                    #endif
                    return
                }

                // v2.0 Migration: Fetch full results via HTTP using resourceId
                // WebSocket now only sends lightweight summary
                if let resourceId = aiPayload.summary.resourceId {
                    // Extract jobId from resourceId format: "job-results:uuid"
                    let jobId = resourceId.replacingOccurrences(of: "job-results:", with: "")

                    do {
                        // Fetch full results from KV cache via HTTP
                        let results = try await BookshelfAIService.shared.fetchJobResults(jobId: jobId)
                        let progress = JobProgress(
                            totalItems: 1,
                            processedItems: 1,
                            currentStatus: "Complete!",
                            keepAlive: false,
                            scanResult: results
                        )
                        await MainActor.run {
                            progressHandler?(progress)
                        }
                    } catch {
                        #if DEBUG
                        print("❌ Failed to fetch scan results for job \(jobId): \(error)")
                        #endif
                        // Notify handler of failure
                        let progress = JobProgress(
                            totalItems: 1,
                            processedItems: 1,
                            currentStatus: "Failed to load results",
                            keepAlive: false,
                            scanResult: nil
                        )
                        await MainActor.run {
                            progressHandler?(progress)
                        }
                    }
                } else {
                    // No resourceId - create minimal result from summary (no books data available)
                    let scanResult = ScanResultPayload(
                        totalDetected: aiPayload.summary.totalDetected ?? 0,
                        approved: aiPayload.summary.approved ?? 0,
                        needsReview: aiPayload.summary.needsReview ?? 0,
                        books: [],  // Empty - full results must be fetched via HTTP
                        metadata: ScanResultPayload.ScanMetadataPayload(
                            processingTime: aiPayload.summary.duration,
                            enrichedCount: aiPayload.summary.approved ?? 0,
                            timestamp: String(message.timestamp),
                            modelUsed: "gemini-2.0-flash"
                        ),
                        expiresAt: aiPayload.expiresAt  // Pass through from backend
                    )

                    let progress = JobProgress(
                        totalItems: 1,
                        processedItems: 1,
                        currentStatus: "Complete!",
                        keepAlive: false,
                        scanResult: scanResult
                    )

                    await MainActor.run {
                        progressHandler?(progress)
                    }
                }

            case .error(let errorPayload):
                #if DEBUG
                print("❌ WebSocket error: \(errorPayload.message) (code: \(errorPayload.code), retryable: \(errorPayload.retryable ?? false))")
                #endif

                // Use retryable field from v2.0 API contract (Issue #5)
                let shouldRetry = errorPayload.retryable ?? false

                // Handle specific error codes
                switch errorPayload.code {
                case "CONNECTION_LIMIT_EXCEEDED":
                    // Never retry connection limits (v2.4.1 API contract)
                    lastError = WebSocketError.connectionLimitExceeded
                    disconnectionHandler?(lastError!)

                case "AUTHENTICATION_FAILED":
                    // Never retry auth failures
                    lastError = WebSocketError.authenticationFailed
                    disconnectionHandler?(lastError!)

                case "PROVIDER_TIMEOUT", "NETWORK_ERROR":
                    // Retry transient errors if backend says retryable
                    if shouldRetry {
                        #if DEBUG
                        print("🔄 Transient error (\(errorPayload.code)) - will attempt reconnection")
                        #endif
                        // Let natural reconnection handle it
                    } else {
                        let error = NSError(
                            domain: "WebSocket",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: errorPayload.message]
                        )
                        lastError = WebSocketError.connectionFailed(error)
                        disconnectionHandler?(lastError!)
                    }

                default:
                    // Use retryable field for unknown error codes
                    if !shouldRetry {
                        let error = NSError(
                            domain: "WebSocket",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: errorPayload.message]
                        )
                        lastError = WebSocketError.connectionFailed(error)
                        disconnectionHandler?(lastError!)
                    }
                }

            case .reconnected(let payload):
                #if DEBUG
                print("✅ Reconnected - syncing state: \(payload.processedCount)/\(payload.totalCount)")
                #endif

                if let handler = progressHandler {
                    let progress = JobProgress(
                        totalItems: payload.totalCount,
                        processedItems: payload.processedCount,
                        currentStatus: payload.message,
                        keepAlive: false,
                        scanResult: nil
                    )
                    handler(progress)
                }

            case .readyAck:
                // Backend acknowledged ready signal - no action needed
                #if DEBUG
                print("✅ Backend acknowledged ready signal (structured decoding)")
                #endif

            case .jobStarted, .ping, .pong:
                // No action needed for infrastructure messages
                // jobStarted: Optional pre-processing notification
                // ping/pong: Keep-alive messages
                break

            case .batchInit, .batchProgress, .batchComplete, .batchCanceling:
                // Batch scanning messages - ignore in AI scan pipeline
                // These should never reach here due to pipeline filtering at line 439
                break
            }

        } catch {
            #if DEBUG
            print("⚠️ Failed to parse progress update: \(error)")
            #endif
        }
    }
}

// MARK: - URLSessionWebSocketDelegate
extension WebSocketProgressManager {
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        self.isConnected = true
        self.reconnectionAttempt = 0  // Reset reconnection counter on successful connection
        #if DEBUG
        print("🔌 WebSocket established (delegate)")
        #endif

        // Start receiving messages in background
        Task {
            await startReceiving()
        }

        // Resume continuation to signal connection is ready
        let token = ConnectionToken(connectionId: UUID().uuidString, createdAt: Date())
        connectionContinuation?.resume(returning: token)
        connectionContinuation = nil
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            let nsError = error as NSError

            // Check for HTTP 426 Upgrade Required (HTTP/2 mismatch - Issue #227)
            if nsError.code == -1011 && nsError.domain == NSURLErrorDomain {
                #if DEBUG
                print("❌ HTTP upgrade required - possible HTTP/2 negotiation: \(error.localizedDescription)")
                #endif
                self.isConnected = false

                let upgradeError = URLError(
                    .badServerResponse,
                    userInfo: [
                        NSLocalizedDescriptionKey: "WebSocket upgrade failed - server requires HTTP/1.1 but got HTTP/2",
                        "code": "HTTP_VERSION_MISMATCH",
                        "retryable": false
                    ]
                )
                connectionContinuation?.resume(throwing: upgradeError)
                connectionContinuation = nil
                disconnect()
                return
            }

            #if DEBUG
            print("🔌 WebSocket task completed with error: \(error)")
            #endif
            self.isConnected = false
            connectionContinuation?.resume(throwing: error)
            connectionContinuation = nil

            // This is called for network errors, so we attempt reconnection.
            // The didCloseWith delegate is for graceful or ungraceful closures.
            reconnect()
        }
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        #if DEBUG
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "none"
        print("🔌 WebSocket closed with code: \(closeCode.rawValue), reason: \(reasonString)")
        #endif

        self.isConnected = false

        switch closeCode {
        case .normalClosure, .goingAway:
            #if DEBUG
            print("✅ Job completed normally - no reconnection")
            #endif
            disconnect() // Clean up
            return

        case .policyViolation:  // 1008 - Auth failure or connection limit exceeded (v2.4.1)
            // Parse reason to differentiate between auth failure and connection limit
            if let reason = reason,
               let reasonString = String(data: reason, encoding: .utf8),
               reasonString.contains("Connection limit exceeded") {
                lastError = WebSocketError.connectionLimitExceeded
                #if DEBUG
                print("❌ Connection limit exceeded (5 concurrent connections per job)")
                #endif
            } else {
                lastError = WebSocketError.authenticationFailed
                #if DEBUG
                print("❌ Authentication failed")
                #endif
            }
            disconnectionHandler?(lastError!)
            disconnect() // Clean up - don't retry on policy violations
            return

        default:  // Network errors, etc. - reconnect
            reconnect()
        }
    }
    
    private func reconnect() {
        // Attempt automatic reconnection if we have jobId and token in Keychain
        Task {
            do {
                if let jobId = boundJobId, try KeychainHelper.getToken(for: jobId) != nil {
                    #if DEBUG
                    print("🔄 Connection lost - attempting reconnection...")
                    #endif
                    
                    // Spawn reconnection task (don't await to avoid blocking)
                    reconnectionTask = Task {
                        await self.attemptReconnection()
                    }
                } else {
                    // No reconnection info - notify and disconnect
                    let error = URLError(.networkConnectionLost)
                    disconnectionHandler?(error)
                    self.disconnect()
                }
            } catch {
                #if DEBUG
                print("❌ Keychain error during reconnection check: \(error)")
                #endif
                disconnectionHandler?(error)
                self.disconnect()
            }
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
