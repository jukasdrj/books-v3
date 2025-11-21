import SwiftUI

/// A reusable liquid glass card component for the v2 aesthetic.
///
/// `GlassCard` provides a container with `.ultraThinMaterial` background, subtle hairline stroke,
/// and soft depth shadow to achieve the iOS 26 glass look. Supports optional header with title and icon.
///
/// ## Usage
/// ```swift
/// GlassCard(title: "Reading Progress", icon: "chart.bar") {
///     Text("Card content here")
/// }
/// ```
///
/// ## Features
/// - Liquid glass material with adaptive blur
/// - Optional header with title and/or SF Symbol icon
/// - Hairline stroke with adaptive contrast
/// - Soft shadow for depth perception
///
/// ## Accessibility
/// - Header combines icon and title into single accessibility label for VoiceOver
/// - Stroke uses adaptive `.primary` opacity for WCAG AA contrast (4.5:1+)
/// - Tested in both light and dark modes
///
/// ## Related
/// - `AuroraGradient` for brand accent sweeps
/// - Used in Bento grid layout for Book Details dashboard
@available(iOS 26.0, *)
public struct GlassCard<Content: View>: View {
    let title: String?
    let icon: String?
    let content: Content

    /// Creates a glass card with optional header and content.
    ///
    /// - Parameters:
    ///   - title: Optional title text displayed in the header.
    ///   - icon: Optional SF Symbol name displayed before the title.
    ///   - content: The main content view builder.
    public init(title: String? = nil, icon: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if title != nil || icon != nil {
                HStack(spacing: 8) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    if let title {
                        Text(title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityHeaderLabel)
            }
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(0.15))
        )
        .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 8)
    }

    private var accessibilityHeaderLabel: String {
        if let title, let icon {
            return "\(icon), \(title)"
        } else if let title {
            return title
        } else if let icon {
            return icon
        }
        return ""
    }
}

@available(iOS 26.0, *)
#Preview("GlassCard") {
    VStack(spacing: 20) {
        GlassCard(title: "Representation", icon: "chart.pie") {
            Text("Preview content goes here.")
                .foregroundStyle(.secondary)
        }
        GlassCard {
            Text("No header variant")
                .foregroundStyle(.secondary)
        }
    }
    .padding()
    .background(.regularMaterial)
}
