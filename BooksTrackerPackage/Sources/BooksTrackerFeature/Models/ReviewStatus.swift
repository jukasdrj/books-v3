//
//  ReviewStatus.swift
//  BooksTrackerFeature
//
//  Tracks human review status for AI-detected books
//

import Foundation

/// Tracks human review status for AI-detected books
public enum ReviewStatus: String, Codable, Sendable {
    /// Book data verified by AI or user
    case verified = "verified"

    /// Low-confidence AI result requiring human review
    case needsReview = "needsReview"

    /// User manually corrected AI result
    case userEdited = "userEdited"
}