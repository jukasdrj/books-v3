# Security Audit Implementation Plan

**Created:** November 4, 2025
**Source:** `docs/code-review.md` (Comprehensive Code Quality Audit)
**Overall Assessment:** 8.5/10 (EXCELLENT)
**Strategy:** Component-based approach for parallel team execution

---

## Overview

This plan implements 10 priority action items from the security audit, organized by system component to enable parallel development and clear ownership assignment.

### Component Breakdown

| Component | Items | Priority | Est. Time | Owner |
|-----------|-------|----------|-----------|-------|
| **Backend Security** | 3 items | 🔴 CRITICAL | 1-2 days | Backend Engineer |
| **iOS Data Layer** | 4 items | 🟡 HIGH-MEDIUM | 4-6 days | iOS Engineer |
| **Cross-Platform** | 3 items | 🟡 HIGH-MEDIUM | 3-5 days | Both Teams |

---

## Component 1: Backend Security Hardening 🔴 CRITICAL

**Priority:** Ship within 1 week
**Location:** `cloudflare-workers/api-worker/src/`
**Owner:** Backend Engineer

### Task 1.1: Add Rate Limiting to Enrichment Endpoints

**Severity:** 🚨 CRITICAL
**Est. Time:** 4-6 hours
**Files:** `index.js`, `wrangler.toml`

**Problem:**
- `/api/enrichment/start` has no rate limiting
- Attacker can spawn unlimited Durable Objects
- Denial-of-wallet attack vector (unlimited Cloudflare bills)

**Implementation Steps:**

1. **Add Cloudflare Rate Limiting binding** (`wrangler.toml`)
   ```toml
   [[unsafe.bindings]]
   name = "RATE_LIMITER"
   type = "ratelimit"
   namespace_id = "books-api-rate-limiter"
   # 10 requests per minute per IP
   simple = { limit = 10, period = 60 }
   ```

2. **Create rate limiting middleware** (`src/middleware/rate-limiter.js`)
   ```javascript
   export async function checkRateLimit(request, env) {
     const clientIP = request.headers.get('CF-Connecting-IP') || 'unknown';
     const { success } = await env.RATE_LIMITER.limit({ key: clientIP });

     if (!success) {
       return new Response(JSON.stringify({
         error: 'Rate limit exceeded. Try again in 60 seconds.',
         code: 'RATE_LIMIT_EXCEEDED'
       }), {
         status: 429,
         headers: { 'Retry-After': '60' }
       });
     }

     return null; // No rate limit hit
   }
   ```

3. **Apply to enrichment endpoints** (`src/index.js`)
   ```javascript
   // Before processing expensive operations
   if (url.pathname === '/api/enrichment/start' && request.method === 'POST') {
     const rateLimitResponse = await checkRateLimit(request, env);
     if (rateLimitResponse) return rateLimitResponse;

     // ... existing enrichment logic
   }
   ```

4. **Apply to other expensive endpoints:**
   - `/api/scan-bookshelf`
   - `/api/scan-bookshelf/batch`
   - `/api/import/csv-gemini`

**Testing:**
```bash
# Test rate limiting
for i in {1..15}; do
  curl -X POST https://books-api-proxy.jukasdrj.workers.dev/api/enrichment/start \
    -H "Content-Type: application/json" \
    -d '{"jobId":"test","workIds":["1"]}' &
done
wait

# Expected: First 10 succeed (200), next 5 fail (429)
```

**Success Criteria:**
- [ ] 11th request within 60s returns 429 status
- [ ] Response includes `Retry-After: 60` header
- [ ] Rate limit resets after 60 seconds
- [ ] Different IPs have independent rate limits

**Cost:** ~$5/month for 10M requests

---

### Task 1.2: Validate Request Size Before Parsing

**Severity:** 🔴 HIGH
**Est. Time:** 2-3 hours
**Files:** `index.js`, `src/handlers/csv-import.js`

**Problem:**
- No size validation before parsing request body
- 500MB CSV upload → crashes worker (256MB memory limit)
- Disrupts service for all users

**Implementation Steps:**

1. **Create size validation middleware** (`src/middleware/size-validator.js`)
   ```javascript
   export function validateRequestSize(request, maxSizeMB = 10) {
     const contentLength = parseInt(request.headers.get('Content-Length') || '0');
     const maxBytes = maxSizeMB * 1024 * 1024;

     if (contentLength > maxBytes) {
       return new Response(JSON.stringify({
         error: `File too large. Maximum ${maxSizeMB}MB allowed.`,
         code: 'FILE_TOO_LARGE',
         details: {
           receivedMB: (contentLength / 1024 / 1024).toFixed(2),
           maxMB: maxSizeMB
         }
       }), { status: 413 });
     }

     return null; // Size OK
   }
   ```

2. **Apply to CSV import endpoint** (`src/index.js`)
   ```javascript
   if (url.pathname === '/api/import/csv-gemini' && request.method === 'POST') {
     const sizeCheck = validateRequestSize(request, 10); // 10MB limit
     if (sizeCheck) return sizeCheck;

     return handleCSVImport(request, { ...env, ctx });
   }
   ```

3. **Apply to bookshelf scan endpoints**
   ```javascript
   if (url.pathname === '/api/scan-bookshelf' && request.method === 'POST') {
     const sizeCheck = validateRequestSize(request, 5); // 5MB per photo
     if (sizeCheck) return sizeCheck;

     // ... existing scan logic
   }
   ```

4. **Update iOS error handling** (`BooksTrackerPackage/Sources/BooksTrackerFeature/Services/GeminiCSVImportService.swift`)
   ```swift
   // Add to parseError()
   case 413:
     return .fileTooLarge(details: errorData["details"] as? [String: Any])
   ```

**Testing:**
```bash
# Generate 11MB test file
dd if=/dev/zero of=large.csv bs=1M count=11

# Test size validation
curl -X POST https://books-api-proxy.jukasdrj.workers.dev/api/import/csv-gemini \
  -H "Content-Type: text/csv" \
  --data-binary @large.csv

# Expected: 413 status with helpful error message
```

