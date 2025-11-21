import Foundation

#if os(iOS)

/// Handles WebSocket connection for batch scan progress updates
/// Actor-isolated for thread-safe WebSocket operations
actor BatchWebSocketHandler {
    private var webSocket: URLSessionWebSocketTask?
    private let jobId: String
    private let onProgress: @MainActor (BatchProgress) -> Void
    private let onDisconnect: (@MainActor () -> Void)?
    private var isConnected = false

    // Track simple Sendable state instead of @MainActor BatchProgress
    private var totalPhotos: Int = 0
    private var currentOverallStatus: String = "queued"

    init(
        jobId: String,
        onProgress: @MainActor @escaping (BatchProgress) -> Void,
        onDisconnect: (@MainActor () -> Void)? = nil
    ) {
        self.jobId = jobId
        self.onProgress = onProgress
        self.onDisconnect = onDisconnect
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

        #if DEBUG
        print("[BatchWebSocket] Connected for job \(jobId)")
        #endif

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
            #if DEBUG
            print("[BatchWebSocket] Error: \(error)")
            #endif
            isConnected = false

            // CRITICAL: Notify caller of unexpected disconnection (#307)
            // This ensures idle timer is re-enabled to prevent battery drain
            if let onDisconnect = onDisconnect {
                await MainActor.run {
                    onDisconnect()
                }
            }
        }
    }

    /// Parse and handle incoming message
    private func handleMessage(_ text: String) async {
        guard let data = text.data(using: .utf8) else { return }

        // Check for legacy ready_ack message (backend still sends this without unified schema)
        if text.contains("\"type\":\"ready_ack\"") {
            #if DEBUG
            print("[BatchWebSocket] ✅ Backend acknowledged ready signal")
            #endif
            return
        }

        let decoder = JSONDecoder()

        // Use unified WebSocket schema (Phase 1 #363)
        do {
            let message = try decoder.decode(TypedWebSocketMessage.self, from: data)

            #if DEBUG
            print("[BatchWebSocket] Decoded message type: \(message.type), pipeline: \(message.pipeline)")
            #endif

            // Verify this is for ai_scan pipeline
            guard message.pipeline == .aiScan else {
                #if DEBUG
                print("[BatchWebSocket] ⚠️ Ignoring message for different pipeline: \(message.pipeline)")
                #endif
                return
            }

            switch message.payload {
            case .jobStarted(let startedPayload):
                #if DEBUG
                print("[BatchWebSocket] Job started: \(startedPayload.totalCount ?? 0) items")
                #endif
                // Initialize BatchProgress with totalCount
                await initializeBatchProgress(totalPhotos: startedPayload.totalCount ?? 0)

            case .jobProgress(let progressPayload):
                await processProgressUpdate(progressPayload)

            case .reconnected(let reconnectedPayload):
                await processProgressUpdate(reconnectedPayload.toJobProgressPayload())

            case .jobComplete(let completePayload):
                // Extract AI scan-specific completion data
                guard case .aiScan(let aiPayload) = completePayload else {
                    #if DEBUG
                    print("[BatchWebSocket] ❌ Wrong completion payload type for ai_scan")
                    #endif
                    return
                }
                await processCompletion(aiPayload)

            case .error(let errorPayload):
                #if DEBUG
                print("[BatchWebSocket] ❌ Error: \(errorPayload.message)")
                #endif
                // Notify error via callback if needed

            // Batch-specific messages (Section 7.6)
            case .batchInit(let initPayload):
                #if DEBUG
                print("[BatchWebSocket] Batch init: \(initPayload.totalPhotos) photos, status: \(initPayload.status)")
                #endif
                await initializeBatchProgress(totalPhotos: initPayload.totalPhotos)

            case .batchProgress(let batchProgressPayload):
                #if DEBUG
                print("[BatchWebSocket] Batch progress: photo \(batchProgressPayload.currentPhoto)/\(batchProgressPayload.totalPhotos)")
                #endif
                await processBatchProgress(batchProgressPayload)

            case .batchComplete(let batchCompletePayload):
                #if DEBUG
                print("[BatchWebSocket] Batch complete: \(batchCompletePayload.totalBooks) total books")
                #endif
                await processBatchComplete(batchCompletePayload)

            case .batchCanceling(let cancelPayload):
                #if DEBUG
                print("[BatchWebSocket] Batch canceling: \(cancelPayload.reason ?? "no reason")")
                #endif
                disconnect()

            case .readyAck, .ping, .pong:
                // Infrastructure messages, no action needed
                // readyAck: Backend acknowledgment of client ready signal
                // ping/pong: Heartbeat messages
                break
            }

        } catch {
            #if DEBUG
            print("[BatchWebSocket] ❌ Failed to decode message: \(error)")
            print("[BatchWebSocket] Raw message: \(text)")
            #endif
        }
    }

    /// Initialize BatchProgress object
    private func initializeBatchProgress(totalPhotos: Int) async {
        // Store totalPhotos for later use
        self.totalPhotos = totalPhotos

        // Extract values before crossing actor boundary
        let jobId = self.jobId

        await MainActor.run {
            let progress = BatchProgress(jobId: jobId, totalPhotos: totalPhotos)
            onProgress(progress)
        }
    }

    /// Update batch progress on main thread
    private func processProgressUpdate(_ progressPayload: JobProgressPayload) async {
        // Extract values before crossing actor boundary
        let progress = progressPayload.progress
        let status = progressPayload.status
        let processedCount = progressPayload.processedCount ?? 0
        let currentItem = progressPayload.currentItem
        let jobId = self.jobId
        let totalPhotos = self.totalPhotos

        // Update stored status
        self.currentOverallStatus = status

        await MainActor.run {
            #if DEBUG
            if let currentItem = currentItem {
                print("[BatchWebSocket] Progress: \(Int(progress * 100))% - \(status) (Item: \(currentItem), Processed: \(processedCount))")
            } else {
                print("[BatchWebSocket] Progress: \(Int(progress * 100))% - \(status)")
            }
            #endif

            // Create fresh BatchProgress instance with current state
            let batchProgress = BatchProgress(jobId: jobId, totalPhotos: totalPhotos)
            batchProgress.overallStatus = status

            // Update current photo index if provided
            if let currentItem = currentItem, let photoIndex = Int(currentItem) {
                batchProgress.currentPhotoIndex = photoIndex
                batchProgress.updatePhoto(index: photoIndex, status: .processing)
            }

            // Call the callback with updated progress
            onProgress(batchProgress)
        }
    }

    /// Handle batch completion (v2.0 summary format)
    private func processCompletion(_ aiPayload: AIScanCompletePayload) async {
        // Extract values from summary before crossing actor boundary
        let totalDetected = aiPayload.summary.totalDetected ?? 0
        let approved = aiPayload.summary.approved ?? 0
        let needsReview = aiPayload.summary.needsReview ?? 0
        let jobId = self.jobId
        let totalPhotos = self.totalPhotos

        await MainActor.run {
            #if DEBUG
            print("[BatchWebSocket] Batch complete: \(totalDetected) books detected (\(approved) approved, \(needsReview) need review)")
            #endif

            // Create fresh BatchProgress instance with final state
            let batchProgress = BatchProgress(jobId: jobId, totalPhotos: totalPhotos)
            batchProgress.complete(totalBooks: totalDetected)

            // Call the callback with final progress
            onProgress(batchProgress)
        }

        disconnect()
    }

    /// Handle batch progress (unified schema batch-progress message)
    private func processBatchProgress(_ batchProgressPayload: BatchProgressPayload) async {
        // Extract values before crossing actor boundary
        let currentPhoto = batchProgressPayload.currentPhoto
        let totalPhotos = batchProgressPayload.totalPhotos
        let totalBooksFound = batchProgressPayload.totalBooksFound
        let jobId = self.jobId

        await MainActor.run {
            #if DEBUG
            print("[BatchWebSocket] Batch progress: Photo \(currentPhoto)/\(totalPhotos), Books: \(totalBooksFound)")
            #endif

            // Create fresh BatchProgress instance
            let batchProgress = BatchProgress(jobId: jobId, totalPhotos: totalPhotos)
            batchProgress.currentPhotoIndex = currentPhoto
            batchProgress.totalBooksFound = totalBooksFound

            // Update individual photo statuses from payload
            for photoData in batchProgressPayload.photos {
                let status: PhotoStatus
                switch photoData.status.lowercased() {
                case "queued": status = .queued
                case "processing": status = .processing
                case "complete": status = .complete
                case "error": status = .error
                default: status = .queued
                }

                batchProgress.updatePhoto(
                    index: photoData.index,
                    status: status,
                    error: photoData.error
                )
            }

            // Call the callback with updated progress
            onProgress(batchProgress)
        }
    }

    /// Handle batch completion (unified schema batch-complete message)
    private func processBatchComplete(_ batchCompletePayload: BatchCompletePayload) async {
        // Extract values before crossing actor boundary
        let totalBooks = batchCompletePayload.totalBooks
        let jobId = self.jobId
        let totalPhotos = self.totalPhotos

        await MainActor.run {
            #if DEBUG
            print("[BatchWebSocket] Batch complete: \(totalBooks) total books detected")
            #endif

            // Create fresh BatchProgress instance with final state
            let batchProgress = BatchProgress(jobId: jobId, totalPhotos: totalPhotos)

            // Update individual photo results
            for photoResult in batchCompletePayload.photoResults {
                let status: PhotoStatus
                switch photoResult.status.lowercased() {
                case "complete": status = .complete
                case "error": status = .error
                default: status = .complete
                }

                batchProgress.updatePhoto(
                    index: photoResult.index,
                    status: status,
                    error: photoResult.error
                )
            }

            batchProgress.complete(totalBooks: totalBooks)

            // Call the callback with final progress
            onProgress(batchProgress)
        }

        disconnect()
    }

    /// Close WebSocket connection
    func disconnect() {
        guard isConnected else { return }

        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        isConnected = false

        #if DEBUG
        print("[BatchWebSocket] Disconnected for job \(jobId)")
        #endif
    }
}

#endif // os(iOS)