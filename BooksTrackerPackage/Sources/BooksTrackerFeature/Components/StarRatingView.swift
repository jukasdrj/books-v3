import SwiftUI

struct StarRatingView: View {
    @Binding var rating: Double
    @Environment(\.iOS26ThemeStore) private var themeStore

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { star in
                Button(action: {
                    rating = Double(star)
                    triggerHaptic(.light)
                }) {
                    Image(systemName: star <= Int(rating) ? "star.fill" : "star")
                        .foregroundColor(star <= Int(rating) ? .yellow : .secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            if rating > 0 {
                Text("\(Int(rating))/5")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
    }

    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let impactFeedback = UIImpactFeedbackGenerator(style: style)
        impactFeedback.impactOccurred()
    }
}
