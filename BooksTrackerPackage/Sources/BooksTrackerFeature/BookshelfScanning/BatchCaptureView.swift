import SwiftUI
import Observation
import PhotosUI

#if os(iOS)
import UIKit

// MARK: - Batch Capture Model

/// State manager for batch photo capture with 5-photo limit enforcement
@Observable
@MainActor
public final class BatchCaptureModel {
    public var capturedPhotos: [CapturedPhoto] = []
    public var showingPostCaptureOptions = false
    public var showingCamera = true
    public var isSubmitting = false
    public var batchProgress: BatchProgress?
    private var wsHandler: BatchWebSocketHandler?

    public init() {}

    /// Add photo to batch (enforces 5-photo limit)
    @discardableResult
    public func addPhoto(_ image: UIImage) -> CapturedPhoto? {
        guard capturedPhotos.count < CapturedPhoto.maxPhotosPerBatch else {
            #if DEBUG
            print("Cannot add more than \(CapturedPhoto.maxPhotosPerBatch) photos")
            #endif
            return nil
        }

        let photo = CapturedPhoto(image: image)
        capturedPhotos.append(photo)
        showingPostCaptureOptions = true
        showingCamera = false
        return photo
    }

    /// Add photo silently (for library import - no UI state changes)
    /// Use this when importing multiple photos to avoid UI conflicts
    @discardableResult
    public func addPhotoQuietly(_ image: UIImage) -> CapturedPhoto? {
        guard capturedPhotos.count < CapturedPhoto.maxPhotosPerBatch else {
            #if DEBUG
            print("Cannot add more than \(CapturedPhoto.maxPhotosPerBatch) photos")
            #endif
            return nil
        }

        let photo = CapturedPhoto(image: image)
        capturedPhotos.append(photo)
        return photo
    }

    /// User chose "Take More" - return to camera
    public func handleTakeMore() {
        showingPostCaptureOptions = false
        showingCamera = true
    }

    /// User chose "Submit" - start batch processing
    public func submitBatch() async {
        guard !capturedPhotos.isEmpty else { return }

        isSubmitting = true

        // CRITICAL: Prevent device from sleeping during batch processing
        // Batch scans can take 2-5 minutes for 5 photos (25-40s per photo)
        UIApplication.shared.isIdleTimerDisabled = true
        #if DEBUG
        print("🔒 Idle timer disabled - device won't sleep during batch scan")
        #endif

        let jobId = UUID().uuidString
        let progress = BatchProgress(jobId: jobId, totalPhotos: capturedPhotos.count)
        self.batchProgress = progress

        do {
            // Submit batch to backend
            let service = BookshelfAIService.shared
            let response = try await service.submitBatch(jobId: jobId, photos: capturedPhotos)

            #if DEBUG
            print("[BatchCapture] Batch submitted: \(response.jobId), \(response.totalPhotos) photos")
            #endif

            // Connect WebSocket for progress updates
            let handler = BatchWebSocketHandler(
                jobId: jobId,
                onProgress: { [weak self] updatedProgress in
                    guard let self = self else { return }
                    self.batchProgress = updatedProgress

                    // Re-enable idle timer when batch completes
                    if updatedProgress.isComplete {
                        UIApplication.shared.isIdleTimerDisabled = false
                        #if DEBUG
                        print("🔓 Idle timer re-enabled (batch complete)")
                        #endif
                    }
                },
                onDisconnect: { [weak self] in
                    guard let self = self else { return }
                    // CRITICAL: Re-enable idle timer on unexpected disconnection (#307)
                    UIApplication.shared.isIdleTimerDisabled = false
                    #if DEBUG
                    print("🔓 Idle timer re-enabled (WebSocket disconnected)")
                    #endif
                    self.isSubmitting = false
                }
            )
            self.wsHandler = handler

            // Connect WebSocket in background
            Task {
                do {
                    try await handler.connect()
                } catch {
                    #if DEBUG
                    print("[BatchCapture] WebSocket connection failed: \(error)")
                    #endif
                    // Re-enable idle timer on connection failure
                    UIApplication.shared.isIdleTimerDisabled = false
                    #if DEBUG
                    print("🔓 Idle timer re-enabled (connection error)")
                    #endif
                }
            }

            // Clear captured photos from memory after upload
            capturedPhotos.removeAll()

        } catch {
            #if DEBUG
            print("[BatchCapture] Batch submission failed: \(error)")
            #endif
            isSubmitting = false

            // CRITICAL: Re-enable idle timer on error
            UIApplication.shared.isIdleTimerDisabled = false
            #if DEBUG
            print("🔓 Idle timer re-enabled (submission error)")
            #endif

            // TODO: Show error alert to user
        }
    }

