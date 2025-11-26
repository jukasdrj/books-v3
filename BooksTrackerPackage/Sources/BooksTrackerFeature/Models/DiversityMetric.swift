import Foundation

/// Represents a single axis on the diversity radar chart.
public struct DiversityMetric: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let axis: Axis
    public let score: Double // A value between 0.0 and 1.0
    public let isMissing: Bool

    /// Defines the five axes of the diversity radar chart.
    public enum Axis: String, CaseIterable, Hashable, Sendable {
        case cultural = "Cultural"
        case gender = "Gender"
        case translation = "Translation"
        case ownVoices = "Own Voices"
        case accessibility = "Accessibility"

        var systemImage: String {
            switch self {
            case .cultural: return "globe.americas.fill"
            case .gender: return "person.2.fill"
            case .translation: return "character.book.closed.fill"
            case .ownVoices: return "person.wave.2.fill"
            case .accessibility: return "figure.walk.circle.fill"
            }
        }
    }
}

// MARK: - Sample Data
extension DiversityMetric {
    /// Provides sample data for SwiftUI Previews and development.
    public static var sample: [DiversityMetric] {
        [
            .init(axis: .cultural, score: 0.8, isMissing: false),
            .init(axis: .gender, score: 0.6, isMissing: false),
            .init(axis: .translation, score: 0.3, isMissing: false),
            .init(axis: .ownVoices, score: 0.9, isMissing: false),
            .init(axis: .accessibility, score: 0.0, isMissing: true),
        ]
    }
}
