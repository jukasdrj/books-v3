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
            logger.debug("  [\(index)] ID: \(id)")
        }
        if workIDs.count > 3 {
            logger.debug("  ... and \(workIDs.count - 3) more")
        }

        for workID in workIDs {
            enqueue(workID: workID)
        }

        logger.debug("📚 [ENRICHMENT] Queue now has \(queue.count) items total")
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
                self.clearCurrentJobId()
                #if DEBUG
                print("🧹 Enrichment cleanup executed")
                #endif
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

            // Start watchdog in background - it will throw TimeoutError if inactive too long
            let watchdog = Task<Void, Error> { @MainActor [weak self] in
                guard let self = self else { return }
                try await self.activityTimeoutWatchdog(timeoutDuration: timeoutDuration)
            }

            do {
                // Run enrichment (returns immediately after starting WebSocket)
                await self.runEnrichment(
                    works: works,
                    jobId: jobId,
                    modelContext: modelContext,
                    progressHandler: progressHandler
                )

                // Wait for watchdog to complete or throw (it monitors WebSocket activity)
                try await watchdog.value

                // Success - enrichment completed before timeout
                #if DEBUG
                print("✅ Enrichment completed successfully")
                #endif
                self.clear()
                NotificationCoordinator.postEnrichmentCompleted()

            } catch let error as EnrichmentTimeoutError {
                // Timeout path
                watchdog.cancel()
                #if DEBUG
                print("⏱️ Enrichment timed out after \(Int(timeoutDuration))s of inactivity")
                #endif
                NotificationCoordinator.postEnrichmentFailed(
                    error: error.localizedDescription
                )
            } catch is CancellationError {
                // User cancellation path
                watchdog.cancel()
                #if DEBUG
                print("🛑 Enrichment canceled by user")
                #endif
                NotificationCoordinator.postEnrichmentCompleted()
            } catch {
                // Other errors
                watchdog.cancel()
                #if DEBUG
                print("❌ Enrichment failed: \(error)")
                #endif
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
        // ✅ CRITICAL FIX: Send POST request FIRST to create Durable Object on backend
        // The backend creates the DO when it receives the POST request (batch-enrichment.js:128-129)
        // WebSocket connection will fail if DO doesn't exist yet!
        #if DEBUG
        print("📤 Sending batch enrichment POST request (creates DO)...")
        #endif

        let enrichmentResult = await EnrichmentService.shared.batchEnrichWorks(works, jobId: jobId, in: modelContext)

        #if DEBUG
        print("✅ Batch enrichment job accepted. \(works.count) books queued for background processing")
        #endif

        // ✅ Guard against nil/empty token (happens on enrichment API errors)
        guard let token = enrichmentResult.token, !token.isEmpty else {
            #if DEBUG
            print("⚠️ No authentication token available, skipping WebSocket connection")
            print("⚠️ Enrichment API may have returned an error")
            #endif
            return
        }

        // ✅ NOW connect WebSocket (DO exists on backend)
        // Use URLComponents for proper URL encoding
        var components = URLComponents(string: "\(EnrichmentConfig.webSocketBaseURL)/ws/progress")!
        components.queryItems = [
            URLQueryItem(name: "jobId", value: jobId),
            URLQueryItem(name: "token", value: token)
        ]

        guard let wsURL = components.url else {
            #if DEBUG
            print("❌ Invalid WebSocket URL")
            #endif
            return
        }

        #if DEBUG
        print("🔐 Using auth token: [REDACTED]")
        #endif

        #if DEBUG
        print("🔌 Connecting WebSocket for progress updates...")
        #endif

        self.webSocketHandler = GenericWebSocketHandler(
            url: wsURL,
            pipeline: .batchEnrichment,
            progressHandler: { [weak self] progressPayload in
                // ✅ Reset activity timer on EVERY WebSocket message
                self?.resetActivityTimer()

                // Extract data from JobProgressPayload
                let processed = progressPayload.processedCount ?? 0
                let total = works.count  // Use local total count
                let title = progressPayload.currentItem ?? "Unknown"

                progressHandler(processed, total, title)
                NotificationCoordinator.postEnrichmentProgress(completed: processed, total: total, currentTitle: title)
            },
            completionHandler: { [weak self] completePayload in
                guard let self = self else { return }
                // ✅ Reset activity timer on completion message
                self.resetActivityTimer()

                // Unwrap the batch enrichment case
                guard case .batchEnrichment(let batchPayload) = completePayload else {
                    #if DEBUG
                    print("⚠️ Unexpected payload type for batch enrichment")
                    #endif
                    return
                }

                let enrichedBooks = batchPayload.enrichedBooks

                // Apply enriched data to SwiftData models
                self.applyEnrichedData(enrichedBooks, in: modelContext)
            },
            errorHandler: { errorPayload in
                #if DEBUG
                print("❌ WebSocket enrichment error: \(errorPayload.message)")
                #endif
                NotificationCoordinator.postEnrichmentFailed(error: errorPayload.message)
            }
        )

        // Connect and wait for handshake (GenericWebSocketHandler already has waitForConnection + sendReadySignal)
        await self.webSocketHandler?.connect()

        #if DEBUG
        print("✅ WebSocket connected. Listening for enrichment progress updates...")
        #endif
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
                print("⏭️ Skipping \(enrichedBook.title) - no enriched data")
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

            // Fallback: If no edition exists OR edition has no cover, use Work-level cover image (PR #290 + Issue #346)
            // This handles books enriched without ISBNs (e.g., from CSV imports) OR edition creation failures
            logger.debug("📚 [APPLY] Checking Work-level cover fallback for '\(work.title)'")
            logger.debug("  - Edition exists: \(edition != nil)")
            logger.debug("  - Edition has cover: \(edition?.coverImageURL != nil)")
            logger.debug("  - Work has cover: \(work.coverImageURL != nil)")
            logger.debug("  - Enriched data has work cover: \(enrichedData.work.coverImageURL != nil)")

            if edition == nil || (edition != nil && edition!.coverImageURL == nil) {
                if work.coverImageURL == nil {
                    if let workCoverURL = enrichedData.work.coverImageURL {
                        work.coverImageURL = workCoverURL
                        logger.debug("✅ Updated Work-level cover for '\(work.title)' (no edition): \(workCoverURL)")
                    } else if let editionCoverURL = enrichedData.edition?.coverImageURL {
                        work.coverImageURL = editionCoverURL
                        logger.debug("✅ Updated Work-level cover for '\(work.title)' (from edition data): \(editionCoverURL)")
                    } else {
                        logger.warning("⚠️ No cover image available for '\(work.title)' in enriched data (Issue #346)")
                        logger.debug("   - enrichedData.work.coverImageURL: \(String(describing: enrichedData.work.coverImageURL))")
                        logger.debug("   - enrichedData.edition?.coverImageURL: \(String(describing: enrichedData.edition?.coverImageURL))")
                    }
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
