import Foundation

/// Calculates diversity metrics for a Work based on author demographics,
/// language, own voices status, and accessibility features.
///
/// Used with `RadarChartView` to visualize the "Representation Radar".
///
/// Example:
/// ```swift
/// let score = DiversityScore(work: myWork)
/// let metrics = score.metrics  // [DiversityMetric] for RadarChartView
/// let overall = score.overallScore  // 0.0-1.0
/// ```
@MainActor
public struct DiversityScore {
    public let work: Work

    public init(work: Work) {
        self.work = work
    }

    // MARK: - Computed Metrics

    /// All metrics as DiversityMetric array for RadarChartView
    public var metrics: [DiversityMetric] {
        [
            culturalMetric,
            genderMetric,
            translationMetric,
            ownVoicesMetric,
            accessibilityMetric
        ]
    }

    /// Overall diversity score (average of non-missing metrics)
    public var overallScore: Double {
        let validMetrics = metrics.filter { !$0.isMissing }
        guard !validMetrics.isEmpty else { return 0.0 }
        return validMetrics.reduce(0) { $0 + $1.score } / Double(validMetrics.count)
    }

    /// Check if any diversity data is available
    public var hasAnyData: Bool {
        metrics.contains { !$0.isMissing }
    }

    // MARK: - Individual Metrics

    /// Cultural origin metric based on author's cultural region
    /// Marginalized regions score 1.0, Western regions score 0.2
    private var culturalMetric: DiversityMetric {
        if let region = work.primaryAuthor?.culturalRegion {
            let marginalizedRegions: [CulturalRegion] = [
                .africa, .asia, .southAmerica, .middleEast,
                .caribbean, .centralAsia, .indigenous
            ]
            let score = marginalizedRegions.contains(region) ? 1.0 : 0.2
            return DiversityMetric(axis: .cultural, score: score, isMissing: false)
        }
        return DiversityMetric(axis: .cultural, score: 0.0, isMissing: true)
    }

    /// Gender identity metric based on author's gender
    /// Non-male identities score 1.0, male scores 0.2
    private var genderMetric: DiversityMetric {
        if let gender = work.primaryAuthor?.gender {
            switch gender {
            case .female, .nonBinary, .other:
                return DiversityMetric(axis: .gender, score: 1.0, isMissing: false)
            case .male:
                return DiversityMetric(axis: .gender, score: 0.2, isMissing: false)
            case .unknown:
                return DiversityMetric(axis: .gender, score: 0.0, isMissing: true)
            }
        }
        return DiversityMetric(axis: .gender, score: 0.0, isMissing: true)
    }

    /// Translation metric based on edition's original language
    /// Non-English languages score 1.0, English scores 0.1
    private var translationMetric: DiversityMetric {
        if let language = work.primaryEdition?.originalLanguage {
            let isNonEnglish = language.lowercased() != "english" && !language.isEmpty
            let score = isNonEnglish ? 1.0 : 0.1
            return DiversityMetric(axis: .translation, score: score, isMissing: false)
        }
        return DiversityMetric(axis: .translation, score: 0.0, isMissing: true)
    }

    /// Own Voices metric - whether author shares identity with protagonist
    private var ownVoicesMetric: DiversityMetric {
        if let isOwnVoices = work.isOwnVoices {
            return DiversityMetric(axis: .ownVoices, score: isOwnVoices ? 1.0 : 0.0, isMissing: false)
        }
        return DiversityMetric(axis: .ownVoices, score: 0.0, isMissing: true)
    }

    /// Accessibility metric based on available accessibility features
    private var accessibilityMetric: DiversityMetric {
        if !work.accessibilityTags.isEmpty {
            // Score based on number of accessibility features
            let hasDyslexiaSupport = work.accessibilityTags.contains {
                $0.lowercased().contains("dyslexia")
            }
            let score = hasDyslexiaSupport ? 1.0 : 0.5
            return DiversityMetric(axis: .accessibility, score: score, isMissing: false)
        }
        // Empty = no data (encourage contribution)
        return DiversityMetric(axis: .accessibility, score: 0.0, isMissing: true)
    }
}

// MARK: - Metric Descriptions

extension DiversityScore {
    /// Human-readable descriptions for each metric axis
    public static nonisolated let metricDescriptions: [DiversityMetric.Axis: String] = [
        .cultural: "Cultural background of the author. Highlights voices from underrepresented regions.",
        .gender: "Gender identity of the author. Highlights non-male voices.",
        .translation: "Whether the book was originally written in a non-English language.",
        .ownVoices: "Whether the author shares the identity/experience they're writing about.",
        .accessibility: "Availability of accessible formats (large print, audiobook, dyslexia-friendly)."
    ]
}
