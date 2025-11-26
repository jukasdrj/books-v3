import Foundation

// MARK: - SSE Client Errors

enum SSEClientError: Error, LocalizedError {
    case invalidURL
    case notConnected
    case invalidEventFormat
    case connectionFailed(Error)
    case httpError(Int)
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid SSE URL"
        case .notConnected: return "SSE connection not established"
        case .invalidEventFormat: return "Invalid SSE event format"
        case .connectionFailed(let error): return "Connection failed: \(error.localizedDescription)"
        case .httpError(let code): return "HTTP error: \(code)"
        case .timeout: return "Connection timeout"
        }
    }
}

// MARK: - SSE Event

/// Represents a Server-Sent Event
public struct SSEEvent: Sendable {
    public let event: String?
    public let data: String
    public let id: String?
    public let retry: Int?
    
    public init(event: String?, data: String, id: String?, retry: Int?) {
        self.event = event
        self.data = data
        self.id = id
        self.retry = retry
    }
}

// MARK: - SSE Client

/// Actor-isolated SSE client for Server-Sent Events streaming
/// Implements SSE spec with Last-Event-ID reconnection support
///
/// **Concurrency Safety:** Actor-isolated for thread-safe network operations
/// **Reconnection:** Automatic with Last-Event-ID header
/// **Lifecycle:** Use connect() -> listen(), then disconnect() when done
actor SSEClient {
    
    // MARK: - Properties
    
    private var streamTask: Task<Void, Never>?
    private var lastEventID: String?
    private var retryInterval: TimeInterval = 5.0
    private var isConnected = false
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Connection Management
    
    /// Connect and parse SSE events using URLSessionDelegate for streaming
    /// - Parameters:
    ///   - url: SSE endpoint URL
    ///   - lastEventID: Optional Last-Event-ID for reconnection
    /// - Returns: AsyncStream of parsed SSE events
    func connectAndStream(to url: URL, lastEventID: String? = nil) async throws -> AsyncStream<SSEEvent> {
        // Cancel any existing connection
        disconnect()
        
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 0 // SSE connections can be long-lived
        
        // Add Last-Event-ID for reconnection
        if let eventID = lastEventID ?? self.lastEventID {
            request.setValue(eventID, forHTTPHeaderField: "Last-Event-ID")
            #if DEBUG
            print("[SSE] Reconnecting with Last-Event-ID: \(eventID)")
            #endif
        }
        
        #if DEBUG
        print("[SSE] Connecting to: \(url)")
        #endif
        
        isConnected = true
        
        // Return AsyncStream that will emit parsed SSE events
        return AsyncStream { continuation in
            let streamingTask = Task {
                do {
                    // Use AsyncBytes for streaming response
                    let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
                    
                    // Validate HTTP response
                    guard let httpResponse = response as? HTTPURLResponse else {
                        #if DEBUG
                        print("[SSE] Invalid response type")
                        #endif
                        continuation.finish()
                        return
                    }
                    
                    guard (200...299).contains(httpResponse.statusCode) else {
                        #if DEBUG
                        print("[SSE] HTTP error: \(httpResponse.statusCode)")
                        #endif
                        continuation.finish()
                        return
                    }
                    
                    #if DEBUG
                    print("[SSE] ✅ Connection established")
                    #endif
                    
                    // Parse SSE stream
                    var eventBuilder = SSEEventBuilder()
                    
                    for try await line in asyncBytes.lines {
                        #if DEBUG
                        if !line.isEmpty {
                            print("[SSE] Line: \(line)")
                        }
                        #endif
                        
                        if let event = eventBuilder.processLine(line) {
                            // Update last event ID
                            if let eventID = event.id {
                                await self.updateLastEventID(eventID)
                            }
                            
                            // Update retry interval if specified
                            if let retry = event.retry {
                                await self.updateRetryInterval(TimeInterval(retry) / 1000.0)
                            }
                            
                            continuation.yield(event)
                            eventBuilder = SSEEventBuilder() // Reset for next event
                        }
                    }
                    
                    #if DEBUG
                    print("[SSE] Stream ended")
                    #endif
                    continuation.finish()
                    
                } catch {
                    #if DEBUG
                    print("[SSE] Stream error: \(error)")
                    #endif
                    continuation.finish()
                }
            }
            
            // Store task for cancellation
            Task {
                await self.setStreamTask(streamingTask)
            }
            
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.disconnect()
                }
            }
        }
    }
    
    /// Disconnect from SSE endpoint
    func disconnect() {
        streamTask?.cancel()
        streamTask = nil
        isConnected = false
        
        #if DEBUG
        print("[SSE] Disconnected")
        #endif
    }
    
    /// Get last event ID for reconnection
    func getLastEventID() -> String? {
        return lastEventID
    }
    
    /// Get retry interval
    func getRetryInterval() -> TimeInterval {
        return retryInterval
    }
    
    /// Check if connected
    func isCurrentlyConnected() -> Bool {
        return isConnected
    }
    
    // MARK: - Private Helpers
    
    private func setConnected(_ connected: Bool) {
        isConnected = connected
    }
    
    private func setStreamTask(_ task: Task<Void, Never>) {
        streamTask = task
    }
    
    private func updateLastEventID(_ id: String) {
        lastEventID = id
        #if DEBUG
        print("[SSE] Updated Last-Event-ID: \(id)")
        #endif
    }
    
    private func updateRetryInterval(_ interval: TimeInterval) {
        retryInterval = interval
        #if DEBUG
        print("[SSE] Updated retry interval: \(interval)s")
        #endif
    }
}

// MARK: - SSE Event Builder

/// Helper for building SSE events from lines
/// Handles multi-line data fields and buffering
private struct SSEEventBuilder {
    private var event: String?
    private var data: [String] = []
    private var id: String?
    private var retry: Int?
    
    /// Process a line from SSE stream
    /// - Parameter line: Raw line from stream
    /// - Returns: Complete SSEEvent if event is finished, nil if still building
    mutating func processLine(_ line: String) -> SSEEvent? {
        // Empty line signals end of event
        if line.isEmpty {
            guard !data.isEmpty else { return nil }
            
            let event = SSEEvent(
                event: self.event,
                data: data.joined(separator: "\n"),
                id: self.id,
                retry: self.retry
            )
            
            // Reset for next event
            self.event = nil
            self.data = []
            // Note: id and retry persist across events until updated
            
            return event
        }
        
        // Comment line (ignore)
        if line.hasPrefix(":") {
            return nil
        }
        
        // Parse field
        guard let colonIndex = line.firstIndex(of: ":") else {
            return nil
        }
        
        let field = String(line[..<colonIndex])
        var value = String(line[line.index(after: colonIndex)...])
        
        // SSE spec: Remove single leading space from value if present
        if value.hasPrefix(" ") {
            value.removeFirst()
        }
        
        switch field {
        case "event":
            self.event = value
        case "data":
            self.data.append(value)
        case "id":
            self.id = value
        case "retry":
            self.retry = Int(value)
        default:
            // Unknown field, ignore per SSE spec
            break
        }
        
        return nil
    }
}
