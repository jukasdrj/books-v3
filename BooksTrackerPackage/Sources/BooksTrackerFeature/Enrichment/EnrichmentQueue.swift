import Foundation
import SwiftData

// MARK: - Enrichment Queue
/// Priority queue for managing background enrichment of imported books
/// Supports FIFO ordering with ability to prioritize specific items (e.g., user scrolled to book)
/// MainActor-isolated for SwiftData compatibility
@MainActor
public final class EnrichmentQueue {
    public static let shared = EnrichmentQueue()

    // MARK: - Properties

    private var queue: [EnrichmentQueueItem] = []
    private var processing: Bool = false
    private var currentTask: Task<Void, Never>?
    private var webSocketHandler: EnrichmentWebSocketHandler?
    // Track current backend job ID for cancellation
    private var currentJobId: String?

    // Persistence
    private let queueStorageKey = "EnrichmentQueueStorage"

    // MARK: - Queue Item

    public struct EnrichmentQueueItem: Codable, Sendable, Identifiable {
        public let id: UUID
        public let workPersistentID: PersistentIdentifier
        public var priority: Int
        public let addedDate: Date

        public init(workPersistentID: PersistentIdentifier, priority: Int = 0) {
            self.id = UUID()
            self.workPersistentID = workPersistentID
            self.priority = priority
            self.addedDate = Date()
        }

        // Make the priority mutable for updates
        public mutating func setPriority(_ newPriority: Int) {
            priority = newPriority
        }
    }

    // MARK: - Initialization

    private init() {
        loadQueue()
    }

    // MARK: - Public Methods

    /// Add a work to the enrichment queue
    public func enqueue(workID: PersistentIdentifier, priority: Int = 0) {
        // Check if already in queue
        guard !queue.contains(where: { $0.workPersistentID == workID }) else {
            return
        }

        let item = EnrichmentQueueItem(workPersistentID: workID, priority: priority)
        queue.append(item)

        // Sort by priority (higher priority first), then by date (FIFO)
        queue.sort {
            if $0.priority == $1.priority {
                return $0.addedDate < $1.addedDate
            }
            return $0.priority > $1.priority
        }

        saveQueue()
    }

    /// Add multiple works to the queue
    public func enqueueBatch(_ workIDs: [PersistentIdentifier]) {
        for workID in workIDs {
            enqueue(workID: workID)
        }
    }

    /// Move a specific work to the front of the queue (e.g., user viewed it)
    public func prioritize(workID: PersistentIdentifier) {
        guard let index = queue.firstIndex(where: { $0.workPersistentID == workID }) else {
            // Not in queue - add it with high priority
            enqueue(workID: workID, priority: 1000)
            return
        }

        // Update priority and re-sort
        let item = queue[index]
        queue.remove(at: index)

        var mutableItem = item
        mutableItem.priority = 1000 // High priority
        queue.insert(mutableItem, at: 0) // Move to front

        saveQueue()
    }

    /// Remove a work from the queue
    public func dequeue(workID: PersistentIdentifier) {
        queue.removeAll { $0.workPersistentID == workID }
        saveQueue()
    }

    /// Get the next work to enrich (highest priority / oldest)
    public func next() -> PersistentIdentifier? {
        return queue.first?.workPersistentID
    }

    /// Remove and return the next work to enrich
    public func pop() -> PersistentIdentifier? {
        guard !queue.isEmpty else { return nil }
        let item = queue.removeFirst()
        saveQueue()
        return item.workPersistentID
    }

    /// Get current queue size
    public func count() -> Int {
        return queue.count
    }

    /// Get all queued work IDs as strings for API calls
    /// - Returns: Array of persistent identifier strings
    public func getQueuedWorkIds() -> [String] {
        return queue.map { "\($0.workPersistentID)" }
    }

    /// Clear all items from the queue
    public func clear() {
        queue.removeAll()
        saveQueue()
        print("🧹 EnrichmentQueue cleared")
    }

    /// Validate queue on startup - remove invalid persistent IDs
    public func validateQueue(in modelContext: ModelContext) {
        let initialCount = queue.count

        queue.removeAll { item in
            // Try to fetch the work - if it fails, remove from queue
            if modelContext.model(for: item.workPersistentID) as? Work == nil {
                print("🧹 Removing invalid work ID from queue")
                return true  // Remove this item
            }
            return false  // Keep this item
        }

        let removedCount = initialCount - queue.count
        if removedCount > 0 {
            print("🧹 Queue cleanup: Removed \(removedCount) invalid items (was \(initialCount), now \(queue.count))")
            saveQueue()  // Persist cleanup
        }
    }

