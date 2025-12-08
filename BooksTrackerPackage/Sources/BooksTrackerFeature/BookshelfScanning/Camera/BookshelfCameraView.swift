import SwiftUI

#if os(iOS)
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Bookshelf Camera View

/// Main camera capture interface for bookshelf scanning.
/// iOS 26 HIG compliant with Liquid Glass design system.
public struct BookshelfCameraView: View {
    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.iOS26ThemeStore) private var themeStore

    // MARK: - State

    @State private var viewModel = BookshelfCameraViewModel()

    // MARK: - Callbacks

    let onCaptureComplete: (UIImage) -> Void

    // MARK: - Initialization

    public init(onCaptureComplete: @escaping (UIImage) -> Void) {
        self.onCaptureComplete = onCaptureComplete
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            switch viewModel.cameraState {
            case .idle, .settingUp:
                setupView

            case .permissionDenied:
                permissionDeniedView

            case .ready, .capturing:
                cameraView

            case .error(let message):
                errorView(message: message)
            }
        }
        .task {
            await viewModel.setupCamera()
        }
        .sheet(isPresented: $viewModel.showReviewSheet) {
            if let image = viewModel.capturedImage {
                PhotoReviewView(
                    image: image,
                    onUsePhoto: { finalImage in
                        onCaptureComplete(finalImage)
                        Task {
                            await viewModel.cleanup()
                            dismiss()
                        }
                    },
                    onRetake: {
                        viewModel.capturedImage = nil
                        viewModel.showReviewSheet = false
                    }
                )
            }
        }
    }

    // MARK: - Setup View

    private var setupView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(themeStore.primaryColor)

            Text("Setting up camera...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Permission Denied View

    private var permissionDeniedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.fill.badge.exclamationmark")
                .font(.system(size: 60))
                .foregroundStyle(themeStore.primaryColor)

            VStack(spacing: 12) {
                Text("Camera Access Required")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("BooksTrack needs camera access to scan your bookshelf. Please enable it in Settings.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 12) {
                Button("Open Settings") {
                    viewModel.openSettings()
                }
                .buttonStyle(.borderedProminent)
                .tint(themeStore.primaryColor)

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Camera View

    @ViewBuilder
    private var cameraView: some View {
        if let manager = viewModel.cameraManager {
            ZStack {
                // Camera preview (full screen)
                BookshelfCameraPreview(cameraManager: manager)
                    .ignoresSafeArea()

                // Controls overlay
                cameraControlsOverlay
            }
        }
    }

    // MARK: - Camera Controls Overlay

    private var cameraControlsOverlay: some View {
        VStack {
            // Top bar with guidance text (iOS HIG compliant)
            VStack(spacing: 12) {
                HStack {
                    // Cancel button
                    Button(action: {
                        Task {
                            await viewModel.cleanup()
                            dismiss()
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Cancel")

                    Spacer()

                    // Flash toggle (if available)
                    if viewModel.isFlashAvailable {
                        Button(action: {
                            viewModel.toggleFlash()
                        }) {
                            Image(systemName: flashIcon)
                                .font(.title2)
                                .foregroundStyle(.white)
                                .padding(12)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .accessibilityLabel("Flash: \(flashLabel)")
                    }
                }

                // Guidance text at top (iOS HIG best practice)
                Text("Align your bookshelf in the frame")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 2)
            }
            .padding()

            Spacer()

            // Bottom controls
            HStack {
                Color.clear.frame(width: 70) // Balance layout

                Spacer()

                // Capture button
                Button(action: {
                    Task {
                        await viewModel.capturePhoto()
                    }
                }) {
                    ZStack {
                        // Inner circle
                        Circle()
                            .fill(.white)
                            .frame(width: 70, height: 70)

                        // Outer ring
                        Circle()
                            .stroke(.white, lineWidth: 4)
                            .frame(width: 82, height: 82)
                    }
                }
                .disabled(viewModel.cameraState == .capturing)
                .opacity(viewModel.cameraState == .capturing ? 0.5 : 1.0)
                .accessibilityLabel("Take photo")
                .sensoryFeedback(.impact, trigger: viewModel.cameraState == .capturing)

                Spacer()

                Color.clear.frame(width: 70) // Balance layout
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            VStack(spacing: 12) {
                Text("Camera Error")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 12) {
                Button("Retry") {
                    Task {
                        await viewModel.retrySetup()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(themeStore.primaryColor)

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Helpers

    private var flashIcon: String {
        switch viewModel.flashMode {
        case .auto:
            return "bolt.badge.automatic"
        case .on:
            return "bolt.fill"
        case .off:
            return "bolt.slash.fill"
        @unknown default:
            return "bolt.badge.automatic"
        }
    }

    private var flashLabel: String {
        switch viewModel.flashMode {
        case .auto: return "Auto"
        case .on: return "On"
        case .off: return "Off"
        @unknown default: return "Auto"
        }
    }
}

// MARK: - Photo Review View

/// Post-capture review sheet with retake/confirm actions.
private struct PhotoReviewView: View {
    // MARK: - Environment

    @Environment(\.iOS26ThemeStore) private var themeStore

    // MARK: - Properties

    let image: UIImage
    let onUsePhoto: (UIImage) -> Void
    let onRetake: () -> Void

    // MARK: - State

    @State private var isProcessing = false

    // MARK: - Body

    var body: some View {
        ZStack {
            // Full screen captured image
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .ignoresSafeArea()
                .background(Color.black)

            // Controls overlay
            VStack {
                Spacer()

                HStack(spacing: 40) {
                    // Retake
                    Button(action: onRetake) {
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                                .font(.title)
                            Text("Retake")
                                .font(.caption)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    .disabled(isProcessing)
                    .accessibilityLabel("Retake photo")

                    // Use photo
                    Button(action: {
                        isProcessing = true
                        onUsePhoto(image)
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title)
                            Text("Use Photo")
                                .font(.caption)
                        }
                        .foregroundStyle(themeStore.primaryColor)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    .disabled(isProcessing)
                    .accessibilityLabel("Use this photo")
                }
                .padding(.bottom, 40)
            }

            // Processing indicator
            if isProcessing {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)

                    Text("Processing...")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

#endif  // os(iOS)
