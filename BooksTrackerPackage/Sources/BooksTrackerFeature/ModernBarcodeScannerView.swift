import SwiftUI
import AVFoundation

#if canImport(UIKit)
import UIKit
#endif

/// Modern barcode scanner view using Swift 6 concurrency patterns
/// Replaces the legacy BarcodeScanner.swift with clean architecture
@available(iOS 26.0, *)
struct ModernBarcodeScannerView: View {
    // MARK: - Properties

    @Environment(\.dismiss) private var dismiss
    @Environment(\.iOS26ThemeStore) private var themeStore

    let onISBNScanned: (ISBNValidator.ISBN) -> Void

    @State private var permissionStatus: AVAuthorizationStatus = .notDetermined
    @State private var showingPermissionAlert = false
    @State private var isTorchOn = false
    @State private var scanFeedback: ScanFeedback?
    @State private var isbnDetectionTask: Task<Void, Never>?
    @State private var cameraManager: CameraManager?

    // Camera configuration
    private let cameraConfiguration = ModernCameraPreview.Configuration(
        regionOfInterest: CGRect(x: 0.1, y: 0.3, width: 0.8, height: 0.4),
        showFocusIndicator: true,
        showScanningOverlay: true,
        enableTapToFocus: true,
        aspectRatio: nil,
        overlayStyle: .isbn
    )

    private let detectionConfiguration = BarcodeDetectionService.Configuration(
        enableVisionDetection: true,
        enableAVFoundationFallback: true,
        isbnValidationEnabled: true,
        duplicateThrottleInterval: 2.0,
        regionOfInterest: CGRect(x: 0.1, y: 0.3, width: 0.8, height: 0.4)
    )

    // MARK: - Feedback State

    private enum ScanFeedback: Equatable {
        case scanning
        case detected(String)
        case processing
        case error(String)

        var message: String {
            switch self {
            case .scanning:
                return "Position the barcode within the frame"
            case .detected(let isbn):
                return "ISBN detected: \(isbn)"
            case .processing:
                return "Processing barcode..."
            case .error(let message):
                return message
            }
        }

