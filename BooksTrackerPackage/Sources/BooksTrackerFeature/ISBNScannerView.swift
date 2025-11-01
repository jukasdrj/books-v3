import SwiftUI
import VisionKit
import UIKit
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
    @Binding var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    private let logger = Logger(subsystem: "com.oooefam.booksV3", category: "ISBNScanner")

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )

        scanner.delegate = context.coordinator

        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
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
        Coordinator(onISBNScanned: onISBNScanned, errorMessage: $errorMessage, dismiss: dismiss)
    }

    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onISBNScanned: (ISBNValidator.ISBN) -> Void
        @Binding var errorMessage: String?
        let dismiss: DismissAction
        private let logger = Logger(subsystem: "com.oooefam.booksV3", category: "ISBNScanner")

        init(onISBNScanned: @escaping (ISBNValidator.ISBN) -> Void, errorMessage: Binding<String?>, dismiss: DismissAction) {
            self.onISBNScanned = onISBNScanned
            self._errorMessage = errorMessage
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
                // Silently ignore non-ISBN barcodes
                return
            }
        }
    }
}

/// Apple-native barcode scanner using VisionKit DataScannerViewController
/// Follows official guidance from "Scanning data with the camera"
@available(iOS 16.0, *)
public struct ISBNScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    let onISBNScanned: (ISBNValidator.ISBN) -> Void

    public init(onISBNScanned: @escaping (ISBNValidator.ISBN) -> Void) {
        self.onISBNScanned = onISBNScanned
    }

    public var body: some View {
        Group {
            if !DataScannerViewController.isSupported {
                UnsupportedDeviceView()
            } else if !DataScannerViewController.isAvailable {
                PermissionDeniedView()
            } else {
                DataScannerRepresentable(
                    onISBNScanned: onISBNScanned,
                    errorMessage: $errorMessage
                )
                .ignoresSafeArea()
            }
        }
        .alert("Scanner Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
                dismiss()
            }
        } message: {
            if let errorMessage {
                Text(errorMessage)
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
