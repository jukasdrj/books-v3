import AVFoundation
import Vision
import Combine

/// Modern AsyncStream-based barcode detection service
/// Provides real-time barcode scanning with intelligent filtering and validation
@CameraSessionActor
final class BarcodeDetectionService {

    // MARK: - Detection Result Types

    struct BarcodeDetection: Sendable {
        let value: String
        let confidence: Float
        let timestamp: Date
        let detectionMethod: DetectionMethod
        let isbn: ISBNValidator.ISBN?

        enum DetectionMethod: Sendable {
            case vision
            case avFoundation
        }
    }

    enum DetectionError: LocalizedError, Sendable {
        case sessionNotRunning
        case noValidBarcodes
        case processingFailed(Error)

        var errorDescription: String? {
            switch self {
            case .sessionNotRunning:
                return "Camera session is not running"
            case .noValidBarcodes:
                return "No valid barcodes found in frame"
            case .processingFailed(let error):
                return "Barcode processing failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Configuration

    struct Configuration {
        let enableVisionDetection: Bool
        let enableAVFoundationFallback: Bool
        let isbnValidationEnabled: Bool
        let duplicateThrottleInterval: TimeInterval
        let regionOfInterest: CGRect?

        static let `default` = Configuration(
            enableVisionDetection: true,
            enableAVFoundationFallback: true,
            isbnValidationEnabled: true,
            duplicateThrottleInterval: 2.0,
            regionOfInterest: nil
        )
    }

    // MARK: - Private Properties

    private let configuration: Configuration
    private let visionQueue = DispatchQueue(label: "barcode.vision.queue", qos: .userInitiated)

    // Throttling state
    private var lastDetectionTime: Date = .distantPast
    private var lastDetectedValue: String = ""

    // Stream management
    private var detectionContinuation: AsyncStream<BarcodeDetection>.Continuation?

    // MARK: - Initialization

    nonisolated init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    // MARK: - Public Interface

    /// Start barcode detection stream
    /// Returns an AsyncStream of barcode detections
    func startDetection(cameraManager: CameraManager) -> AsyncStream<BarcodeDetection> {
        // This AsyncStream uses the "delegate bridging" pattern, which is ideal for
        // event-driven systems like AVFoundation's camera output. It does not use
        // a `while !Task.isCancelled` loop because data is pushed from the delegate
        // callbacks, not pulled via polling.
        //
        // See `docs/CONCURRENCY_GUIDE.md` for more details on this pattern.
        AsyncStream<BarcodeDetection> { continuation in
            self.detectionContinuation = continuation

            Task {
                await setupDetection(cameraManager: cameraManager, continuation: continuation)
            }

            continuation.onTermination = { _ in
                Task {
                    await self.stopDetection(cameraManager: cameraManager)
                }
            }
        }
    }

    /// Stop barcode detection
    func stopDetection() async {
        detectionContinuation?.finish()
        detectionContinuation = nil
    }

    // MARK: - Private Implementation

    private func setupDetection(
        cameraManager: CameraManager,
        continuation: AsyncStream<BarcodeDetection>.Continuation
    ) async {
        do {
            let session = try await cameraManager.startSession()

            // Setup Vision detection if enabled
            if configuration.enableVisionDetection {
                await setupVisionDetection(session: session)
            }

            // Setup AVFoundation fallback if enabled
            if configuration.enableAVFoundationFallback {
                await setupAVFoundationDetection(session: session)
            }

        } catch {
            let _ = DetectionError.processingFailed(error)
            continuation.finish()
        }
    }

    private func stopDetection(cameraManager: CameraManager) async {
        await cameraManager.stopSession()
    }

    private func setupVisionDetection(session: AVCaptureSession) async {
        // Find video output
        guard let videoOutput = session.outputs.compactMap({ $0 as? AVCaptureVideoDataOutput }).first else {
            return
        }

        // Setup delegate for Vision processing
        let delegate = VisionProcessingDelegate(
            service: self,
            configuration: configuration
        )

        videoOutput.setSampleBufferDelegate(delegate, queue: visionQueue)
    }

    private func setupAVFoundationDetection(session: AVCaptureSession) async {
        // Find metadata output
        guard let metadataOutput = session.outputs.compactMap({ $0 as? AVCaptureMetadataOutput }).first else {
            return
        }

        // Setup delegate for AVFoundation processing
        let delegate = MetadataProcessingDelegate(
            service: self,
            configuration: configuration
        )

        metadataOutput.setMetadataObjectsDelegate(delegate, queue: visionQueue)
    }

    internal func processDetectedBarcode(
        value: String,
        confidence: Float,
        method: BarcodeDetection.DetectionMethod
    ) {
        // Apply throttling to prevent duplicate detections
        let now = Date()
        if value == lastDetectedValue &&
           now.timeIntervalSince(lastDetectionTime) < configuration.duplicateThrottleInterval {
            return
        }

        lastDetectionTime = now
        lastDetectedValue = value

        // Validate as ISBN if enabled
        var isbn: ISBNValidator.ISBN?
        if configuration.isbnValidationEnabled {
            switch ISBNValidator.validate(value) {
            case .valid(let validISBN):
                isbn = validISBN
            case .invalid:
                // Not a valid ISBN, skip detection
                return
            }
        }

        // Create detection result
        let detection = BarcodeDetection(
            value: value,
            confidence: confidence,
            timestamp: now,
            detectionMethod: method,
            isbn: isbn
        )

        // Send through stream
        detectionContinuation?.yield(detection)
    }
}

// MARK: - Vision Processing Delegate

private final class VisionProcessingDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private weak var service: BarcodeDetectionService?
    private let configuration: BarcodeDetectionService.Configuration

    init(service: BarcodeDetectionService, configuration: BarcodeDetectionService.Configuration) {
        self.service = service
        self.configuration = configuration
        super.init()
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let service = service else {
            return
        }

        // Create Vision request
        let request = VNDetectBarcodesRequest { [weak service] request, error in
            guard let service = service,
                  error == nil,
                  let results = request.results as? [VNBarcodeObservation] else {
                return
            }

            // Process each detected barcode
            for observation in results {
                guard let payloadString = observation.payloadStringValue else { continue }

                // Filter by region of interest if configured
                if let roi = self.configuration.regionOfInterest {
                    let boundingBox = observation.boundingBox
                    if !roi.intersects(boundingBox) {
                        continue
                    }
                }

                let confidence = observation.confidence
                Task { @CameraSessionActor in
                    service.processDetectedBarcode(
                        value: payloadString,
                        confidence: confidence,
                        method: .vision
                    )
                }
            }
        }

        // Configure barcode types
        request.symbologies = [
            VNBarcodeSymbology.ean13,
            VNBarcodeSymbology.ean8,
            VNBarcodeSymbology.upce,
            VNBarcodeSymbology.code128,
            VNBarcodeSymbology.code39,
            VNBarcodeSymbology.code93,
            VNBarcodeSymbology.i2of5
        ]

        // Perform request
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            // Silently handle Vision processing errors
        }
    }
}

// MARK: - Metadata Processing Delegate

private final class MetadataProcessingDelegate: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    private weak var service: BarcodeDetectionService?
    private let configuration: BarcodeDetectionService.Configuration

    init(service: BarcodeDetectionService, configuration: BarcodeDetectionService.Configuration) {
        self.service = service
        self.configuration = configuration
        super.init()
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let service = service else { return }

        for metadataObject in metadataObjects {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
                  let stringValue = readableObject.stringValue else {
                continue
            }

            // Filter by region of interest if configured
            if let roi = configuration.regionOfInterest {
                if !roi.intersects(readableObject.bounds) {
                    continue
                }
            }

            Task { @CameraSessionActor in
                service.processDetectedBarcode(
                    value: stringValue,
                    confidence: 1.0, // AVFoundation doesn't provide confidence
                    method: .avFoundation
                )
            }
        }
    }
}

// MARK: - Convenience Extensions

extension BarcodeDetectionService {
    /// Create a stream that only emits valid ISBN detections
    func isbnDetectionStream(cameraManager: CameraManager) -> AsyncStream<ISBNValidator.ISBN> {
        AsyncStream { continuation in
            Task {
                for await detection in startDetection(cameraManager: cameraManager) {
                    if let isbn = detection.isbn {
                        continuation.yield(isbn)
                    }
                }
                continuation.finish()
            }
        }
    }
}