import SwiftUI
@preconcurrency import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

/// Modern SwiftUI camera preview component with proper error handling
/// Designed for Swift 6 concurrency and clean separation of concerns
struct ModernCameraPreview: View {
    // MARK: - Configuration

    struct Configuration {
        let regionOfInterest: CGRect?
        let showFocusIndicator: Bool
        let showScanningOverlay: Bool
        let enableTapToFocus: Bool
        let aspectRatio: CGFloat?
        let overlayStyle: ScanningOverlayStyle

        static let `default` = Configuration(
            regionOfInterest: nil,
            showFocusIndicator: true,
            showScanningOverlay: true,
            enableTapToFocus: true,
            aspectRatio: nil,
            overlayStyle: .standard
        )

        static let isbnScanning = Configuration(
            regionOfInterest: CGRect(x: 0.2, y: 0.3, width: 0.6, height: 0.4),
            showFocusIndicator: true,
            showScanningOverlay: true,
            enableTapToFocus: true,
            aspectRatio: 4/3,
            overlayStyle: .isbn
        )
    }

    enum ScanningOverlayStyle {
        case standard
        case isbn
        case minimal
    }

    // MARK: - Properties

    private let configuration: Configuration
    private let onError: (CameraError) -> Void
    private let detectionConfiguration: BarcodeDetectionService.Configuration

    private let cameraManager: CameraManager
    @State private var detectionService: BarcodeDetectionService?
    @State private var sessionState: CameraSessionState = .idle
    @State private var focusPoint: CGPoint?
    @State private var showingFocusIndicator = false

    // MARK: - Initialization

    init(
        cameraManager: CameraManager,
        configuration: Configuration = .default,
        detectionConfiguration: BarcodeDetectionService.Configuration = .default,
        onError: @escaping (CameraError) -> Void = { _ in }
    ) {
        self.configuration = configuration
        self.onError = onError
        self.detectionConfiguration = detectionConfiguration
        self.cameraManager = cameraManager

        // Detection service will be initialized in onAppear
        self._detectionService = State(initialValue: nil)
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Camera preview layer
                CameraPreviewLayer(
                    cameraManager: cameraManager,
                    sessionState: $sessionState
                )
                .onTapGesture { location in
                    if configuration.enableTapToFocus {
                        handleTapToFocus(at: location, in: geometry.size)
                    }
                }

                // Focus indicator
                if configuration.showFocusIndicator, let focusPoint = focusPoint, showingFocusIndicator {
                    FocusIndicator()
                        .position(focusPoint)
                        .transition(.scale.combined(with: .opacity))
                        .zIndex(1)
                }

                // Scanning overlay
                if configuration.showScanningOverlay {
                    ScanningOverlay(
                        regionOfInterest: configuration.regionOfInterest,
                        style: configuration.overlayStyle
                    )
                        .allowsHitTesting(false)
                        .zIndex(2)
                }

                // Error overlay
                if case .error(let error) = sessionState {
                    ErrorOverlay(error: error, onRetry: startSession)
                        .zIndex(3)
                }
            }
        }
        .aspectRatio(configuration.aspectRatio, contentMode: .fit)
        .onAppear {
            // Initialize detection service if needed
            if detectionService == nil {
                Task { @CameraSessionActor in
                    let service = BarcodeDetectionService(configuration: detectionConfiguration)
                    await MainActor.run {
                        detectionService = service
                    }
                }
            }
            startSession()
        }
        .onDisappear {
            stopSession()
        }
    }

    // MARK: - Public Methods

    /// Start barcode detection and return AsyncStream of ISBN detections
    func startISBNDetection() -> AsyncStream<ISBNValidator.ISBN> {
        guard let detectionService = detectionService else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }
        let manager = cameraManager
        return AsyncStream { continuation in
            Task { @CameraSessionActor in
                for await isbn in detectionService.isbnDetectionStream(cameraManager: manager) {
                    continuation.yield(isbn)
                }
                continuation.finish()
            }
        }
    }

    /// Start general barcode detection
    func startBarcodeDetection() -> AsyncStream<BarcodeDetectionService.BarcodeDetection> {
        guard let detectionService = detectionService else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }
        let manager = cameraManager
        return AsyncStream { continuation in
            Task { @CameraSessionActor in
                for await detection in detectionService.startDetection(cameraManager: manager) {
                    continuation.yield(detection)
                }
                continuation.finish()
            }
        }
    }

    /// Toggle torch (flashlight)
    func toggleTorch() async {
        do {
            try await cameraManager.toggleTorch()
        } catch {
            if let cameraError = error as? CameraError {
                onError(cameraError)
            }
        }
    }

    /// Focus at center of preview
    func focusAtCenter() async {
        do {
            try await cameraManager.focusAtCenter()
            await showFocusAnimation(at: CGPoint(x: 0.5, y: 0.5))
        } catch {
            if let cameraError = error as? CameraError {
                onError(cameraError)
            }
        }
    }

    // MARK: - Private Methods

    private func startSession() {
        Task {
            do {
                sessionState = .configuring
                _ = try await cameraManager.startSession()
                sessionState = .running
            } catch {
                let cameraError = error as? CameraError ?? .sessionConfigurationFailed
                sessionState = .error(cameraError)
                onError(cameraError)
            }
        }
    }

    private func stopSession() {
        Task {
            await cameraManager.stopSession()
            await detectionService?.stopDetection()
            sessionState = .stopped
        }
    }

    private func handleTapToFocus(at location: CGPoint, in size: CGSize) {
        Task {
            do {
                // Convert tap location to camera coordinates
                _ = CGPoint(
                    x: location.x / size.width,
                    y: location.y / size.height
                )
                // TODO: Pass normalizedPoint to focus method when implemented

                // Show focus animation
                await showFocusAnimation(at: location)

                // Focus camera (this would need to be implemented in CameraManager)
                try await cameraManager.focusAtCenter()

            } catch {
                if let cameraError = error as? CameraError {
                    onError(cameraError)
                }
            }
        }
    }

    @MainActor
    private func showFocusAnimation(at point: CGPoint) async {
        focusPoint = point

        withAnimation(.easeInOut(duration: 0.2)) {
            showingFocusIndicator = true
        }

        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds

        withAnimation(.easeInOut(duration: 0.3)) {
            showingFocusIndicator = false
        }
    }
}

