import SwiftUI

/// A view that displays a success animation with a checkmark, confetti, and points awarded.
@available(iOS 26.0, *)
public struct CelebrationView: View {
    let pointsAwarded: Int

    @Environment(\.iOS26ThemeStore) private var themeStore
    @State private var animateCheckmark = false
    @State private var animatePoints = false
    @State private var showConfetti = false

    public var body: some View {
        VStack(spacing: 24) {
            ZStack {
                // Confetti particles
                if showConfetti {
                    ConfettiView()
                }

                // Checkmark icon
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.green)
                    .scaleEffect(animateCheckmark ? 1 : 0.5)
                    .opacity(animateCheckmark ? 1 : 0)
            }

            // Points award text
            Text("+\(pointsAwarded) Curator Points")
                .font(.headline.bold())
                .foregroundColor(themeStore.primaryColor)
                .opacity(animatePoints ? 1 : 0)
                .offset(y: animatePoints ? 0 : 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .onAppear {
            performAnimations()
        }
    }

    private func performAnimations() {
        // Animation sequence
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0)) {
            animateCheckmark = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 0.5)) {
                animatePoints = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showConfetti = true
        }
    }
}

/// A simple confetti view using particle effects.
@available(iOS 26.0, *)
struct ConfettiView: View {
    var body: some View {
        ZStack {
            ForEach(0..<50) { _ in
                Circle()
                    .fill(randomColor())
                    .frame(width: .random(in: 4...8), height: .random(in: 4...8))
                    .offset(x: .random(in: -150...150), y: .random(in: -150...150))
                    .opacity(.random(in: 0.5...1.0))
                    .animation(
                        Animation.spring(
                            response: 1,
                            dampingFraction: 0.5,
                            blendDuration: 1
                        )
                        .repeatForever(autoreverses: false)
                        .delay(.random(in: 0...0.5)),
                        value: UUID()
                    )
            }
        }
    }

    private func randomColor() -> Color {
        let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink]
        return colors.randomElement()!
    }
}

#Preview {
    let themeStore = BooksTrackerFeature.iOS26ThemeStore()

    return CelebrationView(pointsAwarded: 15)
        .environment(\.iOS26ThemeStore, themeStore)
}
