import Foundation
import SwiftData

/// `WorkOverride` stores work-specific exceptions to cascaded author metadata.
@Model
public final class WorkOverride {
    /// The unique identifier for the specific work (e.g., book) this override applies to.
    public var workId: String

    /// The specific field of `AuthorMetadata` being overridden (e.g., "culturalBackground", "genderIdentity").
    public var field: String

    /// The custom value for the overridden field.
    public var customValue: String

    /// An optional reason for why this override was created (e.g., "Co-author with different background").
    public var reason: String?

    /// The date and time when this override was created.
    public var createdAt: Date

    /// The `AuthorMetadata` instance this override belongs to.
    /// This is the inverse of the `AuthorMetadata.workOverrides` relationship.
    public var authorMetadata: AuthorMetadata?

    /// Initializes a new `WorkOverride` instance.
    /// - Parameters:
    ///   - workId: The ID of the work this override applies to.
    ///   - field: The name of the field being overridden.
    ///   - customValue: The custom value for the field.
    ///   - reason: An optional reason for the override (defaults to `nil`).
    ///   - createdAt: The creation date (defaults to the current date).
    ///   - authorMetadata: The associated `AuthorMetadata` instance (defaults to `nil`).
    init(workId: String,
         field: String,
         customValue: String,
         reason: String? = nil,
         createdAt: Date = Date(),
         authorMetadata: AuthorMetadata? = nil) {
        self.workId = workId
        self.field = field
        self.customValue = customValue
        self.reason = reason
        self.createdAt = createdAt
        self.authorMetadata = authorMetadata
    }
}
