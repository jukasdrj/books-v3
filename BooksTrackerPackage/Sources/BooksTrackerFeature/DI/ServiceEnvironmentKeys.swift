import SwiftUI
import SwiftData
import Combine

// MARK: - EnrichmentService Protocol

/// Protocol abstraction for enrichment service
/// Enables dependency injection and testability
@MainActor
public protocol EnrichmentServiceProtocol: Sendable {
    /// Enrich a single work with metadata from the API
    func enrichWork(
        _ work: Work,
        in modelContext: ModelContext
    ) async -> EnrichmentResult

    /// Enrich a batch of works with metadata from the API
    func batchEnrichWorks(
        _ works: [Work],
        jobId: String,
        in modelContext: ModelContext
    ) async -> BatchEnrichmentResult

    /// Get enrichment statistics
    func getStatistics() -> EnrichmentStatistics

    /// Enrich a book by barcode (V2 API)
    func enrichBookV2(
        barcode: String,
        in modelContext: ModelContext
    ) async -> Result<Work, EnrichmentError>
}

// MARK: - EnrichmentQueue Protocol

/// Protocol abstraction for enrichment queue
/// Enables dependency injection and testability
@MainActor
public protocol EnrichmentQueueProtocol: Sendable {
    /// Books currently being enriched
    var activeEnrichments: Set<PersistentIdentifier> { get }

    /// Completion events publisher
    var completionEvents: PassthroughSubject<EnrichmentQueue.EnrichmentCompletionEvent, Never> { get }

    /// Add a work to the enrichment queue
    func enqueue(workID: PersistentIdentifier, priority: Int)

    /// Add multiple works to the queue
    func enqueueBatch(_ workIDs: [PersistentIdentifier])

    /// Move a specific work to the front of the queue
    func prioritize(workID: PersistentIdentifier)

    /// Remove a work from the queue
    func dequeue(workID: PersistentIdentifier)

    /// Get the next work to enrich
    func next() -> PersistentIdentifier?

    /// Remove and return the next work to enrich
    func pop() -> PersistentIdentifier?

    /// Get current queue size
    func count() -> Int

    /// Get all queued work IDs as strings
    func getQueuedWorkIds() -> [String]

    /// Clear all items from the queue
    func clearQueue()

    /// Validate queue on startup
    func validateQueue(in modelContext: ModelContext)

    /// Check if queue is empty
    func isEmpty() -> Bool

    /// Get all pending work IDs
    func getAllPending() -> [PersistentIdentifier]

    /// Start background enrichment process
    func startProcessing(
        in modelContext: ModelContext,
        progressHandler: @escaping (Int, Int, String) -> Void,
        timeoutDuration: TimeInterval
    )

    /// Stop background processing
    func stop() async

    /// Cancel the backend enrichment job
    func cancelBackendJob() async

    /// Check if currently processing
    func isProcessing() -> Bool

    /// Set the current backend job ID
    func setCurrentJobId(_ jobId: String)

    /// Get the current backend job ID
    func getCurrentJobId() -> String?

    /// Clear the current job ID
    func clearCurrentJobId()

    /// Reset the enrichment activity timer
    func resetActivityTimer()
}

// MARK: - Default Service Holders (Swift 6 Concurrency Safe)

/// Thread-safe holder for default EnrichmentService instance
/// Uses @unchecked Sendable since we know the service is always accessed from MainActor in SwiftUI
@MainActor
private final class DefaultEnrichmentServiceHolder: @unchecked Sendable {
    static let shared = DefaultEnrichmentServiceHolder()
    let service: any EnrichmentServiceProtocol = EnrichmentService()
}

/// Thread-safe holder for default EnrichmentQueue instance
@MainActor
private final class DefaultEnrichmentQueueHolder: @unchecked Sendable {
    static let shared = DefaultEnrichmentQueueHolder()
    let queue: any EnrichmentQueueProtocol = EnrichmentQueue()
}

// MARK: - Environment Keys

private struct EnrichmentServiceKey: EnvironmentKey {
    // Use placeholder that will be replaced by the actual service from the holder
    // The actual value is provided via .environment() in BooksTrackerApp
    static let defaultValue: any EnrichmentServiceProtocol = PlaceholderEnrichmentService()
}

