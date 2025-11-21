import SwiftUI

/// A vibrant gradient component for the v2 aesthetic using Indigo → Cyan → Teal brand colors.
///
/// `AuroraGradient` provides a reusable accent gradient for AI-forward visuals, data charts, and
/// background sweeps. Supports horizontal, vertical, and radial directions with adjustable intensity.
///
/// ## Usage
/// ```swift
/// Rectangle()
///     .fill(AuroraGradient(direction: .horizontal, intensity: 0.8))
///     .frame(height: 100)
/// ```
///
/// ## Accessibility
/// - Brand-mandated RGB colors are fixed to maintain visual identity
/// - When overlaying text, ensure WCAG AA contrast (4.5:1+) by adjusting intensity or background
/// - Test in both light and dark modes to verify readability
///
/// ## Related
/// - `GlassCard` for liquid glass container components
@available(iOS 26.0, *)
public struct AuroraGradient: View {
    /// The direction of the gradient sweep.
    public enum Direction {
        case horizontal
        case vertical
        case radial
    }

    let direction: Direction
    let intensity: Double

    /// Creates an aurora gradient with the specified direction and intensity.
    ///
    /// - Parameters:
    ///   - direction: The gradient direction (horizontal, vertical, or radial). Default is `.horizontal`.
    ///   - intensity: The opacity multiplier for gradient colors (0.0 to 1.0). Default is `1.0`.
    public init(direction: Direction = .horizontal, intensity: Double = 1.0) {
        self.direction = direction
        self.intensity = intensity
    }

    public var body: some View {
        Group {
            switch direction {
            case .horizontal:
                LinearGradient(
                    colors: colors.map { $0.opacity(intensity) },
                    startPoint: .leading,
                    endPoint: .trailing
                )
            case .vertical:
                LinearGradient(
                    colors: colors.map { $0.opacity(intensity) },
                    startPoint: .top,
                    endPoint: .bottom
                )
            case .radial:
                RadialGradient(
                    colors: colors.map { $0.opacity(intensity) },
                    center: .center,
                    startRadius: 0,
                    endRadius: 220
                )
            }
        }
        .drawingGroup()
    }

    private var colors: [Color] {
        [
            Color(red: 0.42, green: 0.39, blue: 1.00), // Indigo
            Color(red: 0.00, green: 0.82, blue: 1.00), // Cyan
            Color(red: 0.07, green: 0.89, blue: 0.64)  // Teal
        ]
    }
}

@available(iOS 26.0, *)
#Preview("AuroraGradient") {
    VStack(spacing: 20) {
        Rectangle().fill(AuroraGradient(direction: .horizontal)).frame(height: 80)
        Rectangle().fill(AuroraGradient(direction: .vertical)).frame(height: 80)
        Circle().fill(AuroraGradient(direction: .radial)).frame(height: 120)
    }
    .padding()
}