    /// Check if queue is empty
    public func isEmpty() -> Bool {
        return queue.isEmpty
    }

    /// Get all pending work IDs (for debugging/monitoring)
    public func getAllPending() -> [PersistentIdentifier] {
        return queue.map { $0.workPersistentID }
    }

    // MARK: - Background Processing

    /// Start background enrichment process
    /// - Parameters:
    ///   - modelContext: SwiftData model context for database operations
    ///   - progressHandler: Callback with (processed, total, currentTitle)
    public func startProcessing(
        in modelContext: ModelContext,
        progressHandler: @escaping (Int, Int, String) -> Void
    ) {
        guard !processing else { return }
        guard !queue.isEmpty else { return }

        processing = true
        let totalCount = queue.count

        NotificationCoordinator.postEnrichmentStarted(totalBooks: totalCount)

        currentTask = Task { @MainActor in
            let workIDs = self.getAllPending()
            let works = workIDs.compactMap { modelContext.work(for: $0) }

            guard !works.isEmpty else {
                self.clear()
                processing = false
                NotificationCoordinator.postEnrichmentCompleted()
                return
            }

            let jobId = UUID().uuidString
            self.setCurrentJobId(jobId)

            self.webSocketHandler = EnrichmentWebSocketHandler(jobId: jobId, progressHandler: { processed, total, title in
                progressHandler(processed, total, title)
                NotificationCoordinator.postEnrichmentProgress(completed: processed, total: total, currentTitle: title)
            })
            self.webSocketHandler?.connect()

            let result = await EnrichmentService.shared.batchEnrichWorks(works, jobId: jobId, in: modelContext)

            self.webSocketHandler?.disconnect()
            self.webSocketHandler = nil

            if Task.isCancelled {
                processing = false
                return
            }

            print("✅ Batch enrichment complete. Success: \(result.successCount), Failed: \(result.failureCount)")

            self.clear()
            processing = false
            NotificationCoordinator.postEnrichmentCompleted()
        }
    }

    /// Stop background processing
    public func stopProcessing() {
        currentTask?.cancel()
        currentTask = nil
        processing = false
    }

    /// Cancel the backend enrichment job
    /// Sends cancellation request to Cloudflare Worker
    public func cancelBackendJob() async {
        guard let jobId = currentJobId else {
            print("⚠️ No active backend job to cancel")
            return
        }

        print("🛑 Canceling backend job: \(jobId)")

        do {
            let url = URL(string: "https://books-api-proxy.jukasdrj.workers.dev/api/enrichment/cancel")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body = ["jobId": jobId]
            request.httpBody = try JSONEncoder().encode(body)

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("✅ Backend job canceled successfully: \(jobId)")
            } else {
                print("⚠️ Backend job cancellation returned non-200 status")
            }

            // Clear the job ID
            clearCurrentJobId()

        } catch {
            print("❌ Failed to cancel backend job: \(error)")
            // Still clear the job ID - best effort
            clearCurrentJobId()
        }
    }

    /// Check if currently processing
    public func isProcessing() -> Bool {
        return processing
    }

    /// Set the current backend job ID (called when starting enrichment)
    public func setCurrentJobId(_ jobId: String) {
        currentJobId = jobId
    }

    /// Get the current backend job ID (used for cancellation)
    public func getCurrentJobId() -> String? {
        return currentJobId
    }

    /// Clear the current job ID (called when job completes)
    public func clearCurrentJobId() {
        currentJobId = nil
    }

    // MARK: - Persistence

    private func saveQueue() {
        // Encode queue to UserDefaults
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(queue) {
            UserDefaults.standard.set(encoded, forKey: queueStorageKey)
        }
    }

    private func loadQueue() {
        // Decode queue from UserDefaults
        guard let data = UserDefaults.standard.data(forKey: queueStorageKey) else {
            return
        }

        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode([EnrichmentQueueItem].self, from: data) {
            queue = decoded
        }
    }
}

// MARK: - Convenience Extension for ModelContext

extension ModelContext {
    /// Get a work by its persistent identifier
    public func work(for id: PersistentIdentifier) -> Work? {
        return model(for: id) as? Work
    }
}