        var color: Color {
            switch self {
            case .scanning:
                return .white.opacity(0.8)
            case .detected:
                return .green
            case .processing:
                return .yellow
            case .error:
                return .red
            }
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // Theme-aware background gradient
                LinearGradient(
                    colors: [themeStore.primaryColor.opacity(0.3), themeStore.primaryColor.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(0.3)
                .ignoresSafeArea()

                // Main content based on permission status
                Group {
                    switch permissionStatus {
                    case .authorized:
                        authorizedContent
                    case .denied, .restricted:
                        permissionDeniedContent
                    case .notDetermined:
                        permissionRequestContent
                    @unknown default:
                        permissionRequestContent
                    }
                }
            }
            .themedBackground()
            .navigationTitle("Scan ISBN")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        cleanup()
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            #endif
        }
        .onAppear {
            print("🔍 DEBUG: ModernBarcodeScannerView appeared")
            print("🔍 DEBUG: Permission status: \(permissionStatus.rawValue)")
            checkCameraPermission()
        }
        .onDisappear {
            print("🔍 DEBUG: ModernBarcodeScannerView disappeared")
            cleanup()
        }
        .alert("Camera Permission Required", isPresented: $showingPermissionAlert) {
            Button("Settings") {
                openSettings()
            }
            Button("Cancel", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("Please allow camera access in Settings to scan barcodes.")
        }
    }

    // MARK: - Content Views

    @ViewBuilder
    private var authorizedContent: some View {
        ZStack {
            // Camera preview - pass shared cameraManager
            if let cameraManager = cameraManager {
                ModernCameraPreview(
                    cameraManager: cameraManager,
                    configuration: cameraConfiguration,
                    detectionConfiguration: detectionConfiguration
                ) { error in
                    handleCameraError(error)
                }
                .ignoresSafeArea()
                .onAppear {
                    startISBNDetection()
                }
            }

            // Controls overlay
            VStack {
                // Top controls
                HStack {
                    Spacer()

                    VStack(spacing: 12) {
                        // Torch button
                        Button(action: toggleTorch) {
                            Image(systemName: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .themedGlass()
                        }
                        .accessibilityLabel(isTorchOn ? "Turn off torch" : "Turn on torch")

                        // Focus button
                        Button(action: focusCamera) {
                            Image(systemName: "camera.metering.center.weighted")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .themedGlass()
                        }
                        .accessibilityLabel("Focus camera")
                    }
                }
                .padding(.trailing)
                .padding(.top, 60)

                Spacer()

                // Bottom feedback
                feedbackView
                    .padding(.bottom, 100)
            }
        }
    }

    @ViewBuilder
    private var permissionDeniedContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.fill")
                .font(.system(size: 64))
                .foregroundColor(.white.opacity(0.6))

            Text("Camera Access Required")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Text("Please enable camera access in Settings to scan ISBN barcodes.")
                .font(.body)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Open Settings") {
                openSettings()
            }
            .foregroundColor(themeStore.primaryColor)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.white)
            .cornerRadius(8)
        }
    }

    @ViewBuilder
    private var permissionRequestContent: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

            Text("Requesting Camera Access...")
                .font(.headline)
                .foregroundColor(.white)
        }
    }

    @ViewBuilder
    private var feedbackView: some View {
        VStack(spacing: 16) {
            Text(scanFeedback?.message ?? "Position the barcode within the frame")
                .font(.body)
                .foregroundColor(scanFeedback?.color ?? .white.opacity(0.8))
                .multilineTextAlignment(.center)
                .animation(.easeInOut(duration: 0.3), value: scanFeedback)

            // Processing indicator
            if case .processing = scanFeedback {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.yellow)
            }
        }
        .padding()
        .themedGlass()
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Actions

    private func checkCameraPermission() {
        print("🔍 DEBUG: checkCameraPermission() called")
        Task { @CameraSessionActor in
            let status = CameraManager.cameraPermissionStatus
            print("🔍 DEBUG: Camera permission status: \(status.rawValue)")
            await MainActor.run {
                permissionStatus = status
            }

            if status == .notDetermined {
                print("🔍 DEBUG: Requesting camera permission...")
                let granted = await CameraManager.requestCameraPermission()
                print("🔍 DEBUG: Camera permission granted: \(granted)")
                await MainActor.run {
                    permissionStatus = granted ? .authorized : .denied
                    if !granted {
                        showingPermissionAlert = true
                    }
                }
            } else if status == .denied || status == .restricted {
                print("🔍 DEBUG: Camera permission denied or restricted")
                await MainActor.run {
                    showingPermissionAlert = true
                }
            }
        }
    }

    private func startISBNDetection() {
        // Cancel any existing detection task
        isbnDetectionTask?.cancel()

        isbnDetectionTask = Task {
            await handleISBNDetectionStream()
        }
    }

    private func handleISBNDetectionStream() async {
        // Initialize scanning state
        await MainActor.run {
            scanFeedback = .scanning
        }

        // Create camera manager once if not already created
        if cameraManager == nil {
            // FIX: Directly initialize CameraManager without explicit actor wrapper
            // Swift concurrency runtime handles actor initialization correctly
            // This prevents deadlock between @CameraSessionActor and MainActor
            let manager = CameraManager()

            await MainActor.run {
                cameraManager = manager
            }
        }

        // Use the existing camera manager instance
        guard let manager = cameraManager else {
            await MainActor.run {
                handleCameraError(.deviceUnavailable)
            }
            return
        }

        // Create detection service
        let detectionService = await Task { @CameraSessionActor in
            return BarcodeDetectionService(configuration: detectionConfiguration)
        }.value

        // Start the detection stream using the shared camera manager
        for await isbn in await detectionService.isbnDetectionStream(cameraManager: manager) {
            handleISBNDetected(isbn)
            break // Exit after first successful detection
        }
    }

    @MainActor
    private func handleISBNDetected(_ isbn: ISBNValidator.ISBN) {
        // Provide immediate feedback
        withAnimation {
            scanFeedback = .detected(isbn.displayValue)
        }

        // Haptic feedback
        #if canImport(UIKit)
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        #endif

        // Brief processing state
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            await MainActor.run {
                withAnimation {
                    scanFeedback = .processing
                }
            }

            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            await MainActor.run {
                onISBNScanned(isbn)
                cleanup()
                dismiss()
            }
        }
    }

    private func toggleTorch() {
        // Haptic feedback
        #if canImport(UIKit)
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        #endif

        // Toggle torch via camera manager
        Task {
            guard let manager = cameraManager else {
                await MainActor.run {
                    handleCameraError(.deviceUnavailable)
                }
                return
            }

            do {
                try await manager.toggleTorch()
                let torchState = manager.isTorchOn
                await MainActor.run {
                    isTorchOn = torchState
                }
            } catch {
                await MainActor.run {
                    handleCameraError(.torchUnavailable)
                }
            }
        }
    }

    private func focusCamera() {
        // Haptic feedback
        #if canImport(UIKit)
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        #endif

        // Temporary feedback
        withAnimation {
            scanFeedback = .scanning
        }

        // Focus camera via camera manager
        Task {
            guard let manager = cameraManager else {
                await MainActor.run {
                    handleCameraError(.deviceUnavailable)
                }
                return
            }

            do {
                try await manager.focusAtCenter()
            } catch {
                await MainActor.run {
                    handleCameraError(.focusUnavailable)
                }
            }
        }
    }

    private func handleCameraError(_ error: CameraError) {
        withAnimation {
            scanFeedback = .error(error.localizedDescription)
        }

        // Auto-clear error after delay
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            await MainActor.run {
                if case .error = scanFeedback {
                    withAnimation {
                        scanFeedback = .scanning
                    }
                }
            }
        }
    }

    private func openSettings() {
        #if canImport(UIKit)
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
        #endif
    }

    private func cleanup() {
        // Cancel detection task
        isbnDetectionTask?.cancel()
        isbnDetectionTask = nil

        // Stop camera session and cleanup
        Task {
            if let manager = cameraManager {
                // Turn off torch if enabled
                if isTorchOn {
                    try? await manager.setTorchMode(.off)
                }

                // Stop the camera session
                await manager.stopSession()
            }

            await MainActor.run {
                isTorchOn = false
                cameraManager = nil
            }
        }
    }
}

// MARK: - Integration Extension

@available(iOS 26.0, *)
extension ModernBarcodeScannerView {
    /// Create scanner view with legacy callback compatibility
    static func withCallback(onBarcodeScanned: @escaping (String) -> Void) -> some View {
        ModernBarcodeScannerView { isbn in
            onBarcodeScanned(isbn.normalizedValue)
        }
    }
}