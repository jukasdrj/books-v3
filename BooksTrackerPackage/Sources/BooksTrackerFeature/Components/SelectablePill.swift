import SwiftUI

/// A selectable pill button with haptic feedback
/// Used in multiple-choice questions for a more engaging UI
@available(iOS 26.0, *)
struct SelectablePill: View {
    let text: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.iOS26ThemeStore) private var themeStore

    var body: some View {
        Button(action: {
            #if canImport(UIKit)
            // Haptic feedback on selection
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            #endif
            action()
        }) {
            Text(text)
                .font(.subheadline)
                .fontWeight(isSelected ? .medium : .regular)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isSelected ? themeStore.primaryColor : Color.gray.opacity(0.15))
                }
                .scaleEffect(isSelected ? 1.0 : 1.0) // Can add subtle scale on press if desired
        }
        .buttonStyle(PillButtonStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

/// Custom button style for pill buttons with press effect
@available(iOS 26.0, *)
private struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview("Unselected Pill") {
    SelectablePill(text: "Fiction", isSelected: false, action: {})
        .padding()
        .environment(\.iOS26ThemeStore, BooksTrackerFeature.iOS26ThemeStore())
}

#Preview("Selected Pill") {
    SelectablePill(text: "Fiction", isSelected: true, action: {})
        .padding()
        .environment(\.iOS26ThemeStore, BooksTrackerFeature.iOS26ThemeStore())
}

#Preview("Pill Flow Layout") {
    @Previewable @State var selectedOption: String? = "Fiction"

    let options = ["Fiction", "Non-Fiction", "Biography", "Science Fiction", "Mystery", "Romance", "Thriller", "Fantasy", "Historical Fiction", "Self-Help"]

    FlowLayout(spacing: 8) {
        ForEach(options, id: \.self) { option in
            SelectablePill(
                text: option,
                isSelected: selectedOption == option,
                action: { selectedOption = option }
            )
        }
    }
    .padding()
    .environment(\.iOS26ThemeStore, BooksTrackerFeature.iOS26ThemeStore())
}
