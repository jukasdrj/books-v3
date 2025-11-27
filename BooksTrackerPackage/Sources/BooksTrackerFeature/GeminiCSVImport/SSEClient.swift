import Foundation

// MARK: - SSE Client

/// Actor-based SSE client for streaming CSV import progress from V2 API
/// Thread-safe streaming with automatic reconnection and network transition handling
actor SSEClient: NSObject {
    // MARK: - Configuration

    private let baseURL: String
    private let maxReconnectionAttempts: Int = 3
    private let reconnectionDelay: TimeInterval = 5.0

    // MARK: - State

    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var currentJobId: String?
    private var lastEventId: String?
    private var reconnectionAttempts: Int = 0
    private var eventBuffer: String = ""
    private var isCancelled: Bool = false

    // MARK: - Callbacks

    /// Called when a queued event is received
    nonisolated let onQueued: @Sendable (SSEQueuedEvent) -> Void

    /// Called when a started event is received
    nonisolated let onStarted: @Sendable (SSEStartedEvent) -> Void

    /// Called when a progress event is received
    nonisolated let onProgress: @Sendable (SSEProgressEvent) -> Void

    /// Called when a complete event is received
    nonisolated let onComplete: @Sendable (SSECompleteEvent) -> Void

    /// Called when an error event is received
    nonisolated let onError: @Sendable (SSEClientError) -> Void

    // MARK: - Initialization

    init(
        baseURL: String = EnrichmentConfig.baseURL,
        onQueued: @escaping @Sendable (SSEQueuedEvent) -> Void,
        onStarted: @escaping @Sendable (SSEStartedEvent) -> Void,
        onProgress: @escaping @Sendable (SSEProgressEvent) -> Void,
        onComplete: @escaping @Sendable (SSECompleteEvent) -> Void,
        onError: @escaping @Sendable (SSEClientError) -> Void
    ) {
        self.baseURL = baseURL
        self.onQueued = onQueued
        self.onStarted = onStarted
        self.onProgress = onProgress
        self.onComplete = onComplete
        self.onError = onError
        super.init()
    }

    // MARK: - Public Methods

    /// Connect to SSE stream for a specific job
    /// - Parameter jobId: The import job ID to stream
    func connect(jobId: String) {
        #if DEBUG
        print("[SSE] Connecting to job: \(jobId)")
        #endif

        self.currentJobId = jobId
        self.isCancelled = false
        self.reconnectionAttempts = 0

        createSession()
        startStreaming(jobId: jobId)
    }

    /// Disconnect from SSE stream
    func disconnect() {
        #if DEBUG
        print("[SSE] Disconnecting")
        #endif

        isCancelled = true
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        currentJobId = nil
        lastEventId = nil
        eventBuffer = ""
        reconnectionAttempts = 0
    }

    // MARK: - Private Methods

    private func createSession() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = .infinity  // SSE is long-lived
        config.timeoutIntervalForResource = .infinity
        config.httpAdditionalHeaders = [
            "Accept": "text/event-stream",
            "Cache-Control": "no-cache"
        ]

        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    private func startStreaming(jobId: String) {
        guard let session = session else {
            #if DEBUG
            print("[SSE] ❌ No session available")
            #endif
            return
        }

        guard let url = URL(string: "\(baseURL)/api/v2/imports/\(jobId)/stream") else {
            #if DEBUG
            print("[SSE] ❌ Invalid URL")
            #endif
            onError(.invalidURL)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // Add Last-Event-ID header for reconnection
        if let lastEventId = lastEventId {
            request.setValue(lastEventId, forHTTPHeaderField: "Last-Event-ID")
            #if DEBUG
            print("[SSE] Reconnecting with Last-Event-ID: \(lastEventId)")
            #endif
        }

        task = session.dataTask(with: request)
        task?.resume()

        #if DEBUG
        print("[SSE] ✅ Stream started")
        #endif
    }

    private func attemptReconnection() {
        guard !isCancelled else {
            #if DEBUG
            print("[SSE] Skipping reconnection (cancelled)")
            #endif
            return
        }

        guard reconnectionAttempts < maxReconnectionAttempts else {
            #if DEBUG
            print("[SSE] ❌ Max reconnection attempts exceeded")
            #endif
            onError(.reconnectionLimitExceeded)
            return
        }

        reconnectionAttempts += 1

        #if DEBUG
        print("[SSE] Attempting reconnection \(reconnectionAttempts)/\(maxReconnectionAttempts)")
        #endif

        Task {
            try? await Task.sleep(for: .seconds(reconnectionDelay))

            guard let jobId = await self.currentJobId else {
                #if DEBUG
                print("[SSE] No job ID for reconnection")
                #endif
                return
            }

            await self.startStreaming(jobId: jobId)
        }
    }

    private func parseSSEEvents(_ eventString: String) {
        // Append to buffer
        eventBuffer += eventString

        // Split on double newline (SSE event separator)
        let events = eventBuffer.components(separatedBy: "\n\n")

        // Keep the last incomplete event in the buffer
        if !eventBuffer.hasSuffix("\n\n") {
            eventBuffer = events.last ?? ""
        } else {
            eventBuffer = ""
        }

        // Process all complete events
        for event in events.dropLast() {
            if event.isEmpty { continue }
            parseEvent(event)
        }
    }

    private func parseEvent(_ eventString: String) {
        var eventType: String?
        var eventData: String = ""
        var eventId: String?

        let lines = eventString.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix("event: ") {
                eventType = String(line.dropFirst(7))
            } else if line.hasPrefix("data: ") {
                if !eventData.isEmpty {
                    eventData += "\n"
                }
                eventData += String(line.dropFirst(6))
            } else if line.hasPrefix("id: ") {
                eventId = String(line.dropFirst(4))
            } else if line.hasPrefix("retry: ") {
                // Parse retry value if needed
                #if DEBUG
                let retryMs = String(line.dropFirst(7))
                print("[SSE] Server retry suggestion: \(retryMs)ms")
                #endif
            } else if line.hasPrefix(":") {
                // Comment line, skip
                continue
            }
        }

        // Store last event ID for reconnection
        if let eventId = eventId {
            lastEventId = eventId
        }

        // Handle event based on type
        guard let type = eventType, !eventData.isEmpty else {
            #if DEBUG
            print("[SSE] ⚠️ Skipping event (no type or data)")
            #endif
            return
        }

        handleEvent(type: type, data: eventData)
    }

    private func handleEvent(type: String, data: String) {
        guard let jsonData = data.data(using: .utf8) else {
            #if DEBUG
            print("[SSE] ❌ Failed to convert data to UTF-8")
            #endif
            onError(.eventParsingFailed)
            return
        }

        #if DEBUG
        print("[SSE] 📩 Event type: \(type)")
        #endif

        let decoder = JSONDecoder()

        switch type {
        case "queued":
            do {
                let event = try decoder.decode(SSEQueuedEvent.self, from: jsonData)
                onQueued(event)
            } catch {
                #if DEBUG
                print("[SSE] ❌ Failed to decode queued event: \(error)")
                #endif
                onError(.eventParsingFailed)
            }

        case "started":
            do {
                let event = try decoder.decode(SSEStartedEvent.self, from: jsonData)
                onStarted(event)
            } catch {
                #if DEBUG
                print("[SSE] ❌ Failed to decode started event: \(error)")
                #endif
                onError(.eventParsingFailed)
            }

        case "progress":
            do {
                let event = try decoder.decode(SSEProgressEvent.self, from: jsonData)
                onProgress(event)
            } catch {
                #if DEBUG
                print("[SSE] ❌ Failed to decode progress event: \(error)")
                #endif
                onError(.eventParsingFailed)
            }

        case "complete":
            do {
                let event = try decoder.decode(SSECompleteEvent.self, from: jsonData)
                onComplete(event)
                // Auto-disconnect on completion
                Task {
                    await self.disconnect()
                }
            } catch {
                #if DEBUG
                print("[SSE] ❌ Failed to decode complete event: \(error)")
                #endif
                onError(.eventParsingFailed)
            }

        case "error":
            do {
                let event = try decoder.decode(SSEErrorEvent.self, from: jsonData)
                onError(.serverError(event.error))
                // Auto-disconnect on error
                Task {
                    await self.disconnect()
                }
            } catch {
                #if DEBUG
                print("[SSE] ❌ Failed to decode error event: \(error)")
                #endif
                onError(.eventParsingFailed)
            }

        default:
            #if DEBUG
            print("[SSE] ⚠️ Unknown event type: \(type)")
            #endif
        }
    }
}

// MARK: - URLSessionDataDelegate

extension SSEClient: URLSessionDataDelegate {
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task {
            // Parse SSE events from incoming data
            guard let eventString = String(data: data, encoding: .utf8) else {
                #if DEBUG
                print("[SSE] ❌ Failed to decode data as UTF-8")
                #endif
                return
            }

            await self.parseSSEEvents(eventString)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task {
            let wasCancelled = await self.isCancelled

            if let error = error {
                let nsError = error as NSError

                // Check if it's a normal cancellation
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                    if !wasCancelled {
                        #if DEBUG
                        print("[SSE] Connection cancelled (not by user)")
                        #endif
                        // Network transition or unexpected cancellation - attempt reconnection
                        await self.attemptReconnection()
                    } else {
                        #if DEBUG
                        print("[SSE] Connection cancelled by user")
                        #endif
                    }
                } else {
                    #if DEBUG
                    print("[SSE] ❌ Connection error: \(error.localizedDescription)")
                    #endif

                    if !wasCancelled {
                        // Attempt reconnection for other errors
                        await self.attemptReconnection()
                    }
                }
            } else {
                #if DEBUG
                print("[SSE] Connection completed normally")
                #endif
            }
        }
    }
}
