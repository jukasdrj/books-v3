import SwiftUI

/// Bento Box Grid Layout - 2x2 Modular Dashboard
/// Inspired by Apple Fitness+ activity cards and iOS Control Center
@available(iOS 26.0, *)
public struct BentoGridView<Content: View>: View {
    let content: Content
    
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    public var body: some View {
        // Use LazyVGrid for efficient rendering
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            content
        }
    }
}

/// Individual Bento module container with glass effect
@available(iOS 26.0, *)
public struct BentoModule<Content: View>: View {
    let title: String?
    let icon: String?
    let span: BentoSpan
    let content: Content
    
    @Environment(\.iOS26ThemeStore) private var themeStore
    
    public init(
        title: String? = nil,
        icon: String? = nil,
        span: BentoSpan = .single,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.span = span
        self.content = content()
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Optional header
            if title != nil || icon != nil {
                HStack(spacing: 6) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.caption.bold())
                            .foregroundStyle(themeStore.primaryColor)
                    }
                    if let title {
                        Text(title)
                            .font(.caption.bold())
                            .foregroundStyle(.primary)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
            
            // Content
            content
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(0.1))
        }
        .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 4)
        .gridCellColumns(span.columnCount)
    }
}

/// Defines how many grid columns a module spans
public enum BentoSpan {
    case single   // 1 column (compact)
    case wide     // 2 columns (full width)
    
    var columnCount: Int {
        switch self {
        case .single: return 1
        case .wide: return 2
        }
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview("Bento Grid") {
    let themeStore = BooksTrackerFeature.iOS26ThemeStore()
    
    ScrollView {
        BentoGridView {
            // Top row
            BentoModule(title: "Reading", icon: "book.pages", span: .single) {
                Text("Progress: 45%")
            }
            
            BentoModule(title: "Stats", icon: "chart.bar", span: .single) {
                Text("30 pgs/hr")
            }
            
            // Bottom row (wide module)
            BentoModule(title: "Diversity", icon: "globe", span: .wide) {
                Text("Radar chart preview")
            }
            
            // More modules
            BentoModule(title: "Notes", icon: "note.text", span: .single) {
                Text("Your notes")
            }
            
            BentoModule(title: "Rating", icon: "star", span: .single) {
                Text("4.5 stars")
            }
        }
        .padding()
    }
    .environment(\.iOS26ThemeStore, themeStore)
    .themedBackground()
}
