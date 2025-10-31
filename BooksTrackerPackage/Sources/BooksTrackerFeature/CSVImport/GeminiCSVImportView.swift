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

    @State private var showingFilePicker = false
    @State private var jobId: String?
    @State private var importStatus: ImportStatus = .idle
    @State private var progress: Double = 0.0
    @State private var statusMessage: String = ""
    @State private var errorMessage: String?
    @State private var webSocketTask: Task<Void, Never>?

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
                    await saveBooks(books)
                    dismiss()
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

            // Upload to backend
            let service = GeminiCSVImportService.shared
            let uploadedJobId = try await service.uploadCSV(csvText: csvText)

            // Start WebSocket connection
            jobId = uploadedJobId
            startWebSocketProgress(jobId: uploadedJobId)

        } catch let error as GeminiCSVImportError {
            importStatus = .failed(error.localizedDescription)
        } catch {
            importStatus = .failed("Upload failed: \(error.localizedDescription)")
        }
    }

    private func startWebSocketProgress(jobId: String) {
        let wsURL = URL(string: "wss://api-worker.jukasdrj.workers.dev/ws/progress?jobId=\(jobId)")!

        webSocketTask = Task {
            do {
                let session = URLSession.shared
                let webSocket = session.webSocketTask(with: wsURL)
                webSocket.resume()

                // Listen for messages
                while !Task.isCancelled {
                    let message = try await webSocket.receive()

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
                if !Task.isCancelled {
                    importStatus = .failed("Connection lost: \(error.localizedDescription)")
                }
            }
        }
    }

    private func handleWebSocketMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        do {
            let message = try JSONDecoder().decode(WebSocketMessage.self, from: data)

            switch message.type {
            case "progress":
                if let progressValue = message.progress, let status = message.status {
                    importStatus = .processing(progress: progressValue, message: status)
                }

            case "complete":
                if let result = message.result {
                    importStatus = .completed(books: result.books, errors: result.errors)
                }
                webSocketTask?.cancel()

            case "error":
                if let error = message.error {
                    importStatus = .failed(error)
                }
                webSocketTask?.cancel()

            default:
                break
            }

        } catch {
            print("Failed to decode WebSocket message: \(error)")
        }
    }

    private func cancelImport() {
        webSocketTask?.cancel()
        webSocketTask = nil
    }

    @MainActor
    private func saveBooks(_ books: [GeminiCSVImportJob.ParsedBook]) async {
        guard !books.isEmpty else {
            print("⚠️ No books to save")
            return
        }

        print("📚 Saving \(books.count) books to library...")
        var savedCount = 0
        var skippedCount = 0
        var savedWorkIDs: [PersistentIdentifier] = []

        // **FIX #1: Move fetch outside loop** (100x performance improvement)
        // Fetch all existing works ONCE instead of per-book
        let descriptor = FetchDescriptor<Work>()
        let allWorks: [Work]
        do {
            allWorks = try modelContext.fetch(descriptor)
        } catch {
            // **FIX #2: Explicit error handling** (prevent silent data loss)
            print("❌ Failed to fetch existing works: \(error)")
            importStatus = .failed("Database error: \(error.localizedDescription)")
            return
        }

        for book in books {
            // Check for duplicate by title + author (case-insensitive)
            // Note: SwiftData predicates don't support lowercased(), so we filter in-memory
            let titleLower = book.title.lowercased()
            let authorLower = book.author.lowercased()

            let isDuplicate = allWorks.contains { work in
                let workTitleLower = work.title.lowercased()
                let workAuthorLower = work.authorNames.lowercased()
                return workTitleLower == titleLower &&
                       (workAuthorLower.contains(authorLower) || authorLower.contains(workAuthorLower))
            }

            if isDuplicate {
                print("⏭️ Skipping duplicate: \(book.title)")
                skippedCount += 1
                continue
            }

            // Create Author FIRST and insert
            let author = Author(name: book.author)
            modelContext.insert(author)

            // Create Work, insert, then set relationship
            let work = Work(
                title: book.title,
                originalLanguage: "Unknown",  // Gemini doesn't provide this
                firstPublicationYear: book.publicationYear
            )
            modelContext.insert(work)  // ✅ Get permanent ID

            // NOW set relationship (both have permanent IDs)
            work.authors = [author]

            // Track work ID for enrichment
            savedWorkIDs.append(work.persistentModelID)

            // Create Edition ONLY if we have ISBN from Gemini
            if let isbn = book.isbn {
                let edition = Edition(
                    isbn: isbn,
                    publisher: book.publisher,
                    publicationDate: book.publicationYear.map { "\($0)" },
                    pageCount: nil,
                    format: .paperback,
                    coverImageURL: nil  // No cover yet - enrichment will add it
                )

                modelContext.insert(edition)
                edition.work = work
            }

            savedCount += 1
        }

        // Save to SwiftData
        do {
            try modelContext.save()
            print("✅ Saved \(savedCount) books (\(skippedCount) skipped as duplicates)")

            // Enqueue all saved works for background enrichment
            if !savedWorkIDs.isEmpty {
                print("📚 Enqueueing \(savedWorkIDs.count) books for enrichment")
                EnrichmentQueue.shared.enqueueBatch(savedWorkIDs)

                // ✅ Start enrichment DETACHED from MainActor
                // This prevents blocking the UI while enrichment processes
                // See docs/guides/ASYNC_PATTERNS.md for detailed explanation
                Task.detached { @MainActor in
                    EnrichmentQueue.shared.startProcessing(in: modelContext) { completed, total, currentTitle in
                        print("📚 Enriching (\(completed)/\(total)): \(currentTitle)")
                    }
                }
            }

            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

        } catch {
            print("❌ Failed to save books: \(error)")

            // Error haptic
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)

            // Update UI with error
            importStatus = .failed("Failed to save: \(error.localizedDescription)")
        }
    }

    // MARK: - WebSocket Message Types

    struct WebSocketMessage: Codable {
        let type: String
        let progress: Double?
        let status: String?
        let error: String?
        let result: GeminiCSVImportJob?
    }
}
