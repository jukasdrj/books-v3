import SwiftUI
import SwiftData
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#endif

// MARK: - CSV Import Job Results (v2.0)

/// Full job results fetched via HTTP GET after WebSocket completion
/// v2.0 Migration: WebSocket now sends lightweight summary, full results stored in KV cache
struct CSVImportJobResults: Codable, Sendable {
    let books: [ParsedBook]?
    let errors: [ImportError]?
}

/// CSV Import errors
enum CSVImportError: Error, LocalizedError {
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

/// Simplified CSV import using Gemini AI for parsing with WebSocket progress
/// No column mapping needed - Gemini handles intelligent parsing
@available(iOS 26.0, *)
@MainActor
public struct GeminiCSVImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(TabCoordinator.self) private var tabCoordinator

    @State private var showingFilePicker = false
    @State private var jobId: String?
    @State private var importStatus: ImportStatus = .idle
    @State private var progress: Double = 0.0
    @State private var statusMessage: String = ""
    @State private var errorMessage: String?
    @State private var webSocketTask: URLSessionWebSocketTask?
    @State private var receiveTask: Task<Void, Never>?
    
    // V2 API SSE support
    @State private var progressTracker: V2ImportProgressTracker?

    // Rate limit banner (Issue #426)
    @State private var showRateLimitBanner = false
    @State private var rateLimitRetryAfter = 0
    
    // Computed property for V2 API feature flag
    private var useV2API: Bool {
        FeatureFlags.shared.useV2APIForImports
    }

    public init() {}

    public enum ImportStatus: Equatable {
        case idle
        case uploading
        case processing(progress: Double, message: String)
        case completed(books: [GeminiCSVImportJob.ParsedBook], errors: [GeminiCSVImportJob.ImportError])
        case failed(String)
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

    private func completedView(books: [GeminiCSVImportJob.ParsedBook], errors: [GeminiCSVImportJob.ImportError]) -> some View {
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

    private func failedView(error: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundColor(.red)

            Text("Import Failed")
                .font(.title2)
                .fontWeight(.semibold)

            Text(error)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
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
            importStatus = .failed("File selection failed: \(error.localizedDescription)")
        }
    }

