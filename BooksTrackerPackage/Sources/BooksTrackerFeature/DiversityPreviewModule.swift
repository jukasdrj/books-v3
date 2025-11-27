import SwiftUI

struct DiversityPreviewModule: View {
    @Bindable var work: Work

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModuleHeader(title: "Diversity", icon: "globe.americas.fill")

            Spacer()

            // Placeholder for Representation Radar
            ZStack {
                Circle()
                    .stroke(lineWidth: 10)
                    .opacity(0.3)
                    .foregroundColor(.secondary)

                Circle()
                    .trim(from: 0.0, to: 0.42) // Placeholder value
                    .stroke(style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                    .foregroundColor(.orange)
                    .rotationEffect(Angle(degrees: 270.0))

                Text("42%")
                    .font(.title3.bold())
            }
            .frame(width: 100, height: 100)

            Text("Cultural origin preview text.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button(action: {
                // Navigate to Representation Radar view (to be implemented)
            }) {
                Text("View Details")
                    .font(.headline)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.orange.opacity(0.1))
                .blendMode(.overlay)
                .allowsHitTesting(false)
        }
        .cornerRadius(20)
    }
}
