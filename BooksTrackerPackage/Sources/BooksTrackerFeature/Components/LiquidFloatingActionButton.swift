import SwiftUI

/// A floating action button (FAB) component using the "Liquid Glass" theme.
/// Supports a primary action or an expandable menu of actions.
@available(iOS 26.0, *)
public struct LiquidFloatingActionButton: View {
    let icon: String
    let accessibilityLabel: String
    let items: [FABItem]

    @State private var isExpanded = false
    @Environment(\.iOS26ThemeStore) private var themeStore

    public init(items: [FABItem], icon: String = "plus", accessibilityLabel: String = "Add options") {
        self.icon = icon
        self.accessibilityLabel = accessibilityLabel
        self.items = items
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: 16) {
            if isExpanded {
                ForEach(items) { item in
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isExpanded = false
                        }
                        // Delay slightly to allow animation to start
                        Task {
                            try? await Task.sleep(for: .milliseconds(100))
                            item.action()
                        }
                    }) {
                        HStack(spacing: 12) {
                            Text(item.label)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background {
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                                }

                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 48, height: 48)
                                .overlay {
                                    Image(systemName: item.icon)
                                        .font(.title3)
                                        .foregroundStyle(item.color ?? themeStore.primaryColor)
                                }
                                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityLabel(item.label)
                    .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.8)))
                }
            }

            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    isExpanded.toggle()
                }
            }) {
                Circle()
                    .fill(themeStore.primaryColor)
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: icon)
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                            .rotationEffect(.degrees(isExpanded ? 45 : 0))
                    }
                    .shadow(color: themeStore.primaryColor.opacity(0.4), radius: 10, x: 0, y: 5)
            }
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(isExpanded ? "Collapse menu" : "Expand menu to see add options")
            .accessibilityAddTraits(.isButton)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }
}

public struct FABItem: Identifiable {
    public let id = UUID()
    let label: String
    let icon: String
    let color: Color?
    let action: () -> Void

    public init(label: String, icon: String, color: Color? = nil, action: @escaping () -> Void) {
        self.label = label
        self.icon = icon
        self.color = color
        self.action = action
    }
}

@available(iOS 26.0, *)
#Preview {
    ZStack {
        Color.gray.opacity(0.2).ignoresSafeArea()

        VStack {
            Spacer()
            HStack {
                Spacer()
                LiquidFloatingActionButton(items: [
                    FABItem(label: "Scan Barcode", icon: "barcode.viewfinder", action: {}),
                    FABItem(label: "Search Online", icon: "magnifyingglass", color: .blue, action: {}),
                    FABItem(label: "Scan Shelf", icon: "books.vertical", color: .purple, action: {})
                ])
            }
        }
    }
    .iOS26ThemeStore(BooksTrackerFeature.iOS26ThemeStore())
}
