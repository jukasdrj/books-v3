#if os(iOS)
@preconcurrency import AVFoundation
import Vision
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Actor-based camera session manager for barcode scanning
/// Provides Swift 6 compliant concurrency and session lifecycle management
@globalActor
actor CameraSessionActor {
    static let shared = CameraSessionActor()
}

/// Represents different types of camera-related errors
enum CameraError: LocalizedError {
    case permissionDenied
    case deviceUnavailable
    case sessionConfigurationFailed
    case torchUnavailable
    case focusUnavailable
    case photoCaptureFailed(Error?)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera permission is required to scan barcodes"
        case .deviceUnavailable:
            return "Camera device is not available"
        case .sessionConfigurationFailed:
            return "Failed to configure camera session"
        case .torchUnavailable:
            return "Torch is not available on this device"
        case .focusUnavailable:
            return "Auto-focus is not available on this device"
        case .photoCaptureFailed(let error):
            return "Failed to capture photo: \(error?.localizedDescription ?? "Unknown error")"
        }
    }
}

/// Session state for camera operations
enum CameraSessionState: Equatable {
    case idle
    case configuring
    case running
    case stopped
    case error(CameraError)

    static func == (lhs: CameraSessionState, rhs: CameraSessionState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.configuring, .configuring), (.running, .running), (.stopped, .stopped):
            return true
        case (.error, .error):
            return true // Consider all errors equal for state comparison
        default:
            return false
        }
    }
}

/// Camera session manager with Swift 6 concurrency compliance and ObservableObject support
@CameraSessionActor
final class CameraManager: ObservableObject {

    // MARK: - Published Properties
    @MainActor @Published var isTorchOn: Bool = false
    @MainActor @Published var isSessionRunning: Bool = false
    @MainActor @Published var lastError: CameraError?

    // MARK: - Private Properties
    private var captureSession: AVCaptureSession?
    private var videoDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var metadataOutput: AVCaptureMetadataOutput?
    private var photoOutput: AVCapturePhotoOutput?

    private var sessionState: CameraSessionState = .idle
    private let sessionQueue = DispatchQueue(label: "camera.session.queue", qos: .userInitiated)
    private let visionQueue = DispatchQueue(label: "camera.vision.queue", qos: .userInitiated)

    // MARK: - Public Interface

    /// Current session state
    var state: CameraSessionState {
        sessionState
    }

    /// Check if the device has torch capability
    var hasTorch: Bool {
        videoDevice?.hasTorch ?? false
    }

    /// Check if the device supports auto-focus
    var hasAutoFocus: Bool {
        videoDevice?.isFocusModeSupported(.autoFocus) ?? false
    }

    // MARK: - Session Management

    /// Configure and start the camera session
    func startSession() async throws -> AVCaptureSession {
        guard sessionState != .running else {
            guard let session = captureSession else {
                throw CameraError.sessionConfigurationFailed
            }
            return session
        }

        sessionState = .configuring

        do {
            let session = try await configureSession()
            sessionState = .running

            // Start session on background queue
            await withCheckedContinuation { continuation in
                sessionQueue.async {
                    session.startRunning()
                    continuation.resume()
                }
            }

            // Update published state on main actor
            await MainActor.run {
                isSessionRunning = true
                lastError = nil
            }

            return session
        } catch {
            sessionState = .error(error as? CameraError ?? .sessionConfigurationFailed)

            await MainActor.run {
                isSessionRunning = false
                lastError = error as? CameraError ?? .sessionConfigurationFailed
            }

            throw error
        }
    }

    /// Stop the camera session and clean up resources
    func stopSession() async {
        guard let session = captureSession else { return }

        sessionState = .stopped

        // Turn off torch before stopping
        if let device = videoDevice, device.hasTorch {
            try? await setTorchMode(.off)
        }

        await withCheckedContinuation { continuation in
            sessionQueue.async {
                session.stopRunning()
                continuation.resume()
            }
        }

        // Clean up resources
        captureSession = nil
        videoDevice = nil
        videoInput = nil
        videoOutput = nil
        metadataOutput = nil
        photoOutput = nil

        sessionState = .idle

        // Update published state on main actor
        await MainActor.run {
            isSessionRunning = false
            isTorchOn = false
        }
    }