// MARK: - Camera Preview Layer

private struct CameraPreviewLayer: UIViewRepresentable {
    let cameraManager: CameraManager
    @Binding var sessionState: CameraSessionState

    func makeUIView(context: Context) -> CameraPreviewUIView {
        CameraPreviewUIView()
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        Task {
            await uiView.updateSession(cameraManager: cameraManager)
        }
    }
}

private final class CameraPreviewUIView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer?

    @MainActor
    func updateSession(cameraManager: CameraManager) async {
        guard previewLayer == nil else { return }

        do {
            let session = try await cameraManager.startSession()

            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = bounds

            layer.addSublayer(previewLayer)
            self.previewLayer = previewLayer
        } catch {
            // Handle error through parent view
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

// MARK: - Focus Indicator

private struct FocusIndicator: View {
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Circle()
            .stroke(Color.yellow, lineWidth: 2)
            .frame(width: 60, height: 60)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.3).repeatCount(2, autoreverses: true)) {
                    scale = 0.8
                }
            }
    }
}

// MARK: - Error Overlay

private struct ErrorOverlay: View {
    let error: CameraError
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.yellow)

            Text(error.localizedDescription)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundColor(.white)

            if case .permissionDenied = error {
                Button("Open Settings") {
                    #if canImport(UIKit)
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsURL)
                    }
                    #endif
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.white)
                .cornerRadius(8)
            } else {
                Button("Retry", action: onRetry)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
        .padding()
    }
}

// MARK: - Modern Scanning Overlay

private struct ScanningOverlay: View {
    let regionOfInterest: CGRect?
    let style: ModernCameraPreview.ScanningOverlayStyle
    @State private var isScanning = false

