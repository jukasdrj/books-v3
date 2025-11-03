import SwiftUI

/// Banner displaying real-time enrichment progress with glass effect.
/// Shown at bottom of screen during background metadata enrichment.
public struct EnrichmentBanner: View {
    public let completed: Int
    public let total: Int
    public let currentBookTitle: String
    public let themeStore: iOS26ThemeStore

    public init(
        completed: Int,
        total: Int,
        currentBookTitle: String,
        themeStore: iOS26ThemeStore
    ) {
        self.completed = completed
        self.total = total
        self.currentBookTitle = currentBookTitle
        self.themeStore = themeStore
    }

    private var progress: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 4)

                    // Progress fill with gradient
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [themeStore.primaryColor, themeStore.secondaryColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: geometry.size.width * min(1.0, max(0.0, progress)),
                            height: 4
                        )
                        .animation(.smooth(duration: 0.5), value: progress)
                }
            }
            .frame(height: 4)

            // Content
            HStack(spacing: 12) {
                // Icon
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [themeStore.primaryColor, themeStore.secondaryColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.pulse)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Enriching Metadata")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if !currentBookTitle.isEmpty {
                        Text(currentBookTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Progress text
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(completed)/\(total)")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background {
                GlassEffectContainer {
                    Rectangle()
                        .fill(.clear)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -4)
    }
}
