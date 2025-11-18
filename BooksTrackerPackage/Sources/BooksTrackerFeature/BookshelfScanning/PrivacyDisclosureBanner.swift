import SwiftUI

/// Privacy disclosure banner for bookshelf scanning feature
/// Informs users that photos are only used for AI analysis and not stored
@available(iOS 26.0, *)
struct PrivacyDisclosureBanner: View {
    @Environment(\.iOS26ThemeStore) private var themeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.title2)
                    .foregroundStyle(themeStore.primaryColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Private & Secure")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Your photo is uploaded for AI analysis and is not stored.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(themeStore.primaryColor.opacity(0.3), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Privacy notice: Your photo is uploaded for AI analysis and is not stored.")
    }
}
