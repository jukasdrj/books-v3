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
    @State private var sseClient: SSEClient?

    // Rate limit banner (Issue #426)
    @State private var showRateLimitBanner = false
    @State private var rateLimitRetryAfter = 0

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
        importStatus = .uploading

        do {
            // Read CSV content
            guard url.startAccessingSecurityScopedResource() else {
                importStatus = .failed("Cannot access file")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let csvText = try String(contentsOf: url, encoding: .utf8)

            // Upload to V2 API and get jobId
            let service = GeminiCSVImportService.shared
            let uploadedJobId = try await service.uploadCSV(csvText: csvText)

            #if DEBUG
            print("[CSV Upload] ✅ Job created: \(uploadedJobId)")
            #endif

            // Start SSE stream for progress tracking
            jobId = uploadedJobId
            startSSEStream(jobId: uploadedJobId)

        } catch let error as GeminiCSVImportError {
            importStatus = .failed(error.localizedDescription)
        } catch {
            importStatus = .failed("Upload failed: \(error.localizedDescription)")
        }
    }

    private func startSSEStream(jobId: String) {
        #if DEBUG
        print("[CSV SSE] Starting SSE stream for job: \(jobId)")
        #endif

        // Create SSE client with V2 API callbacks
        let client = SSEClient(
            baseURL: EnrichmentConfig.apiBaseURL,
            onInitialized: { event in
                Task { @MainActor in
                    #if DEBUG
                    print("[CSV SSE] Initialized: \(event.jobId), total: \(event.totalCount)")
                    #endif
                    self.importStatus = .processing(progress: event.progress, message: "Job initialized...")
                }
            },
            onProcessing: { event in
                Task { @MainActor in
                    #if DEBUG
                    print("[CSV SSE] Processing: \(Int(event.progress * 100))% (\(event.processedCount)/\(event.totalCount))")
                    #endif
                    self.importStatus = .processing(
                        progress: event.progress,
                        message: "Processed \(event.processedCount) of \(event.totalCount) rows..."
                    )
                }
            },
            onCompleted: { event in
                Task { @MainActor in
                    #if DEBUG
                    print("[CSV SSE] Completed: \(event.jobId)")
                    #endif

                    // V2 API: Fetch full results from /api/v2/imports/{jobId}/results
                    do {
                        let results = try await GeminiCSVImportService.shared.fetchResults(jobId: event.jobId)

                        #if DEBUG
                        print("[CSV SSE] Results: \(results.booksCreated) created, \(results.booksUpdated) updated")
                        #endif

                        // Convert to display format (no book details, just summary)
                        let errors = results.errors.map { error in
                            GeminiCSVImportJob.ImportError(title: error.isbn, error: error.error)
                        }

                        // Display completion with summary
                        self.importStatus = .completed(books: [], errors: errors)
                    } catch {
                        #if DEBUG
                        print("[CSV SSE] ❌ Failed to fetch results: \(error)")
                        #endif
                        self.importStatus = .failed("Failed to fetch results: \(error.localizedDescription)")
                    }
                }
            },
            onFailed: { event in
                Task { @MainActor in
                    #if DEBUG
                    print("[CSV SSE] Failed: \(event.message)")
                    #endif
                    self.importStatus = .failed(event.message)
                }
            },
            onError: { error in
                Task { @MainActor in
                    #if DEBUG
                    print("[CSV SSE] Error: \(error.localizedDescription)")
                    #endif
                    self.importStatus = .failed(error.localizedDescription)
                }
            },
            onTimeout: { event in
                Task { @MainActor in
                    #if DEBUG
                    print("[CSV SSE] Timeout: \(event.message)")
                    #endif
                    self.importStatus = .failed("Import timed out: \(event.message)")
                }
            }
        )

        self.sseClient = client

        Task {
            await client.connect(jobId: jobId)
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