    private func uploadCSV(from url: URL) async {
        // Use V2 API if feature flag is enabled
        if useV2API {
            await uploadCSVV2(from: url)
            return
        }
        
        // Otherwise use V1 WebSocket-based import
        importStatus = .uploading

        do {
            // Read CSV content
            guard url.startAccessingSecurityScopedResource() else {
                importStatus = .failed("Cannot access file")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let csvText = try String(contentsOf: url, encoding: .utf8)

            // Upload to backend and get auth token
            let service = GeminiCSVImportService.shared
            let (uploadedJobId, authToken) = try await service.uploadCSV(csvText: csvText)

            #if DEBUG
            print("[CSV Upload] 🔐 Auth token received (length: \(authToken.count))")
            #endif

            // Start WebSocket connection with authentication
            jobId = uploadedJobId
            startWebSocketProgress(jobId: uploadedJobId, token: authToken)

        } catch let error as GeminiCSVImportError {
            importStatus = .failed(error.localizedDescription)
        } catch {
            importStatus = .failed("Upload failed: \(error.localizedDescription)")
        }
    }
    
    /// Upload CSV using V2 API with SSE progress tracking
    private func uploadCSVV2(from url: URL) async {
        importStatus = .uploading
        
        do {
            // Read CSV content
            guard url.startAccessingSecurityScopedResource() else {
                importStatus = .failed("Cannot access file")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            let csvText = try String(contentsOf: url, encoding: .utf8)
            
            // Upload to V2 API
            let service = GeminiCSVImportService.shared
            let response = try await service.uploadCSVV2(csvText: csvText)
            
            #if DEBUG
            print("[CSV Upload V2] Job created: \(response.jobId)")
            print("[CSV Upload V2] SSE URL: \(response.sseUrl)")
            #endif
            
            // Start SSE-based progress tracking
            jobId = response.jobId
            await startV2ProgressTracking(jobId: response.jobId)
            
        } catch let error as GeminiCSVImportError {
            importStatus = .failed(error.localizedDescription)
        } catch {
            importStatus = .failed("Upload failed: \(error.localizedDescription)")
        }
    }
    
    /// Start V2 progress tracking with SSE and polling fallback
    private func startV2ProgressTracking(jobId: String) async {
        #if DEBUG
        print("[CSV V2] Starting SSE progress tracking for job \(jobId)")
        #endif
        
        let tracker = V2ImportProgressTracker()
        progressTracker = tracker
        
        await tracker.startTracking(jobId: jobId) { progress, processed, total in
            Task { @MainActor in
                let message = "Processing \(processed)/\(total) rows..."
                importStatus = .processing(progress: progress, message: message)
                
                #if DEBUG
                print("[CSV V2] Progress: \(Int(progress * 100))% - \(message)")
                #endif
            }
        } onComplete: { result in
            Task { @MainActor in
                #if DEBUG
                print("[CSV V2] Import complete!")
                #endif
                
                // Convert SSEImportResult to legacy format for UI compatibility
                let books = result.resultSummary.map { summary in
                    // Create placeholder books from summary stats
                    // Note: V2 API doesn't return individual book data in completion event
                    // Full results would need to be fetched separately if needed
                    [] as [GeminiCSVImportJob.ParsedBook]
                } ?? []
                
                let errors = result.resultSummary?.errors?.map { error in
                    GeminiCSVImportJob.ImportError(
                        title: error.isbn ?? "Row \(error.row ?? 0)",
                        error: error.error ?? "Unknown error"
                    )
                } ?? []
                
                // For now, show completion with summary stats
                let successCount = result.resultSummary?.booksCreated ?? 0
                let errorCount = result.resultSummary?.errors?.count ?? 0
                
                // Create synthetic books for display (actual saving happens on backend)
                // V2 API auto-saves to user's library, so we just show completion
                importStatus = .processing(
                    progress: 1.0,
                    message: "✅ Import complete! \(successCount) books added, \(errorCount) errors"
                )
                
                // Auto-dismiss and switch to library after brief delay
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    await MainActor.run {
                        tabCoordinator.switchToLibrary()
                        dismiss()
                    }
                }
            }
        } onError: { error in
            Task { @MainActor in
                #if DEBUG
                print("[CSV V2] Error: \(error)")
                #endif
                
                importStatus = .failed(error.localizedDescription)
            }
        }
    }

    private func startWebSocketProgress(jobId: String, token: String) {
        #if DEBUG
        print("[CSV WebSocket] Starting secure WebSocket connection (v2.4.1 compliant)")
        #endif

        receiveTask = Task {
            do {
                // ✅ SECURITY FIX (#7): Secure WebSocket authentication
                // Build WebSocket URL (jobId in query is OK, token MUST be in header)
                let wsURL = URL(string: "\(EnrichmentConfig.webSocketBaseURL)/ws/progress?jobId=\(jobId)")!

                // ✅ PROTOCOL FIX (#7): HTTP/1.1 enforcement for WebSocket compatibility
                // iOS defaults to HTTP/2 for HTTPS, which breaks RFC 6455 WebSocket upgrade
                var request = URLRequest(url: wsURL)
                request.assumesHTTP3Capable = false  // Forces HTTP/1.1 negotiation (disables HTTP/2 and HTTP/3)
                request.setValue("websocket", forHTTPHeaderField: "Upgrade")
                request.setValue("Upgrade", forHTTPHeaderField: "Connection")

                // ✅ SECURITY FIX (#7): Add token via Sec-WebSocket-Protocol header
                // This prevents token leakage in server logs, proxy logs, or error reports
                // Matches WebSocketProgressManager pattern (line 156 in WebSocketProgressManager.swift)
                request.setValue("bookstrack-auth.\(token)", forHTTPHeaderField: "Sec-WebSocket-Protocol")

                #if DEBUG
                print("[CSV WebSocket] 🔐 Token secured in Sec-WebSocket-Protocol header")
                print("[CSV WebSocket] 🌐 HTTP/1.1 enforcement enabled (assumesHTTP3Capable=false)")
                #endif

                // Create URLSession with HTTP/1.1 configuration
                let config = URLSessionConfiguration.default
                config.httpMaximumConnectionsPerHost = 1
                config.timeoutIntervalForRequest = 10.0  // 10 second timeout
                let session = URLSession(configuration: config)

                // Create and start WebSocket task
                let wsTask = session.webSocketTask(with: request)
                self.webSocketTask = wsTask
                wsTask.resume()

                #if DEBUG
                print("[CSV WebSocket] ⏳ Waiting for WebSocket handshake...")
                #endif

                // Wait for connection (prevents POSIX error 57 "Socket is not connected")
                try await WebSocketHelpers.waitForConnection(wsTask, timeout: 10.0)

                #if DEBUG
                print("[CSV WebSocket] ✅ WebSocket connection established")
                #endif

                // Send ready signal to backend
                let readyMessage: [String: Any] = [
                    "type": "ready",
                    "timestamp": Date().timeIntervalSince1970 * 1000
                ]
                if let messageData = try? JSONSerialization.data(withJSONObject: readyMessage),
                   let messageString = String(data: messageData, encoding: .utf8) {
                    try await wsTask.send(.string(messageString))
                    #if DEBUG
                    print("[CSV WebSocket] ✅ Sent ready signal to backend")
                    #endif
                }

                // Listen for messages
                #if DEBUG
                print("[CSV WebSocket] 📡 Listening for csv_import pipeline messages...")
                #endif

                while !Task.isCancelled {
                    let message = try await wsTask.receive()

                    switch message {
                    case .string(let text):
                        handleWebSocketMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            handleWebSocketMessage(text)
                        }
                    @unknown default:
                        break
                    }
                }

            } catch {
                #if DEBUG
                print("[CSV WebSocket] ❌ Error: \(String(describing: error))")
                #endif

                if !Task.isCancelled {
                    // Fall back to polling
                    importStatus = .processing(progress: 0.1, message: "Connecting via alternate method...")
                    await fallbackPollingForJobStatus(jobId: jobId)
                }
            }
        }
    }

