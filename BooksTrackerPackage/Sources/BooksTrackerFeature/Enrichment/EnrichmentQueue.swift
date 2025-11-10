import Foundation
import SwiftData

// MARK: - Timeout Error

/// Error thrown when enrichment activity timeout is reached
struct EnrichmentTimeoutError: Error, LocalizedError {
    let timeout: TimeInterval

    var errorDescription: String? {
        let minutes = Int(timeout / 60)
        let minuteString = minutes > 1 ? "minutes" : "minute"
        return "Enrichment timed out after \(minutes) \(minuteString) of inactivity. The backend may be experiencing issues. Please try again."
    }
}

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
    // Activity tracking for timeout watchdog
    private var lastActivityTime = Date()

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
        // Early exit if queue is empty - avoid unnecessary work
        guard !queue.isEmpty else {
            print("✅ EnrichmentQueue empty - skipping validation")
            return
        }

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

    /// Start background enrichment process with activity-based timeout
    /// - Parameters:
    ///   - modelContext: SwiftData model context for database operations
    ///   - progressHandler: Callback with (processed, total, currentTitle)
    ///   - timeoutDuration: Timeout duration in seconds (default: 300 = 5 minutes)
    public func startProcessing(
        in modelContext: ModelContext,
        progressHandler: @escaping (Int, Int, String) -> Void,
        timeoutDuration: TimeInterval = 300
    ) {
        guard !processing else { return }
        guard !queue.isEmpty else { return }

        processing = true
        let totalCount = queue.count

        NotificationCoordinator.postEnrichmentStarted(totalBooks: totalCount)

        currentTask = Task { @MainActor in
            // ✅ GUARANTEE cleanup on ALL exit paths (success, timeout, error, cancellation)
            defer {
                self.processing = false
                self.webSocketHandler?.disconnect()
                self.webSocketHandler = nil
                self.clearCurrentJobId()
                print("🧹 Enrichment cleanup executed")
            }

            let workIDs = self.getAllPending()
            let works = workIDs.compactMap { modelContext.work(for: $0) }

            guard !works.isEmpty else {
                self.clear()
                NotificationCoordinator.postEnrichmentCompleted()
                return
            }

            let jobId = UUID().uuidString
            self.setCurrentJobId(jobId)

            // Reset activity timer at start
            self.lastActivityTime = Date()

            do {
                // ✅ Structured concurrency: Race enrichment task vs timeout watchdog
                try await withThrowingTaskGroup(of: Void.self) { group in
                    // Task 1: WebSocket enrichment processing
                    group.addTask {
                        await self.runEnrichment(
                            works: works,
                            jobId: jobId,
                            modelContext: modelContext,
                            progressHandler: progressHandler
                        )
                    }

                    // Task 2: Activity timeout watchdog
                    group.addTask {
                        try await self.activityTimeoutWatchdog(timeoutDuration: timeoutDuration)
                    }

                    // Wait for FIRST task to complete (enrichment success OR timeout)
                    try await group.next()

                    // Cancel remaining tasks
                    group.cancelAll()
                }

                // Success path
                print("✅ Enrichment completed successfully")
                self.clear()
                NotificationCoordinator.postEnrichmentCompleted()

            } catch let error as EnrichmentTimeoutError {
                // Timeout path
                print("⏱️ Enrichment timed out after \(Int(timeoutDuration))s of inactivity")
                NotificationCoordinator.postEnrichmentFailed(
                    error: error.localizedDescription
                )
            } catch is CancellationError {
                // User cancellation path
                print("🛑 Enrichment canceled by user")
                NotificationCoordinator.postEnrichmentCompleted()
            } catch {
                // Other errors
                print("❌ Enrichment failed: \(error)")
                NotificationCoordinator.postEnrichmentFailed(error: error.localizedDescription)
            }
        }
    }

    /// Run the enrichment process (extracted for clarity)
    private func runEnrichment(
        works: [Work],
        jobId: String,
        modelContext: ModelContext,
        progressHandler: @escaping (Int, Int, String) -> Void
    ) async {
        self.webSocketHandler = EnrichmentWebSocketHandler(
            jobId: jobId,
            progressHandler: { [weak self] processed, total, title in
                // ✅ Reset activity timer on EVERY WebSocket message
                self?.resetActivityTimer()
                progressHandler(processed, total, title)
                NotificationCoordinator.postEnrichmentProgress(completed: processed, total: total, currentTitle: title)
            },
            completionHandler: { [weak self] enrichedBooks in
                guard let self = self else { return }
                // ✅ Reset activity timer on completion message
                self.resetActivityTimer()
                // Apply enriched data to SwiftData models
                self.applyEnrichedData(enrichedBooks, in: modelContext)
            }
        )
        await self.webSocketHandler?.connect()

        _ = await EnrichmentService.shared.batchEnrichWorks(works, jobId: jobId, in: modelContext)

        print("✅ Batch enrichment job accepted. \(works.count) books queued for background processing via WebSocket")
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
            let url = EnrichmentConfig.enrichmentCancelURL
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

    /**
     Resets the enrichment activity timer to the current time.

     - Important: This method **must** be called whenever enrichment activity occurs, such as when receiving WebSocket messages or when enrichment completions are processed. Failure to call this method will result in premature timeouts and interruption of enrichment jobs.

     - Note: This method is automatically called by the WebSocket handler callbacks. If you manually trigger enrichment activity outside of those handlers, you are responsible for calling this method.

     - Thread Safety: Must be called on MainActor.
     */
    public func resetActivityTimer() {
        lastActivityTime = Date()
    }

    /// Activity timeout watchdog - throws TimeoutError if no activity for specified duration
    /// - Parameter timeoutDuration: Duration in seconds before timeout (default: 300 = 5 minutes)
    /// - Parameter clock: Injectable time provider for testing (default: Date())
    private func activityTimeoutWatchdog(
        timeoutDuration: TimeInterval = 300,
        clock: @escaping @MainActor () -> Date = { Date() }
    ) async throws {
        while !Task.isCancelled {
            let timeSinceActivity = clock().timeIntervalSince(lastActivityTime)

            if timeSinceActivity > timeoutDuration {
                print("⏱️ Enrichment timeout: No activity for \(Int(timeSinceActivity))s (limit: \(Int(timeoutDuration))s)")
                throw EnrichmentTimeoutError(timeout: timeoutDuration)
            }

            // Check every 10 seconds
            try await Task.sleep(for: .seconds(10))
        }
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

    // MARK: - Enriched Data Application

    /// Apply enriched data from backend to SwiftData models
    /// Called when WebSocket receives complete message with enriched books
    private func applyEnrichedData(_ enrichedBooks: [EnrichedBookPayload], in modelContext: ModelContext) {
        print("📚 Applying enriched data for \(enrichedBooks.count) books")

        var saveCounter = 0
        for enrichedBook in enrichedBooks {
            guard enrichedBook.success,
                  let enrichedData = enrichedBook.enriched else {
                print("⏭️ Skipping \(enrichedBook.title) - no enriched data")
                continue
            }

            // Enhanced ID-based matching (Issue #313)
            // Priority 1: openLibraryWorkID (most reliable)
            // Priority 2: googleBooksVolumeID
            // Priority 3: Multi-field fallback (title + author + year)

            var work: Work?
            var matchMethod: String = "unknown"

            // Try openLibraryWorkID first
            if let olWorkId = enrichedData.work.openLibraryWorkID {
                let olDescriptor = FetchDescriptor<Work>(
                    predicate: #Predicate { w in
                        w.openLibraryWorkID == olWorkId
                    }
                )
                if let works = try? modelContext.fetch(olDescriptor), let matched = works.first {
                    work = matched
                    matchMethod = "openLibraryWorkID"
                }
            }

            // Fallback to googleBooksVolumeID
            if work == nil, let gbVolumeId = enrichedData.work.googleBooksVolumeID {
                let gbDescriptor = FetchDescriptor<Work>(
                    predicate: #Predicate { w in
                        w.googleBooksVolumeID == gbVolumeId
                    }
                )
                if let works = try? modelContext.fetch(gbDescriptor), let matched = works.first {
                    work = matched
                    matchMethod = "googleBooksVolumeID"
                }
            }

            // Final fallback: title + author + year (multi-field validation)
            if work == nil {
                let workTitle = enrichedBook.title
                let titleDescriptor = FetchDescriptor<Work>(
                    predicate: #Predicate { w in
                        w.title.localizedStandardContains(workTitle)
                    }
                )

                if let candidates = try? modelContext.fetch(titleDescriptor) {
                    // Filter by author name if available
                    let primaryAuthor = enrichedData.authors.first?.name
                    let publicationYear = enrichedData.work.firstPublicationYear

                    for candidate in candidates {
                        var authorMatch = true
                        var yearMatch = true

                        // Check author match if we have author data
                        if let primaryAuthor = primaryAuthor {
                            authorMatch = candidate.authors?.contains(where: { author in
                                author.name.localizedStandardContains(primaryAuthor) ||
                                primaryAuthor.localizedStandardContains(author.name)
                            }) ?? false
                        }

                        // Check year match if we have year data (allow ±1 year tolerance)
                        if let publicationYear = publicationYear, let candidateYear = candidate.firstPublicationYear {
                            yearMatch = abs(candidateYear - publicationYear) <= 1
                        }

                        if authorMatch && yearMatch {
                            work = candidate
                            matchMethod = "title+author+year"
                            break
                        }
                    }

                    // If no multi-field match, fall back to first title match (legacy behavior)
                    if work == nil, let firstCandidate = candidates.first {
                        work = firstCandidate
                        matchMethod = "title-only (legacy)"
                    }
                }
            }

            guard let work = work else {
                print("⚠️ Could not find work for '\(enrichedBook.title)' (match failed)")
                continue
            }

            print("✅ Matched '\(enrichedBook.title)' via \(matchMethod)")

            // Update work metadata
            if work.firstPublicationYear == nil, let year = enrichedData.work.firstPublicationYear {
                work.firstPublicationYear = year
            }

            if work.openLibraryWorkID == nil, let olWorkId = enrichedData.work.openLibraryWorkID {
                work.openLibraryWorkID = olWorkId
            }

            if work.googleBooksVolumeID == nil, let gbVolumeId = enrichedData.work.googleBooksVolumeID {
                work.googleBooksVolumeID = gbVolumeId
            }

            // Find or create edition
            var edition: Edition?

            if let existingEditions = work.editions, !existingEditions.isEmpty {
                edition = existingEditions.first
            }

            // Create new edition if needed and we have data
            if edition == nil, let editionDTO = enrichedData.edition, let isbn = editionDTO.isbn, !isbn.isEmpty {
                // Only create edition if we have a valid ISBN

                let newEdition = Edition(
                    isbn: isbn,
                    publisher: editionDTO.publisher,
                    publicationDate: editionDTO.publicationDate,
                    pageCount: editionDTO.pageCount,
                    format: .paperback,
                    coverImageURL: editionDTO.coverImageURL  // ✅ Cover image!
                )
                modelContext.insert(newEdition)  // Get temporary ID

                // Set relationship AFTER both are inserted
                newEdition.work = work

                // CRITICAL: Save immediately to convert temporary IDs to permanent IDs
                // This prevents "Illegal attempt to create a full future for a temporary identifier" crashes
                do {
                    try modelContext.save()
                    edition = newEdition
                    print("✅ Created edition with cover: \(editionDTO.coverImageURL ?? "nil")")
                } catch {
                    print("❌ Failed to save new edition: \(error)")
                    continue
                }
            }

            // Update existing edition with cover image
            if let edition = edition, let editionDTO = enrichedData.edition {
                if edition.coverImageURL == nil, let coverURL = editionDTO.coverImageURL {
                    edition.coverImageURL = coverURL
                    print("✅ Updated edition cover for '\(work.title)': \(coverURL)")
                }

                if edition.pageCount == nil, let pageCount = editionDTO.pageCount {
                    edition.pageCount = pageCount
                }

                if edition.publisher == nil, let publisher = editionDTO.publisher {
                    edition.publisher = publisher
                }

                if let isbn = editionDTO.isbn {
                    edition.addISBN(isbn)
                }

                edition.touch()
            }

            // Fallback: If no edition exists, use Work-level cover image (added in PR #290)
            // This handles books enriched without ISBNs (e.g., from CSV imports)
            if edition == nil, work.coverImageURL == nil {
                if let workCoverURL = enrichedData.work.coverImageURL {
                    work.coverImageURL = workCoverURL
                    print("✅ Updated Work-level cover for '\(work.title)' (no edition): \(workCoverURL)")
                } else if let editionCoverURL = enrichedData.edition?.coverImageURL {
                    work.coverImageURL = editionCoverURL
                    print("✅ Updated Work-level cover for '\(work.title)' (from edition data): \(editionCoverURL)")
                }
            }

            work.touch()

            saveCounter += 1

            // Incremental saves every 10 books to:
            // 1. Convert temporary IDs to permanent IDs progressively
            // 2. Reduce memory pressure (don't keep all 98 books dirty)
            // 3. Allow UI to update incrementally
            if saveCounter % 10 == 0 {
                do {
                    try modelContext.save()
                    print("💾 Incremental save: \(saveCounter)/\(enrichedBooks.count) books processed")
                } catch {
                    print("❌ Failed incremental save at \(saveCounter) books: \(error)")
                }
            }
        }

        // Final save for remaining books (if total wasn't multiple of 10)
        do {
            try modelContext.save()
            print("✅ Successfully applied enriched data to \(enrichedBooks.count) books")
        } catch {
            print("❌ Failed final save of enriched data: \(error)")
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
