import SwiftUI

// MARK: - iOS 26 HIG Compliance Documentation
/*
 AboutMakerView - 100% iOS 26 Human Interface Guidelines Compliant

 This view implements iOS 26 HIG best practices for personal story presentation:

 ✅ HIG Compliance:
 1. **Information Presentation** (HIG: Lists and Tables)
    - Grouped list for organized storytelling
    - Clear section headers
    - Easy to scan, warm tone

 2. **Visual Design** (HIG: Visual Design)
    - Consistent with app theme
    - Proper spacing and hierarchy
    - Engaging and personal

 3. **Accessibility** (HIG: Accessibility)
    - VoiceOver-friendly
    - Dynamic Type support
    - Semantic grouping
 */

@MainActor
public struct AboutMakerView: View {
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                // MARK: - Origin Story Section

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("📚 Built with Love (and SwiftUI)")
                            .font(.title2.bold())
                            .foregroundStyle(themeStore.primaryColor)

                        Text("This app started as a gift.")
                            .font(.body)

                        Text("My partner is an avid reader—the kind who devours books like some people binge Netflix. I watched them struggle with spreadsheets, Goodreads exports, and the nagging feeling that their bookshelf wasn't as diverse as they wanted it to be.")
                            .font(.body)

                        Text("So I did what any developer in love would do: I spent way too many late nights building the perfect book tracking app.")
                            .font(.body)
                    }
                    .padding(.vertical, 8)
                }

                // MARK: - Evolution Section

                Section("What Started Simple...") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What started as \"I'll just make a simple tracker\" turned into:")
                            .font(.body)

                        FeatureRow(
                            icon: "camera.fill",
                            title: "AI-powered bookshelf scanning",
                            subtitle: "because typing ISBNs is for mortals"
                        )

                        FeatureRow(
                            icon: "globe.americas.fill",
                            title: "Cultural diversity insights",
                            subtitle: "the original mission"
                        )

                        FeatureRow(
                            icon: "icloud.fill",
                            title: "CloudKit sync",
                            subtitle: "because they have an iPhone AND an iPad"
                        )

                        FeatureRow(
                            icon: "paintpalette.fill",
                            title: "Five gorgeous themes",
                            subtitle: "because I couldn't pick just one"
                        )
                    }
                    .padding(.vertical, 8)
                }

                // MARK: - Philosophy Section

                Section("The Making") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Every feature, every pixel, every swipe gesture was built with one reader in mind. If it helps other book lovers discover new voices and track their reading journeys, well... that's just a bonus.")
                            .font(.body)
                    }
                    .padding(.vertical, 8)
                }

                // MARK: - Signature Section

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("— Justin Gardner")
                            .font(.body.italic())
                            .foregroundStyle(.secondary)

                        Text("iOS Developer & Professional Gift-Giver")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("(also available for weddings, bar mitzvahs, and bug fixes)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)
                }

                // MARK: - P.S. Section

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("P.S. If you find a bug, please know I'm more embarrassed than you are annoyed. I promise.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                    .padding(.vertical, 4)
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

                            Text("for one reader (and now you)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 16)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("About the Maker")
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

private struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Environment(\.iOS26ThemeStore) private var themeStore

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(themeStore.primaryColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview {
    AboutMakerView()
        .iOS26ThemeStore(BooksTrackerFeature.iOS26ThemeStore())
}
