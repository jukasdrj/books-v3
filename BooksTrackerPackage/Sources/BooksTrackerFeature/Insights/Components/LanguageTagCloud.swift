import SwiftUI

/// Tag cloud displaying languages with flag emojis
/// Tappable pills to filter library by language
@MainActor
public struct LanguageTagCloud: View {
    let stats: [DiversityStats.LanguageStat]
    let onLanguageTap: (String) -> Void

    @Environment(\.iOS26ThemeStore) private var themeStore

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Language Diversity")
                .font(.title3.bold())
                .foregroundStyle(.primary)

            if stats.isEmpty {
                emptyState
            } else {
                tagCloud
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var tagCloud: some View {
        FlowLayout(spacing: 8) {
            ForEach(stats) { stat in
                LanguageTag(stat: stat, themeColor: themeStore.primaryColor) {
                    onLanguageTap(stat.language)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Languages read")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No language data yet")
                .font(.body)
                .foregroundStyle(.secondary)

            Text("Add books with original language info")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

@MainActor
private struct LanguageTag: View {
    let stat: DiversityStats.LanguageStat
    let themeColor: Color
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Text(stat.emoji)
                    .font(.body)

                Text(stat.language)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Text("(\(stat.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(themeColor.opacity(0.1))
                    .overlay(
                        Capsule()
                            .strokeBorder(themeColor.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel("\(stat.language): \(stat.count) books")
        .accessibilityHint("Double tap to filter library")
    }
}

// MARK: - Preview

#Preview("Language Tag Cloud") {
    let sampleStats: [DiversityStats.LanguageStat] = [
        .init(language: "English", count: 45),
        .init(language: "Spanish", count: 18),
        .init(language: "French", count: 12),
        .init(language: "Japanese", count: 8),
        .init(language: "Arabic", count: 5),
        .init(language: "German", count: 4),
        .init(language: "Swahili", count: 3),
        .init(language: "Korean", count: 2),
        .init(language: "Portuguese", count: 2),
        .init(language: "Russian", count: 1)
    ]

    ScrollView {
        LanguageTagCloud(stats: sampleStats) { language in
            #if DEBUG
            print("Tapped language: \(language)")
            #endif
        }
        .padding()
    }
    .iOS26ThemeStore(BooksTrackerFeature.iOS26ThemeStore())
}