    /// Delete a specific photo
    public func deletePhoto(_ photo: CapturedPhoto) {
        capturedPhotos.removeAll { $0.id == photo.id }
    }

    /// Can add more photos
    public var canAddMore: Bool {
        capturedPhotos.count < CapturedPhoto.maxPhotosPerBatch
    }

    /// Cancel the current batch processing
    public func cancelBatch() async {
        guard let progress = batchProgress else {
            #if DEBUG
            print("[BatchCapture] No batch in progress to cancel")
            #endif
            return
        }

        do {
            // POST to cancel endpoint
            let endpoint = EnrichmentConfig.scanCancelURL

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let cancelPayload = ["jobId": progress.jobId]
            request.httpBody = try JSONEncoder().encode(cancelPayload)

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                #if DEBUG
                print("[BatchCapture] Batch canceled successfully")
                #endif
                progress.overallStatus = "canceled"
                isSubmitting = false

                // Disconnect WebSocket (actor-isolated call)
                if let handler = wsHandler {
                    await handler.disconnect()
                }
            } else {
                #if DEBUG
                print("[BatchCapture] Cancel request failed with status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                #endif
            }

        } catch {
            #if DEBUG
            print("[BatchCapture] Cancel batch failed: \(error)")
            #endif
        }

        // CRITICAL: Re-enable idle timer to prevent battery drain (#311)
        UIApplication.shared.isIdleTimerDisabled = false
        #if DEBUG
        print("🔓 Idle timer re-enabled (batch canceled)")
        #endif
    }
}

// MARK: - Batch Capture View