    var body: some View {
        ZStack {
            // Darkened background
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            // Scanning frame
            VStack {
                Spacer()

                ZStack {
                    // Frame based on style
                    switch style {
                    case .standard:
                        standardScanningFrame
                    case .isbn:
                        isbnScanningFrame
                    case .minimal:
                        minimalScanningFrame
                    }
                }

                Spacer()
            }
        }
        .onAppear {
            isScanning = true
        }
    }

    @ViewBuilder
    private var standardScanningFrame: some View {
        let frameSize = regionOfInterest ?? CGRect(x: 0, y: 0, width: 280, height: 140)

        RoundedRectangle(cornerRadius: 12)
            .fill(Color.clear)
            .frame(width: frameSize.width, height: frameSize.height)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white, lineWidth: 2)
            )
            .overlay(animatedScanLine(width: frameSize.width, height: frameSize.height))
    }

    @ViewBuilder
    private var isbnScanningFrame: some View {
        let frameSize = regionOfInterest ?? CGRect(x: 0, y: 0, width: 300, height: 120)

        RoundedRectangle(cornerRadius: 8)
            .fill(Color.clear)
            .frame(width: frameSize.width, height: frameSize.height)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue, lineWidth: 3)
            )
            .overlay(
                // Corner indicators for ISBN scanning
                VStack {
                    HStack {
                        cornerMarker
                        Spacer()
                        cornerMarker
                    }
                    Spacer()
                    HStack {
                        cornerMarker
                        Spacer()
                        cornerMarker
                    }
                }
                .padding(8)
            )
            .overlay(animatedScanLine(width: frameSize.width, height: frameSize.height, color: .blue))
    }

    @ViewBuilder
    private var minimalScanningFrame: some View {
        let frameSize = regionOfInterest ?? CGRect(x: 0, y: 0, width: 260, height: 100)

        Rectangle()
            .fill(Color.clear)
            .frame(width: frameSize.width, height: frameSize.height)
            .overlay(
                Rectangle()
                    .stroke(Color.white.opacity(0.8), lineWidth: 1)
            )
            .overlay(animatedScanLine(width: frameSize.width, height: frameSize.height, thickness: 1))
    }

    private var cornerMarker: some View {
        Rectangle()
            .fill(Color.blue)
            .frame(width: 20, height: 3)
    }

    private func animatedScanLine(width: CGFloat, height: CGFloat, color: Color = .red, thickness: CGFloat = 3) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, color, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: max(0, width - 20), height: thickness)
            .offset(y: isScanning ? -height/2 + 20 : height/2 - 20)
            .animation(
                .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                value: isScanning
            )
    }
}

// MARK: - Convenience Initializers

extension ModernCameraPreview {
    /// Create preview specifically for ISBN barcode scanning
    static func forISBNScanning(
        cameraManager: CameraManager,
        onError: @escaping (CameraError) -> Void = { _ in }
    ) -> ModernCameraPreview {
        ModernCameraPreview(
            cameraManager: cameraManager,
            configuration: .isbnScanning,
            onError: onError
        )
    }

    /// Create minimal preview without overlays
    static func minimal(
        cameraManager: CameraManager,
        aspectRatio: CGFloat = 16/9,
        onError: @escaping (CameraError) -> Void = { _ in }
    ) -> ModernCameraPreview {
        let config = Configuration(
            regionOfInterest: nil,
            showFocusIndicator: false,
            showScanningOverlay: false,
            enableTapToFocus: false,
            aspectRatio: aspectRatio,
            overlayStyle: .minimal
        )
        return ModernCameraPreview(
            cameraManager: cameraManager,
            configuration: config,
            onError: onError
        )
    }

    /// Create full-featured preview
    static func fullFeatured(
        cameraManager: CameraManager,
        onError: @escaping (CameraError) -> Void = { _ in }
    ) -> ModernCameraPreview {
        ModernCameraPreview(
            cameraManager: cameraManager,
            configuration: .default,
            onError: onError
        )
    }
}