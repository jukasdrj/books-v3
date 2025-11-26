import SwiftUI
import VisionKit
#if canImport(UIKit)
import UIKit
#endif
import OSLog

@available(iOS 16.0, *)
private struct UnsupportedDeviceView: View {
    @Environment(\.iOS26ThemeStore) private var themeStore

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 64))
                .foregroundColor(.white.opacity(0.6))
                .accessibilityLabel("Barcode scanning unavailable")

            Text("Barcode Scanning Not Available")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Text("This device doesn't support the barcode scanner. Please use a device with an A12 Bionic chip or later (iPhone XS/XR+).")
                .font(.body)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [themeStore.primaryColor.opacity(0.3), themeStore.primaryColor.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

@available(iOS 16.0, *)
private struct PermissionDeniedView: View {
    @Environment(\.iOS26ThemeStore) private var themeStore

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.fill")
                .font(.system(size: 64))
                .foregroundColor(.white.opacity(0.6))
                .accessibilityLabel("Camera access required")

            Text("Camera Access Required")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Text("Please enable camera access in Settings to scan ISBN barcodes.")
                .font(.body)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Open Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            .foregroundColor(themeStore.primaryColor)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHint("Opens system settings to enable camera access")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [themeStore.primaryColor.opacity(0.3), themeStore.primaryColor.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

@available(iOS 16.0, *)
private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let onISBNScanned: (ISBNValidator.ISBN) -> Void
    let onInvalidBarcode: () -> Void
    @Binding var errorMessage: String?
    @Binding var shouldResetScanner: Bool
    @Environment(\.dismiss) private var dismiss
    private let logger = Logger(subsystem: "com.oooefam.booksV3", category: "ISBNScanner")

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false, // Disabled to fix #478 - prevents middle-screen positioning issue
            isHighlightingEnabled: true
        )

        scanner.delegate = context.coordinator

        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        if shouldResetScanner {
            uiViewController.stopScanning()
            do {
                try uiViewController.startScanning()
                shouldResetScanner = false
            } catch {
                logger.error("Failed to restart scanning: \(error.localizedDescription)")
                context.coordinator.handleError("Unable to restart scanner: \(error.localizedDescription)")
            }
            return
        }

        if !uiViewController.isScanning {
            do {
                try uiViewController.startScanning()
            } catch {
                logger.error("Failed to start scanning: \(error.localizedDescription)")
                context.coordinator.handleError("Unable to start scanner. Please ensure the camera is not in use by another app.")
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onISBNScanned: onISBNScanned,
            onInvalidBarcode: onInvalidBarcode,
            errorMessage: $errorMessage,
            shouldResetScanner: $shouldResetScanner,
            dismiss: dismiss
        )
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator _: Coordinator) {
        uiViewController.stopScanning()
        uiViewController.delegate = nil
    }

    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onISBNScanned: (ISBNValidator.ISBN) -> Void
        let onInvalidBarcode: () -> Void
        @Binding var errorMessage: String?
        @Binding var shouldResetScanner: Bool
        let dismiss: DismissAction
        private let logger = Logger(subsystem: "com.oooefam.booksV3", category: "ISBNScanner")

        init(
            onISBNScanned: @escaping (ISBNValidator.ISBN) -> Void,
            onInvalidBarcode: @escaping () -> Void,
            errorMessage: Binding<String?>,
            shouldResetScanner: Binding<Bool>,
            dismiss: DismissAction
        ) {
            self.onISBNScanned = onISBNScanned
            self.onInvalidBarcode = onInvalidBarcode
            self._errorMessage = errorMessage
            self._shouldResetScanner = shouldResetScanner
            self.dismiss = dismiss
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handleScannedItem(item, dataScanner: dataScanner)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard let firstItem = addedItems.first else { return }
            handleScannedItem(firstItem, dataScanner: dataScanner)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: Error) {
            logger.error("Scanner became unavailable: \(error.localizedDescription)")
            handleError("Scanner stopped unexpectedly: \(error.localizedDescription)")
        }

        func handleError(_ message: String) {
            Task { @MainActor in
                errorMessage = message
                // Let user dismiss the alert manually instead of auto-dismissing
            }
        }

        private func handleScannedItem(_ item: RecognizedItem, dataScanner: DataScannerViewController) {
            guard case .barcode(let barcode) = item,
                  let payload = barcode.payloadStringValue else {
                return
            }

            switch ISBNValidator.validate(payload) {
            case .valid(let isbn):
                // Haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()

                // Stop scanning
                dataScanner.stopScanning()

                // Callback and dismiss
                Task { @MainActor in
                    onISBNScanned(isbn)
                    dismiss()
                }

            case .invalid:
                let feedbackGenerator = UINotificationFeedbackGenerator()
                feedbackGenerator.notificationOccurred(.error)

                onInvalidBarcode()
                return
            }
        }
    }
}

