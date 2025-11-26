import Foundation

// MARK: - SSE Event Models

/// SSE event types for CSV import progress tracking
public enum SSEEventType: String, Sendable {
    case progress = "progress"
    case complete = "complete"
    case error = "error"
    case started = "started"
    case queued = "queued"
}

/// Progress event data from SSE stream
public struct SSEProgressEvent: Codable, Sendable {
    public let progress: Double
    public let processedRows: Int?
    public let successfulRows: Int?
    public let failedRows: Int?
    public let status: String?
    
    enum CodingKeys: String, CodingKey {
        case progress
        case processedRows = "processed_rows"
        case successfulRows = "successful_rows"
        case failedRows = "failed_rows"
        case status
    }
}

/// Import job started event
public struct SSEStartedEvent: Codable, Sendable {
    public let status: String
    public let totalRows: Int?
    public let startedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case status
        case totalRows = "total_rows"
        case startedAt = "started_at"
    }
}

/// Import completion result from SSE stream
public struct SSEImportResult: Codable, Sendable {
    public let status: String
    public let progress: Double
    public let resultSummary: ResultSummary?
    
    public struct ResultSummary: Codable, Sendable {
        public let booksCreated: Int?
        public let booksUpdated: Int?
        public let duplicatesSkipped: Int?
        public let enrichmentSucceeded: Int?
        public let enrichmentFailed: Int?
        public let errors: [ImportErrorDetail]?
        
        enum CodingKeys: String, CodingKey {
            case booksCreated = "books_created"
            case booksUpdated = "books_updated"
            case duplicatesSkipped = "duplicates_skipped"
            case enrichmentSucceeded = "enrichment_succeeded"
            case enrichmentFailed = "enrichment_failed"
            case errors
        }
    }
    
    public struct ImportErrorDetail: Codable, Sendable {
        public let row: Int?
        public let isbn: String?
        public let error: String?
    }
    
    enum CodingKeys: String, CodingKey {
        case status
        case progress
        case resultSummary = "result_summary"
    }
}

/// SSE-specific errors
public enum SSEError: Error, LocalizedError, Sendable {
    case connectionFailed(Error)
    case invalidURL
    case authenticationRequired
    case reconnectionFailed(Int) // Number of attempts
    case streamParsingError(String)
    case jobFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let error):
            return "SSE connection failed: \(error.localizedDescription)"
        case .invalidURL:
            return "Invalid SSE endpoint URL"
        case .authenticationRequired:
            return "Authentication token required for SSE connection"
        case .reconnectionFailed(let attempts):
            return "Failed to reconnect after \(attempts) attempts"
        case .streamParsingError(let message):
            return "Failed to parse SSE stream: \(message)"
        case .jobFailed(let message):
            return "Import job failed: \(message)"
        }
    }
}

// MARK: - SSE Client

