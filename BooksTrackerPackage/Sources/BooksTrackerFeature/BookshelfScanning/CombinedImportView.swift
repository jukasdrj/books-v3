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

                        HStack(spacing: 16) {
                            // Scan card
                            NavigationLink(value: "scan") {
                                importCard(
                                    title: "Scan Bookshelf",
                                    subtitle: "Capture photos of your shelf to detect books",
                                    systemImage: "viewfinder",
                                    accent: themeStore.primaryColor
                                )
                            }
                            .buttonStyle(.plain)

                            // CSV import card (sheet)
                            Button {
                                showingCSVImport = true
                            } label: {
                                importCard(
                                    title: "Import CSV",
                                    subtitle: "Upload a CSV export to add many books",
                                    systemImage: "doc.badge.plus",
                                    accent: themeStore.primaryColor
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal)

                        // Secondary actions / guidance
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Quick actions")
                                .font(.headline)

                            HStack(spacing: 12) {
                                Button(action: { showingCSVImport = true }) {
                                    Label("Select CSV", systemImage: "tray.and.arrow.down")
                                }
                                .buttonStyle(.borderedProminent)

                                NavigationLink("Open Scanner", value: "scan")
                                    .buttonStyle(.bordered)
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)

                        Spacer()
                    }
                    .padding(.top, 24)
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
            Text("Add books quickly")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Scan your shelf or import a CSV to populate your library fast")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 12)
    }

    private func importCard<Accent: View>(title: String, subtitle: String, systemImage: String, accent: Accent) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundStyle(themeStore.primaryColor)

            Text(title)
                .font(.headline)

            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 140)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
                }
        }
    }
}
