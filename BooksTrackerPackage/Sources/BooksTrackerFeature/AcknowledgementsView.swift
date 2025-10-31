import SwiftUI

// MARK: - iOS 26 HIG Compliance Documentation
/*
 AcknowledgementsView - 100% iOS 26 Human Interface Guidelines Compliant

 This view implements iOS 26 HIG best practices for credits and acknowledgements:

 ✅ HIG Compliance:
 1. **Information Presentation** (HIG: Lists and Tables)
    - Grouped list for organized content
    - Clear section headers
    - Easy to scan

 2. **Visual Design** (HIG: Visual Design)
    - Consistent with app theme
    - Proper spacing and hierarchy
    - Subtle visual interest

 3. **Accessibility** (HIG: Accessibility)
    - VoiceOver-friendly
    - Dynamic Type support
    - Semantic grouping
 */

@MainActor
public struct AcknowledgementsView: View {
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                // MARK: - Credits Section

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Books Tracker")
                            .font(.headline)

                        Text("A beautiful way to track your reading journey and discover diverse voices in literature.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                // MARK: - Development Section

                Section("Development") {
                    CreditRow(
                        icon: "hammer.fill",
                        title: "Built with SwiftUI",
                        subtitle: "Apple's declarative UI framework"
                    )

                    CreditRow(
                        icon: "cylinder.fill",
                        title: "SwiftData",
                        subtitle: "For persistent storage and CloudKit sync"
                    )

                    CreditRow(
                        icon: "sparkles",
                        title: "iOS 26 Liquid Glass Design",
                        subtitle: "Beautiful, accessible interface design"
                    )

                    CreditRow(
                        icon: "swift",
                        title: "Swift 6",
                        subtitle: "Safe, modern, and concurrent"
                    )
                }

                // MARK: - Design Inspiration Section

                Section("Design Inspiration") {
                    CreditRow(
                        icon: "paintbrush.fill",
                        title: "Apple Human Interface Guidelines",
                        subtitle: "iOS 26 design principles and best practices"
                    )

                    CreditRow(
                        icon: "wand.and.stars",
                        title: "Material Design",
                        subtitle: "Color theory and motion principles"
                    )

                    CreditRow(
                        icon: "circle.hexagonpath.fill",
                        title: "Glassmorphism",
                        subtitle: "Modern frosted glass aesthetic"
                    )
                }

                // MARK: - Data Sources Section

                Section("Data Sources") {
                    CreditRow(
                        icon: "books.vertical.fill",
                        title: "OpenLibrary",
                        subtitle: "Open book data API"
                    )

                    CreditRow(
                        icon: "book.closed.fill",
                        title: "Google Books API",
                        subtitle: "Comprehensive book metadata"
                    )

                    CreditRow(
                        icon: "barcode",
                        title: "ISBNdb",
                        subtitle: "ISBN validation and lookup"
                    )
                }

                // MARK: - Special Thanks Section

                Section("Special Thanks") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("To all the developers, designers, and creators who share their knowledge and inspire better software.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("To readers everywhere who believe in the power of diverse voices and inclusive storytelling.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                // MARK: - Open Source Section

                Section("Open Source") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("This app is built with love for the reading community.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("While the app itself is not open source, it's built entirely with open standards and publicly available APIs.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                // MARK: - Footer

                Section {
                    HStack {
                        Spacer()

                        VStack(spacing: 8) {
                            Image(systemName: "heart.fill")
                                .font(.title)
                                .foregroundStyle(themeStore.primaryColor)

                            Text("Made with care")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("for book lovers everywhere")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 16)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Acknowledgements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .background(backgroundView.ignoresSafeArea())
        }
    }

    // MARK: - View Components

    private var backgroundView: some View {
        themeStore.backgroundGradient
    }
}

// MARK: - Supporting Views

private struct CreditRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Environment(\.iOS26ThemeStore) private var themeStore

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview {
    AcknowledgementsView()
        .iOS26ThemeStore(BooksTrackerFeature.iOS26ThemeStore())
}