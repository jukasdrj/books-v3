import SwiftUI
import SwiftData

#if canImport(PhotosUI)
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Bookshelf Scanner View

/// Main view for scanning bookshelf photos and detecting books
/// Phase 1: PhotosPicker → VisionProcessingActor → Review → Add to library
@MainActor
public struct BookshelfScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(TabCoordinator.self) private var tabCoordinator

    // MARK: - State Management

    @State private var scanModel = BookshelfScanModel()
    @State private var showingResults = false
    @State private var showCamera = false
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var batchModeEnabled = false
    @State private var showingErrorAlert = false

    public init() {}

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                themeStore.backgroundGradient
                    .ignoresSafeArea()

                // Main content
                ScrollView {
                    VStack(spacing: 24) {
                        // Rate limit banner (GitHub Issue #426)
                        if scanModel.showRateLimitBanner {
                            RateLimitBanner(retryAfter: scanModel.rateLimitRetryAfter) {
                                scanModel.showRateLimitBanner = false
                                scanModel.rateLimitRetryAfter = 0  // Reset state when dismissed
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        
                        // Privacy disclosure banner
                        PrivacyDisclosureBanner()

                        // Photo selection area
                        cameraSection

                        // Batch mode toggle
                        batchModeToggle

                        // Statistics (if scanning or completed)
                        if scanModel.scanState != .idle {
                            ScanStatisticsView(
                                scanState: scanModel.scanState,
                                currentProgress: scanModel.currentProgress,
                                currentStage: scanModel.currentStage,
                                detectedCount: scanModel.detectedCount,
                                confirmedCount: scanModel.confirmedCount,
                                uncertainCount: scanModel.uncertainCount
                            )
                        }

                        // Action buttons
                        actionButtonsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
            }
            .navigationTitle("Scan Bookshelf (Beta)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        Task {
                            await scanModel.cleanupTempFiles(mode: .perSession)
                        }
                        dismiss()
                    }
                    .foregroundStyle(themeStore.primaryColor)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if scanModel.scanState == .processing {
                        ProgressView()
                            .tint(themeStore.primaryColor)
                    }
                }
            }
            .sheet(isPresented: $showingResults) {
                ScanResultsView(
                    scanResult: scanModel.scanResult,
                    modelContext: modelContext,
                    onDismiss: {
                        // ✅ Fix #383: Reset scan state and redirect to Library after adding books
                        showingResults = false
                        // Reset scan model to initial state
                        scanModel.resetToInitialState()
                        // Switch to Library tab to see newly added books
                        tabCoordinator.switchToLibrary()
                        dismiss()
                    }
                )
            }
            .fullScreenCover(isPresented: $showCamera) {
                if batchModeEnabled {
                    NavigationStack {
                        BatchCaptureView()
                    }
                } else {
                    BookshelfCameraView { capturedImage in
                        Task {
                            await scanModel.processImage(capturedImage)
                            if scanModel.scanState == .completed {
                                showingResults = true
                            }
                        }
                    }
                }
            }

            .alert("Scan Failed", isPresented: $showingErrorAlert, presenting: scanModel.errorMessage) { _ in
                Button("OK", role: .cancel) {
                    Task {
                        await scanModel.cleanupTempFiles(mode: .perSession)
                    }
                    scanModel.scanState = .idle
                }
            } message: { errorMessage in
                Text(errorMessage)
            }
            .onChange(of: scanModel.isError) { oldValue, newValue in
                showingErrorAlert = newValue
            }
        }
        .onDisappear {
            Task {
                await scanModel.cleanupTempFiles(mode: .global)
            }
        }
    }

    // MARK: - Camera Section

    private var cameraSection: some View {
        VStack(spacing: 16) {
            // Camera button - Swift 6.1 compliant with global actor pattern ✅
            Button(action: { showCamera = true }) {
                VStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(scanModel.showRateLimitBanner ? .gray : themeStore.primaryColor)
                        .symbolRenderingMode(.hierarchical)

                    Text("Scan Bookshelf")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Take a photo of your bookshelf")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(
                                    scanModel.showRateLimitBanner ? Color.gray.opacity(0.3) : themeStore.primaryColor.opacity(0.3),
                                    lineWidth: 2
                                )
                        }
                }
            }
            .buttonStyle(.plain)
            .disabled(scanModel.showRateLimitBanner) // Disable during rate limit
            .accessibilityLabel("Tap to capture bookshelf photo")
            .accessibilityHint("Opens camera to scan your bookshelf")

            #if DEBUG
            PhotosPicker(selection: $photosPickerItem, matching: .images) {
                Text("Select Test Image")
            }
            .onChange(of: photosPickerItem) {
                Task {
                    if let data = try? await photosPickerItem?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await scanModel.processImage(image)
                        if scanModel.scanState == .completed {
                            showingResults = true
                        }
                    }
                }
            }
            #endif
        }
    }


    // MARK: - Action Buttons Section

    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            // Primary action button (camera opens automatically, no manual analyze button needed)
            if scanModel.scanState == .processing {
                VStack(spacing: 8) {
                    HStack {
                        ProgressView()
                            .tint(.white)
                        Text("Analyzing bookshelf...")
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(themeStore.primaryColor.gradient)
                    }

                    // User guidance: Keep app open
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption)
                        Text("Keep app open during analysis (25-40s)")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Keep app open during analysis, typically takes 25 to 40 seconds")
                }

            } else if scanModel.scanState == .completed {
                Button {
                    showingResults = true
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)

                        Text("Review Results (\(scanModel.detectedCount))")
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.green.gradient)
                    }
                }
                .accessibilityLabel("Review \(scanModel.detectedCount) detected books")
            }

            // Tips section
            if scanModel.scanState == .idle {
                ScanningTipsView()
            }
        }
    }

    // MARK: - Batch Mode Toggle

    private var batchModeToggle: some View {
        VStack(spacing: 8) {
            Toggle("Batch Mode (Beta)", isOn: $batchModeEnabled)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if batchModeEnabled {
                Text("Capture up to 5 photos in one session")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Bookshelf Scan Model

@MainActor
@Observable
class BookshelfScanModel {
    var scanState: ScanState = .idle
    var detectedCount: Int = 0
    var confirmedCount: Int = 0
    var uncertainCount: Int = 0
    var scanResult: ScanResult?

    // Real-time progress tracking
    var currentProgress: Double = 0.0
    var currentStage: String = ""

    // Original image storage for correction UI
    public var lastSavedImagePath: String?
    
    // Temp file tracking for per-session cleanup (Issue #472)
    private var tempFiles: [URL] = []
    
    // Rate limit state (GitHub Issue #426)
    var rateLimitRetryAfter: Int = 0
    var showRateLimitBanner: Bool = false

    enum ScanState: Equatable {
        case idle
        case processing
        case completed
        case error(String)
    }

    // Helper computed properties for error handling
    var isError: Bool {
        if case .error = scanState {
            return true
        }
        return false
    }

    var errorMessage: String? {
        if case .error(let message) = scanState {
            return message
        }
        return nil
    }

    /// Reset scan model to initial state (Issue #383)
    /// Called after successfully adding books to library
    func resetToInitialState() {
        Task {
            await cleanupTempFiles(mode: .perSession)
        }
        scanState = .idle
        detectedCount = 0
        confirmedCount = 0
        uncertainCount = 0
        scanResult = nil
        currentProgress = 0.0
        currentStage = ""
        lastSavedImagePath = nil
        #if DEBUG
        print("🔄 Scan model reset to initial state")
        #endif
    }

    /// Cleanup modes for temp file management (Issue #472)
    enum CleanupMode {
        case perSession  // Delete only tracked files from current session
        case global      // Delete all matching files older than 24 hours
    }

    /// Cleans up temporary bookshelf scan files
    /// - Parameter mode: perSession for current tracked files, global for all stale matching files
    /// - Returns: true if all deletions succeeded or partial success
    @MainActor
    func cleanupTempFiles(mode: CleanupMode) async -> Bool {
        let success: Bool
        switch mode {
        case .perSession:
            success = await deleteTrackedFiles()
        case .global:
            success = await deleteStaleGlobalFiles()
        }
        
        // Clear tracked files after per-session cleanup
        if mode == .perSession {
            tempFiles.removeAll()
        }
        
        return success
    }
    
    /// Deletes only the tracked temp files from the current session
    private func deleteTrackedFiles() async -> Bool {
        await Task.detached(priority: .utility) { [tempFiles] in
            var allSucceeded = true
            for url in tempFiles {
                do {
                    if FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.removeItem(at: url)
                        #if DEBUG
                        print("🗑️ Deleted per-session temp file: \(url.lastPathComponent)")
                        #endif
                    }
                } catch {
                    #if DEBUG
                    print("⚠️ Failed to delete temp file \(url.lastPathComponent): \(error.localizedDescription)")
                    #endif
                    allSucceeded = false
                }
            }
            return allSucceeded
        }.value
    }
    
    /// Deletes all bookshelf_scan_*.jpg files in temp dir older than 24 hours
    private func deleteStaleGlobalFiles() async -> Bool {
        let ttlInterval: TimeInterval = 24 * 60 * 60  // 24 hours
        let tempDirectory = FileManager.default.temporaryDirectory
        
        return await Task.detached(priority: .utility) {
            var allSucceeded = true
            
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(
                    at: tempDirectory,
                    includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                )
                
                let pattern = "bookshelf_scan_.*\\.jpg"
                let staleFiles = fileURLs.filter { url in
                    url.lastPathComponent.range(of: pattern, options: .regularExpression) != nil
                }
                
                for url in staleFiles {
                    do {
                        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                        if let modDate = attributes[.modificationDate] as? Date,
                           Date().timeIntervalSince(modDate) > ttlInterval {
                            
                            if FileManager.default.fileExists(atPath: url.path) {
                                try FileManager.default.removeItem(at: url)
                                #if DEBUG
                                print("🗑️ Deleted stale temp file: \(url.lastPathComponent)")
                                #endif
                            }
                        }
                    } catch {
                        #if DEBUG
                        print("⚠️ Failed to check/delete stale file \(url.lastPathComponent): \(error.localizedDescription)")
                        #endif
                        allSucceeded = false
                    }
                }
            } catch {
                #if DEBUG
                print("⚠️ Failed to enumerate temp directory: \(error.localizedDescription)")
                #endif
                allSucceeded = false
            }
            
            return allSucceeded
        }.value
    }

    /// Saves original bookshelf image to temporary storage for correction UI
    /// - Parameter image: The captured bookshelf image
    /// - Returns: File path to saved image, or nil if saving failed
    @MainActor
    private func saveOriginalImage(_ image: UIImage) async -> String? {
        let tempDirectory = FileManager.default.temporaryDirectory
        let filename = "bookshelf_scan_\(UUID().uuidString).jpg"
        let fileURL = tempDirectory.appendingPathComponent(filename)

        // Offload JPEG compression to background task
        let imageData = await Task.detached(priority: .background) { () -> Data? in
            guard let data = image.jpegData(compressionQuality: 0.8) else {
                #if DEBUG
                print("⚠️ Failed to convert image to JPEG data")
                #endif
                return nil
            }
            return data
        }.value

        guard let imageData = imageData else {
            return nil
        }

        // Offload file write to background task
        do {
            let savedURL = try await Task.detached(priority: .background) { () -> URL in
                try imageData.write(to: fileURL)
                #if DEBUG
                print("✅ Saved original image to: \(fileURL.path)")
                #endif
                return fileURL
            }.value

            // Track the URL for cleanup (Issue #472)
            tempFiles.append(savedURL)
            
            return savedURL.path
        } catch {
            #if DEBUG
            print("❌ Failed to save original image: \(error)")
            #endif
            return nil
        }
    }

    /// Process captured image with WebSocket real-time progress tracking
    func processImage(_ image: UIImage) async {
        scanState = .processing
        currentProgress = 0.0
        currentStage = "Initializing..."
        let startTime = Date()

        // CRITICAL: Prevent device from sleeping during scan (25-40s AI processing)
        // iOS will kill the app if it enters background while WebSocket is waiting
        UIApplication.shared.isIdleTimerDisabled = true
        #if DEBUG
        print("🔒 Idle timer disabled - device won't sleep during scan")
        #endif

        // Save original image first for correction UI
        self.lastSavedImagePath = await saveOriginalImage(image)

        do {
            // Use new WebSocket method for real-time progress updates
            let (capturedImage, detectedBooks, suggestions) = try await BookshelfAIService.shared.processBookshelfImageWithWebSocket(image) { progress, stage in
                // Progress handler runs on MainActor - safe for UI updates
                self.currentProgress = progress
                self.currentStage = stage
                #if DEBUG
                print("📸 WebSocket progress: \(Int(progress * 100))% - \(stage)")
                #endif
            }

            // Attach original image path to each detected book for correction UI
            let booksWithImagePath = detectedBooks.map { book in
                var updatedBook = book
                updatedBook.originalImagePath = self.lastSavedImagePath
                return updatedBook
            }

            // Calculate statistics
            detectedCount = booksWithImagePath.count
            confirmedCount = booksWithImagePath.filter { $0.status == .detected || $0.status == .confirmed }.count
            uncertainCount = booksWithImagePath.filter { $0.status == .uncertain }.count

            // Create scan result
            let processingTime = Date().timeIntervalSince(startTime)
            scanResult = ScanResult(
                capturedImage: capturedImage,
                detectedBooks: booksWithImagePath,
                totalProcessingTime: processingTime,
                suggestions: suggestions
            )

            currentProgress = 1.0
            currentStage = "Complete!"
            scanState = .completed

            // Re-enable idle timer on success
            UIApplication.shared.isIdleTimerDisabled = false
            #if DEBUG
            print("🔓 Idle timer re-enabled")
            #endif

        } catch {
            // Per-session cleanup on error (Issue #472)
            Task {
                await cleanupTempFiles(mode: .perSession)
            }
            
            // Check for rate limit error (GitHub Issue #426)
            if let aiError = error as? BookshelfAIError,
               case .rateLimitExceeded(let retryAfter) = aiError {
                // Show rate limit banner instead of generic error
                withAnimation {
                    rateLimitRetryAfter = retryAfter
                    showRateLimitBanner = true
                }
                scanState = .idle // Reset to idle (don't show error alert)
                
                #if DEBUG
                print("⏱️ Rate limit hit - retry after \(retryAfter)s")
                #endif
            } else {
                // Generic error handling
                scanState = .error(error.localizedDescription)
            }

            // CRITICAL: Re-enable idle timer on error (prevent battery drain)
            UIApplication.shared.isIdleTimerDisabled = false
            #if DEBUG
            print("🔓 Idle timer re-enabled (error case)")
            #endif
        }
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview {
    BookshelfScannerView()
        .modelContainer(for: [Work.self, Edition.self, UserLibraryEntry.self, Author.self])
        .environment(BooksTrackerFeature.iOS26ThemeStore())
}

#endif  // canImport(PhotosUI)