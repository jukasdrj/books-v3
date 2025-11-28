import SwiftData
import Foundation

/// User-specific settings and preferences
@Model
public final class UserSettings {
    @Attribute(.unique) public var userId: String

    /// Primary reading language for determining translation status
    /// Stored as lowercase display name (e.g., "english", "spanish")
    public var primaryReadingLanguage: String

    public init(userId: String, primaryReadingLanguage: String) {
        self.userId = userId
        self.primaryReadingLanguage = primaryReadingLanguage
    }

    /// Provides the default primary reading language based on device locale.
    /// Returns a lowercase English display name of the language (e.g., "english", "spanish")
    /// for direct comparison with `edition.originalLanguage.lowercased()`.
    public static func defaultPrimaryReadingLanguage() -> String {
        let currentLanguageCode = Locale.current.language.languageCode?.identifier ?? "en"

        // Use a fixed English locale to get consistent English language names
        let englishLocale = Locale(identifier: "en_US")

        if let englishLanguageName = englishLocale.localizedString(forLanguageCode: currentLanguageCode) {
            return englishLanguageName.lowercased()
        }

        // Fallback to "english" if the language code cannot be resolved
        return "english"
    }
}
