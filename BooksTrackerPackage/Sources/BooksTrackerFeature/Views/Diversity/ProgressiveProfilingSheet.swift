import SwiftUI
import SwiftData

struct ProgressiveProfilingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var work: Work
    @Bindable var author: Author?
    let metric: DiversityMetric

    @State private var selectedGender: Gender?
    @State private var otherGenderText: String = ""
    @State private var selectedRegion: CulturalRegion?
    @State private var originalLanguage: String = ""
    @State private var isOwnVoices: Bool?
    @State private var accessibilityTags: String = ""

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Help Complete This Profile")
                    .font(.largeTitle.bold())
                    .padding(.bottom, 10)

                switch metric.id {
                case "gender":
                    genderProfilingView
                case "origin":
                    originProfilingView
                case "translation":
                    translationProfilingView
                case "ownVoices":
                    ownVoicesProfilingView
                case "nicheAccess":
                    nicheAccessProfilingView
                default:
                    Text("More profiling options coming soon.")
                }

                Spacer()

                HStack {
                    Button("Skip") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Submit") {
                        saveContribution()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSubmitDisabled())
                }
            }
            .padding()
            .navigationTitle("Contribute Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var genderProfilingView: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Which gender does \(author?.name ?? "the author") identify with?")
                .font(.headline)

            ForEach(Gender.allCases) { gender in
                HStack {
                    Image(systemName: selectedGender == gender ? "largecircle.fill.circle" : "circle")
                        .foregroundColor(.accentColor)
                    Text(gender.displayName)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedGender = gender
                }

                if gender == .other && selectedGender == .other {
                    TextField("Please specify", text: $otherGenderText)
                        .textFieldStyle(.roundedBorder)
                        .padding(.leading, 40)
                }
            }
        }
    }

    private var originProfilingView: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("What is the cultural origin of the author?")
                .font(.headline)
            Picker("Cultural Region", selection: $selectedRegion) {
                ForEach(CulturalRegion.allCases) { region in
                    Text(region.displayName).tag(region as CulturalRegion?)
                }
            }
            .pickerStyle(.wheel)
        }
    }

    private var translationProfilingView: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("What was the original language of this book?")
                .font(.headline)
            TextField("e.g., Japanese", text: $originalLanguage)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var ownVoicesProfilingView: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Does this book qualify as 'Own Voices'?")
                .font(.headline)
            Picker("Own Voices", selection: $isOwnVoices) {
                Text("Yes").tag(true as Bool?)
                Text("No").tag(false as Bool?)
            }
            .pickerStyle(.segmented)
        }
    }

    private var nicheAccessProfilingView: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Enter accessibility tags (comma-separated)")
                .font(.headline)
            TextField("e.g., Dyslexia Friendly, Large Print", text: $accessibilityTags)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func saveContribution() {
        switch metric.id {
        case "gender":
            author?.gender = selectedGender
            if selectedGender == .other {
                author?.customGender = otherGenderText
            }
        case "origin":
            author?.culturalRegion = selectedRegion
        case "translation":
            work.primaryEdition?.originalLanguage = originalLanguage
        case "ownVoices":
            work.isOwnVoices = isOwnVoices
        case "nicheAccess":
            work.accessibilityTags = accessibilityTags.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
        default:
            break
        }

        do {
            try modelContext.save()
        } catch {
            print("Failed to save contribution: \(error)")
        }
    }

    private func isSubmitDisabled() -> Bool {
        switch metric.id {
        case "gender":
            if selectedGender == nil {
                return true
            }
            if selectedGender == .other && otherGenderText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
            return false
        case "origin":
            return selectedRegion == nil
        case "translation":
            return originalLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case "ownVoices":
            return isOwnVoices == nil
        case "nicheAccess":
            return accessibilityTags.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return true
        }
    }
}
