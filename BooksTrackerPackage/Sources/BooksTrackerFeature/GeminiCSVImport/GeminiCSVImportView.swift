import SwiftUI
import SwiftData
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#endif

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
    @State private var webSocketTask: Task<Void, Never>?
    @State private var webSocket: URLSessionWebSocketTask?

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

            // Upload to backend and get auth token
            let service = GeminiCSVImportService.shared
            let (uploadedJobId, authToken) = try await service.uploadCSV(csvText: csvText)

            #if DEBUG
            print("[CSV Upload] 🔐 Auth token received: \(authToken.prefix(8))...")
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

    private func startWebSocketProgress(jobId: String, token: String) {
        // Build WebSocket URL with authentication token
        var components = URLComponents(string: "\(EnrichmentConfig.webSocketBaseURL)/ws/progress")!
        components.queryItems = [
            URLQueryItem(name: "jobId", value: jobId),
            URLQueryItem(name: "token", value: token)
        ]
        guard let wsURL = components.url else {
            importStatus = .failed("Invalid WebSocket URL")
            return
        }

        #if DEBUG
        print("[CSV WebSocket] Connecting to backend with authentication")
        #endif

        webSocketTask = Task {
            do {
                // Use a new URLSession with default configuration, which is more reliable for
                // WebSockets than the shared session. This mirrors the implementation in
                // EnrichmentWebSocketHandler.
                let session = URLSession(configuration: .default)
                let webSocketTask = session.webSocketTask(with: wsURL)
                self.webSocket = webSocketTask
                webSocketTask.resume()
                
                // ✅ CRITICAL: Wait for WebSocket handshake to complete
                // Prevents POSIX error 57 "Socket is not connected"
                try await WebSocketHelpers.waitForConnection(webSocketTask, timeout: 10.0)
                
                #if DEBUG
                print("[CSV WebSocket] ✅ WebSocket connection established")
                #endif

                // Send ready signal to backend (required for processing to start)
                let readyMessage: [String: Any] = [
                    "type": "ready",
                    "timestamp": Date().timeIntervalSince1970 * 1000
                ]
                if let messageData = try? JSONSerialization.data(withJSONObject: readyMessage),
                   let messageString = String(data: messageData, encoding: .utf8) {
                    try await webSocketTask.send(.string(messageString))
                    #if DEBUG
                    print("[CSV WebSocket] ✅ Sent ready signal to backend")
                    #endif
                }

                // Listen for messages
                #if DEBUG
                print("[CSV WebSocket] Waiting for messages...")
                #endif
                while !Task.isCancelled {
                    let message = try await webSocketTask.receive()
                    #if DEBUG
                    print("[CSV WebSocket] 📨 Received message")
                    #endif

                    switch message {
                    case .string(let text):
                        #if DEBUG
                        print("[CSV WebSocket] Message text: \(text.prefix(200))")
                        #endif
                        handleWebSocketMessage(text)
                    case .data(let data):
                        #if DEBUG
                        print("[CSV WebSocket] Message data: \(data.count) bytes")
                        #endif
                        if let text = String(data: data, encoding: .utf8) {
                            handleWebSocketMessage(text)
                        }
                    @unknown default:
                        #if DEBUG
                        print("[CSV WebSocket] ⚠️ Unknown message type")
                        #endif
                        break
                    }
                }
                #if DEBUG
                print("[CSV WebSocket] Message loop ended (task cancelled)")
                #endif

            } catch {
                // Per best practices, use String(describing:) for detailed internal logging
                // This provides more context than error.localizedDescription for debugging
                let errorMessage = String(describing: error)
                #if DEBUG
                print("[CSV WebSocket] ❌ Error: \(errorMessage)")
                #endif
                if !Task.isCancelled {
                    importStatus = .failed("Connection lost: \(errorMessage)")
                }
            }
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

                case .jobComplete(let completePayload):
                    // Extract CSV-specific completion data
                    guard case .csvImport(let csvPayload) = completePayload else {
                        #if DEBUG
                        print("[CSV WebSocket] ❌ Wrong completion payload type for csv_import")
                        #endif
                        return
                    }

                    #if DEBUG
                    print("[CSV WebSocket] ✅ Import complete: \(csvPayload.books.count) books, \(csvPayload.errors.count) errors")
                    #endif

                    // Convert unified schema ParsedBook to legacy GeminiCSVImportJob.ParsedBook
                    let legacyBooks = csvPayload.books.map { book in
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
                    let legacyErrors = csvPayload.errors.map { error in
                        GeminiCSVImportJob.ImportError(title: error.title, error: error.error)
                    }

                    importStatus = .completed(books: legacyBooks, errors: legacyErrors)

                    // Proactively close the connection from the client side
                    // This prevents the ENOTCONN (57) "Socket not connected" error
                    self.webSocket?.cancel(with: .goingAway, reason: "Job complete".data(using: .utf8))
                    self.webSocketTask?.cancel()
                    return  // Exit message loop - job is complete

                case .error(let errorPayload):
                    #if DEBUG
                    print("[CSV WebSocket] ❌ Error from backend: \(errorPayload.message)")
                    #endif
                    importStatus = .failed(errorPayload.message)
                    self.webSocket?.cancel(with: .goingAway, reason: "Job failed".data(using: .utf8))
                    self.webSocketTask?.cancel()
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
                }
            }

        } catch {
            #if DEBUG
            print("[CSV WebSocket] ❌ Failed to decode WebSocket message: \(error)")
            print("[CSV WebSocket] Raw message: \(text)")
            #endif
        }
    }

    private func cancelImport() {
        // Explicitly close the WebSocket with a normal "going away" message
        webSocket?.cancel(with: .goingAway, reason: "User canceled".data(using: .utf8))
        webSocketTask?.cancel()
        webSocket = nil
        webSocketTask = nil
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
                // CRITICAL: Poll for SwiftData context merging
                // ImportService uses background actor context, main view uses different context
                // Without polling, modelContext.work(for:) returns nil for all IDs (cross-context issue)
                Task {
                    // Poll until SwiftData merges changes from background context
                    let workIDs = result.newWorkIDs
                    let deadline = Date.now.addingTimeInterval(5.0) // 5-second timeout

                    while Date.now < deadline {
                        let foundCount = workIDs.compactMap { modelContext.model(for: $0) as? Work }.count
                        if foundCount == workIDs.count {
                            break // All works are available
                        }
                        try? await Task.sleep(for: .milliseconds(100))
                    }

                    #if DEBUG
                    let finalFoundCount = workIDs.compactMap { modelContext.model(for: $0) as? Work }.count
                    print("📚 Context merge complete: \(finalFoundCount)/\(workIDs.count) works available")
                    #endif

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
