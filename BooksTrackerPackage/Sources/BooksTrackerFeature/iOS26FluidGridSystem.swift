import SwiftUI

// MARK: - iOS 26 Fluid Grid System

/// Advanced fluid grid that adapts to screen size and content
/// V1.0 Specification: 2 columns on phone, more on tablet with smooth transitions
struct iOS26FluidGridSystem<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let columns: [GridItem]
    let spacing: CGFloat
    let content: (Item) -> Content

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    init(
        items: [Item],
        columns: [GridItem],
        spacing: CGFloat = 20,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.items = items
        self.columns = columns
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            LazyVGrid(columns: adaptiveColumns(for: geometry.size), spacing: spacing) {
                ForEach(items) { item in
                    content(item)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity),
                            removal: .scale(scale: 0.9).combined(with: .opacity)
                        ))
                }
            }
            .animation(.smooth(duration: 0.6), value: adaptiveColumns(for: geometry.size).count)
        }
        .frame(height: estimatedHeight(for: items.count))
    }

    // MARK: - Height Estimation

    /// Estimates grid height based on item count and column configuration
    /// Prevents GeometryReader collapse in ScrollView contexts
    private func estimatedHeight(for itemCount: Int) -> CGFloat {
        guard itemCount > 0 else { return 0 }

        // Estimate based on typical book card height (~250pt) + spacing
        let estimatedCardHeight: CGFloat = 250
        let columnCount = max(columns.count, 2)  // Default to 2 columns minimum
        let rowCount = ceil(Double(itemCount) / Double(columnCount))

        return CGFloat(rowCount) * (estimatedCardHeight + spacing) - spacing
    }

    // MARK: - Adaptive Column Logic

    /// Dynamically calculates optimal column count based on device and orientation
    private func adaptiveColumns(for size: CGSize) -> [GridItem] {
        let baseColumns = calculateOptimalColumns(for: size)
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: baseColumns)
    }

    private func calculateOptimalColumns(for size: CGSize) -> Int {
        // Use modern geometry-based approach instead of UIScreen.main
        let screenWidth = size.width
        let screenHeight = size.height

        // Determine device type
        let isIPad = horizontalSizeClass == .regular
        let isLandscape = screenWidth > screenHeight

        // V1.0 Specification Implementation
        switch (isIPad, isLandscape) {
        case (true, true):   // iPad Landscape
            return screenWidth > 1200 ? 6 : 5  // iPad Pro vs regular iPad
        case (true, false):  // iPad Portrait
            return screenWidth > 900 ? 4 : 3   // iPad Pro vs regular iPad
        case (false, true):  // iPhone Landscape
            return screenWidth > 700 ? 4 : 3   // iPhone Pro Max vs regular
        case (false, false): // iPhone Portrait (V1.0 spec: 2 columns)
            return 2
        }
    }
}

// MARK: - Fluid Grid with Dynamic Spacing

/// Enhanced version with adaptive spacing based on content density
struct iOS26AdaptiveFluidGrid<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let baseSpacing: CGFloat
    let content: (Item) -> Content

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var contentSize: CGSize = .zero

    init(
        items: [Item],
        baseSpacing: CGFloat = 16,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.items = items
        self.baseSpacing = baseSpacing
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.vertical], showsIndicators: true) {
                LazyVGrid(columns: adaptiveColumns(for: geometry.size), spacing: adaptiveSpacing(for: geometry.size)) {
                    ForEach(items) { item in
                        content(item)
                            .background {
                                // Measure content size for adaptive spacing
                                GeometryReader { itemGeometry in
                                    Color.clear
                                        .onAppear {
                                            contentSize = itemGeometry.size
                                        }
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.8).combined(with: .opacity).combined(with: .offset(y: 20)),
                                removal: .scale(scale: 0.9).combined(with: .opacity).combined(with: .offset(y: -10))
                            ))
                    }
                }
                .padding(.horizontal, adaptiveHorizontalPadding(for: geometry.size))
            }
            .animation(.smooth(duration: 0.6), value: adaptiveColumns(for: geometry.size).count)
        }
    }

    // MARK: - Adaptive Properties

    private func adaptiveColumns(for size: CGSize) -> [GridItem] {
        let screenWidth = size.width
        let isIPad = horizontalSizeClass == .regular
        let columnCount: Int

        if isIPad {
            columnCount = screenWidth > 1100 ? 6 : screenWidth > 900 ? 5 : 4
        } else {
            columnCount = screenWidth > 600 ? 3 : 2  // V1.0 spec baseline
        }

        return Array(repeating: GridItem(.flexible(), spacing: adaptiveSpacing(for: size)), count: columnCount)
    }

    private func adaptiveSpacing(for size: CGSize) -> CGFloat {
        let screenWidth = size.width
        let densityFactor = min(max(screenWidth / 400.0, 0.8), 1.5)
        return baseSpacing * densityFactor
    }

    private func adaptiveHorizontalPadding(for size: CGSize) -> CGFloat {
        let screenWidth = size.width
        return screenWidth > 1000 ? 32 : screenWidth > 600 ? 24 : 16
    }
}

