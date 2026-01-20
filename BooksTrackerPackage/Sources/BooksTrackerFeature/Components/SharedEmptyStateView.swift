import SwiftUI

/// A reusable, theme-aware empty state view for the "Liquid Glass" design system.
/// Displays an icon, title, description, and optional action buttons.
@available(iOS 26.0, *)
public struct SharedEmptyStateView: View {
    let icon: String
    let title: String
    let description: String
    let actions: [EmptyStateAction]

    @Environment(\.iOS26ThemeStore) private var themeStore

    public init(
        icon: String = "books.vertical.fill",
        title: String = "No Content",
        description: String = "There is nothing to display here yet.",
        actions: [EmptyStateAction] = []
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.actions = actions
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Hero section
                VStack(spacing: 16) {
                    Image(systemName: icon)
                        .font(.system(size: 72, weight: .ultraLight))
                        .foregroundStyle(themeStore.primaryColor)
                        .symbolEffect(.pulse, options: .repeating)
                        .accessibilityHidden(true)

                    VStack(spacing: 8) {
                        Text(title)
                            .font(.title.bold())
                            .foregroundStyle(.primary)

                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }
                .padding(.top, 60)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(title), \(description)")

                // Actions section
                if !actions.isEmpty {
                    VStack(spacing: 16) {
                        ForEach(actions) { action in
                            Button(action: action.handler) {
                                HStack(spacing: 16) {
                                    Image(systemName: action.icon)
                                        .font(.title2)
                                        .foregroundStyle(action.color ?? themeStore.primaryColor)
                                        .frame(width: 48, height: 48)
                                        .background(
                                            Circle()
                                                .fill((action.color ?? themeStore.primaryColor).opacity(0.15))
                                        )

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(action.title)
                                            .font(.headline)
                                            .foregroundStyle(.primary)

                                        if let sub = action.subtitle {
                                            Text(sub)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }

                                    Spacer(minLength: 0)

                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                }
                                .padding(16)
                                .background {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(.ultraThinMaterial)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 16)
                                                .strokeBorder((action.color ?? themeStore.primaryColor).opacity(0.2), lineWidth: 1)
                                        }
                                }
                                .contentShape(Rectangle()) // Ensure tap target covers the whole area
                            }
                            .buttonStyle(ScaleButtonStyle(enableHaptics: true))
                            .accessibilityLabel(action.title)
                            .accessibilityHint(action.subtitle ?? "")
                        }
                    }
                    .padding(.horizontal, 20)
                }

                Spacer(minLength: 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

public struct EmptyStateAction: Identifiable {
    public let id = UUID()
    let title: String
    let subtitle: String?
    let icon: String
    let color: Color?
    let handler: () -> Void

    public init(
        title: String,
        subtitle: String? = nil,
        icon: String,
        color: Color? = nil,
        handler: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.color = color
        self.handler = handler
    }
}

@available(iOS 26.0, *)
#Preview {
    SharedEmptyStateView(
        icon: "books.vertical.fill",
        title: "Your Library Awaits",
        description: "Start building your personal collection of books",
        actions: [
            EmptyStateAction(
                title: "Search for Books",
                subtitle: "Browse millions of books by title, author, or ISBN",
                icon: "magnifyingglass",
                color: .blue,
                handler: {}
            ),
            EmptyStateAction(
                title: "Scan a Barcode",
                subtitle: "Use your camera to quickly add books",
                icon: "barcode.viewfinder",
                color: .purple,
                handler: {}
            )
        ]
    )
    .iOS26ThemeStore(BooksTrackerFeature.iOS26ThemeStore())
}
