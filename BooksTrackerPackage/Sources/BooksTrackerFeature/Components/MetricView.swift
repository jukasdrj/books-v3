import SwiftUI

// MARK: - Metric View Component

/// A reusable metric display component for statistics and KPIs
@available(iOS 26.0, *)
struct MetricView: View {
    @Environment(\.iOS26ThemeStore) private var themeStore

    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundColor(color)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview {
    HStack(spacing: 20) {
        MetricView(title: "Books Read", value: "42", color: .blue)
        MetricView(title: "Diverse", value: "65%", color: .green)
        MetricView(title: "Languages", value: "5", color: .purple)
    }
    .padding()
}