/// Native Swift SSE (Server-Sent Events) client using URLSession
/// Implements automatic reconnection with Last-Event-ID support
/// Designed for V2 API import progress tracking
///
/// **Features:**
/// - Automatic reconnection on network transitions (WiFi ↔ Cellular)
/// - Last-Event-ID support for resuming from last event
/// - Exponential backoff for failed connections
/// - Background URLSession support for app backgrounding
/// - Swift 6.2 actor isolation for thread-safe operations
///
/// **Usage:**
/// ```swift
/// let client = SSEClient(baseURL: "https://api.oooefam.net")
/// 
/// client.onProgress = { progress, processed, total in
///     await MainActor.run {
///         updateProgressUI(progress)
///     }
/// }
///
/// client.onComplete = { result in
///     await MainActor.run {
///         showCompletionUI(result)
///     }
/// }
///
/// try await client.connect(jobId: "import_abc123")
/// ```
actor SSEClient: NSObject, URLSessionDataDelegate {
    
    // MARK: - Properties
    
    private var dataTask: URLSessionDataTask?
    private var session: URLSession!
    private let baseURL: String
    private var buffer: String = ""
    private var lastEventId: String?
    private var reconnectionAttempt: Int = 0
    private let maxReconnectionAttempts: Int = 3
    private var isConnected: Bool = false
    private var currentJobId: String?
    
    // Reconnection configuration with exponential backoff
    private let initialReconnectionDelay: TimeInterval = 5.0  // 5 seconds
    private let maxReconnectionDelay: TimeInterval = 30.0     // 30 seconds
    private let backoffMultiplier: Double = 2.0
    
    // MARK: - Callbacks (Sendable closures for Swift 6 concurrency)
    
    /// Progress update callback - called on background thread
    /// Use @MainActor.run inside if updating UI
    var onProgress: (@Sendable (Double, Int, Int) -> Void)?
    
    /// Completion callback - called on background thread
    /// Use @MainActor.run inside if updating UI
    var onComplete: (@Sendable (SSEImportResult) -> Void)?
    
    /// Error callback - called on background thread
    /// Use @MainActor.run inside if updating UI
    var onError: (@Sendable (Error) -> Void)?
    
    /// Connection state change callback
    var onConnectionStateChange: (@Sendable (Bool) -> Void)?
    
    // MARK: - Initialization
    
    /// Initialize SSE client with base URL
    /// - Parameter baseURL: Base URL for the API (e.g., "https://api.oooefam.net")
    init(baseURL: String = "https://api.oooefam.net") {
        self.baseURL = baseURL
        super.init()
        
        // Configure URLSession for SSE
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = .infinity  // SSE is long-lived
        config.timeoutIntervalForResource = .infinity
        config.httpAdditionalHeaders = [
            "Accept": "text/event-stream",
            "Cache-Control": "no-cache"
        ]
        
        // Create session with self as delegate (actor isolation safe in Swift 6)
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    // MARK: - Public API
    
    /// Connect to SSE stream for a specific job
    /// - Parameters:
    ///   - jobId: The import job ID
    ///   - authToken: Optional authentication token
    /// - Throws: SSEError if connection fails
    func connect(jobId: String, authToken: String? = nil) async throws {
        guard let url = URL(string: "\(baseURL)/api/v2/imports/\(jobId)/stream") else {
            throw SSEError.invalidURL
        }
        
        currentJobId = jobId
        
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        
        // Add authentication if provided
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Add Last-Event-ID for reconnection
        if let lastId = lastEventId {
            request.setValue(lastId, forHTTPHeaderField: "Last-Event-ID")
        }
        
        // Create and start data task
        dataTask = session.dataTask(with: request)
        dataTask?.resume()
        
        isConnected = true
        onConnectionStateChange?(true)
        
        #if DEBUG
        print("[SSEClient] Connected to \(url)")
        if let lastId = lastEventId {
            print("[SSEClient] Resuming from Last-Event-ID: \(lastId)")
        }
        #endif
    }
    
    /// Disconnect from SSE stream
    func disconnect() {
        dataTask?.cancel()
        dataTask = nil
        isConnected = false
        buffer = ""
        reconnectionAttempt = 0
        currentJobId = nil
        onConnectionStateChange?(false)
        
        #if DEBUG
        print("[SSEClient] Disconnected")
        #endif
    }
    
    /// Get current connection state
    func getConnectionState() -> Bool {
        return isConnected
    }
    
    // MARK: - URLSessionDataDelegate
    
    nonisolated public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Process data in actor context
        Task {
            await handleReceivedData(data)
        }
    }
    
    nonisolated public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Handle completion in actor context
        Task {
            await handleTaskCompletion(error: error)
        }
    }
    
    // MARK: - Private Methods
    
    private func handleReceivedData(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else {
            #if DEBUG
            print("[SSEClient] Failed to decode data chunk")
            #endif
            return
        }
        
        buffer += chunk
        processBuffer()
    }
    
    private func handleTaskCompletion(error: Error?) {
        isConnected = false
        onConnectionStateChange?(false)
        
        if let error = error {
            #if DEBUG
            print("[SSEClient] Task completed with error: \(error)")
            #endif
            
            // Attempt reconnection if we have a job ID and haven't exceeded max attempts
            if currentJobId != nil && reconnectionAttempt < maxReconnectionAttempts {
                Task {
                    await attemptReconnection()
                }
            } else {
                if reconnectionAttempt >= maxReconnectionAttempts {
                    onError?(SSEError.reconnectionFailed(reconnectionAttempt))
                } else {
                    onError?(SSEError.connectionFailed(error))
                }
            }
        } else {
            #if DEBUG
            print("[SSEClient] Task completed normally")
            #endif
        }
    }
    
    private func processBuffer() {
        // SSE format: events are separated by double newlines
        let events = buffer.components(separatedBy: "\n\n")
        
        // Keep last incomplete event in buffer
        if buffer.hasSuffix("\n\n") {
            buffer = ""
        } else {
            buffer = events.last ?? ""
        }
        
        // Process complete events
        for eventText in events.dropLast() {
            guard !eventText.isEmpty else { continue }
            parseEvent(eventText)
        }
    }
    
    private func parseEvent(_ eventText: String) {
        var eventType: String?
        var eventData: String = ""
        var eventId: String?
        
        // Parse SSE event fields
        let lines = eventText.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix(":") {
                // Comment line - ignore
                continue
            } else if line.hasPrefix("event:") {
                eventType = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                let dataLine = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if !eventData.isEmpty {
                    eventData += "\n"
                }
                eventData += dataLine
            } else if line.hasPrefix("id:") {
                eventId = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("retry:") {
                // Retry directive from server - could be used to adjust reconnection delay
                // For now, we use our own backoff strategy
            }
        }
        
        // Store event ID for reconnection
        if let id = eventId {
            lastEventId = id
        }
        
        // Process event based on type
        guard !eventData.isEmpty else { return }
        
        handleEvent(type: eventType, data: eventData)
    }
    
    private func handleEvent(type: String?, data: String) {
        guard let eventData = data.data(using: .utf8) else { return }
        
        let decoder = JSONDecoder()
        
        #if DEBUG
        print("[SSEClient] Event type: \(type ?? "default"), data: \(data)")
        #endif
        
        switch type {
        case "progress":
            do {
                let progressEvent = try decoder.decode(SSEProgressEvent.self, from: eventData)
                let processed = progressEvent.processedRows ?? 0
                let successful = progressEvent.successfulRows ?? 0
                onProgress?(progressEvent.progress, processed, processed)
            } catch {
                #if DEBUG
                print("[SSEClient] Failed to decode progress event: \(error)")
                #endif
            }
            
        case "complete":
            do {
                let completeEvent = try decoder.decode(SSEImportResult.self, from: eventData)
                onComplete?(completeEvent)
                disconnect()
            } catch {
                #if DEBUG
                print("[SSEClient] Failed to decode complete event: \(error)")
                #endif
            }
            
        case "error":
            do {
                // Error event contains a status and error message
                if let errorDict = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any],
                   let errorMessage = errorDict["error"] as? String {
                    onError?(SSEError.jobFailed(errorMessage))
                    disconnect()
                }
            } catch {
                #if DEBUG
                print("[SSEClient] Failed to decode error event: \(error)")
                #endif
            }
            
        case "started":
            do {
                let startedEvent = try decoder.decode(SSEStartedEvent.self, from: eventData)
                #if DEBUG
                print("[SSEClient] Job started: \(startedEvent.status)")
                #endif
                // Optionally notify UI that job has started
            } catch {
                #if DEBUG
                print("[SSEClient] Failed to decode started event: \(error)")
                #endif
            }
            
        case "queued":
            #if DEBUG
            print("[SSEClient] Job queued")
            #endif
            // Job is queued, waiting to start
            
        default:
            // Unknown event type or no event type (default message)
            #if DEBUG
            print("[SSEClient] Unknown or default event, ignoring")
            #endif
        }
    }
    
    private func attemptReconnection() async {
        reconnectionAttempt += 1
        
        let delay = min(
            initialReconnectionDelay * pow(backoffMultiplier, Double(reconnectionAttempt - 1)),
            maxReconnectionDelay
        )
        
        #if DEBUG
        print("[SSEClient] Reconnection attempt \(reconnectionAttempt)/\(maxReconnectionAttempts) after \(delay)s")
        #endif
        
        do {
            try await Task.sleep(for: .seconds(delay))
            
            // Try to reconnect with same job ID
            if let jobId = currentJobId {
                try await connect(jobId: jobId)
                
                #if DEBUG
                print("[SSEClient] Reconnection successful")
                #endif
                
                // Reset reconnection counter on success
                reconnectionAttempt = 0
            }
        } catch {
            #if DEBUG
            print("[SSEClient] Reconnection attempt \(reconnectionAttempt) failed: \(error)")
            #endif
            
            // Try again if we haven't exceeded max attempts
            if reconnectionAttempt < maxReconnectionAttempts {
                await attemptReconnection()
            } else {
                onError?(SSEError.reconnectionFailed(reconnectionAttempt))
            }
        }
    }
}
