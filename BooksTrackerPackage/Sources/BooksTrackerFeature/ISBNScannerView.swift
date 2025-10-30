import SwiftUI
import VisionKit

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
    @Environment(\.dismiss) private var dismiss

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
            try? uiViewController.startScanning()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onISBNScanned: onISBNScanned, dismiss: dismiss)
    }

    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onISBNScanned: (ISBNValidator.ISBN) -> Void
        let dismiss: DismissAction

        init(onISBNScanned: @escaping (ISBNValidator.ISBN) -> Void, dismiss: DismissAction) {
            self.onISBNScanned = onISBNScanned
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
            print("📷 Scanner became unavailable: \(error)")
            dismiss()
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
                DataScannerRepresentable(onISBNScanned: onISBNScanned)
                    .ignoresSafeArea()
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
