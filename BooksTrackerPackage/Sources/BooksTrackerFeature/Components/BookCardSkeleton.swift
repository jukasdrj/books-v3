import SwiftUI

/// A view that displays a placeholder for a book card with a shimmering animation.
///
/// This view is used to provide visual feedback to the user while the actual book data is being loaded.
/// It mimics the layout of the `iOS26AdaptiveBookCard` to ensure a smooth visual transition.
///
/// ## Accessibility
/// The skeleton view is hidden from accessibility by default, and a container view should provide a
/// "Loading" announcement to VoiceOver users.
///
/// ## Shimmer Effect
/// The shimmer is achieved by using a gradient that moves across the view. The animation is
/// controlled by the `ShimmerViewModifier`.
///
@available(iOS 26.0, *)
public struct BookCardSkeleton: View {
    public var body: some View {
        VStack {
            // Cover image placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.3))
                .frame(height: 150)

            // Title placeholder
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.3))
                .frame(height: 20)

            // Author placeholder
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.3))
                .frame(height: 16)
                .padding(.top, 4)
        }
        .modifier(ShimmerViewModifier())
        .accessibilityHidden(true) // Hide individual skeletons from VoiceOver
    }
}

/// A view modifier that applies a shimmering effect to a view.
@available(iOS 26.0, *)
struct ShimmerViewModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    private let duration = 1.5
    private let gradient = Gradient(colors: [
        .white.opacity(0.0),
        .white.opacity(0.4),
        .white.opacity(0.0)
    ])

    public func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: gradient,
                    startPoint: .init(x: -1 + phase, y: 0.5),
                    endPoint: .init(x: 0 + phase, y: 0.5)
                )
                .animation(
                    .linear(duration: duration).repeatForever(autoreverses: false),
                    value: phase
                )
            )
            .onAppear {
                phase = 2.0
            }
    }
}

@available(iOS 26.0, *)
#Preview("Book Card Skeleton") {
    BookCardSkeleton()
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
}