    /// Fallback polling when WebSocket connection fails
    /// Used when backend closes connection after ready_ack (POSIX error 57)
    private func fallbackPollingForJobStatus(jobId: String) async {
        #if DEBUG
        print("[CSV Polling] Starting fallback polling for job \(jobId)")
        #endif

        let maxPolls = 60 // Poll for up to 5 minutes (60 * 5s = 5min)
        var pollCount = 0

        while pollCount < maxPolls && !Task.isCancelled {
            do {
                // Wait before polling (exponential backoff: 2s, 4s, then 5s)
                let delay: TimeInterval = min(5.0, 2.0 * pow(2.0, Double(min(pollCount, 2))))
                try await Task.sleep(for: .seconds(delay))

                pollCount += 1

                #if DEBUG
                print("[CSV Polling] Poll #\(pollCount) (every \(Int(delay))s)")
                #endif

                // Check job status via REST API
                let service = GeminiCSVImportService.shared
                let result = try await service.checkJobStatus(jobId: jobId)

                #if DEBUG
                print("[CSV Polling] Status: \(result.status)")
                #endif

                switch result.status {
                case "completed":
                    if let books = result.books, let errors = result.errors {
                        #if DEBUG
                        print("[CSV Polling] ✅ Job complete: \(books.count) books, \(errors.count) errors")
                        #endif
                        importStatus = .completed(books: books, errors: errors)
                        return
                    } else {
                        throw GeminiCSVImportError.serverError(500, "Job completed but missing data")
                    }

                case "failed":
                    let errorMsg = result.error ?? "Unknown error"
                    #if DEBUG
                    print("[CSV Polling] ❌ Job failed: \(errorMsg)")
                    #endif
                    importStatus = .failed(errorMsg)
                    return

                case "processing":
                    let progress = result.progress ?? 0.0
                    let message = result.message ?? "Processing..."
                    #if DEBUG
                    print("[CSV Polling] Processing: \(Int(progress * 100))% - \(message)")
                    #endif
                    importStatus = .processing(progress: progress, message: message)

                default:
                    #if DEBUG
                    print("[CSV Polling] Unknown status: \(result.status)")
                    #endif
                }

            } catch {
                #if DEBUG
                print("[CSV Polling] ❌ Error: \(error)")
                #endif
                if !Task.isCancelled {
                    importStatus = .failed("Polling failed: \(error.localizedDescription)")
                }
                return
            }
        }

        // Timeout after max polls
        if pollCount >= maxPolls {
            #if DEBUG
            print("[CSV Polling] ❌ Timeout after \(maxPolls) polls")
            #endif
            importStatus = .failed("Import timed out. Please try again.")
        }
    }

