import SwiftUI

/// Tips section for optimal bookshelf scanning
/// Provides guidance on lighting, camera positioning, and distance
@available(iOS 26.0, *)
struct ScanningTipsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tips for Best Results")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 8) {
                tipRow(icon: "sun.max.fill", text: "Use good lighting")
                tipRow(icon: "arrow.up.backward.and.arrow.down.forward", text: "Keep camera level with spines")
                tipRow(icon: "camera.metering.center.weighted", text: "Get close enough to read titles")
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.orange)
                .font(.caption)
                .frame(width: 16)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