**Success Criteria:**
- [ ] 11MB CSV returns 413 status
- [ ] Error message includes actual size and limit
- [ ] Worker memory usage stays below 100MB
- [ ] iOS displays user-friendly error alert

---

### Task 1.3: Fix CORS Wildcard Configuration

**Severity:** 🔴 HIGH
**Est. Time:** 1-2 hours
**Files:** `index.js`

**Problem:**
- `'Access-Control-Allow-Origin': '*'` allows any website to call API
- Malicious site could trigger enrichment from victim's browser
- CSRF vulnerability

**Implementation Steps:**

1. **Create CORS middleware** (`src/middleware/cors.js`)
   ```javascript
   const ALLOWED_ORIGINS = [
     'https://bookstrack.app',           // Production
     'https://www.bookstrack.app',       // Production www
     'http://localhost:3000',            // Local development
     'capacitor://localhost',            // iOS Capacitor (if used)
     'ionic://localhost'                 // iOS Ionic (if used)
   ];

   export function getCorsHeaders(request) {
     const origin = request.headers.get('Origin');
     const allowedOrigin = ALLOWED_ORIGINS.includes(origin) ? origin : null;

     return {
       'Access-Control-Allow-Origin': allowedOrigin || 'null',
       'Access-Control-Allow-Credentials': 'true',
       'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
       'Access-Control-Allow-Headers': 'Content-Type, Authorization',
       'Access-Control-Max-Age': '86400' // 24 hours
     };
   }
   ```

2. **Apply CORS middleware globally** (`src/index.js`)
   ```javascript
   import { getCorsHeaders } from './middleware/cors.js';

   export default {
     async fetch(request, env, ctx) {
       // Handle OPTIONS preflight
       if (request.method === 'OPTIONS') {
         return new Response(null, {
           status: 204,
           headers: getCorsHeaders(request)
         });
       }

       // ... existing routing logic

       // Add CORS headers to all responses
       const response = await handleRequest(request, env, ctx);
       const corsHeaders = getCorsHeaders(request);

       Object.entries(corsHeaders).forEach(([key, value]) => {
         response.headers.set(key, value);
       });

       return response;
     }
   };
   ```

3. **Update wrangler.toml with allowed origins** (documentation)
   ```toml
   # wrangler.toml - Add comment for future reference
   # CORS allowed origins defined in src/middleware/cors.js
   # Production: https://bookstrack.app
   # Development: http://localhost:3000
   ```

**Testing:**
```bash
# Test allowed origin
curl -X POST https://books-api-proxy.jukasdrj.workers.dev/api/enrichment/start \
  -H "Origin: https://bookstrack.app" \
  -H "Content-Type: application/json" \
  -d '{"jobId":"test","workIds":["1"]}'

# Expected: Response includes 'Access-Control-Allow-Origin: https://bookstrack.app'

# Test blocked origin
curl -X POST https://books-api-proxy.jukasdrj.workers.dev/api/enrichment/start \
  -H "Origin: https://evil.com" \
  -H "Content-Type: application/json" \
  -d '{"jobId":"test","workIds":["1"]}'

# Expected: Response includes 'Access-Control-Allow-Origin: null'
```

**Success Criteria:**
- [ ] Production domain allowed
- [ ] Localhost allowed (for development)
- [ ] Unknown domains blocked (return 'null')
- [ ] OPTIONS preflight handled correctly
- [ ] iOS app still works (if using Capacitor/Ionic)

---

### Component 1 Verification

**Security Checklist:**
- [ ] Rate limiting active on all expensive endpoints
- [ ] Request size validation prevents memory crashes
- [ ] CORS restricted to known domains
- [ ] All 3 fixes deployed to production
- [ ] iOS app tested against production backend
- [ ] Monitoring alerts configured for rate limit hits

**Deployment Steps:**
1. Deploy to staging: `npx wrangler deploy --env staging`
2. Run integration tests against staging
3. Deploy to production: `npx wrangler deploy`
4. Monitor logs for 24 hours: `/logs` command
5. Verify no false positives (legitimate users blocked)

---

## Component 2: iOS Data Layer Refactoring 🟡 HIGH-MEDIUM

