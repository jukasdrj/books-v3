import Foundation
import SwiftData
import os.log

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

    private let logger = Logger(subsystem: "com.oooefam.booksV3", category: "EnrichmentQueue")
    private var queue: [EnrichmentQueueItem] = []
    private var processing: Bool = false
    private var currentTask: Task<Void, Never>?
    private var webSocketHandler: GenericWebSocketHandler?
    // Track current backend job ID for cancellation
    private var currentJobId: String?
    // Activity tracking for timeout watchdog
    private var lastActivityTime = Date()
    // Watchdog task for cancellation on successful completion
    private var watchdogTask: Task<Void, Error>?

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
        logger.debug("📚 [ENRICHMENT] enqueueBatch() called with \(workIDs.count) IDs")
        logger.debug("📚 [ENRICHMENT] Context: @MainActor isolation")
        workIDs.prefix(3).enumerated().forEach { index, id in
            logger.debug("  [\(index)] ID: \(String(describing: id))")
        }
        if workIDs.count > 3 {
            logger.debug("  ... and \(workIDs.count - 3) more")
        }

        for workID in workIDs {
            enqueue(workID: workID)
        }

        logger.debug("📚 [ENRICHMENT] Queue now has \(self.queue.count) items total")
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
        #if DEBUG
        print("🧹 EnrichmentQueue cleared")
        #endif
    }

    /// Validate queue on startup - remove invalid persistent IDs
    public func validateQueue(in modelContext: ModelContext) {
        // Early exit if queue is empty - avoid unnecessary work
        guard !queue.isEmpty else {
            #if DEBUG
            print("✅ EnrichmentQueue empty - skipping validation")
            #endif
            return
        }

        let initialCount = queue.count

        queue.removeAll { item in
            // Try to fetch the work - if it fails, remove from queue
            if modelContext.model(for: item.workPersistentID) as? Work == nil {
                #if DEBUG
                print("🧹 Removing invalid work ID from queue")
                #endif
                return true  // Remove this item
            }
            return false  // Keep this item
        }

        let removedCount = initialCount - queue.count
        if removedCount > 0 {
            #if DEBUG
            print("🧹 Queue cleanup: Removed \(removedCount) invalid items (was \(initialCount), now \(queue.count))")
            #endif
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
                self.watchdogTask?.cancel()
                self.watchdogTask = nil
                self.clearCurrentJobId()
                #if DEBUG
                print("🧹 Enrichment cleanup executed")
                #endif
            }

            let workIDs = self.getAllPending()
            let works = workIDs.compactMap { modelContext.work(for: $0) }

            #if DEBUG
            print("[DEBUGGER:EnrichmentQueue:startProcessing:242] workIDs.count=\(workIDs.count), works.count=\(works.count)")
            #endif
            
            logger.debug("📚 [ENRICHMENT] Fetched \(works.count)/\(workIDs.count) works from context")
            if works.isEmpty && !workIDs.isEmpty {
                #if DEBUG
                print("[DEBUGGER:EnrichmentQueue:startProcessing:249] CONTEXT MERGE ISSUE DETECTED!")
                print("[DEBUGGER:EnrichmentQueue:startProcessing:250] Queue has \(workIDs.count) IDs but 0 works resolved")
                print("[DEBUGGER:EnrichmentQueue:startProcessing:251] First 3 IDs: \(workIDs.prefix(3))")
                #endif
                logger.warning("⚠️ [ENRICHMENT] All persistent IDs returned nil! Possible cross-context issue.")
                logger.debug("⚠️ [ENRICHMENT] This usually means:")
                logger.debug("   1. Works were created in different ModelContext (actor/background)")
                logger.debug("   2. Main context hasn't merged changes yet (need polling)")
                logger.debug("   3. Works were deleted after queueing")
            }

            guard !works.isEmpty else {
                #if DEBUG
                print("[DEBUGGER:EnrichmentQueue:startProcessing:263] EARLY EXIT - clearing queue and returning")
                #endif
                self.clear()
                NotificationCoordinator.postEnrichmentCompleted()
                return
            }

            // Reset activity timer at start
            self.lastActivityTime = Date()

            do {
                // Start watchdog task in background
                let watchdogTask = Task { [weak self] in
                    guard let self = self else { return }
                    try await self.activityTimeoutWatchdog(timeoutDuration: timeoutDuration)
                }

                defer {
                    // Cancel watchdog when batch processing completes (success or error)
                    watchdogTask.cancel()
                }

                // Split into 100-book chunks
                let batchSize = 100
                let batches = stride(from: 0, to: works.count, by: batchSize).map {
                    Array(works[$0 ..< min($0 + batchSize, works.count)])
                }
                var processedCount = 0

                for (index, batch) in batches.enumerated() {
                    if Task.isCancelled { throw CancellationError() }

                    logger.info("📦 Processing batch \(index + 1) of \(batches.count)...")

                    let jobId = UUID().uuidString
                    self.setCurrentJobId(jobId)

                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        Task { @MainActor in
                            #if DEBUG
                            print("📤 Sending batch enrichment POST request...")
                            #endif

                            let enrichmentResult = await EnrichmentService.shared.batchEnrichWorks(batch, jobId: jobId, in: modelContext)

                            guard let token = enrichmentResult.token, !token.isEmpty else {
                                #if DEBUG
                                print("⚠️ No authentication token available, skipping WebSocket connection")
                                #endif
                                continuation.resume(throwing: EnrichmentError.apiError("Failed to get enrichment token for batch \(index + 1). The backend may have rejected the request."))
                                return
                            }

                            var components = URLComponents(string: "\(EnrichmentConfig.webSocketBaseURL)/ws/progress")!
                            components.queryItems = [
                                URLQueryItem(name: "jobId", value: jobId),
                                URLQueryItem(name: "token", value: token)
                            ]

                            guard let wsURL = components.url else {
                                continuation.resume(throwing: EnrichmentError.invalidURL)
                                return
                            }

                            #if DEBUG
                            print("🔌 Connecting WebSocket for batch \(index + 1)...")
                            #endif

                            self.webSocketHandler = GenericWebSocketHandler(
                                url: wsURL,
                                pipeline: .batchEnrichment,
                                progressHandler: { [weak self] progressPayload in
                                    self?.resetActivityTimer()
                                    let batchProcessed = progressPayload.processedCount ?? 0
                                    let totalForUI = works.count
                                    let currentTitle = progressPayload.currentItem ?? "Unknown"
                                    let overallProcessed = processedCount + batchProcessed

                                    let progressTitle = "(\(index + 1)/\(batches.count)) \(currentTitle)"

                                    progressHandler(overallProcessed, totalForUI, progressTitle)
                                    NotificationCoordinator.postEnrichmentProgress(completed: overallProcessed, total: totalForUI, currentTitle: progressTitle)
                                },
                                completionHandler: { [weak self] completePayload in
                                    guard let self = self else { return }
                                    self.resetActivityTimer()
                                    guard case .batchEnrichment(let batchPayload) = completePayload else {
                                        #if DEBUG
                                        print("⚠️ Unexpected payload type for batch enrichment completion")
                                        #endif
                                        continuation.resume()
                                        return
                                    }

                                    self.applyEnrichedData(batchPayload.enrichedBooks, in: modelContext)

                                    continuation.resume()
                                },
                                errorHandler: { errorPayload in
                                    #if DEBUG
                                    print("❌ WebSocket enrichment error for batch \(index + 1): \(errorPayload.message)")
                                    #endif
                                    NotificationCoordinator.postEnrichmentFailed(error: errorPayload.message)
                                    continuation.resume(throwing: EnrichmentError.apiError(errorPayload.message))
                                }
                            )
                            await self.webSocketHandler?.connect()
                        }
                    }
                    processedCount += batch.count
                }

                // Success - all batches completed
                #if DEBUG
                print("✅ All enrichment batches completed successfully")
                #endif
                self.clear()
                NotificationCoordinator.postEnrichmentCompleted()

            } catch let error as EnrichmentTimeoutError {
                // Timeout path
                #if DEBUG
                print("⏱️ Enrichment timed out after \(Int(timeoutDuration))s of inactivity")
                #endif
                NotificationCoordinator.postEnrichmentFailed(
                    error: error.localizedDescription
                )
            } catch {
                // Other errors
                #if DEBUG
                print("❌ Enrichment failed: \(error)")
                #endif
                NotificationCoordinator.postEnrichmentFailed(error: error.localizedDescription)
            }
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
            #if DEBUG
            print("⚠️ No active backend job to cancel")
            #endif
            return
        }

        #if DEBUG
        print("🛑 Canceling backend job: \(jobId)")
        #endif

        do {
            let url = EnrichmentConfig.enrichmentCancelURL
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body = ["jobId": jobId]
            request.httpBody = try JSONEncoder().encode(body)

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                #if DEBUG
                print("✅ Backend job canceled successfully: \(jobId)")
                #endif
            } else {
                #if DEBUG
                print("⚠️ Backend job cancellation returned non-200 status")
                #endif
            }

            // Clear the job ID
            clearCurrentJobId()

        } catch {
            #if DEBUG
            print("❌ Failed to cancel backend job: \(error)")
            #endif
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
                #if DEBUG
                print("⏱️ Enrichment timeout: No activity for \(Int(timeSinceActivity))s (limit: \(Int(timeoutDuration))s)")
                #endif
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
        #if DEBUG
        print("📚 Applying enriched data for \(enrichedBooks.count) books")
        #endif

        var saveCounter = 0
        for enrichedBook in enrichedBooks {
            guard enrichedBook.success,
                  let enrichedData = enrichedBook.enriched else {
                #if DEBUG
                let reason = enrichedBook.error ?? "no enriched data available"
                print("⏭️ Skipping \(enrichedBook.title) - \(reason)")
                #endif
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
                #if DEBUG
                print("⚠️ Could not find work for '\(enrichedBook.title)' (match failed)")
                #endif
                continue
            }

            #if DEBUG
            print("✅ Matched '\(enrichedBook.title)' via \(matchMethod)")
            #endif

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
                    #if DEBUG
                    print("✅ Created edition with cover: \(editionDTO.coverImageURL ?? "nil")")
                    #endif
                } catch {
                    #if DEBUG
                    print("❌ Failed to save new edition: \(error)")
                    #endif
                    continue
                }
            }

            // Update existing edition with cover image
            if let edition = edition, let editionDTO = enrichedData.edition {
                if edition.coverImageURL == nil, let coverURL = editionDTO.coverImageURL {
                    edition.coverImageURL = coverURL
                    #if DEBUG
                    print("✅ Updated edition cover for '\(work.title)': \(coverURL)")
                    #endif
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

            // Always populate Work-level cover for CoverImageService fallback (Issue #346 + CLAUDE.md)
            // CoverImageService uses Work.coverImageURL as fallback when Edition is missing/has no cover
            // This ensures covers display consistently even when Edition selection changes
            logger.debug("📚 [APPLY] Checking Work-level cover for '\(work.title)'")
            logger.debug("  - Edition exists: \(edition != nil)")
            logger.debug("  - Edition has cover: \(edition?.coverImageURL != nil)")
            logger.debug("  - Work has cover: \(work.coverImageURL != nil)")
            logger.debug("  - Enriched data has work cover: \(enrichedData.work.coverImageURL != nil)")

            if work.coverImageURL == nil {
                if let workCoverURL = enrichedData.work.coverImageURL {
                    work.coverImageURL = workCoverURL
                    logger.debug("✅ Updated Work-level cover for '\(work.title)': \(workCoverURL)")
                } else if let editionCoverURL = enrichedData.edition?.coverImageURL {
                    work.coverImageURL = editionCoverURL
                    logger.debug("✅ Updated Work-level cover for '\(work.title)' (from edition data): \(editionCoverURL)")
                } else {
                    logger.warning("⚠️ No cover image available for '\(work.title)' in enriched data (Issue #346)")
                    logger.debug("   - enrichedData.work.coverImageURL: \(String(describing: enrichedData.work.coverImageURL))")
                    logger.debug("   - enrichedData.edition?.coverImageURL: \(String(describing: enrichedData.edition?.coverImageURL))")
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
                    #if DEBUG
                    print("💾 Incremental save: \(saveCounter)/\(enrichedBooks.count) books processed")
                    #endif
                } catch {
                    #if DEBUG
                    print("❌ Failed incremental save at \(saveCounter) books: \(error)")
                    #endif
                }
            }
        }

        // Final save for remaining books (if total wasn't multiple of 10)
        do {
            try modelContext.save()
            #if DEBUG
            print("✅ Successfully applied enriched data to \(enrichedBooks.count) books")
            #endif
        } catch {
            #if DEBUG
            print("❌ Failed final save of enriched data: \(error)")
            #endif
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
