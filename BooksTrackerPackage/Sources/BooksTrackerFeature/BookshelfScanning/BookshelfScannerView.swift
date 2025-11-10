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
                        // Privacy disclosure banner
                        privacyDisclosureBanner

                        // Photo selection area
                        cameraSection

                        // Batch mode toggle
                        batchModeToggle

                        // Statistics (if scanning or completed)
                        if scanModel.scanState != .idle {
                            statisticsSection
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
                        showingResults = false
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
                    scanModel.scanState = .idle
                }
            } message: { errorMessage in
                Text(errorMessage)
            }
            .onChange(of: scanModel.isError) { oldValue, newValue in
                showingErrorAlert = newValue
            }
        }
    }

    // MARK: - Privacy Disclosure Banner

    private var privacyDisclosureBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.title2)
                    .foregroundStyle(themeStore.primaryColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Private & Secure")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Your photo is uploaded for AI analysis and is not stored.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(themeStore.primaryColor.opacity(0.3), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Privacy notice: Your photo is uploaded for AI analysis and is not stored.")
    }

    // MARK: - Camera Section

    private var cameraSection: some View {
        VStack(spacing: 16) {
            // Camera button - Swift 6.1 compliant with global actor pattern ✅
            Button(action: { showCamera = true }) {
                VStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(themeStore.primaryColor)
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
                                    themeStore.primaryColor.opacity(0.3),
                                    lineWidth: 2
                                )
                        }
                }
            }
            .buttonStyle(.plain)
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


    // MARK: - Statistics Section

    private var statisticsSection: some View {
        VStack(spacing: 12) {
            Text("Scan Progress")
                .font(.headline)
                .foregroundStyle(.primary)

            // Real-time WebSocket progress (when processing)
            if scanModel.scanState == .processing {
                VStack(spacing: 12) {
                    // Progress bar
                    ProgressView(value: scanModel.currentProgress, total: 1.0)
                        .tint(themeStore.primaryColor)

                    // Stage label
                    Text(scanModel.currentStage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Percentage
                    Text("\(Int(scanModel.currentProgress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            // Statistics (when completed)
            if scanModel.scanState == .completed {
                HStack(spacing: 20) {
                    statisticBadge(
                        icon: "books.vertical.fill",
                        value: "\(scanModel.detectedCount)",
                        label: "Detected"
                    )

                    statisticBadge(
                        icon: "checkmark.circle.fill",
                        value: "\(scanModel.confirmedCount)",
                        label: "Ready"
                    )

                    statisticBadge(
                        icon: "questionmark.circle.fill",
                        value: "\(scanModel.uncertainCount)",
                        label: "Review"
                    )
                }
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        }
    }

    private func statisticBadge(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(themeStore.primaryColor)

            Text(value)
                .font(.title3.bold())
                .foregroundStyle(.primary)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
                tipsSection
            }
        }
    }

    // MARK: - Tips Section

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tips for Best Results")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 8) {
                tipRow(icon: "sun.max.fill", text: "Use good lighting")
                tipRow(icon: "arrow.up.backward.and.arrow.down.forward", text: "Keep camera level with spines")
                tipRow(icon: "camera.metering.center.weighted", text: "Get close enough to read titles")
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.orange)
                .font(.caption)
                .frame(width: 16)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
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

    /// Saves original bookshelf image to temporary storage for correction UI
    /// - Parameter image: The captured bookshelf image
    /// - Returns: File path to saved image, or nil if saving failed
    private func saveOriginalImage(_ image: UIImage) -> String? {
        let tempDirectory = FileManager.default.temporaryDirectory
        let filename = "bookshelf_scan_\(UUID().uuidString).jpg"
        let fileURL = tempDirectory.appendingPathComponent(filename)

        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            #if DEBUG
            print("⚠️ Failed to convert image to JPEG data")
            #endif
            return nil
        }

        do {
            try imageData.write(to: fileURL)
            #if DEBUG
            print("✅ Saved original image to: \(fileURL.path)")
            #endif
            return fileURL.path
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
        self.lastSavedImagePath = saveOriginalImage(image)

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
            scanState = .error(error.localizedDescription)

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