    // MARK: - Photo Capture

    func takePhoto() async throws -> Data {
        guard let photoOutput = photoOutput else {
            throw CameraError.sessionConfigurationFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            let settings = AVCapturePhotoSettings()
            let delegate = PhotoCaptureDelegate(continuation: continuation)

            sessionQueue.async {
                photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    // MARK: - Device Controls

    /// Set torch mode (flashlight)
    func setTorchMode(_ mode: AVCaptureDevice.TorchMode) async throws {
        guard let device = videoDevice else {
            throw CameraError.deviceUnavailable
        }

        guard device.hasTorch else {
            throw CameraError.torchUnavailable
        }

        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    try device.lockForConfiguration()
                    device.torchMode = mode
                    device.unlockForConfiguration()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        // Update published state on main actor
        await MainActor.run {
            isTorchOn = (mode == .on)
            lastError = nil
        }
    }

    /// Toggle torch on/off
    func toggleTorch() async throws {
        let currentTorchState = await isTorchOn
        let newMode: AVCaptureDevice.TorchMode = currentTorchState ? .off : .on
        try await setTorchMode(newMode)
    }

    /// Focus at the center of the frame
    func focusAtCenter() async throws {
        guard let device = videoDevice else {
            throw CameraError.deviceUnavailable
        }

        guard device.isFocusModeSupported(.autoFocus) else {
            throw CameraError.focusUnavailable
        }

        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    try device.lockForConfiguration()

                    device.focusMode = .autoFocus
                    device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)

                    if device.isExposureModeSupported(.autoExpose) {
                        device.exposureMode = .autoExpose
                        device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                    }

                    device.unlockForConfiguration()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        // Update published state on main actor
        await MainActor.run {
            lastError = nil
        }
    }

    /// Set region of interest for optimized barcode detection
    /// - Parameter rect: Normalized rectangle (0.0-1.0) for region of interest
    func setRegionOfInterest(_ rect: CGRect) async {
        guard let metadataOutput = metadataOutput else { return }

        await withCheckedContinuation { continuation in
            sessionQueue.async {
                metadataOutput.rectOfInterest = rect
                continuation.resume()
            }
        }
    }

    /// Provides read-only access to the capture session for preview layer
    var session: AVCaptureSession? {
        captureSession
    }

    // MARK: - Private Methods

    private func configureSession() async throws -> AVCaptureSession {
        // Check camera permission
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        guard authStatus == .authorized else {
            throw CameraError.permissionDenied
        }

        let session = AVCaptureSession()
        session.beginConfiguration()

        // Configure video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            session.commitConfiguration()
            throw CameraError.deviceUnavailable
        }

        guard let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            session.commitConfiguration()
            throw CameraError.sessionConfigurationFailed
        }

        guard session.canAddInput(videoInput) else {
            session.commitConfiguration()
            throw CameraError.sessionConfigurationFailed
        }

        session.addInput(videoInput)

        // Store references
        self.videoDevice = videoDevice
        self.videoInput = videoInput
        self.captureSession = session

        // Configure device settings
        try await configureVideoDevice(videoDevice)

        // Add outputs
        try configureOutputs(session)

        session.commitConfiguration()
        return session
    }

    private func configureVideoDevice(_ device: AVCaptureDevice) async throws {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try device.lockForConfiguration()

                // Enable continuous auto focus
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }

                // Enable continuous auto exposure
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }

                // Optimize for barcode scanning (disable HDR for speed)
                if device.activeFormat.isVideoHDRSupported {
                    device.automaticallyAdjustsVideoHDREnabled = false
                    device.isVideoHDREnabled = false
                }

                device.unlockForConfiguration()
                continuation.resume()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func configureOutputs(_ session: AVCaptureSession) throws {
        // Video output for Vision framework
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        guard session.canAddOutput(videoOutput) else {
            throw CameraError.sessionConfigurationFailed
        }

        session.addOutput(videoOutput)
        self.videoOutput = videoOutput

        // Metadata output as fallback
        let metadataOutput = AVCaptureMetadataOutput()
        metadataOutput.metadataObjectTypes = [
            AVMetadataObject.ObjectType.ean13,
            AVMetadataObject.ObjectType.ean8,
            AVMetadataObject.ObjectType.upce,
            AVMetadataObject.ObjectType.code128,
            AVMetadataObject.ObjectType.code39,
            AVMetadataObject.ObjectType.code93,
            AVMetadataObject.ObjectType.interleaved2of5
        ]

        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            self.metadataOutput = metadataOutput
        }

        // Photo output for still images
        let photoOutput = AVCapturePhotoOutput()
        guard session.canAddOutput(photoOutput) else {
            throw CameraError.sessionConfigurationFailed
        }
        session.addOutput(photoOutput)
        self.photoOutput = photoOutput
    }

    // MARK: - Lifecycle Management

    /// Initialize lifecycle observers
    nonisolated init() {
        setupAppLifecycleObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)

        // Note: Cannot access actor-isolated properties in deinit
        // Cleanup will be handled by app lifecycle observers and explicit stopSession() calls
    }

    nonisolated private func setupAppLifecycleObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @CameraSessionActor in
                await self?.handleAppWillEnterForeground()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @CameraSessionActor in
                await self?.handleAppDidEnterBackground()
            }
        }
    }

    private func handleAppWillEnterForeground() async {
        guard let session = captureSession, sessionState == .stopped else { return }

        await withCheckedContinuation { continuation in
            sessionQueue.async {
                session.startRunning()
                continuation.resume()
            }
        }

        sessionState = .running
        await MainActor.run {
            isSessionRunning = true
        }
    }

    private func handleAppDidEnterBackground() async {
        guard let session = captureSession, sessionState == .running else { return }

        // Turn off torch when going to background
        if let device = videoDevice, device.hasTorch, await isTorchOn {
            try? await setTorchMode(.off)
        }

        await withCheckedContinuation { continuation in
            sessionQueue.async {
                session.stopRunning()
                continuation.resume()
            }
        }

        sessionState = .stopped
        await MainActor.run {
            isSessionRunning = false
        }
    }
}

// MARK: - Delegate Support

extension CameraManager {
    /// Sets delegates for video and metadata output
    /// - Parameters:
    ///   - videoDelegate: Delegate for video sample buffer output
    ///   - metadataDelegate: Delegate for metadata object detection
    ///   - delegateQueue: Queue for delegate callbacks
    func setDelegates(
        videoDelegate: AVCaptureVideoDataOutputSampleBufferDelegate?,
        metadataDelegate: AVCaptureMetadataOutputObjectsDelegate?,
        delegateQueue: DispatchQueue
    ) async {
        let currentVideoOutput = videoOutput
        let currentMetadataOutput = metadataOutput

        await withCheckedContinuation { continuation in
            sessionQueue.async {
                currentVideoOutput?.setSampleBufferDelegate(videoDelegate, queue: delegateQueue)
                currentMetadataOutput?.setMetadataObjectsDelegate(metadataDelegate, queue: delegateQueue)
                continuation.resume()
            }
        }
    }
}

// MARK: - Permission Management

extension CameraManager {

    /// Request camera permission asynchronously
    static func requestCameraPermission() async -> Bool {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)

        switch currentStatus {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// Check current camera permission status
    static var cameraPermissionStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }
}

// MARK: - Photo Capture Delegate

// SAFETY: @unchecked Sendable because continuation is used once then set to nil.
// AVFoundation callbacks are thread-safe. Short-lived object for single photo capture.
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<Data, Error>?

    init(continuation: CheckedContinuation<Data, Error>) {
        self.continuation = continuation
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let continuation = continuation else { return }

        if let error = error {
            continuation.resume(throwing: CameraError.photoCaptureFailed(error))
            self.continuation = nil
            return
        }

        guard let imageData = photo.fileDataRepresentation() else {
            continuation.resume(throwing: CameraError.photoCaptureFailed(nil))
            self.continuation = nil
            return
        }

        continuation.resume(returning: imageData)
        self.continuation = nil
    }
}

#endif  // os(iOS)