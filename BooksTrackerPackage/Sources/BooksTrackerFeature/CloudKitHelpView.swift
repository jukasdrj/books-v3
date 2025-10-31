import SwiftUI

// MARK: - iOS 26 HIG Compliance Documentation
/*
 CloudKitHelpView - 100% iOS 26 Human Interface Guidelines Compliant

 This view implements iOS 26 HIG best practices for help documentation:

 ✅ HIG Compliance:
 1. **Information Hierarchy** (HIG: Typography)
    - Clear section headers
    - Scannable content
    - Progressive disclosure

 2. **Visual Design** (HIG: Visual Design)
    - Consistent with app theme
    - Icons for visual communication
    - Proper spacing and grouping

 3. **Accessibility** (HIG: Accessibility)
    - VoiceOver-friendly structure
    - Dynamic Type support
    - Semantic content organization
 */

@MainActor
public struct CloudKitHelpView: View {
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "icloud.and.arrow.up")
                            .font(.system(size: 60))
                            .foregroundStyle(themeStore.primaryColor)

                        Text("How iCloud Sync Works")
                            .font(.title2.bold())

                        Text("Keep your library in sync across all your devices")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)

                    // What Syncs Section
                    HelpSection(
                        icon: "checkmark.icloud",
                        iconColor: .green,
                        title: "What Syncs",
                        items: [
                            "Your complete book library",
                            "Reading status (To Read, Reading, Read)",
                            "Reading progress and page numbers",
                            "Personal ratings and notes",
                            "Tags and organization",
                            "Dates started and completed"
                        ]
                    )

                    // Requirements Section
                    HelpSection(
                        icon: "exclamationmark.icloud",
                        iconColor: .orange,
                        title: "Requirements",
                        items: [
                            "Signed into iCloud on this device",
                            "iCloud Drive enabled in Settings",
                            "Internet connection for syncing",
                            "Sufficient iCloud storage space",
                            "iOS 26.0 or later"
                        ]
                    )

                    // How It Works Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "gearshape.2")
                                .font(.title2)
                                .foregroundStyle(themeStore.primaryColor)

                            Text("How It Works")
                                .font(.headline)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            HowItWorksStep(
                                number: 1,
                                description: "Changes are automatically saved to iCloud in the background"
                            )

                            HowItWorksStep(
                                number: 2,
                                description: "Other devices download changes when the app opens"
                            )

                            HowItWorksStep(
                                number: 3,
                                description: "Conflicts are resolved automatically using the most recent change"
                            )
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                        )
                    }

                    // Troubleshooting Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.title2)
                                .foregroundStyle(themeStore.primaryColor)

                            Text("Troubleshooting")
                                .font(.headline)
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            TroubleshootingItem(
                                problem: "Changes not syncing?",
                                solutions: [
                                    "Check your internet connection",
                                    "Verify iCloud Drive is enabled in Settings",
                                    "Ensure you're signed into the same iCloud account on all devices",
                                    "Try closing and reopening the app"
                                ]
                            )

                            Divider()

                            TroubleshootingItem(
                                problem: "Missing books?",
                                solutions: [
                                    "Give iCloud a few minutes to sync",
                                    "Check your iCloud storage isn't full",
                                    "Make sure the book was added on a device with iCloud enabled"
                                ]
                            )
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                        )
                    }

                    // Privacy Note
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "lock.shield")
                                .foregroundStyle(themeStore.primaryColor)

                            Text("Your Privacy")
                                .font(.subheadline.bold())
                        }

                        Text("Your library data is encrypted and stored in your personal iCloud account. Only you can access it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(themeStore.primaryColor.opacity(0.1))
                    )

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("iCloud Sync")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            #endif
            .background(backgroundView.ignoresSafeArea())
        }
    }

    // MARK: - View Components

    private var backgroundView: some View {
        themeStore.backgroundGradient
    }
}

// MARK: - Supporting Views

private struct HelpSection: View {
    let icon: String
    let iconColor: Color
    let title: String
    let items: [String]
    @Environment(\.iOS26ThemeStore) private var themeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(iconColor)

                Text(title)
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
        }
    }
}

private struct HowItWorksStep: View {
    let number: Int
    let description: String
    @Environment(\.iOS26ThemeStore) private var themeStore

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(number)")
                .font(.title3.bold())
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.blue)
                )

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TroubleshootingItem: View {
    let problem: String
    let solutions: [String]
    @Environment(\.iOS26ThemeStore) private var themeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(problem)
                .font(.subheadline.bold())

            VStack(alignment: .leading, spacing: 6) {
                ForEach(solutions, id: \.self) { solution in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundStyle(.secondary)

                        Text(solution)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview {
    CloudKitHelpView()
        .iOS26ThemeStore(BooksTrackerFeature.iOS26ThemeStore())
}