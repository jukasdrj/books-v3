import SwiftUI
import SwiftData
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#endif

// MARK: - CSV Import Job Results (v2.0)

/// Full job results fetched via HTTP GET after SSE completion
/// v2.0 Migration: SSE now sends lightweight summary, full results stored in KV cache
struct CSVImportJobResults: Codable, Sendable {
    let books: [CSVParsedBook]?
    let errors: [CSVImportError]?
}

/// CSV Import errors (distinct from CSVImportError DTO struct)
enum CSVImportViewError: Error, LocalizedError {
    case invalidResponse
    case emptyResults
    case resultsExpired          // Results no longer available in KV cache (> 24 hours)
    case rateLimited(retryAfter: Int?)
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .emptyResults:
            return "No results returned from server"
        case .resultsExpired:
            return "Results expired (job older than 24 hours). Please re-run the import."
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited. Try again in \(seconds)s."
            }
            return "Rate limited. Please try again later."
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        }
    }
}

// MARK: - Gemini CSV Import View

/// Simplified CSV import using Gemini AI for parsing with SSE progress tracking
/// No column mapping needed - Gemini handles intelligent parsing
@available(iOS 26.0, *)
@MainActor
public struct GeminiCSVImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.tabCoordinator) private var tabCoordinator
    @Environment(\.enrichmentQueue) private var enrichmentQueue

    @State private var showingFilePicker = false
    @State private var jobId: String?
    @State private var importStatus: ImportStatus = .idle
    @State private var progress: Double = 0.0
    @State private var statusMessage: String = ""
    @State private var errorMessage: String?
    @State private var sseClient: SSEClient?

    // Rate limit banner (Issue #426)
    @State private var showRateLimitBanner = false
    @State private var rateLimitRetryAfter = 0

    public init() {}

    public enum ImportStatus: Equatable {
        case idle
        case uploading
        case processing(progress: Double, message: String)
        case completed(books: [CSVParsedBook], errors: [CSVImportError])
        case failed(ErrorDetail)
    }

    // Helper to create ErrorDetail for local errors
    private func makeErrorDetail(code: String = "CLIENT_ERROR", message: String, retryable: Bool = false) -> ErrorDetail {
        ErrorDetail(message: message, code: code, retryable: retryable)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                // iOS 26 Liquid Glass background
                themeStore.backgroundGradient
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    // Rate Limit Banner (Issue #426)
                    if showRateLimitBanner {
                        RateLimitBanner(retryAfter: rateLimitRetryAfter) {
                            showRateLimitBanner = false
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    switch importStatus {
                    case .idle:
                        idleStateView

                    case .uploading:
                        uploadingView

                    case .processing(let progress, let message):
                        progressView(progress: progress, message: message)

                    case .completed(let books, let errors):
                        completedView(books: books, errors: errors)

                    case .failed(let error):
                        failedView(error: error)
                    }
                }
                .padding()
            }
            .navigationTitle("AI-Powered Import")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancelImport()
                        dismiss()
                    }
                    .disabled(importStatus == .uploading)
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
            .onDisappear {
                cancelImport()
            }
        }
    }

    // MARK: - Subviews

    private var idleStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 64))
                .foregroundStyle(themeStore.primaryColor)

            Text("AI-Powered CSV Import")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Gemini automatically detects book data\nNo column mapping needed!")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showingFilePicker = true
            } label: {
                Label("Select CSV File", systemImage: "doc.badge.plus")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(themeStore.primaryColor)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
        }
    }

    private var uploadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Uploading CSV...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }

    private func progressView(progress: Double, message: String) -> some View {
        VStack(spacing: 20) {
            ProgressView(value: progress) {
                Text("Processing")
                    .font(.headline)
            } currentValueLabel: {
                Text("\(Int(progress * 100))%")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .progressViewStyle(.linear)
            .tint(themeStore.primaryColor)

            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding()
    }

    private func completedView(books: [CSVParsedBook], errors: [CSVImportError]) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Import Complete")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text("✅ Successfully imported: \(books.count) books")
                if !errors.isEmpty {
                    Text("⚠️ Errors: \(errors.count) books")
                        .foregroundColor(.orange)
                }
            }
            .font(.body)

            if !errors.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(errors, id: \.title) { error in
                            HStack {
                                Text(error.title)
                                    .font(.caption)
                                Spacer()
                                Text(error.error)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .frame(maxHeight: 200)
            }

            Button {
                Task {
                    let success = await saveBooks(books)
                    if success {
                        // ✅ Fix #383: Switch to Library tab after CSV import success
                        tabCoordinator.switchToLibrary()
                        dismiss()
                    }
                    // If failed, saveBooks() already updated importStatus to .failed
                    // View will automatically switch to failedView
                }
            } label: {
                Text("Add to Library")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(themeStore.primaryColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func failedView(error: ErrorDetail) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundColor(.red)

            Text("Import Failed")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 8) {
                Text(error.message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Text("Error Code: \(error.code ?? "UNKNOWN")")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.6))

                if let retryable = error.retryable, retryable {
                    Label("This error is retryable", systemImage: "arrow.clockwise.circle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding()

            Button {
                importStatus = .idle
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(themeStore.primaryColor)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
        }
    }

    // MARK: - Import Logic

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await uploadCSV(from: url) }

        case .failure(let error):
            importStatus = .failed(makeErrorDetail(message: "File selection failed: \(error.localizedDescription)"))
        }
    }

    private func uploadCSV(from url: URL) async {
        importStatus = .uploading

        do {
            // Read CSV content
            guard url.startAccessingSecurityScopedResource() else {
                importStatus = .failed(makeErrorDetail(message: "Cannot access file"))
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let csvText = try String(contentsOf: url, encoding: .utf8)

            #if DEBUG
            print("[CSV Upload] 📄 CSV file read: \(csvText.count) characters, \(csvText.utf8.count) bytes")
            print("[CSV Upload] 📝 First 200 chars: \(csvText.prefix(200))")
            print("[CSV Upload] 📝 Last 200 chars: \(csvText.suffix(200))")
            let lineCount = csvText.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
            print("[CSV Upload] 📊 Total lines: \(lineCount)")
            #endif

            // Upload to V2 API and get jobId + authToken
            let service = GeminiCSVImportService.shared
            let (uploadedJobId, authToken) = try await service.uploadCSV(csvText: csvText)

            #if DEBUG
            print("[CSV Upload] ✅ Job created: \(uploadedJobId)")
            #endif

            // Start SSE stream for progress tracking
            jobId = uploadedJobId
            await startSSEStream(jobId: uploadedJobId, authToken: authToken)

        } catch let error as GeminiCSVImportError {
            importStatus = .failed(makeErrorDetail(message: error.localizedDescription))
        } catch {
            importStatus = .failed(makeErrorDetail(message: "Upload failed: \(error.localizedDescription)"))
        }
    }

    private func startSSEStream(jobId: String, authToken: String) async {
        #if DEBUG
        print("[CSV SSE] Starting SSE stream for job: \(jobId)")
        #endif

        // Connect to SSE stream and store client for cancellation support
        let (client, stream) = await GeminiCSVImportService.shared.streamImportProgress(jobId: jobId, authToken: authToken)
        sseClient = client

        // Track if SSE connection was successful (received at least one progress event)
        var sseSucceeded = false
        var connectionFailed = false
        var receivedAnyEvent = false

        // Timeout detection: If no events received within 60 seconds, fall back to polling
        // This handles the case where SSE connects but backend processing times out
        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(60))
            if !receivedAnyEvent && !Task.isCancelled {
                #if DEBUG
                print("[CSV SSE] ⏱️ Timeout: No events received in 60s, falling back to polling")
                #endif
                await client.disconnect()
            }
        }

        // Process events (AsyncStream doesn't throw - errors come via .failed events)
        for await event in stream {
            receivedAnyEvent = true
            timeoutTask.cancel() // Cancel timeout since we're receiving events

            switch event {
            case .csvImportProgress, .csvImportCompleted:
                sseSucceeded = true
            case .failed(let failure):
                // Check if this is a connection failure (not a job failure)
                if failure.status == "connection_failed" {
                    connectionFailed = true
                    #if DEBUG
                    print("[CSV SSE] ⚠️ Connection failed: \(failure.error)")
                    #endif
                    // CRITICAL FIX: Disconnect immediately to stop automatic reconnection
                    // Otherwise the stream never ends and fallback never triggers
                    await client.disconnect()
                    break // Exit the for-await loop
                }
            default:
                break
            }
            await handleSSEEvent(event)
        }

        timeoutTask.cancel() // Clean up timeout task

        #if DEBUG
        print("[CSV SSE] Stream ended for job: \(jobId), sseSucceeded: \(sseSucceeded), connectionFailed: \(connectionFailed), receivedAnyEvent: \(receivedAnyEvent)")
        #endif

        // If SSE failed to connect or timed out without events, fall back to polling
        if (connectionFailed || !receivedAnyEvent) && !sseSucceeded {
            #if DEBUG
            print("[CSV SSE] 🔄 SSE failed or timed out, falling back to polling for job: \(jobId)")
            #endif
            await startPollingFallback(jobId: jobId)
        }
    }

    /// Polling fallback when SSE connection fails
    /// Polls job status every 2 seconds until completed or failed
    private func startPollingFallback(jobId: String) async {
        #if DEBUG
        print("[CSV Polling] Starting polling fallback for job: \(jobId)")
        #endif

        let maxAttempts = 60 // 2 minutes max (60 * 2 seconds)
        var attempts = 0

        while attempts < maxAttempts, !Task.isCancelled {
            attempts += 1

            do {
                let status = try await GeminiCSVImportService.shared.checkJobStatus(jobId: jobId)

                #if DEBUG
                print("[CSV Polling] Attempt \(attempts): status=\(status.status), progress=\(status.progress ?? 0)")
                #endif

                switch status.status {
                case "processing", "queued":
                    // Update progress UI
                    let progressValue = status.progress ?? 0
                    await MainActor.run {
                        importStatus = .processing(
                            progress: progressValue,
                            message: status.message ?? "Processing..."
                        )
                    }

                case "completed":
                    #if DEBUG
                    print("[CSV Polling] ✅ Job completed, fetching results")
                    #endif
                    await fetchResults(jobId: jobId)
                    return

                case "failed":
                    #if DEBUG
                    print("[CSV Polling] ❌ Job failed: \(status.error ?? "Unknown error")")
                    #endif
                    await MainActor.run {
                        importStatus = .failed(makeErrorDetail(
                            code: "JOB_FAILED",
                            message: status.error ?? "Import failed"
                        ))
                    }
                    return

                default:
                    #if DEBUG
                    print("[CSV Polling] Unknown status: \(status.status)")
                    #endif
                }

                // Wait 2 seconds before next poll
                try await Task.sleep(for: .seconds(2))

            } catch {
                #if DEBUG
                print("[CSV Polling] ❌ Polling error: \(error.localizedDescription)")
                #endif
                // Don't fail immediately on polling error - retry a few times
                if attempts >= 3 {
                    await MainActor.run {
                        importStatus = .failed(makeErrorDetail(
                            code: "POLLING_FAILED",
                            message: "Failed to check import status: \(error.localizedDescription)"
                        ))
                    }
                    return
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }

        // Timeout after max attempts
        #if DEBUG
        print("[CSV Polling] ⏰ Polling timed out after \(maxAttempts) attempts")
        #endif
        await MainActor.run {
            importStatus = .failed(makeErrorDetail(
                code: "POLLING_TIMEOUT",
                message: "Import timed out. Please check your imports later."
            ))
        }
    }

    private func handleSSEEvent(_ event: EnrichmentEvent) async {
        await MainActor.run {
            switch event {
            case .csvImportProgress(let progress):
                #if DEBUG
                print("[CSV SSE] Progress: \(Int(progress.progress * 100))% - \(progress.status)")
                #endif
                let message = "Processing: \(progress.processedCount)/\(progress.totalCount) books"
                importStatus = .processing(
                    progress: progress.progress,  // Already 0.0-1.0
                    message: message
                )

            case .csvImportCompleted(let completion):
                #if DEBUG
                print("[CSV SSE] Completed event received, fetching results...")
                #endif
                // Fetch full results now that import is complete
                Task {
                    await fetchResults(jobId: completion.jobId)
                }

            case .csvImportFailed(let failure):
                #if DEBUG
                print("[CSV SSE] Failed: \(failure.error.message)")
                #endif
                importStatus = .failed(failure.error)

            default:
                // Ignore other event types (enrichment, photoscan)
                break
            }
        }
    }

    private func fetchResults(jobId: String) async {
        do {
            let results = try await GeminiCSVImportService.shared.fetchResults(jobId: jobId)

            #if DEBUG
            print("[CSV SSE] Results: \(results.books.count) books parsed")
            print("[CSV SSE] Success rate: \(results.successRate)")
            print("[CSV SSE] Errors: \(results.errors.count)")
            #endif

            await MainActor.run {
                // Results already in correct format
                importStatus = .completed(books: results.books, errors: results.errors)
            }

            // Save books in background
            _ = await saveBooks(results.books)

        } catch {
            #if DEBUG
            print("[CSV SSE] ❌ Failed to fetch results: \(error)")
            #endif

            await MainActor.run {
                importStatus = .failed(makeErrorDetail(code: "FETCH_RESULTS_FAILED", message: error.localizedDescription))
            }
        }
    }


    /// Fetch full job results from KV cache via HTTP GET
    /// V3 Migration: SSE sends lightweight summary, full results fetched on demand
    /// Results are cached for 24 hours after job completion
    private func fetchJobResults(jobId: String) async throws -> CSVImportJobResults {
        let baseURL = "https://api.oooefam.net"
        let url = URL(string: "\(baseURL)/v3/jobs/imports/\(jobId)/results")!

        #if DEBUG
        print("[CSV Import] 🌐 Fetching results from: \(url)")
        #endif

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CSVImportViewError.invalidResponse
        }

        #if DEBUG
        print("[CSV Import] 📡 HTTP Response: \(httpResponse.statusCode)")
        #endif

        switch httpResponse.statusCode {
        case 200:
            // Success - decode results using ResponseEnvelope
            let envelope = try JSONDecoder().decode(
                ResponseEnvelope<CSVImportJobResults>.self,
                from: data
            )

            // Check for API error in envelope
            if envelope.error != nil {
                throw CSVImportViewError.emptyResults
            }

            guard let results = envelope.data else {
                throw CSVImportViewError.emptyResults
            }

            return results

        case 404:
            // Results expired (> 24 hours old)
            throw CSVImportViewError.resultsExpired

        case 429:
            // Rate limited - use value(forHTTPHeaderField:) for reliable header access
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw CSVImportViewError.rateLimited(retryAfter: retryAfter)

        default:
            throw CSVImportViewError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    private func cancelImport() {
        // Cancel backend job if one is running
        if let jobId = jobId {
            Task {
                do {
                    try await GeminiCSVImportService.shared.cancelJob(jobId: jobId)
                    #if DEBUG
                    print("[CSV Import] ✅ Backend job canceled")
                    #endif
                } catch {
                    #if DEBUG
                    print("[CSV Import] ⚠️ Failed to cancel backend job: \(error.localizedDescription)")
                    #endif
                    // Continue with local cleanup even if backend cancel fails
                }
            }
        }

        // Disconnect SSE stream
        if let sseClient = sseClient {
            Task {
                await sseClient.disconnect()
                #if DEBUG
                print("[CSV Import] ✅ SSE stream disconnected")
                #endif
            }
        }
        sseClient = nil
    }

    @MainActor
    private func saveBooks(_ books: [CSVParsedBook]) async -> Bool {
        guard !books.isEmpty else {
            #if DEBUG
            print("⚠️ No books to save")
            #endif
            return false
        }

        #if DEBUG
        print("📚 Saving \(books.count) books to library using background import...")
        #endif

        // NEW: Use ImportService for background import
        let service = ImportService(modelContainer: modelContext.container)

        do {
            // Import in background (UI stays responsive!)
            // Actor fetches existing works in its own context for thread safety
            let result = try await service.importCSVBooks(books)

            #if DEBUG
            print("✅ Background import complete: \(result.successCount) saved, \(result.skippedCount) skipped, \(result.failedCount) failed in \(String(format: "%.2f", result.duration))s")
            if !result.errors.isEmpty {
                print("❌ Errors:")
                for error in result.errors {
                    print("  - \(error.title): \(error.message)")
                }
            }
            #endif

            // Enqueue saved works for enrichment using PersistentIdentifiers
            if !result.newWorkIDs.isEmpty {
                #if DEBUG
                print("📚 Enqueueing \(result.newWorkIDs.count) books for enrichment")
                #endif
                enrichmentQueue.enqueueBatch(result.newWorkIDs)

                // Start enrichment in background
                // Wait for SwiftData context merging with exponential backoff (Issue #467)
                // ImportService uses background actor context, main view uses different context
                Task {
                    let workIDs = result.newWorkIDs
                    let startTime = Date.now
                    let timeout: TimeInterval = 5.0

                    // Try immediate check first (often succeeds immediately)
                    var foundCount = workIDs.compactMap { modelContext.model(for: $0) as? Work }.count
                    if foundCount == workIDs.count {
                        #if DEBUG
                        print("📚 Context merge: Immediate (\(foundCount)/\(workIDs.count))")
                        #endif
                    } else {
                        // Exponential backoff: 250ms, 500ms, then 1s intervals
                        let intervals: [Duration] = [.milliseconds(250), .milliseconds(500), .milliseconds(1000)]
                        var intervalIndex = 0

                        while Date.now.timeIntervalSince(startTime) < timeout {
                            let currentInterval = intervals[min(intervalIndex, intervals.count - 1)]
                            try? await Task.sleep(for: currentInterval)

                            foundCount = workIDs.compactMap { modelContext.model(for: $0) as? Work }.count
                            if foundCount == workIDs.count {
                                break
                            }

                            intervalIndex += 1
                        }

                        #if DEBUG
                        let elapsed = Date.now.timeIntervalSince(startTime)
                        print("📚 Context merge: \(foundCount)/\(workIDs.count) in \(Int(elapsed * 1000))ms")
                        #endif
                    }

                    enrichmentQueue.startProcessing(
                        in: modelContext,
                        progressHandler: { completed, total, currentTitle in
                            #if DEBUG
                            print("📚 Enriching (\(completed)/\(total)): \(currentTitle)")
                            #endif
                        },
                        timeoutDuration: 300
                    )
                }
            }

            // Haptic feedback
            #if canImport(UIKit)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            #endif

            return true

        } catch {
            #if DEBUG
            print("❌ Background import failed: \(error)")
            #endif

            // Error haptic
            #if canImport(UIKit)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            #endif

            // Update UI with error
            importStatus = .failed(makeErrorDetail(code: "SAVE_FAILED", message: "Failed to save: \(error.localizedDescription)"))
            return false
        }
    }
}