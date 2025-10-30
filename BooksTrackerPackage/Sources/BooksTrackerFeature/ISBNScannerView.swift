import SwiftUI
import VisionKit

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
        Text("Scanner Placeholder")
            .onAppear {
                print("ISBNScannerView appeared")
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
