import Foundation

/// Service for parsing reading status from import strings (CSV, Goodreads, LibraryThing).
///
/// Supports direct mapping (O(1) lookup) and fuzzy matching (Levenshtein distance ≤2)
/// for handling typos like "currenty reading" → `.reading`.
///
/// **Usage:**
/// ```swift
/// let status = ReadingStatusParser.parse("want to read")  // → .wishlist
/// let typo = ReadingStatusParser.parse("currenty reading") // → .reading (fuzzy match)
/// ```
///
/// **Supported Formats:**
/// - Goodreads: "to-read", "currently-reading", "read"
/// - LibraryThing: "Wishlist", "On Shelf", "Reading"
/// - Generic: "want", "started", "finished", "dnf"
///
/// - SeeAlso: `ReadingStatus.from(string:)` for backward compatibility wrapper
public struct ReadingStatusParser {

    // MARK: - Direct Mappings (O(1) lookup)

    /// Pre-defined mappings for exact string matches.
    /// Case-insensitive lookup via lowercased keys.
    private static let mappings: [String: ReadingStatus] = [
        // Wishlist variants
        "wishlist": .wishlist,
        "want to read": .wishlist,
        "to-read": .wishlist,
        "want": .wishlist,
        "planned": .wishlist,

        // To Read (owned but not started)
        "to read": .toRead,
        "owned": .toRead,
        "unread": .toRead,
        "not started": .toRead,
        "tbr": .toRead,
        "to-be-read": .toRead,
        "on shelf": .toRead,

        // Currently Reading
        "reading": .reading,
        "currently reading": .reading,
        "in progress": .reading,
        "started": .reading,
        "current": .reading,
        "currently-reading": .reading,  // Goodreads format

        // Read/Finished
        "read": .read,
        "finished": .read,
        "completed": .read,
        "done": .read,

        // On Hold
        "on hold": .onHold,
        "on-hold": .onHold,
        "paused": .onHold,
        "suspended": .onHold,

        // Did Not Finish
        "dnf": .dnf,
        "did not finish": .dnf,
        "abandoned": .dnf,
        "quit": .dnf,
        "stopped": .dnf
    ]

    // MARK: - Public API

    /// Parse reading status from import string.
    ///
    /// - Parameter string: Input string from CSV, Goodreads, etc.
    /// - Returns: Parsed `ReadingStatus`, or `nil` if no match found
    ///
    /// **Algorithm:**
    /// 1. Normalize input (trim whitespace, lowercase)
    /// 2. Direct lookup in mappings dictionary (O(1))
    /// 3. If no match, try fuzzy matching (Levenshtein distance ≤2)
    /// 4. If still no match, return nil
    ///
    /// **Examples:**
    /// ```swift
    /// parse("Want to Read")       // → .wishlist (exact match)
    /// parse("currenty reading")   // → .reading (fuzzy match, typo)
    /// parse("invalid-status")     // → nil
    /// ```
    public static func parse(_ string: String?) -> ReadingStatus? {
        guard let normalized = string?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !normalized.isEmpty else {
            return nil
        }

        // Direct lookup (O(1))
        if let status = mappings[normalized] {
            return status
        }

        // Fuzzy matching for typos (Levenshtein distance ≤2)
        return fuzzyMatch(normalized)
    }

    // MARK: - Fuzzy Matching

    /// Find closest match using Levenshtein distance.
    ///
    /// Only accepts matches with ≤2 character edits (insertions, deletions, substitutions).
    /// This handles common typos like:
    /// - "currenty reading" → "currently reading" (1 deletion)
    /// - "wishlis" → "wishlist" (1 insertion)
    /// - "finishd" → "finished" (1 substitution)
    ///
    /// **Performance:** O(n * m) where n = input length, m = candidate length.
    /// With typical status strings (~15 chars) and 60 candidates, this is <1ms per call.
    ///
    /// - Parameter string: Normalized input string
    /// - Returns: Matched `ReadingStatus`, or `nil` if no close match found
    private static func fuzzyMatch(_ string: String) -> ReadingStatus? {
        let candidates = mappings.keys

        var closestMatch: String?
        var minDistance = Int.max

        for candidate in candidates {
            let distance = levenshteinDistance(string, candidate)
            if distance < minDistance {
                minDistance = distance
                closestMatch = candidate
            }
        }

        // Only accept if ≤2 character edits (typos, not different words)
        if minDistance <= 2, let match = closestMatch {
            return mappings[match]
        }

        return nil
    }

    // MARK: - Levenshtein Distance

    /// Calculate edit distance between two strings.
    ///
    /// **Algorithm:** Dynamic programming (Wagner-Fischer algorithm)
    /// - Time: O(n * m) where n, m are string lengths
    /// - Space: O(n * m) for DP table
    ///
    /// **Reference:** https://en.wikipedia.org/wiki/Levenshtein_distance
    ///
    /// - Parameters:
    ///   - s1: First string
    ///   - s2: Second string
    /// - Returns: Minimum number of edits (insertions, deletions, substitutions) to transform s1 into s2
    ///
    /// **Example:**
    /// ```swift
    /// levenshteinDistance("kitten", "sitting")  // → 3
    /// // k → s (substitution)
    /// // e → i (substitution)
    /// // + g (insertion)
    /// ```
    private static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1 = Array(s1)
        let s2 = Array(s2)

        // Initialize DP table
        var dist = Array(
            repeating: Array(repeating: 0, count: s2.count + 1),
            count: s1.count + 1
        )

        // Base cases: distance from empty string
        for i in 0...s1.count {
            dist[i][0] = i  // Delete all characters from s1
        }
        for j in 0...s2.count {
            dist[0][j] = j  // Insert all characters into s2
        }

        // Fill DP table
        for i in 1...s1.count {
            for j in 1...s2.count {
                let cost = s1[i-1] == s2[j-1] ? 0 : 1  // Substitution cost

                dist[i][j] = min(
                    dist[i-1][j] + 1,        // Deletion
                    dist[i][j-1] + 1,        // Insertion
                    dist[i-1][j-1] + cost    // Substitution
                )
            }
        }

        return dist[s1.count][s2.count]
    }
}
