import SwiftUI
import SwiftData

@available(iOS 26.0, *)
@MainActor
public struct CombinedImportView: View {
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(TabCoordinator.self) private var tabCoordinator
    @Environment(\.modelContext) private var modelContext

    @State private var showingCSVImport = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                themeStore.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
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
                    .padding(.top, 24)
                    .padding(.horizontal, 20)
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
        VStack(spacing: 8) {
            Text("AI-Powered Book Import")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Scan your shelf or import a CSV to populate your library")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 12)
    }

    private func largeGlassCard(icon: String, title: String, description: String, accent: Color) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(accent)
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 100)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                }
        }
    }
}