    private func handleWebSocketMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            #if DEBUG
            print("[CSV WebSocket] ❌ Failed to convert text to data")
            #endif
            return
        }

        // First check for legacy ready_ack message (backend still sends this without unified schema)
        if text.contains("\"type\":\"ready_ack\"") {
            #if DEBUG
            print("[CSV WebSocket] ✅ Backend acknowledged ready signal, processing will start")
            #endif
            return
        }

        do {
            // Use unified WebSocket schema (Phase 1 #363)
            let message = try JSONDecoder().decode(TypedWebSocketMessage.self, from: data)
            #if DEBUG
            print("[CSV WebSocket] Decoded message type: \(message.type), pipeline: \(message.pipeline)")
            #endif

            // Verify this is for csv_import pipeline
            guard message.pipeline == .csvImport else {
                #if DEBUG
                print("[CSV WebSocket] ⚠️ Ignoring message for different pipeline: \(message.pipeline)")
                #endif
                return
            }

            // Dispatch UI updates to MainActor (WebSocket runs on background thread)
            Task { @MainActor in
                switch message.payload {
                case .jobProgress(let progressPayload):
                    #if DEBUG
                    print("[CSV WebSocket] Progress: \(Int(progressPayload.progress * 100))% - \(progressPayload.status)")
                    #endif
                    importStatus = .processing(progress: progressPayload.progress, message: progressPayload.status)

                case .reconnected(let payload):
                    let syntheticProgress = payload.toJobProgressPayload()
                    #if DEBUG
                    print("[CSV WebSocket] Reconnected: \(Int(syntheticProgress.progress * 100))% - \(syntheticProgress.status)")
                    #endif
                    importStatus = .processing(progress: syntheticProgress.progress, message: syntheticProgress.status)

                case .jobComplete(let completePayload):
                    // Extract CSV-specific completion data
                    guard case .csvImport(let csvPayload) = completePayload else {
                        #if DEBUG
                        print("[CSV WebSocket] ❌ Wrong completion payload type for csv_import")
                        #endif
                        return
                    }

                    #if DEBUG
                    print("[CSV WebSocket] ✅ Import complete: \(csvPayload.summary.successCount) books processed, \(csvPayload.summary.failureCount) errors")
                    print("[CSV WebSocket] 📦 Fetching full results from KV cache (resourceId: \(csvPayload.summary.resourceId ?? "none"))")
                    #endif

                    // v2.0 Migration: Fetch full results via HTTP GET
                    // WebSocket now only sends lightweight summary (<1 KB)
                    // Full results stored in KV cache for 24 hours
                    guard let resourceId = csvPayload.summary.resourceId else {
                        #if DEBUG
                        print("[CSV WebSocket] ❌ No resourceId provided, cannot fetch results")
                        #endif
                        importStatus = .failed("No results available from backend")
                        return
                    }

                    // Extract jobId from resourceId format: "job-results:uuid"
                    let jobId = self.jobId ?? resourceId.replacingOccurrences(of: "job-results:", with: "")

                    // Fetch full results via HTTP
                    do {
                        let fullResults = try await fetchJobResults(jobId: jobId)

                        // Convert unified schema ParsedBook to legacy GeminiCSVImportJob.ParsedBook
                        let legacyBooks = (fullResults.books ?? []).map { book in
                            GeminiCSVImportJob.ParsedBook(
                                title: book.title,
                                author: book.author,
                                isbn: book.isbn,
                                coverUrl: book.coverUrl,
                                publisher: book.publisher,
                                publicationYear: book.publicationYear,
                                enrichmentError: book.enrichmentError
                            )
                        }

                        // Convert unified schema ImportError to legacy GeminiCSVImportJob.ImportError
                        let legacyErrors = (fullResults.errors ?? []).map { error in
                            GeminiCSVImportJob.ImportError(title: error.title, error: error.error)
                        }

                        importStatus = .completed(books: legacyBooks, errors: legacyErrors)

                        #if DEBUG
                        print("[CSV WebSocket] ✅ Fetched full results: \(legacyBooks.count) books, \(legacyErrors.count) errors")
                        #endif
                    } catch {
                        #if DEBUG
                        print("[CSV WebSocket] ❌ Failed to fetch results: \(error)")
                        #endif

                        if let csvError = error as? CSVImportError, case .rateLimited(let retryAfter) = csvError {
                            // Show rate limit banner
                            self.rateLimitRetryAfter = retryAfter ?? 60
                            self.showRateLimitBanner = true
                            importStatus = .failed("Rate limited fetching results. Please wait and try again.")
                        } else {
                            importStatus = .failed("Failed to fetch import results: \(error.localizedDescription)")
                        }
                    }

                    // Proactively close the connection from the client side
                    // This prevents the ENOTCONN (57) "Socket not connected" error
                    self.webSocketTask?.cancel(with: .goingAway, reason: "Job complete".data(using: .utf8))
                    self.receiveTask?.cancel()
                    return  // Exit message loop - job is complete

                case .error(let errorPayload):
                    #if DEBUG
                    print("[CSV WebSocket] ❌ Error from backend: \(errorPayload.message)")
                    #endif
                    importStatus = .failed(errorPayload.message)
                    self.webSocketTask?.cancel(with: .goingAway, reason: "Job failed".data(using: .utf8))
                    self.receiveTask?.cancel()
                    return  // Exit message loop - job failed

                case .readyAck:
                    #if DEBUG
                    print("[CSV WebSocket] ✅ Backend acknowledged ready signal, processing will start")
                    #endif
                    // No UI update needed, progress messages will follow

                case .jobStarted:
                    #if DEBUG
                    print("[CSV WebSocket] Job started (informational)")
                    #endif
                    // No UI update needed, progress messages will follow

                case .ping, .pong:
                    // Heartbeat messages, no action needed
                    break

                case .batchInit, .batchProgress, .batchComplete, .batchCanceling:
                    // Batch scanning messages - ignore in CSV import pipeline
                    // These should never reach here due to pipeline filtering at line 414
                    break
                }
            }

        } catch {
            #if DEBUG
            print("[CSV WebSocket] ❌ Failed to decode WebSocket message: \(error)")
            print("[CSV WebSocket] Raw message: \(text)")
            #endif
        }
    }

    /// Fetch full job results from KV cache via HTTP GET
    /// v2.0 Migration: WebSocket sends lightweight summary, full results fetched on demand
    /// Results are cached for 24 hours after job completion
    private func fetchJobResults(jobId: String) async throws -> CSVImportJobResults {
        let baseURL = "https://api.oooefam.net"
        let url = URL(string: "\(baseURL)/v1/jobs/\(jobId)/results")!

        #if DEBUG
        print("[CSV Import] 🌐 Fetching results from: \(url)")
        #endif

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CSVImportError.invalidResponse
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
                throw CSVImportError.emptyResults
            }

            guard let results = envelope.data else {
                throw CSVImportError.emptyResults
            }

            return results

        case 404:
            // Results expired (> 24 hours old)
            throw CSVImportError.resultsExpired

        case 429:
            // Rate limited - use value(forHTTPHeaderField:) for reliable header access
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw CSVImportError.rateLimited(retryAfter: retryAfter)

        default:
            throw CSVImportError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    private func cancelImport() {
        // Cancel V2 progress tracker if using V2 API
        if let tracker = progressTracker {
            Task {
                await tracker.stopTracking()
            }
            progressTracker = nil
        }
        
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

        // Explicitly close the WebSocket with a normal "going away" message
        webSocketTask?.cancel(with: .goingAway, reason: "User canceled".data(using: .utf8))
        receiveTask?.cancel()
        webSocketTask = nil
        receiveTask = nil
    }

    @MainActor
    private func saveBooks(_ books: [GeminiCSVImportJob.ParsedBook]) async -> Bool {
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
                EnrichmentQueue.shared.enqueueBatch(result.newWorkIDs)

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

                    EnrichmentQueue.shared.startProcessing(in: modelContext) { completed, total, currentTitle in
                        #if DEBUG
                        print("📚 Enriching (\(completed)/\(total)): \(currentTitle)")
                        #endif
                    }
                }
            }

            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            return true

        } catch {
            #if DEBUG
            print("❌ Background import failed: \(error)")
            #endif

            // Error haptic
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)

            // Update UI with error
            importStatus = .failed("Failed to save: \(error.localizedDescription)")
            return false
        }
    }
}