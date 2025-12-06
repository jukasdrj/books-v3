import SwiftUI

/// A view that displays a success animation with a checkmark, confetti, and points awarded.
@available(iOS 26.0, *)
public struct CelebrationView: View {
    let pointsAwarded: Int
    let isCuratorUnlocked: Bool

    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.curatorPointsService) private var curatorPointsService
    @State private var animateCheckmark = false
    @State private var animatePoints = false
    @State private var showConfetti = false
    @State private var showCuratorBadge = false

    public init(pointsAwarded: Int, isCuratorUnlocked: Bool = false) {
        self.pointsAwarded = pointsAwarded
        self.isCuratorUnlocked = isCuratorUnlocked
    }

    public var body: some View {
        VStack(spacing: 24) {
            ZStack {
                // Confetti particles
                if showConfetti {
                    ConfettiView()
                }

                // Checkmark icon or Curator badge
                if isCuratorUnlocked {
                    // Special curator achievement icon
                    VStack(spacing: 16) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        themeStore.primaryColor,
                                        themeStore.primaryColor.opacity(0.7)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .scaleEffect(animateCheckmark ? 1 : 0.5)
                            .opacity(animateCheckmark ? 1 : 0)
                            .symbolEffect(.pulse, options: .repeating)

                        if showCuratorBadge {
                            VStack(spacing: 8) {
                                Text("You're now a Curator!")
                                    .font(.title2.bold())
                                    .foregroundStyle(.primary)

                                Text("🎉")
                                    .font(.system(size: 48))
                            }
                            .opacity(showCuratorBadge ? 1 : 0)
                            .offset(y: showCuratorBadge ? 0 : 20)
                        }
                    }
                } else {
                    // Regular checkmark
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 72))
                        .foregroundColor(.green)
                        .scaleEffect(animateCheckmark ? 1 : 0.5)
                        .opacity(animateCheckmark ? 1 : 0)
                }
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isCuratorUnlocked ? "Curator achievement unlocked! \(pointsAwarded) points awarded" : "Success! \(pointsAwarded) points awarded")
    }

    private func performAnimations() {
        // Animation sequence
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0)) {
            animateCheckmark = true
        }

        Task {
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeInOut(duration: 0.5)) {
                animatePoints = true
            }
        }

        Task {
            try? await Task.sleep(for: .milliseconds(100))
            showConfetti = true
        }

        // Show curator badge text after main animations
        if isCuratorUnlocked {
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    showCuratorBadge = true
                }
            }
        }
    }
}

/// A simple confetti view using particle effects.
@available(iOS 26.0, *)
struct ConfettiView: View {
    @State private var isAnimating = false

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
                        value: isAnimating
                    )
            }
        }
        .onAppear {
            isAnimating = true
        }
    }

    private func randomColor() -> Color {
        let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink]
        return colors.randomElement() ?? .red
    }
}

#Preview {
    let themeStore = BooksTrackerFeature.iOS26ThemeStore()

    return CelebrationView(pointsAwarded: 15)
        .environment(\.iOS26ThemeStore, themeStore)
}
