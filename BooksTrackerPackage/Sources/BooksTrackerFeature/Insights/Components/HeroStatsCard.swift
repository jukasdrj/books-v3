import SwiftUI

/// Hero stats card displaying 4 key diversity metrics
/// Tappable to jump to detailed sections
@MainActor
public struct HeroStatsCard: View {
    let stats: [DiversityStats.HeroStat]
    let onTap: (DiversityStats.HeroStat) -> Void

    @Environment(\.iOS26ThemeStore) private var themeStore

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Reading Diversity")
                .font(.title2.bold())
                .foregroundStyle(.primary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(stats) { stat in
                    StatButton(stat: stat, onTap: { onTap(stat) })
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Diversity overview")
    }
}

@MainActor
private struct StatButton: View {
    let stat: DiversityStats.HeroStat
    let onTap: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: stat.systemImage)
                        .font(.title3)
                        .foregroundStyle(stat.color)

                    Spacer()
                }

                Text(stat.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(stat.value)
                    .font(.body.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(stat.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(stat.color.opacity(0.3), lineWidth: 1)
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
        .accessibilityLabel("\(stat.title): \(stat.value)")
        .accessibilityHint("Double tap to view details")
    }
}

// MARK: - Preview

#Preview("Hero Stats Card") {
    let sampleStats: [DiversityStats.HeroStat] = [
        .init(title: "Cultural Regions", value: "8 of 11 represented", systemImage: "globe", color: .blue),
        .init(title: "Gender Representation", value: "62% Female, 35% Male", systemImage: "person.2", color: .purple),
        .init(title: "Marginalized Voices", value: "28% of library", systemImage: "hands.sparkles", color: .orange),
        .init(title: "Languages Read", value: "12 languages", systemImage: "text.bubble", color: .green)
    ]

    ScrollView {
        HeroStatsCard(stats: sampleStats) { stat in
            print("Tapped: \(stat.title)")
        }
        .padding()
    }
    .iOS26ThemeStore(iOS26ThemeStore())
}
