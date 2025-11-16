import Foundation

/// Centralized confidence score thresholds for AI-detected books
///
/// These thresholds determine confidence level categorization and UI behavior
/// across the app. Maintaining them in one place prevents inconsistencies.
public struct ConfidenceThresholds {
    /// High confidence threshold (80%+) - Books are auto-confirmed
    public static let high: Double = 0.8
    
    /// Medium confidence threshold (60-79%) - Books require review
    public static let medium: Double = 0.6
    
    /// Low confidence (<60%) - Books sent to review queue with explanation
    // Implicit: anything below medium is low
    
    private init() {} // Prevent instantiation
}
