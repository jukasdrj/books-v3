import Foundation

/// SearchLinksDTO - HATEOAS links for external book search providers
///
/// Mirrors TypeScript SearchLinksDTO in cloudflare-workers/api-worker/src/types/canonical.ts.
/// Implements HATEOAS (Hypermedia as the Engine of Application State) principle:
/// Clients follow links instead of constructing URLs.
///
/// Design: docs/API_CONTRACT.md v2.4 - Issue #196
///
/// **Backend centralizes URL construction** - iOS never builds provider URLs manually.
/// This fixes the "View on Google Books" crash and eliminates duplicated URL logic.
///
/// Example backend response:
/// ```json
/// {
///   "searchLinks": {
///     "googleBooks": "https://www.googleapis.com/books/v1/volumes?q=isbn:9780743273565",
///     "openLibrary": "https://openlibrary.org/isbn/9780743273565",
///     "amazon": "https://www.amazon.com/s?k=9780743273565"
///   }
/// }
/// ```
public struct SearchLinksDTO: Codable, Sendable, Equatable {
    /// Direct link to Google Books search or volume page
    public let googleBooks: String?

    /// Direct link to OpenLibrary ISBN page or search
    public let openLibrary: String?

    /// Direct link to Amazon search results
    public let amazon: String?

    // MARK: - Public Initializer

    public init(
        googleBooks: String? = nil,
        openLibrary: String? = nil,
        amazon: String? = nil
    ) {
        self.googleBooks = googleBooks
        self.openLibrary = openLibrary
        self.amazon = amazon
    }
}
