import Foundation
import SwiftData
import SwiftUI

/// Orchestrates multi-step background jobs (CSV import, enrichment)
/// Uses PollingUtility for backend polling and JobModels for type-safe tracking
@MainActor
@Observable
public final class SyncCoordinator {

    // MARK: - Public Properties

    public private(set) var activeJobId: JobIdentifier?
    public private(set) var jobStatus: [JobIdentifier: JobStatus] = [:]

    // MARK: - Singleton

    public static let shared = SyncCoordinator()

    // MARK: - Initialization

    private init() {
        // Private initializer for singleton pattern
    }

    // MARK: - Public Methods

    /// Get current status for a job
    public func getJobStatus(for jobId: JobIdentifier) -> JobStatus? {
        return jobStatus[jobId]
    }

    /// Cancel an active job
    public func cancelJob(_ jobId: JobIdentifier) {
        jobStatus[jobId] = .cancelled
        if activeJobId == jobId {
            activeJobId = nil
        }
    }

    // MARK: - Enrichment Orchestration

    /// Start enrichment job for queued works
    /// - Parameters:
    ///   - modelContext: SwiftData model context for persistence
    ///   - enrichmentQueue: EnrichmentQueue instance (defaults to .shared)
    /// - Returns: Job identifier for tracking
    @discardableResult
    public func startEnrichment(
        modelContext: ModelContext,
        enrichmentQueue: EnrichmentQueue = .shared
    ) async -> JobIdentifier {

        let jobId = JobIdentifier(jobType: "enrichment")
        activeJobId = jobId
        jobStatus[jobId] = .queued

        // Get total items to enrich
        let totalItems = enrichmentQueue.count()

        // Start with initial progress
        var progress = JobProgress(
            totalItems: totalItems,
            processedItems: 0,
            currentStatus: "Starting enrichment..."
        )
        jobStatus[jobId] = .active(progress: progress)

        // Start enrichment with progress tracking
        enrichmentQueue.startProcessing(in: modelContext) { [weak self] processedCount, totalCount, currentTitle in
            guard let self = self else { return }

            // Update progress
            progress.processedItems = processedCount
            progress.currentStatus = "Enriching: \(currentTitle)"
            self.jobStatus[jobId] = .active(progress: progress)
        }

        // Wait for enrichment to complete
        // EnrichmentQueue runs in background Task, so we poll for completion
        while !enrichmentQueue.isEmpty() {
            try? await Task.sleep(for: .milliseconds(500))

            // Check if job was cancelled
            if let status = jobStatus[jobId], status == .cancelled {
                enrichmentQueue.stopProcessing()
                break
            }
        }

        // Update final status
        if let status = jobStatus[jobId], status == .cancelled {
            // Already cancelled
        } else {
            let log = [
                "✅ Enrichment completed successfully",
                "📊 Total items: \(totalItems)",
                "✅ Processed: \(progress.processedItems)"
            ]
            jobStatus[jobId] = .completed(log: log)
        }

        // Clear active job
        if activeJobId == jobId {
            activeJobId = nil
        }

        return jobId
    }

    // MARK: - WebSocket-Based Enrichment (New!)

    /// Start enrichment job with WebSocket progress tracking
    /// Replaces polling with real-time server push updates
    /// - Parameters:
    ///   - modelContext: SwiftData model context for persistence
    ///   - enrichmentQueue: EnrichmentQueue instance (defaults to .shared)
    ///   - webSocketManager: WebSocket manager (defaults to new instance)
    /// - Returns: Job identifier for tracking
    @discardableResult
    public func startEnrichmentWithWebSocket(
        modelContext: ModelContext,
        enrichmentQueue: EnrichmentQueue = .shared,
        webSocketManager: WebSocketProgressManager? = nil
    ) async -> JobIdentifier {

        let jobId = JobIdentifier(jobType: "enrichment_ws")
        activeJobId = jobId
        jobStatus[jobId] = .queued

        // Create or use provided WebSocket manager
        let wsManager = webSocketManager ?? WebSocketProgressManager()

        // Get work IDs and convert to Books
        let workIDs = enrichmentQueue.getAllPending()
        let works = workIDs.compactMap { modelContext.work(for: $0) }

        let books = works.map { work in
            Book(
                title: work.title.normalizedTitleForSearch,
                author: work.primaryAuthorName,
                isbn: work.editions?.first?.isbn
            )
        }

        // Initial progress
        let progress = JobProgress(
            totalItems: books.count,
            processedItems: 0,
            currentStatus: "Connecting..."
        )
        jobStatus[jobId] = .active(progress: progress)

        // Connect WebSocket
        await wsManager.connect(jobId: jobId.id.uuidString) { [weak self] receivedProgress in
            guard let self = self else { return }

            // Update job status with WebSocket progress
            self.jobStatus[jobId] = .active(progress: receivedProgress)
        }

        // Trigger backend enrichment via API
        do {
            let enrichmentAPI = EnrichmentAPIClient()
            let result = try await enrichmentAPI.startEnrichment(
                jobId: jobId.id.uuidString,
                books: books
            )

            // Track the job ID for potential cancellation
            EnrichmentQueue.shared.setCurrentJobId(jobId.id.uuidString)

            // Wait for WebSocket to receive all updates
            // Connection will close automatically when backend finishes
            try? await Task.sleep(for: .seconds(1))

            let log = [
                "✅ Enrichment completed successfully",
                "📊 Total items: \(result.totalCount)",
                "✅ Processed: \(result.processedCount)"
            ]
            jobStatus[jobId] = .completed(log: log)

            // Clear job ID when complete
            EnrichmentQueue.shared.clearCurrentJobId()

        } catch {
            jobStatus[jobId] = .failed(error: error.localizedDescription)

            // Clear job ID on error
            EnrichmentQueue.shared.clearCurrentJobId()
        }

        // Cleanup
        wsManager.disconnect()

        if activeJobId == jobId {
            activeJobId = nil
        }

        return jobId
    }
}
