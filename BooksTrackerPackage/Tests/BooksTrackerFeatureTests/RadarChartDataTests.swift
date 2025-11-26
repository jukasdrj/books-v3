import Testing
@testable import BooksTrackerFeature

/// Unit tests for RadarChartData model and completion percentage calculations.
@Test("RadarChartData calculates overall completion percentage correctly")
func testOverallCompletionPercentage() {
    // Given: 5 dimensions with 3 complete and 2 incomplete
    let dimensions = [
        RadarDimension(name: "Cultural", completionPercentage: 80, isComplete: true),
        RadarDimension(name: "Gender", completionPercentage: 50, isComplete: true),
        RadarDimension(name: "Translation", completionPercentage: 0, isComplete: false),
        RadarDimension(name: "Own Voices", completionPercentage: 100, isComplete: true),
        RadarDimension(name: "Accessible", completionPercentage: 0, isComplete: false)
    ]
    
    let chartData = RadarChartData(dimensions: dimensions)
    
    // When: Calculate overall completion percentage
    let percentage = chartData.overallCompletionPercentage
    
    // Then: Should be 60% (3 out of 5 complete)
    #expect(percentage == 60.0, "Expected 60% (3/5 complete), got \(percentage)%")
}

@Test("RadarChartData handles all complete dimensions")
func testAllCompleteDimensions() {
    // Given: All dimensions are complete
    let dimensions = [
        RadarDimension(name: "Cultural", completionPercentage: 100, isComplete: true),
        RadarDimension(name: "Gender", completionPercentage: 100, isComplete: true),
        RadarDimension(name: "Translation", completionPercentage: 100, isComplete: true),
        RadarDimension(name: "Own Voices", completionPercentage: 100, isComplete: true),
        RadarDimension(name: "Accessible", completionPercentage: 100, isComplete: true)
    ]
    
    let chartData = RadarChartData(dimensions: dimensions)
    
    // When: Calculate overall completion percentage
    let percentage = chartData.overallCompletionPercentage
    
    // Then: Should be 100%
    #expect(percentage == 100.0, "Expected 100% (all complete), got \(percentage)%")
}

@Test("RadarChartData handles no complete dimensions")
func testNoCompleteDimensions() {
    // Given: No dimensions are complete
    let dimensions = [
        RadarDimension(name: "Cultural", completionPercentage: 0, isComplete: false),
        RadarDimension(name: "Gender", completionPercentage: 0, isComplete: false),
        RadarDimension(name: "Translation", completionPercentage: 0, isComplete: false),
        RadarDimension(name: "Own Voices", completionPercentage: 0, isComplete: false),
        RadarDimension(name: "Accessible", completionPercentage: 0, isComplete: false)
    ]
    
    let chartData = RadarChartData(dimensions: dimensions)
    
    // When: Calculate overall completion percentage
    let percentage = chartData.overallCompletionPercentage
    
    // Then: Should be 0%
    #expect(percentage == 0.0, "Expected 0% (none complete), got \(percentage)%")
}

@Test("RadarChartData handles partial completion values")
func testPartialCompletionValues() {
    // Given: Dimensions with varying completion percentages
    let dimensions = [
        RadarDimension(name: "Cultural", completionPercentage: 45, isComplete: false),
        RadarDimension(name: "Gender", completionPercentage: 82, isComplete: true),
        RadarDimension(name: "Translation", completionPercentage: 15, isComplete: false),
        RadarDimension(name: "Own Voices", completionPercentage: 91, isComplete: true),
        RadarDimension(name: "Accessible", completionPercentage: 65, isComplete: false)
    ]
    
    let chartData = RadarChartData(dimensions: dimensions)
    
    // When: Calculate overall completion percentage
    let percentage = chartData.overallCompletionPercentage
    
    // Then: Should be 40% (2 out of 5 complete)
    #expect(percentage == 40.0, "Expected 40% (2/5 complete), got \(percentage)%")
}
