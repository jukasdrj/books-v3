import SwiftUI

/// Reusable metadata display component with icon + text pattern
/// Enforces consistent styling and WCAG AA contrast across all themes
@available(iOS 26.0, *)
public struct BookMetadataRow: View {
    let icon: String
    let text: String
    let style: MetadataStyle

    public init(icon: String, text: String, style: MetadataStyle = .secondary) {
        self.icon = icon
        self.text = text
        self.style = style
    }

    public var body: some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(style.color)
            .accessibilityLabel(accessibilityText)
    }

    internal var accessibilityText: String {
        switch icon {
        case "calendar":
            return "Year Published: \(text)"
        case "person":
            return "Author: \(text)"
        case "building.2":
            return "Publisher: \(text)"
        case "book.pages":
            return "Pages: \(text)"
        default:
            return "Info: \(text)"
        }
    }
}

/// Metadata display style with semantic color mapping
public enum MetadataStyle {
    case secondary
    case tertiary

    var color: Color {
        switch self {
        case .secondary: return .secondary
        case .tertiary: return Color(uiColor: .tertiaryLabel)
        }
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview("Metadata Styles") {
    VStack(alignment: .leading, spacing: 12) {
        BookMetadataRow(icon: "calendar", text: "2017", style: .secondary)
        BookMetadataRow(icon: "person.2", text: "Penguin Random House", style: .secondary)
        BookMetadataRow(icon: "book.pages", text: "388 pages", style: .tertiary)
    }
    .padding()
}