private struct EnrichmentQueueKey: EnvironmentKey {
    // Use placeholder that will be replaced by the actual queue from the holder
    // The actual value is provided via .environment() in BooksTrackerApp
    static let defaultValue: any EnrichmentQueueProtocol = PlaceholderEnrichmentQueue()
}

// MARK: - Placeholder Implementations (for default values)

/// Placeholder that crashes if used directly - forces proper DI setup in app
private final class PlaceholderEnrichmentService: EnrichmentServiceProtocol, @unchecked Sendable {
    func enrichWork(_ work: Work, in modelContext: ModelContext) async -> EnrichmentResult {
        fatalError("EnrichmentService not injected via .environment(). Configure in BooksTrackerApp.")
    }

    func batchEnrichWorks(_ works: [Work], jobId: String, in modelContext: ModelContext) async -> BatchEnrichmentResult {
        fatalError("EnrichmentService not injected via .environment(). Configure in BooksTrackerApp.")
    }

    func getStatistics() -> EnrichmentStatistics {
        fatalError("EnrichmentService not injected via .environment(). Configure in BooksTrackerApp.")
    }

    func enrichBookV2(barcode: String, in modelContext: ModelContext) async -> Result<Work, EnrichmentError> {
        fatalError("EnrichmentService not injected via .environment(). Configure in BooksTrackerApp.")
    }
}

/// Placeholder that crashes if used directly - forces proper DI setup in app
private final class PlaceholderEnrichmentQueue: EnrichmentQueueProtocol, @unchecked Sendable {
    var activeEnrichments: Set<PersistentIdentifier> { fatalError("EnrichmentQueue not injected") }
    var completionEvents: PassthroughSubject<EnrichmentQueue.EnrichmentCompletionEvent, Never> { fatalError("EnrichmentQueue not injected") }

    func enqueue(workID: PersistentIdentifier, priority: Int) { fatalError("EnrichmentQueue not injected") }
    func enqueueBatch(_ workIDs: [PersistentIdentifier]) { fatalError("EnrichmentQueue not injected") }
    func prioritize(workID: PersistentIdentifier) { fatalError("EnrichmentQueue not injected") }
    func dequeue(workID: PersistentIdentifier) { fatalError("EnrichmentQueue not injected") }
    func next() -> PersistentIdentifier? { fatalError("EnrichmentQueue not injected") }
    func pop() -> PersistentIdentifier? { fatalError("EnrichmentQueue not injected") }
    func count() -> Int { fatalError("EnrichmentQueue not injected") }
    func getQueuedWorkIds() -> [String] { fatalError("EnrichmentQueue not injected") }
    func clearQueue() { fatalError("EnrichmentQueue not injected") }
    func validateQueue(in modelContext: ModelContext) { fatalError("EnrichmentQueue not injected") }
    func isEmpty() -> Bool { fatalError("EnrichmentQueue not injected") }
    func getAllPending() -> [PersistentIdentifier] { fatalError("EnrichmentQueue not injected") }
    func startProcessing(in modelContext: ModelContext, progressHandler: @escaping (Int, Int, String) -> Void, timeoutDuration: TimeInterval) { fatalError("EnrichmentQueue not injected") }
    func stop() async { fatalError("EnrichmentQueue not injected") }
    func cancelBackendJob() async { fatalError("EnrichmentQueue not injected") }
    func isProcessing() -> Bool { fatalError("EnrichmentQueue not injected") }
    func setCurrentJobId(_ jobId: String) { fatalError("EnrichmentQueue not injected") }
    func getCurrentJobId() -> String? { fatalError("EnrichmentQueue not injected") }
    func clearCurrentJobId() { fatalError("EnrichmentQueue not injected") }
    func resetActivityTimer() { fatalError("EnrichmentQueue not injected") }
}

extension EnvironmentValues {
    @MainActor
    public var enrichmentService: any EnrichmentServiceProtocol {
        get { self[EnrichmentServiceKey.self] }
        set { self[EnrichmentServiceKey.self] = newValue }
    }

    @MainActor
    public var enrichmentQueue: any EnrichmentQueueProtocol {
        get { self[EnrichmentQueueKey.self] }
        set { self[EnrichmentQueueKey.self] = newValue }
    }
}
