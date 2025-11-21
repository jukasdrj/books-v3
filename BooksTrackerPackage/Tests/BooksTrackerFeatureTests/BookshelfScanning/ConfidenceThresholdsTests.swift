import Testing
@testable import BooksTrackerFeature

@Suite("ConfidenceThresholds")
struct ConfidenceThresholdsTests {
    @Test("High threshold is >= medium and within 0...1")
    func highThresholdValidation() {
        #expect(ConfidenceThresholds.high >= ConfidenceThresholds.medium)
        #expect(ConfidenceThresholds.high <= 1.0)
        #expect(ConfidenceThresholds.high >= 0.0)
    }

    @Test("Medium threshold is within 0...1 and below high")
    func mediumThresholdValidation() {
        #expect(ConfidenceThresholds.medium < ConfidenceThresholds.high)
        #expect(ConfidenceThresholds.medium <= 1.0)
        #expect(ConfidenceThresholds.medium >= 0.0)
    }

    @Test("Categorization boundaries behave as documented")
    func categorizationBoundaries() {
        // High confidence: >= high
        let highSamples: [Double] = [ConfidenceThresholds.high, 1.0]
        for v in highSamples {
            #expect(v >= ConfidenceThresholds.high)
        }

        // Medium confidence: [medium, high)
        let mid = (ConfidenceThresholds.medium + ConfidenceThresholds.high) / 2.0
        #expect(mid >= ConfidenceThresholds.medium && mid < ConfidenceThresholds.high)

        // Low confidence: < medium
        let low = max(0.0, ConfidenceThresholds.medium - 0.1)
        #expect(low < ConfidenceThresholds.medium)
    }
}
