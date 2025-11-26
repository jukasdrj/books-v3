import Foundation

struct DiversityScore {
    let work: Work

    var metrics: [DiversityMetric] {
        [
            culturalOriginMetric,
            genderIdentityMetric,
            translationMetric,
            ownVoicesMetric,
            nicheAccessibilityMetric
        ]
    }

    var overallScore: Double {
        let validMetrics = metrics.filter { $0.value != nil }
        guard !validMetrics.isEmpty else { return 0.0 }
        let total = validMetrics.reduce(0) { $0 + ($1.value ?? 0.0) }
        return total / Double(validMetrics.count)
    }

    // MARK: - Metric Calculations

    private var culturalOriginMetric: DiversityMetric {
        let value: Double?
        if let region = work.primaryAuthor?.culturalRegion {
            let marginalizedRegions: [CulturalRegion] = [.africa, .asia, .southAmerica, .middleEast, .caribbean, .centralAsia, .indigenous]
            value = marginalizedRegions.contains(region) ? 1.0 : 0.2
        } else {
            value = nil
        }
        return DiversityMetric(id: "origin", label: "Origin", value: value, axis: 0)
    }

    private var genderIdentityMetric: DiversityMetric {
        let value: Double?
        if let gender = work.primaryAuthor?.gender {
            switch gender {
            case .female, .nonBinary, .other:
                value = 1.0
            case .male:
                value = 0.2
            case .preferNotToSay:
                value = nil
            }
        } else {
            value = nil
        }
        return DiversityMetric(id: "gender", label: "Gender", value: value, axis: 1)
    }

    private var translationMetric: DiversityMetric {
        let value: Double?
        if let language = work.primaryEdition?.originalLanguage {
            value = (language.lowercased() != "english" && !language.isEmpty) ? 1.0 : 0.1
        } else {
            value = nil
        }
        return DiversityMetric(id: "translation", label: "Translation", value: value, axis: 2)
    }

    private var ownVoicesMetric: DiversityMetric {
        let value: Double?
        if let isOwnVoices = work.isOwnVoices {
            value = isOwnVoices ? 1.0 : 0.0
        } else {
            value = nil
        }
        return DiversityMetric(id: "ownVoices", label: "Own Voices", value: value, axis: 3)
    }

    private var nicheAccessibilityMetric: DiversityMetric {
        let value: Double?
        if !work.accessibilityTags.isEmpty {
            // Simple scoring: 1.0 if any accessibility tags are present.
            // Could be more nuanced in the future.
            let hasDyslexiaTag = work.accessibilityTags.contains { $0.lowercased().contains("dyslexia") }
            value = hasDyslexiaTag ? 1.0 : 0.5
        } else {
            // If the array is empty, we assume data is missing (nil) rather than
            // scoring it as 0.0. This encourages users to contribute data, as
            // an empty state is visually distinct from a low-scoring state.
            value = nil
        }
        return DiversityMetric(id: "nicheAccess", label: "Niche/Access", value: value, axis: 4)
    }
}

struct DiversityMetric: Identifiable {
    let id: String
    let label: String
    let value: Double?  // nil = missing data
    let axis: Int
}