/// UI for multi-photo batch capture with "Submit" or "Take More" workflow
@MainActor
public struct BatchCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.iOS26ThemeStore) private var themeStore

    @State private var model = BatchCaptureModel()
    @State private var photosPickerItems: [PhotosPickerItem] = []

    public init() {}

    public var body: some View {
        ZStack {
            // Camera view
            if model.showingCamera && !model.isSubmitting {
                BookshelfCameraView { capturedImage in
                    model.addPhoto(capturedImage)
                }
                .overlay(alignment: .bottom) {
                    // Photo counter overlay
                    if !model.capturedPhotos.isEmpty {
                        photoCounterOverlay
                    }
                }
            }

            // Post-capture options
            if model.showingPostCaptureOptions {
                postCaptureOptionsView
            }

            // Processing view
            if model.isSubmitting, let progress = model.batchProgress {
                batchProgressView(progress: progress)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                PhotosPicker(selection: $photosPickerItems,
                           maxSelectionCount: CapturedPhoto.maxPhotosPerBatch,
                           matching: .images) {
                    Label("Import Photos", systemImage: "photo.on.rectangle")
                }
                .disabled(model.isSubmitting)
            }
        }
        .onChange(of: photosPickerItems) { oldValue, newValue in
            Task {
                await loadSelectedPhotos(newValue)
            }
        }
    }

    // MARK: - Subviews

    private var photoCounterOverlay: some View {
        HStack {
            Image(systemName: "photo.stack")
            Text("\(model.capturedPhotos.count) of \(CapturedPhoto.maxPhotosPerBatch)")
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .padding(.bottom, 100)
    }

    private var postCaptureOptionsView: some View {
        VStack(spacing: 0) {
            // Preview
            if let lastPhoto = model.capturedPhotos.last {
                Image(uiImage: lastPhoto.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 400)
            }

            Spacer()

            // Action buttons
            VStack(spacing: 16) {
                Text("Photo \(model.capturedPhotos.count) captured")
                    .font(.headline)
                    .foregroundStyle(.primary)

                // Submit button
                Button {
                    Task { await model.submitBatch() }
                } label: {
                    Label("Submit \(model.capturedPhotos.count) Photo\(model.capturedPhotos.count > 1 ? "s" : "")",
                          systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(themeStore.primaryColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Take more button (if under limit)
                if model.canAddMore {
                    Button {
                        model.handleTakeMore()
                    } label: {
                        Label("Take More Photos", systemImage: "camera")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.secondary.opacity(0.2))
                            .foregroundStyle(themeStore.primaryColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                } else {
                    Text("Maximum \(CapturedPhoto.maxPhotosPerBatch) photos reached")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Thumbnail strip
                if model.capturedPhotos.count > 1 {
                    thumbnailStrip
                }
            }
            .padding(24)
            .background(.ultraThinMaterial)
        }
        .ignoresSafeArea()
    }

    private var thumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(model.capturedPhotos) { photo in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: photo.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        // Delete button
                        Button {
                            model.deletePhoto(photo)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white, .red)
                                .font(.system(size: 20))
                        }
                        .offset(x: 6, y: -6)
                    }
                }
            }
        }
    }

    private func batchProgressView(progress: BatchProgress) -> some View {
        VStack(spacing: 24) {
            Text("Processing Batch")
                .font(.title2)
                .fontWeight(.semibold)

            // Per-photo progress
            ForEach(progress.photos) { photoProgress in
                HStack(spacing: 16) {
                    // Photo number
                    Text("Photo \(photoProgress.index + 1)")
                        .frame(width: 80, alignment: .leading)

                    // Status icon
                    Group {
                        switch photoProgress.status {
                        case .queued:
                            Image(systemName: "clock")
                                .foregroundStyle(.secondary)
                        case .processing:
                            ProgressView()
                        case .complete:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .error:
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(width: 24)

                    // Books found
                    if let count = photoProgress.booksFound?.count {
                        Text("\(count) books")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .font(.subheadline)
            }

            // Overall progress
            VStack(spacing: 8) {
                HStack {
                    Text("Total Books Found")
                    Spacer()
                    Text("\(progress.totalBooksFound)")
                        .fontWeight(.semibold)
                }

                ProgressView(value: Double(progress.successCount),
                            total: Double(progress.totalPhotos))
                    .tint(themeStore.primaryColor)
            }
            .padding(.top, 16)

            // Cancel button
            Button("Cancel Batch", role: .destructive) {
                Task {
                    await model.cancelBatch()
                }
            }
            .padding(.top)
        }
        .padding(32)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding()
    }

    // MARK: - Photo Loading

    /// Load selected photos from PhotosPicker and add to batch
    private func loadSelectedPhotos(_ items: [PhotosPickerItem]) async {
        // Load all photos quietly (no UI state changes per-photo)
        for item in items {
            // Check if we've hit the limit
            guard model.capturedPhotos.count < CapturedPhoto.maxPhotosPerBatch else {
                #if DEBUG
                print("[BatchCapture] Reached max photo limit, skipping remaining selections")
                #endif
                break
            }

            // Load image data
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                // Add to batch silently
                model.addPhotoQuietly(image)
                #if DEBUG
                print("[BatchCapture] Loaded photo from library (\(model.capturedPhotos.count)/\(CapturedPhoto.maxPhotosPerBatch))")
                #endif
            }
        }

        // Update UI state once after all photos loaded
        if !model.capturedPhotos.isEmpty {
            model.showingPostCaptureOptions = true
            model.showingCamera = false
        }

        // Clear picker selection after loading
        photosPickerItems = []
    }
}

#endif  // os(iOS)
