import SwiftUI

// MARK: - Loading State Views

@available(iOS 26.0, *)
extension SearchView {
    struct LoadingTrendingView: View {
        @Environment(\.iOS26ThemeStore) private var themeStore
        
        var body: some View {
            ScrollView {
                LazyVStack(spacing: 32) {
                    // Welcome section
                    VStack(spacing: 16) {
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 64, weight: .ultraLight))
                            .foregroundStyle(themeStore.primaryColor)
                            .symbolEffect(.pulse, options: .repeating)

                        VStack(spacing: 8) {
                            Text("Discover Your Next Great Read")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .multilineTextAlignment(.center)

                            Text("Search millions of books or scan a barcode to get started")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                    }
                    .padding(.top, 32)

                    // Loading indicator for trending books
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)

                        Text("Loading trending books...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 40)
                }
                .padding(.horizontal, 20)
            }
            .modifier(iOS26ScrollEdgeEffectModifier(edges: [.top]))
        }
    }
    
    struct SearchingView: View {
        let query: String
        let scope: SearchScope
        let previousResults: [SearchResult]
        @Environment(\.iOS26ThemeStore) private var themeStore
        
        var body: some View {
            ZStack {
                // Show previous results if available for smooth transition
                if !previousResults.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(previousResults) { result in
                                iOS26LiquidListRow(
                                    work: result.work,
                                    displayStyle: .standard
                                )
                                .padding(.horizontal, 16)
                                .opacity(0.5)  // Dim to indicate stale
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Book: \(result.displayTitle) by \(result.displayAuthors)")
                            }

                            Spacer(minLength: 20)
                        }
                    }
                    .disabled(true)  // Prevent interaction during loading
                }

                // Loading overlay
                VStack(spacing: 24) {
                    Spacer()

                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 80, height: 80)
                                .overlay {
                                    Circle()
                                        .fill(themeStore.glassStint(intensity: 0.2))
                                }

                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(themeStore.primaryColor)
                        }

                        VStack(spacing: 8) {
                            Text("Searching...")
                                .font(.title3)
                                .fontWeight(.medium)

                            Text(searchStatusMessage(for: scope))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }

                    Spacer()
                }
                .background {
                    if !previousResults.isEmpty {
                        Color.clear.background(.ultraThinMaterial)
                    }
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
        
        // HIG: Contextual loading messages
        private func searchStatusMessage(for scope: SearchScope) -> String {
            switch scope {
            case .all:
                return "Searching all books..."
            case .title:
                return "Looking for titles..."
            case .author:
                return "Finding authors..."
            case .isbn:
                return "Looking up ISBN..."
            case .semantic:
                return "Searching by description..."
            }
        }
    }
}