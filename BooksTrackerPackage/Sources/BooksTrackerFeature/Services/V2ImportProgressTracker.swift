import Foundation

/// V2 API import progress tracker with SSE and polling fallback
/// Automatically switches to polling if SSE reconnection fails 3 times
///
/// **Architecture:**
/// - Primary: SSE streaming for real-time progress
/// - Fallback: HTTP polling every 10 seconds
/// - Auto-reconnect: SSE handles network transitions
///
/// **Usage:**
/// ```swift
/// let tracker = V2ImportProgressTracker()
/// 
/// await tracker.startTracking(jobId: "import_123") { progress in
///     await MainActor.run {
///         updateUI(progress)
///     }
/// }
/// ```
actor V2ImportProgressTracker {
    
    // MARK: - Properties
    
    private var sseClient: SSEClient?
    private var pollingTask: Task<Void, Never>?
    private var isUsingPolling = false
    private let pollingInterval: TimeInterval = 10.0  // 10 seconds
    private var currentJobId: String?
    
    // MARK: - Public API
    
    /// Start tracking import progress for a job
    /// - Parameters:
    ///   - jobId: Import job ID
    ///   - authToken: Optional authentication token
    ///   - onProgress: Progress update callback
    ///   - onComplete: Completion callback
    ///   - onError: Error callback
    func startTracking(
        jobId: String,
        authToken: String? = nil,
        onProgress: @escaping @Sendable (Double, Int, Int) -> Void,
        onComplete: @escaping @Sendable (SSEImportResult) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) async {
        currentJobId = jobId
        
        // Try SSE first
        let client = SSEClient()
        sseClient = client
        
        // Set up SSE callbacks
        await client.onProgress = { progress, processed, total in
            onProgress(progress, processed, total)
        }
        
        await client.onComplete = { result in
            onComplete(result)
        }
        
        await client.onError = { error in
            // If SSE fails, switch to polling
            #if DEBUG
            print("[V2Tracker] SSE error: \(error), switching to polling")
            #endif
            
            Task {
                await self.switchToPolling(
                    onProgress: onProgress,
                    onComplete: onComplete,
                    onError: onError
                )
            }
        }
        
        // Connect to SSE
        do {
            try await client.connect(jobId: jobId, authToken: authToken)
            #if DEBUG
            print("[V2Tracker] Using SSE for job \(jobId)")
            #endif
        } catch {
            #if DEBUG
            print("[V2Tracker] SSE connection failed: \(error), falling back to polling")
            #endif
            onError(error)
            
            // Fall back to polling immediately
            await switchToPolling(
                onProgress: onProgress,
                onComplete: onComplete,
                onError: onError
            )
        }
    }
    
    /// Stop tracking progress
    func stopTracking() {
        pollingTask?.cancel()
        pollingTask = nil
        
        if let client = sseClient {
            Task {
                await client.disconnect()
            }
        }
        sseClient = nil
        currentJobId = nil
        isUsingPolling = false
        
        #if DEBUG
        print("[V2Tracker] Stopped tracking")
        #endif
    }
    
    /// Check if currently using polling fallback
    func isPolling() -> Bool {
        return isUsingPolling
    }
    
    // MARK: - Private Methods
    
    private func switchToPolling(
        onProgress: @escaping @Sendable (Double, Int, Int) -> Void,
        onComplete: @escaping @Sendable (SSEImportResult) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) async {
        guard let jobId = currentJobId else { return }
        
        // Disconnect SSE if still connected
        if let client = sseClient {
            await client.disconnect()
        }
        sseClient = nil
        isUsingPolling = true
        
        #if DEBUG
        print("[V2Tracker] Starting polling for job \(jobId)")
        #endif
        
        // Start polling task
        pollingTask = Task {
            await pollJobStatus(
                jobId: jobId,
                onProgress: onProgress,
                onComplete: onComplete,
                onError: onError
            )
        }
    }
    
    private func pollJobStatus(
        jobId: String,
        onProgress: @Sendable (Double, Int, Int) -> Void,
        onComplete: @Sendable (SSEImportResult) -> Void,
        onError: @Sendable (Error) -> Void
    ) async {
        while !Task.isCancelled {
            do {
                // Poll status endpoint
                let status = try await GeminiCSVImportService.shared.checkV2JobStatus(jobId: jobId)
                
                // Update progress
                let processed = status.processedRows ?? 0
                let total = status.totalRows ?? 0
                onProgress(status.progress, processed, total)
                
                // Check if job is complete
                if status.status == "complete" {
                    // Convert V2ImportStatus to SSEImportResult
                    let result = SSEImportResult(
                        status: status.status,
                        progress: status.progress,
                        resultSummary: status.resultSummary.map { summary in
                            SSEImportResult.ResultSummary(
                                booksCreated: summary.booksCreated,
                                booksUpdated: summary.booksUpdated,
                                duplicatesSkipped: summary.duplicatesSkipped,
                                enrichmentSucceeded: summary.enrichmentSucceeded,
                                enrichmentFailed: summary.enrichmentFailed,
                                errors: summary.errors?.map { error in
                                    SSEImportResult.ImportErrorDetail(
                                        row: error.row,
                                        isbn: error.isbn,
                                        error: error.error
                                    )
                                }
                            )
                        }
                    )
                    onComplete(result)
                    break
                }
                
                // Check if job failed
                if status.status == "failed" {
                    onError(SSEError.jobFailed(status.error ?? "Unknown error"))
                    break
                }
                
                // Wait before next poll
                try await Task.sleep(for: .seconds(pollingInterval))
                
            } catch {
                onError(error)
                break
            }
        }
        
        #if DEBUG
        print("[V2Tracker] Polling stopped")
        #endif
    }
}