**Priority:** Ship within 1 month
**Location:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Models/`
**Owner:** iOS Engineer

### Task 2.1: Extract EditionSelection Strategy Pattern

**Severity:** 🟡 HIGH
**Est. Time:** 1-2 days
**Files:** `Work.swift`, new `EditionSelectionStrategy.swift`

**Problem:**
- `primaryEdition` computed property is 43 lines long
- Mixes user preference checking, strategy matching, quality scoring, date parsing
- Hard to test each strategy in isolation
- Adding new strategies requires modifying Work.swift

**Implementation Steps:**

1. **Define strategy protocol** (`EditionSelectionStrategy.swift`)
   ```swift
   public protocol EditionSelectionStrategy {
       func selectPrimaryEdition(from editions: [Edition], for work: Work) -> Edition?
   }
   ```

2. **Implement concrete strategies**
   ```swift
   // AutoStrategy.swift
   public struct AutoStrategy: EditionSelectionStrategy {
       public func selectPrimaryEdition(from editions: [Edition], for work: Work) -> Edition? {
           let scored = editions.map { edition in
               (edition: edition, score: qualityScore(for: edition, work: work))
           }
           return scored.max(by: { $0.score < $1.score })?.edition
       }

       private func qualityScore(for edition: Edition, work: Work) -> Int {
           var score = 0

           // Cover image (highest priority)
           if let coverURL = edition.coverImageURL, !coverURL.isEmpty {
               score += 10
           }

           // Format preference
           switch edition.format {
           case .hardcover: score += 3
           case .paperback: score += 2
           case .ebook: score += 1
           default: break
           }

           // User's owned edition
           if work.userEntry?.edition?.id == edition.id {
               score += 5
           }

           // Completeness (ISBN, publisher, etc.)
           if !edition.isbns.isEmpty { score += 1 }
           if edition.publisher != nil { score += 1 }

           return score
       }
   }

   // RecentStrategy.swift
   public struct RecentStrategy: EditionSelectionStrategy {
       public func selectPrimaryEdition(from editions: [Edition], for work: Work) -> Edition? {
           return editions
               .compactMap { edition -> (Edition, Date)? in
                   guard let dateStr = edition.publicationDate,
                         let date = parseDate(dateStr) else { return nil }
                   return (edition, date)
               }
               .max(by: { $0.1 < $1.1 })?
               .0
       }

       private func parseDate(_ dateStr: String) -> Date? {
           // ... existing date parsing logic from Work.swift
       }
   }

   // HardcoverStrategy.swift
   public struct HardcoverStrategy: EditionSelectionStrategy {
       public func selectPrimaryEdition(from editions: [Edition], for work: Work) -> Edition? {
           return editions.first(where: { $0.format == .hardcover })
       }
   }

   // ManualStrategy.swift (placeholder for future UI)
   public struct ManualStrategy: EditionSelectionStrategy {
       public func selectPrimaryEdition(from editions: [Edition], for work: Work) -> Edition? {
           // Return user's manually selected edition if set
           return work.userEntry?.manuallySelectedEdition ?? editions.first
       }
   }
   ```

3. **Refactor Work.swift**
   ```swift
   // Work.swift
   public var primaryEdition: Edition? {
       guard let editions = editions, !editions.isEmpty else { return nil }

       let strategy: EditionSelectionStrategy = {
           switch FeatureFlags.shared.coverSelectionStrategy {
           case .auto: return AutoStrategy()
           case .recent: return RecentStrategy()
           case .hardcover: return HardcoverStrategy()
           case .manual: return ManualStrategy()
           }
       }()

       return strategy.selectPrimaryEdition(from: editions, for: self)
   }
   ```

4. **Add tests** (`EditionSelectionStrategyTests.swift`)
   ```swift
   import Testing
   @testable import BooksTrackerFeature

   @Suite("Edition Selection Strategies")
   struct EditionSelectionStrategyTests {

       @Test("AutoStrategy prefers editions with cover images")
       func autoStrategyPrefersCoverImages() {
           let noCover = Edition(coverImageURL: nil)
           let withCover = Edition(coverImageURL: "https://example.com/cover.jpg")

           let strategy = AutoStrategy()
           let selected = strategy.selectPrimaryEdition(
               from: [noCover, withCover],
               for: Work(title: "Test")
           )

           #expect(selected?.id == withCover.id)
       }

       @Test("RecentStrategy prefers newer editions")
       func recentStrategyPrefersNewer() {
           let old = Edition(publicationDate: "2000-01-01")
           let new = Edition(publicationDate: "2024-12-01")

           let strategy = RecentStrategy()
           let selected = strategy.selectPrimaryEdition(
               from: [old, new],
               for: Work(title: "Test")
           )

           #expect(selected?.id == new.id)
       }

       @Test("HardcoverStrategy only selects hardcovers")
       func hardcoverStrategySelectsHardcover() {
           let paperback = Edition(format: .paperback)
           let hardcover = Edition(format: .hardcover)

           let strategy = HardcoverStrategy()
           let selected = strategy.selectPrimaryEdition(
               from: [paperback, hardcover],
               for: Work(title: "Test")
           )

           #expect(selected?.format == .hardcover)
       }
   }
   ```

**Success Criteria:**
- [ ] `primaryEdition` reduced from 43 lines to <10 lines
- [ ] Each strategy testable in isolation
- [ ] All existing tests still pass
- [ ] New strategy tests added (3+ per strategy)
- [ ] No behavior change (before/after comparison)

**Migration Notes:**
- This is a pure refactoring (zero behavior change)
- Existing `qualityScore()` logic moves to `AutoStrategy`
- Existing date parsing moves to `RecentStrategy`

---

### Task 2.2: Add @Bindable Usage Documentation

**Severity:** 🟡 HIGH
**Est. Time:** 30 minutes
**Files:** `Work.swift`, `Edition.swift`, `Author.swift`, `UserLibraryEntry.swift`

**Problem:**
- CLAUDE.md mentions `@Bindable` pattern but models don't document it
- Developers might forget to use `@Bindable` in child views
- Results in views not updating when relationships change

**Implementation Steps:**

1. **Add docstring to Work.swift**
   ```swift
   /// Represents an abstract creative work (book, novel, collection).
   ///
   /// # SwiftUI Reactive Updates
   ///
   /// **CRITICAL:** When passing `Work` to child views that observe relationships,
   /// use `@Bindable` to enable reactive updates:
   ///
   /// ```swift
   /// struct WorkDetailView: View {
   ///     @Bindable var work: Work  // ← Observes userLibraryEntries, editions, authors
   ///
   ///     var body: some View {
   ///         Text("Rating: \(work.userEntry?.personalRating ?? 0)")  // ← Updates reactively!
   ///     }
   /// }
   /// ```
   ///
   /// **Why:** SwiftData relationships don't trigger view updates unless observed via `@Bindable`.
   ///
   /// # Insert-Before-Relate Pattern
   ///
   /// **CRITICAL:** Always call `modelContext.insert()` BEFORE setting relationships:
   ///
   /// ```swift
   /// let work = Work(title: "...", authors: [], ...)
   /// modelContext.insert(work)  // ← Gets permanent ID
   ///
   /// let author = Author(name: "...")
   /// modelContext.insert(author)  // ← Gets permanent ID
   ///
   /// work.authors = [author]  // ← Safe - both have permanent IDs
   /// ```
   ///
   /// - SeeAlso: `CLAUDE.md` lines 126-149 for full SwiftData lifecycle rules
   @Model
   public final class Work {
       // ... existing implementation
   }
   ```

2. **Add docstring to UserLibraryEntry.swift**
   ```swift
   /// Represents a user's interaction with a work (ownership, reading status, rating).
   ///
   /// # SwiftUI Reactive Updates
   ///
   /// Use `@Bindable` when binding to forms or observing status changes:
   ///
   /// ```swift
   /// struct ReadingProgressView: View {
   ///     @Bindable var entry: UserLibraryEntry
   ///
   ///     var body: some View {
   ///         Slider(value: $entry.readingProgress, in: 0...1)  // ← Two-way binding!
   ///     }
   /// }
   /// ```
   @Model
   public final class UserLibraryEntry {
       // ... existing implementation
   }
   ```

3. **Add docstring to Edition.swift**
   ```swift
   /// Represents a physical or digital manifestation of a work.
   ///
   /// # SwiftUI Reactive Updates
   ///
   /// Use `@Bindable` when observing ISBN array or format changes:
   ///
   /// ```swift
   /// struct EditionDetailView: View {
   ///     @Bindable var edition: Edition
   ///
   ///     var body: some View {
   ///         ForEach(edition.isbns, id: \.self) { isbn in  // ← Observes array changes
   ///             Text(isbn)
   ///         }
   ///     }
   /// }
   /// ```
   @Model
   public final class Edition {
       // ... existing implementation
   }
   ```

4. **Update CLAUDE.md with file references**
   ```markdown
   ### State Management - No ViewModels!

   **Property Wrappers:**
   - `@Bindable` - **CRITICAL for SwiftData models!** Enables reactive updates on relationships
     - See `Work.swift:1-35` for complete usage guide
     - See `UserLibraryEntry.swift:1-20` for form binding examples
   ```

**Success Criteria:**
- [ ] All 4 SwiftData models have `@Bindable` docstrings
- [ ] Each docstring includes code example
- [ ] Examples show realistic use cases
- [ ] CLAUDE.md updated with file references

---

### Task 2.3: Add Edition Quality Score Tests

**Severity:** 🟢 MEDIUM
**Est. Time:** 2 hours
**Files:** New `EditionScoringTests.swift`

**Problem:**
- Complex quality scoring logic has no dedicated tests
- Magic numbers (10 for cover, 3 for hardcover) not validated
- Hard to verify scoring changes don't break selection

**Implementation Steps:**

1. **Create test file** (`Tests/BooksTrackerFeatureTests/EditionScoringTests.swift`)
   ```swift
   import Testing
   import SwiftData
   @testable import BooksTrackerFeature

   @Suite("Edition Quality Scoring")
   @MainActor
   struct EditionScoringTests {

       var modelContainer: ModelContainer!
       var modelContext: ModelContext!

       init() throws {
           modelContainer = try ModelContainer(
               for: Work.self, Edition.self,
               configurations: ModelConfiguration(isStoredInMemoryOnly: true)
           )
           modelContext = ModelContext(modelContainer)
       }

       @Test("Cover image adds 10 points")
       func coverImageScoring() {
           let work = Work(title: "Test Book", authors: [], editions: [])
           modelContext.insert(work)

           let noCover = Edition(coverImageURL: nil)
           let withCover = Edition(coverImageURL: "https://example.com/cover.jpg")
           modelContext.insert(noCover)
           modelContext.insert(withCover)

           work.editions = [noCover, withCover]

           let strategy = AutoStrategy()
           let selected = strategy.selectPrimaryEdition(from: work.editions ?? [], for: work)

           #expect(selected?.id == withCover.id, "Edition with cover should score higher")
       }

       @Test("Hardcover preferred over paperback")
       func formatPreference() {
           let work = Work(title: "Test Book", authors: [], editions: [])
           modelContext.insert(work)

           let paperback = Edition(format: .paperback)
           let hardcover = Edition(format: .hardcover)
           modelContext.insert(paperback)
           modelContext.insert(hardcover)

           work.editions = [paperback, hardcover]

           let strategy = AutoStrategy()
           let selected = strategy.selectPrimaryEdition(from: work.editions ?? [], for: work)

           #expect(selected?.format == .hardcover, "Hardcover should score higher than paperback")
       }

       @Test("User's owned edition gets +5 bonus")
       func ownedEditionBonus() {
           let work = Work(title: "Test Book", authors: [], editions: [])
           modelContext.insert(work)

           let regularEdition = Edition(coverImageURL: nil)
           let ownedEdition = Edition(coverImageURL: nil)
           modelContext.insert(regularEdition)
           modelContext.insert(ownedEdition)

           work.editions = [regularEdition, ownedEdition]

           let entry = UserLibraryEntry.createWishlistEntry(for: work)
           entry.edition = ownedEdition
           modelContext.insert(entry)

           let strategy = AutoStrategy()
           let selected = strategy.selectPrimaryEdition(from: work.editions ?? [], for: work)

           #expect(selected?.id == ownedEdition.id, "User's owned edition should get priority")
       }

       @Test("Completeness scoring (ISBN, publisher)")
       func completenessScoring() {
           let work = Work(title: "Test Book", authors: [], editions: [])
           modelContext.insert(work)

           let bareMinimum = Edition()
           let complete = Edition(publisher: "Penguin Books")
           complete.addISBN("978-0-7475-3269-9")
           modelContext.insert(bareMinimum)
           modelContext.insert(complete)

           work.editions = [bareMinimum, complete]

           let strategy = AutoStrategy()
           let selected = strategy.selectPrimaryEdition(from: work.editions ?? [], for: work)

           #expect(selected?.id == complete.id, "Complete edition should score higher")
       }
   }
   ```

**Success Criteria:**
- [ ] 4+ scoring tests added
- [ ] Tests validate magic number values (10, 3, 2, 1)
- [ ] Tests verify user preference bonus
- [ ] All tests pass with zero warnings

---

### Task 2.4: Extract ReadingStatusParser Service

**Severity:** 🟢 MEDIUM
**Est. Time:** 1 day
**Files:** New `ReadingStatusParser.swift`, refactor `UserLibraryEntry.swift`

**Problem:**
- `ReadingStatus.from()` is 68 lines in enum
- Hard to add new import formats (Goodreads, LibraryThing)
- No fuzzy matching for typos ("currenty reading")
- String mapping clutters enum definition

**Implementation Steps:**

1. **Create parser service** (`ReadingStatusParser.swift`)
   ```swift
   public struct ReadingStatusParser {

       // MARK: - Direct Mappings (O(1) lookup)

       private static let mappings: [String: ReadingStatus] = [
           // Wishlist
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

           // Currently Reading
           "reading": .reading,
           "currently reading": .reading,
           "in progress": .reading,
           "started": .reading,

           // Read
           "read": .read,
           "finished": .read,
           "completed": .read,
           "done": .read
       ]

       // MARK: - Public API

       public static func parse(_ string: String?) -> ReadingStatus? {
           guard let normalized = string?
               .trimmingCharacters(in: .whitespacesAndNewlines)
               .lowercased() else { return nil }

           // Direct lookup
           if let status = mappings[normalized] {
               return status
           }

           // Fuzzy matching for typos
           return fuzzyMatch(normalized)
       }

       // MARK: - Fuzzy Matching

       private static func fuzzyMatch(_ string: String) -> ReadingStatus? {
           // Find closest match using Levenshtein distance
           let candidates = mappings.keys
           let closest = candidates.min { key1, key2 in
               levenshteinDistance(string, key1) < levenshteinDistance(string, key2)
           }

           guard let match = closest else { return nil }
           let distance = levenshteinDistance(string, match)

           // Only accept if ≤2 character edits (typos, not different words)
           if distance <= 2 {
               return mappings[match]
           }

           return nil
       }

       // MARK: - Levenshtein Distance

       private static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
           let s1 = Array(s1)
           let s2 = Array(s2)
           var dist = Array(repeating: Array(repeating: 0, count: s2.count + 1), count: s1.count + 1)

           for i in 0...s1.count { dist[i][0] = i }
           for j in 0...s2.count { dist[0][j] = j }

           for i in 1...s1.count {
               for j in 1...s2.count {
                   let cost = s1[i-1] == s2[j-1] ? 0 : 1
                   dist[i][j] = min(
                       dist[i-1][j] + 1,      // deletion
                       dist[i][j-1] + 1,      // insertion
                       dist[i-1][j-1] + cost  // substitution
                   )
               }
           }

           return dist[s1.count][s2.count]
       }
   }
   ```

2. **Refactor UserLibraryEntry.swift**
   ```swift
   // UserLibraryEntry.swift
   public enum ReadingStatus: String, Codable, CaseIterable, Identifiable, Sendable {
       case wishlist = "Wishlist"
       case toRead = "To Read"
       case reading = "Currently Reading"
       case read = "Read"

       // ... existing icon, displayName, etc.

       /// Parse reading status from import string.
       ///
       /// Examples:
       /// - "want to read" → `.wishlist`
       /// - "currenty reading" → `.reading` (typo corrected)
       /// - "completed" → `.read`
       public static func from(string: String?) -> ReadingStatus? {
           return ReadingStatusParser.parse(string)  // Delegate to parser
       }
   }
   ```

3. **Add tests** (`ReadingStatusParserTests.swift`)
   ```swift
   @Test("Direct mapping for standard values")
   func directMapping() {
       #expect(ReadingStatusParser.parse("wishlist") == .wishlist)
       #expect(ReadingStatusParser.parse("currently reading") == .reading)
       #expect(ReadingStatusParser.parse("finished") == .read)
   }

   @Test("Fuzzy matching for typos")
   func fuzzyMatching() {
       #expect(ReadingStatusParser.parse("currenty reading") == .reading)  // typo: currenty
       #expect(ReadingStatusParser.parse("fnished") == .read)              // typo: fnished
       #expect(ReadingStatusParser.parse("wishlis") == .wishlist)          // typo: wishlis
   }

   @Test("Case insensitive")
   func caseInsensitive() {
       #expect(ReadingStatusParser.parse("WISHLIST") == .wishlist)
       #expect(ReadingStatusParser.parse("Currently Reading") == .reading)
   }

   @Test("Returns nil for unrecognized strings")
   func unrecognizedStrings() {
       #expect(ReadingStatusParser.parse("foobar") == nil)
       #expect(ReadingStatusParser.parse("") == nil)
       #expect(ReadingStatusParser.parse(nil) == nil)
   }
   ```

**Success Criteria:**
- [ ] Enum reduced from 68 lines to <20 lines
- [ ] Fuzzy matching handles 1-2 character typos
- [ ] Parser testable with CSV files
- [ ] All existing CSV import tests still pass

---

### Component 2 Verification

**iOS Quality Checklist:**
- [ ] Edition selection strategy pattern implemented
- [ ] All 4 strategies tested in isolation
- [ ] `@Bindable` documented in all SwiftData models
- [ ] Edition scoring tests added (4+ tests)
- [ ] ReadingStatusParser extracted and tested
- [ ] Zero new SwiftData warnings
- [ ] All UI tests still pass

---

## Component 3: Cross-Platform Architecture 🟡 HIGH-MEDIUM

**Priority:** Ship within 3 months
**Location:** Mixed (Swift + TypeScript)
**Owner:** Both teams (coordination required)

### Task 3.1: Delete Archived Code + Add Migration History

**Severity:** 🟡 HIGH
**Est. Time:** 1 hour
**Files:** `cloudflare-workers/_archived/`, `BooksTrackerPackage/Sources/BooksTrackerFeature/_archive/`

**Problem:**
- Archived code confuses new developers
- Git history sufficient for rollback
- Takes up unnecessary space

**Implementation Steps:**

1. **Create migration history document** (`docs/MIGRATION_HISTORY.md`)
   ```markdown
   # Migration History

   ## October 2025: Monolith Consolidation

   **Decision:** Consolidated distributed Cloudflare Workers into single monolith

   **Reason:**
   - Simpler architecture for current scale (<1000 users)
   - Reduced operational complexity
   - Direct function calls instead of RPC overhead

   **Removed:**
   - `cloudflare-workers/_archived/personal-library-cache-warmer/`
   - `cloudflare-workers/_archived/enrichment-worker/`
   - `cloudflare-workers/_archived/ai-worker/`

   **View old code:** `git checkout v3.0.0-pre-monolith`

   **See:** `cloudflare-workers/MONOLITH_ARCHITECTURE.md` for new design

   ---

   ## September 2025: iOS SwiftData Refactoring

   **Decision:** Removed ViewModel layer in favor of @Observable + @State

   **Reason:**
   - SwiftData models already observable
   - ViewModels created unnecessary indirection
   - Simpler state management

   **Removed:**
   - `BooksTrackerPackage/Sources/BooksTrackerFeature/_archive/ViewModels/`

   **View old code:** `git checkout v2.8.0-pre-swiftdata-refactor`

   **See:** `docs/architecture/STATE_MANAGEMENT.md` for patterns
   ```

2. **Delete archived directories**
   ```bash
   cd /Users/justingardner/Downloads/xcode/books-tracker-v1

   # Delete backend archives
   rm -rf cloudflare-workers/_archived/

   # Delete iOS archives
   rm -rf BooksTrackerPackage/Sources/BooksTrackerFeature/_archive/

   # Verify deletion
   git status
   ```

3. **Commit with clear message**
   ```bash
   git add -A
   git commit -m "chore: Delete archived code, add migration history

   - Remove cloudflare-workers/_archived/ (distributed architecture)
   - Remove BooksTrackerPackage/_archive/ (ViewModel layer)
   - Add docs/MIGRATION_HISTORY.md for rollback references

   Git history preserved via tags:
   - v3.0.0-pre-monolith (Workers architecture)
   - v2.8.0-pre-swiftdata-refactor (ViewModel layer)

   Refs: docs/code-review.md §6 (Technical Debt)"
   ```

**Success Criteria:**
- [ ] All `_archived/` directories deleted
- [ ] `MIGRATION_HISTORY.md` created with rollback instructions
- [ ] Git tags created for old code references
- [ ] Commit message explains rationale

---

### Task 3.2: Implement Repository Pattern for Data Access

**Severity:** 🟡 HIGH
**Est. Time:** 2-3 days
**Files:** New `LibraryRepository.swift`, refactor views using `@Query`

**Problem:**
- SwiftData queries scattered across views (10+ places)
- Business logic in UI layer
- Hard to test without SwiftUI environment
- Query performance optimization requires finding all usage sites

**Implementation Steps:**

1. **Create repository interface** (`LibraryRepository.swift`)
   ```swift
   @MainActor
   public class LibraryRepository {
       private let modelContext: ModelContext

       public init(modelContext: ModelContext) {
           self.modelContext = modelContext
       }

       // MARK: - Library Queries

       public func fetchUserLibrary() throws -> [Work] {
           let descriptor = FetchDescriptor<Work>(
               predicate: #Predicate { work in
                   work.userLibraryEntries?.isEmpty == false
               },
               sortBy: [SortDescriptor(\.lastModified, order: .reverse)]
           )
           return try modelContext.fetch(descriptor)
       }

       public func fetchByReadingStatus(_ status: ReadingStatus) throws -> [Work] {
           let descriptor = FetchDescriptor<Work>(
               predicate: #Predicate { work in
                   work.userLibraryEntries?.first?.readingStatus == status
               },
               sortBy: [SortDescriptor(\.lastModified, order: .reverse)]
           )
           return try modelContext.fetch(descriptor)
       }

       public func fetchCurrentlyReading() throws -> [Work] {
           return try fetchByReadingStatus(.reading)
       }

       public func searchLibrary(query: String) throws -> [Work] {
           let descriptor = FetchDescriptor<Work>(
               predicate: #Predicate { work in
                   work.userLibraryEntries?.isEmpty == false &&
                   work.title.localizedStandardContains(query)
               },
               sortBy: [SortDescriptor(\.title)]
           )
           return try modelContext.fetch(descriptor)
       }

       // MARK: - Statistics

       public func totalBooksCount() throws -> Int {
           let descriptor = FetchDescriptor<Work>(
               predicate: #Predicate { work in
                   work.userLibraryEntries?.isEmpty == false
               }
           )
           return try modelContext.fetchCount(descriptor)
       }

       public func completionRate() throws -> Double {
           let total = try totalBooksCount()
           guard total > 0 else { return 0.0 }

           let read = try fetchByReadingStatus(.read).count
           return Double(read) / Double(total)
       }
   }
   ```

2. **Add to Environment** (`BooksTrackerApp.swift`)
   ```swift
   @main
   struct BooksTrackerApp: App {
       let modelContainer: ModelContainer
       let repository: LibraryRepository

       init() {
           do {
               modelContainer = try ModelContainer(for: Work.self, Edition.self, Author.self, UserLibraryEntry.self)
               repository = LibraryRepository(modelContext: modelContainer.mainContext)
           } catch {
               fatalError("Could not initialize ModelContainer: \(error)")
           }
       }

       var body: some Scene {
           WindowGroup {
               ContentView()
                   .modelContainer(modelContainer)
                   .environment(repository)  // ← Inject repository
           }
       }
   }
   ```

3. **Refactor LibraryView** (before)
   ```swift
   struct LibraryView: View {
       @Query(filter: #Predicate<Work> { work in
           work.userLibraryEntries?.isEmpty == false
       }) var libraryWorks: [Work]

       var body: some View {
           List(libraryWorks) { work in
               WorkRowView(work: work)
           }
       }
   }
   ```

4. **Refactor LibraryView** (after)
   ```swift
   struct LibraryView: View {
       @Environment(LibraryRepository.self) private var repository
       @State private var libraryWorks: [Work] = []
       @State private var isLoading = false
       @State private var error: Error?

       var body: some View {
           Group {
               if isLoading {
                   ProgressView("Loading library...")
               } else if let error = error {
                   ErrorView(error: error, retry: loadLibrary)
               } else {
                   List(libraryWorks) { work in
                       WorkRowView(work: work)
                   }
               }
           }
           .task {
               await loadLibrary()
           }
       }

       private func loadLibrary() async {
           isLoading = true
           defer { isLoading = false }

           do {
               libraryWorks = try repository.fetchUserLibrary()
               error = nil
           } catch {
               self.error = error
           }
       }
   }
   ```

5. **Add tests** (`LibraryRepositoryTests.swift`)
   ```swift
   @Test("Fetch user library returns only owned books")
   @MainActor
   func fetchUserLibrary() throws {
       let repository = LibraryRepository(modelContext: modelContext)

       // Create works
       let ownedWork = Work(title: "Owned Book", authors: [], editions: [])
       let notOwnedWork = Work(title: "Not Owned", authors: [], editions: [])
       modelContext.insert(ownedWork)
       modelContext.insert(notOwnedWork)

       // Add library entry for ownedWork only
       let entry = UserLibraryEntry.createWishlistEntry(for: ownedWork)
       modelContext.insert(entry)

       // Fetch
       let library = try repository.fetchUserLibrary()

       #expect(library.count == 1)
       #expect(library.first?.title == "Owned Book")
   }

   @Test("Fetch by reading status filters correctly")
   @MainActor
   func fetchByReadingStatus() throws {
       let repository = LibraryRepository(modelContext: modelContext)

       // Create works with different statuses
       let reading = Work(title: "Reading", authors: [], editions: [])
       let read = Work(title: "Read", authors: [], editions: [])
       modelContext.insert(reading)
       modelContext.insert(read)

       let entry1 = UserLibraryEntry.createWishlistEntry(for: reading)
       entry1.readingStatus = .reading
       let entry2 = UserLibraryEntry.createWishlistEntry(for: read)
       entry2.readingStatus = .read
       modelContext.insert(entry1)
       modelContext.insert(entry2)

       // Fetch currently reading
       let currentlyReading = try repository.fetchCurrentlyReading()

       #expect(currentlyReading.count == 1)
       #expect(currentlyReading.first?.title == "Reading")
   }
   ```

**Success Criteria:**
- [ ] Repository created with 5+ query methods
- [ ] Repository injected via Environment
- [ ] LibraryView refactored to use repository
- [ ] Insights queries refactored
- [ ] Repository tests added (5+ tests)
- [ ] All UI tests still pass

**Migration Notes:**
- Refactor views one at a time (not big bang)
- Keep `@Query` for simple list views (read-only)
- Use repository for complex queries with filters/stats

---

### Task 3.3: Add Canonical DTO Marshaling Tests

**Severity:** 🟢 MEDIUM
**Est. Time:** 1 day
**Files:** New `canonical.test.ts`, update `CanonicalAPIResponseTests.swift`

**Problem:**
- TypeScript → Swift conversion not tested end-to-end
- Field name mismatches could break iOS
- Enum value mismatches could break parsing
- No round-trip tests (TS → JSON → Swift → JSON → TS)

**Implementation Steps:**

1. **Create TypeScript tests** (`cloudflare-workers/api-worker/test/canonical.test.ts`)
   ```typescript
   import { describe, test, expect } from 'vitest';
   import { WorkDTO, EditionDTO, AuthorDTO } from '../src/types/canonical';

   describe('Canonical DTOs', () => {
       test('WorkDTO serializes to JSON matching Swift Codable', () => {
           const work: WorkDTO = {
               title: "The Great Gatsby",
               subjectTags: ["Fiction", "Classic Literature"],
               synthetic: false,
               primaryProvider: "google-books",
               contributors: ["google-books"],
               goodreadsWorkIDs: ["123456"],
               amazonASINs: [],
               librarythingIDs: [],
               googleBooksVolumeIDs: ["abc123"],
               firstPublishedYear: 1925
           };

           const json = JSON.stringify(work);
           const parsed = JSON.parse(json) as WorkDTO;

           // Verify all required fields
           expect(parsed.title).toBe("The Great Gatsby");
           expect(parsed.subjectTags).toEqual(["Fiction", "Classic Literature"]);
           expect(parsed.synthetic).toBe(false);
           expect(parsed.primaryProvider).toBe("google-books");

           // Verify external IDs
           expect(parsed.goodreadsWorkIDs).toHaveLength(1);
           expect(parsed.amazonASINs).toHaveLength(0);
       });

       test('EditionDTO includes all Swift-required fields', () => {
           const edition: EditionDTO = {
               isbns: ["978-0-7432-7356-5"],
               format: "Hardcover",
               coverImageURL: "https://example.com/cover.jpg",
               pageCount: 180,
               publicationDate: "1925-04-10",
               publisher: "Charles Scribner's Sons",
               language: "en",
               editionDescription: "First edition",
               dimensions: "8.5 x 5.5 x 1.2 inches",
               weight: "1.2 lbs"
           };

           const json = JSON.stringify(edition);
           const parsed = JSON.parse(json) as EditionDTO;

           // Verify ISBN array
           expect(parsed.isbns).toContain("978-0-7432-7356-5");

           // Verify format (Swift enum must match)
           expect(parsed.format).toBe("Hardcover");

           // Verify optionals handled correctly
           expect(parsed.coverImageURL).toBeDefined();
           expect(parsed.pageCount).toBe(180);
       });

       test('AuthorDTO diversity fields match Swift enums', () => {
           const author: AuthorDTO = {
               name: "F. Scott Fitzgerald",
               gender: "Male",
               culturalRegion: "North America",
               isMarginalizedVoice: false,
               birthYear: 1896,
               deathYear: 1940,
               photoURL: "https://example.com/author.jpg",
               bio: "American novelist",
               goodreadsAuthorID: "123",
               wikipediaURL: "https://en.wikipedia.org/wiki/F._Scott_Fitzgerald"
           };

           const json = JSON.stringify(author);
           const parsed = JSON.parse(json) as AuthorDTO;

           // Verify gender enum (Swift: .male)
           expect(parsed.gender).toBe("Male");

           // Verify cultural region enum (Swift: .northAmerica)
           expect(parsed.culturalRegion).toBe("North America");

           // Verify marginalized voice boolean
           expect(parsed.isMarginalizedVoice).toBe(false);
       });

       test('Round-trip: TS → JSON → TS preserves all fields', () => {
           const original: WorkDTO = {
               title: "Test Book",
               subjectTags: ["Fiction"],
               synthetic: true,
               primaryProvider: "openlibrary",
               contributors: ["openlibrary", "google-books"],
               goodreadsWorkIDs: [],
               amazonASINs: [],
               librarythingIDs: [],
               googleBooksVolumeIDs: [],
               firstPublishedYear: 2024
           };

           const json = JSON.stringify(original);
           const parsed = JSON.parse(json) as WorkDTO;

           expect(parsed).toEqual(original);
       });
   });
   ```

2. **Add Swift round-trip tests** (`Tests/BooksTrackerFeatureTests/CanonicalAPIResponseTests.swift`)
   ```swift
   @Test("WorkDTO round-trip: Swift → JSON → Swift")
   func workDTORoundTrip() throws {
       let original = WorkDTO(
           title: "Test Book",
           subjectTags: ["Fiction", "Mystery"],
           synthetic: false,
           primaryProvider: "google-books",
           contributors: ["google-books"],
           goodreadsWorkIDs: ["123"],
           amazonASINs: [],
           librarythingIDs: [],
           googleBooksVolumeIDs: ["abc"],
           firstPublishedYear: 2024
       )

       // Encode to JSON
       let encoder = JSONEncoder()
       let jsonData = try encoder.encode(original)

       // Decode back
       let decoder = JSONDecoder()
       let decoded = try decoder.decode(WorkDTO.self, from: jsonData)

       #expect(decoded.title == original.title)
       #expect(decoded.subjectTags == original.subjectTags)
       #expect(decoded.synthetic == original.synthetic)
       #expect(decoded.primaryProvider == original.primaryProvider)
       #expect(decoded.goodreadsWorkIDs == original.goodreadsWorkIDs)
   }

   @Test("AuthorDTO gender enum matches TypeScript")
   func authorGenderEnumMatching() throws {
       let json = """
       {
           "name": "Test Author",
           "gender": "Male",
           "culturalRegion": "North America",
           "isMarginalizedVoice": false
       }
       """

       let decoder = JSONDecoder()
       let author = try decoder.decode(AuthorDTO.self, from: json.data(using: .utf8)!)

       #expect(author.gender == "Male")  // Must match TypeScript exactly
   }

   @Test("EditionDTO format enum matches TypeScript")
   func editionFormatEnumMatching() throws {
       let formats = ["Hardcover", "Paperback", "Ebook", "Audiobook", "Unknown"]

       for format in formats {
           let json = """
           {
               "isbns": ["123"],
               "format": "\(format)"
           }
           """

           let decoder = JSONDecoder()
           let edition = try decoder.decode(EditionDTO.self, from: json.data(using: .utf8)!)

           #expect(edition.format == format, "Format '\(format)' must decode correctly")
       }
   }
   ```

3. **Run tests**
   ```bash
   # TypeScript tests
   cd cloudflare-workers/api-worker
   npm test -- canonical.test.ts

   # Swift tests
   cd /Users/justingardner/Downloads/xcode/books-tracker-v1
   swift test --filter CanonicalAPIResponseTests
   ```

**Success Criteria:**
- [ ] TypeScript round-trip tests pass (4+ tests)
- [ ] Swift round-trip tests pass (3+ tests)
- [ ] Enum value mismatches caught by tests
- [ ] Field name mismatches caught by tests
- [ ] Tests run in CI pipeline

---

### Component 3 Verification

**Cross-Platform Checklist:**
- [ ] Archived code deleted, migration history documented
- [ ] Repository pattern implemented for iOS data access
- [ ] Canonical DTO tests added (TypeScript + Swift)
- [ ] No breaking changes to API contracts
- [ ] Both backend and iOS CI pipelines pass

---

## Implementation Timeline

### Week 1: Critical Security Fixes (Backend Team)
- [ ] Day 1-2: Add rate limiting + request size validation
- [ ] Day 3: Fix CORS wildcard
- [ ] Day 4-5: Deploy to production, monitor

### Week 2-4: iOS Data Layer (iOS Team)
- [ ] Week 2: Extract EditionSelection strategy + tests
- [ ] Week 3: Add @Bindable docs + EditionScoring tests
- [ ] Week 4: Extract ReadingStatusParser

### Month 2-3: Cross-Platform Architecture (Both Teams)
- [ ] Week 5: Implement Repository Pattern (iOS)
- [ ] Week 6: Add Canonical DTO tests (Backend + iOS)
- [ ] Week 7-8: Delete archived code, code review

---

## Success Metrics

### Security Improvements
- [ ] Zero rate limit bypass attempts succeed
- [ ] Zero worker memory crashes from oversized requests
- [ ] Zero CSRF attacks from unauthorized origins
- [ ] Cloudflare bill stays within expected range

### Code Quality Improvements
- [ ] `primaryEdition` reduced from 43 lines to <10 lines
- [ ] All SwiftData models documented with @Bindable examples
- [ ] 10+ new tests added (scoring, parsing, DTOs)
- [ ] ReadingStatus parser handles typos (Levenshtein distance ≤2)

### Architecture Improvements
- [ ] Zero archived code in repository
- [ ] All SwiftData queries centralized in Repository
- [ ] TypeScript ↔ Swift marshaling tested end-to-end

---

## Rollback Plans

### Component 1 (Backend Security)
- If rate limiting causes false positives → adjust limits in wrangler.toml
- If CORS breaks iOS app → add Capacitor/Ionic origins
- If request size validation too strict → increase limit to 20MB

### Component 2 (iOS Data Layer)
- If EditionSelection breaks UI → revert to original `primaryEdition` logic
- If ReadingStatusParser fails imports → fall back to `ReadingStatus.from()`

### Component 3 (Cross-Platform)
- Repository pattern can be gradually adopted (no big bang)
- Archived code deletion is safe (Git history preserved)

---

## Questions for Stakeholders

1. **Backend Team:** Do we have monitoring alerts for rate limit hits?
2. **iOS Team:** Any views besides LibraryView need Repository refactoring?
3. **Product:** Should we prioritize fuzzy matching or manual strategies first?
4. **DevOps:** Can we add Canonical DTO tests to CI pipeline?

---

**Next Steps:** Review this plan, assign owners, and schedule kickoff meeting for Component 1 (Critical Security).