@available(iOS 16.0, *)
private struct ScannerOverlayView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title.weight(.semibold))
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                }
                .accessibilityLabel("Close scanner")
                .padding([.top, .trailing])
            }
            Spacer()
            Text("Point camera at an ISBN barcode")
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .background(Color.black.opacity(0.6))
                .clipShape(Capsule())
                .padding(.bottom)
        }
    }
}

/// Apple-native barcode scanner using VisionKit DataScannerViewController
/// Follows official guidance from "Scanning data with the camera"
@available(iOS 16.0, *)
public struct ISBNScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var shouldResetScanner = false
    @State private var invalidFeedbackVisible = false
    @State private var invalidFeedbackTask: Task<Void, Never>?
    @State private var isLoading = false
    @State private var scannedISBN: String?
    @State private var rateLimitMessage: String?
    @State private var countdown: Int = 0
    @State private var countdownTask: Task<Void, Never>?
    let onWorkReceived: (Work) -> Void
    @Environment(\.modelContext) private var modelContext

    public init(onWorkReceived: @escaping (Work) -> Void) {
        self.onWorkReceived = onWorkReceived
    }

    public var body: some View {
        scannerContent
            .alert("Scanner Error", isPresented: errorBinding) {
                Button("Retry") {
                    errorMessage = nil
                    shouldResetScanner = true
                }

                Button("Close", role: .cancel) {
                    errorMessage = nil
                    dismiss()
                }
            } message: {
                if let rateLimitMessage {
                    Text(rateLimitMessage)
                } else if let errorMessage {
                    Text(errorMessage)
                }
            }
            .onDisappear {
                invalidFeedbackTask?.cancel()
                invalidFeedbackTask = nil
                countdownTask?.cancel()
                countdownTask = nil
            }
    }

    @ViewBuilder
    private var scannerContent: some View {
        if !DataScannerViewController.isSupported {
            UnsupportedDeviceView()
        } else if !DataScannerViewController.isAvailable {
            PermissionDeniedView()
        } else {
            ZStack {
                if isLoading {
                    ProgressView("Looking up ISBN...")
                } else {
                    DataScannerRepresentable(
                        onISBNScanned: { isbn in
                            handleScannedISBN(isbn.normalizedValue)
                        },
                        onInvalidBarcode: triggerInvalidBarcodeFeedback,
                        errorMessage: $errorMessage,
                        shouldResetScanner: $shouldResetScanner
                    )
                }
            }
            .ignoresSafeArea()
            .overlay {
                ScannerOverlayView()
            }
            .overlay(alignment: .bottom) {
                if invalidFeedbackVisible {
                    InvalidBarcodeFeedbackView()
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .padding(.bottom, 120)
                }
            }
        }
    }

    private func handleScannedISBN(_ isbn: String) {
        isLoading = true
        scannedISBN = isbn
        Task {
            let result = await EnrichmentService.shared.enrichBookV2(barcode: isbn, in: modelContext)
            isLoading = false
            switch result {
            case .success(let work):
                onWorkReceived(work)
                dismiss()
            case .failure(let error):
                if case .rateLimitExceeded(let retryAfter) = error {
                    startCountdown(duration: retryAfter)
                } else {
                    errorMessage = userFriendlyError(error, isbn: isbn)
                }
            }
        }
    }

    private func userFriendlyError(_ error: Error, isbn: String) -> String {
        if let enrichmentError = error as? EnrichmentError {
            switch enrichmentError {
            case .noMatchFound:
                return "No book found for ISBN \(isbn). Please try a different barcode."
            case .apiError(let message):
                return "An error occurred: \(message). Please try again."
            default:
                return "An unexpected error occurred. Please try again."
            }
        }
        return "An unexpected error occurred. Please try again."
    }

    private func startCountdown(duration: Int) {
        countdownTask?.cancel()
        countdown = duration
        countdownTask = Task { @MainActor in
            while countdown > 0 {
                rateLimitMessage = "Rate limit exceeded. Please try again in \(countdown) seconds."
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                countdown -= 1
            }
            rateLimitMessage = nil
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil || rateLimitMessage != nil }, set: { isPresented in
            if !isPresented {
                errorMessage = nil
                rateLimitMessage = nil
                countdownTask?.cancel()
            }
        })
    }

    private func triggerInvalidBarcodeFeedback() {
        invalidFeedbackTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            invalidFeedbackVisible = true
        }

        invalidFeedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                invalidFeedbackVisible = false
            }
        }
    }
}

@available(iOS 16.0, *)
extension ISBNScannerView {
    /// Check if scanner is available on this device
    static var isAvailable: Bool {
        DataScannerViewController.isSupported &&
        DataScannerViewController.isAvailable
    }
}

@available(iOS 16.0, *)
private struct InvalidBarcodeFeedbackView: View {
    var body: some View {
        Text("Not an ISBN barcode")
            .font(.callout.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.7))
            .clipShape(Capsule())
            .accessibilityLabel("Invalid barcode detected")
    }
}