// MARK: - Fluid Grid with Masonry Layout

/// Advanced masonry-style grid for varying content heights
struct iOS26MasonryFluidGrid<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let columns: Int
    let spacing: CGFloat
    let content: (Item) -> Content

    @State private var columnHeights: [CGFloat] = []

    init(
        items: [Item],
        columns: Int = 2,
        spacing: CGFloat = 16,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.items = items
        self.columns = columns
        self.spacing = spacing
        self.content = content
        _columnHeights = State(initialValue: Array(repeating: 0, count: columns))
    }

    var body: some View {
        ScrollView([.vertical], showsIndicators: true) {
            LazyVStack(spacing: 0) {
                ForEach(Array(items.chunked(into: columns)), id: \.first?.id) { chunk in
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(Array(chunk.enumerated()), id: \.element.id) { index, item in
                            content(item)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                                    removal: .scale(scale: 1.1).combined(with: .opacity)
                                ))
                        }

                        // Fill remaining columns if chunk is incomplete
                        if chunk.count < columns {
                            ForEach(chunk.count..<columns, id: \.self) { _ in
                                Color.clear
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding(.bottom, spacing)
                }
            }
            .padding(.horizontal, 16)
        }
        .animation(.smooth(duration: 0.5), value: items.count)
    }
}

// MARK: - Array Extension for Chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Fluid Grid Presets

extension iOS26FluidGridSystem {
    /// Preset for book library with optimal book card dimensions
    static func bookLibrary<LibraryItem: Identifiable, LibraryContent: View>(
        items: [LibraryItem],
        @ViewBuilder content: @escaping (LibraryItem) -> LibraryContent
    ) -> some View {
        iOS26FluidGridSystem<LibraryItem, LibraryContent>(
            items: items,
            columns: [GridItem(.flexible())], // Will be overridden by adaptive logic
            spacing: 20,
            content: content
        )
    }

    /// Preset for compact book displays
    static func compactBooks<CompactItem: Identifiable, CompactContent: View>(
        items: [CompactItem],
        @ViewBuilder content: @escaping (CompactItem) -> CompactContent
    ) -> some View {
        iOS26FluidGridSystem<CompactItem, CompactContent>(
            items: items,
            columns: [GridItem(.flexible())],
            spacing: 12,
            content: content
        )
    }

    /// Preset for detailed book cards with more space
    static func detailedBooks<DetailedItem: Identifiable, DetailedContent: View>(
        items: [DetailedItem],
        @ViewBuilder content: @escaping (DetailedItem) -> DetailedContent
    ) -> some View {
        iOS26FluidGridSystem<DetailedItem, DetailedContent>(
            items: items,
            columns: [GridItem(.flexible())],
            spacing: 24,
            content: content
        )
    }
}

// MARK: - Preview

/*
#Preview {
    struct SampleItem: Identifiable {
        let id = UUID()
        let title: String
        let color: Color
    }

    let sampleItems = [
        SampleItem(title: "Book 1", color: .blue),
        SampleItem(title: "Book 2", color: .green),
        SampleItem(title: "Book 3", color: .purple),
        SampleItem(title: "Book 4", color: .orange),
        SampleItem(title: "Book 5", color: .pink),
        SampleItem(title: "Book 6", color: .yellow)
    ]

    NavigationStack {
        iOS26FluidGridSystem.bookLibrary(items: sampleItems) { item in
            VStack(spacing: 12) {
                Rectangle()
                    .fill(item.color.gradient)
                    .aspectRatio(2/3, contentMode: .fill)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(spacing: 4) {
                    Text(item.title)
                        .font(.headline.bold())
                    Text("Author Name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }
        }
        .navigationTitle("Fluid Grid")
    }
}
*/