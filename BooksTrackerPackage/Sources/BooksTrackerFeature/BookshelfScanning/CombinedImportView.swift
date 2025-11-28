import SwiftUI
import SwiftData

@available(iOS 26.0, *)
@MainActor
public struct CombinedImportView: View {
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(TabCoordinator.self) private var tabCoordinator
    @Environment(\.modelContext) private var modelContext

    @State private var showingCSVImport = false

    // MARK: - Design Constants
    private enum Layout {
        static let cardSpacing: CGFloat = 20
        static let cardPadding: CGFloat = 20
        static let cardCornerRadius: CGFloat = 16
        static let cardMinHeight: CGFloat = 100
        static let cardBorderOpacity: CGFloat = 0.1
        static let cardBorderWidth: CGFloat = 1

        static let iconSize: CGFloat = 48
        static let iconFrameSize: CGFloat = 64
        static let iconSpacing: CGFloat = 16

        static let textSpacing: CGFloat = 6
        static let textLineLimit: Int = 2

        static let headerSpacing: CGFloat = 8
        static let headerPaddingVertical: CGFloat = 12
        static let headerPaddingHorizontal: CGFloat = 32

        static let contentPaddingTop: CGFloat = 24
        static let contentPaddingHorizontal: CGFloat = 20
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                themeStore.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Layout.cardSpacing) {
                        topHeader

                        // Card 1: Scan Bookshelf
                        NavigationLink(value: "scan") {
                            largeGlassCard(
                                icon: "camera.fill",
                                title: "Scan Bookshelf",
                                description: "Point at your shelf - AI recognizes books",
                                accent: themeStore.primaryColor
                            )
                        }
                        .buttonStyle(.plain)

                        // Card 2: Import CSV
                        Button {
                            showingCSVImport = true
                        } label: {
                            largeGlassCard(
                                icon: "doc.text.fill",
                                title: "Import CSV",
                                description: "Upload Goodreads export",
                                accent: themeStore.primaryColor
                            )
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                    .padding(.top, Layout.contentPaddingTop)
                    .padding(.horizontal, Layout.contentPaddingHorizontal)
                }
            }
            .navigationTitle("Add Books")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingCSVImport) {
                GeminiCSVImportView()
                    .environment(\.modelContext, modelContext)
                    .environment(tabCoordinator)
            }
            .navigationDestination(for: String.self) { value in
                if value == "scan" {
                    BookshelfScannerView()
                        .environment(tabCoordinator)
                }
            }
        }
    }

    private var topHeader: some View {
        VStack(spacing: Layout.headerSpacing) {
            Text("AI-Powered Book Import")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Scan your shelf or import a CSV to populate your library")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Layout.headerPaddingHorizontal)
        }
        .padding(.vertical, Layout.headerPaddingVertical)
    }

    private func largeGlassCard(icon: String, title: String, description: String, accent: Color) -> some View {
        HStack(spacing: Layout.iconSpacing) {
            Image(systemName: icon)
                .font(.system(size: Layout.iconSize))
                .foregroundStyle(accent)
                .frame(width: Layout.iconFrameSize, height: Layout.iconFrameSize)

            VStack(alignment: .leading, spacing: Layout.textSpacing) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(Layout.textLineLimit)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .padding(Layout.cardPadding)
        .frame(maxWidth: .infinity, minHeight: Layout.cardMinHeight)
        .background {
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                        .strokeBorder(Color.white.opacity(Layout.cardBorderOpacity), lineWidth: Layout.cardBorderWidth)
                }
        }
    }
}
