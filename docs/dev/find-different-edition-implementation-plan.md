# Find Different Edition - Implementation Plan

**Feature:** Allow users to search for and select different editions of books (e.g., switching from paperback to hardcover)

**Status:** Ready for Implementation  
**Backend Dependency:** Issue #63 - `/v1/editions/search` endpoint (in progress)  
**Estimated Effort:** 8-11 hours (2-3 days part-time)

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Critical Code Review Findings](#critical-code-review-findings)
3. [Implementation Phases](#implementation-phases)
4. [Files Summary](#files-summary)
5. [Testing Strategy](#testing-strategy)
6. [Rollout Plan](#rollout-plan)

---

## Architecture Overview

```
User Flow:
1. Long-press book in library
2. Select "Find Different Edition" from context menu
3. Sheet displays editions (HC, PB, Digital, etc.)
4. Tap preferred edition
5. Selection persists to SwiftData
6. ManualStrategy shows selected edition in library view

Data Flow:
iOS26LiquidListRow (context menu)
   |
   v
EditionPickerView (sheet)
   |
   v
EditionPickerViewModel (state machine)
   |
   v
BookSearchAPIService.searchEditions() (API call)
   |
   v
Backend: GET /v1/editions/search?workTitle=...&author=...
   |
   v
CanonicalAPIResponse → EditionDTO[]
   |
   v
DTOMapper → Edition[] (SwiftData models)
   |
   v
User selects edition → userEntry.preferredEdition = edition
   |
   v
ModelContext.save() → Persistence
   |
   v
ManualStrategy.selectPrimaryEdition() → Display in UI
```

---

## Critical Code Review Findings

### HIGH PRIORITY - Must Fix Before Implementation

#### 1. Work.primaryEdition Short-Circuit Bug

**Location:** `Work.swift:247-250`

**Problem:** The existing code returns `userEntry.edition` BEFORE checking ManualStrategy, which means `preferredEdition` will NEVER be used if the user owns any edition.

**Current Code (BROKEN):**
```swift
func primaryEdition(using strategy: CoverSelectionStrategy) -> Edition? {
    // User's owned edition always takes priority (overrides strategy)
    if let userEdition = userEntry?.edition {
        return userEdition  // ❌ Blocks ManualStrategy!
    }
    
    guard let editions = editions, !editions.isEmpty else { return nil }
    
    // Delegate to strategy pattern
    let selectionStrategy: EditionSelectionStrategy = {
        switch strategy {
        case .auto: return AutoStrategy()
        case .recent: return RecentStrategy()
        case .hardcover: return HardcoverStrategy()
        case .manual: return ManualStrategy()
        }
    }()
    
    return selectionStrategy.selectPrimaryEdition(from: editions, for: self)
}
```

**Fix Required:**
```swift
func primaryEdition(using strategy: CoverSelectionStrategy) -> Edition? {
    guard let editions = editions, !editions.isEmpty else { return nil }
    
    // Delegate to strategy pattern (ManualStrategy handles preferredEdition internally)
    let selectionStrategy: EditionSelectionStrategy = {
        switch strategy {
        case .auto: return AutoStrategy()
        case .recent: return RecentStrategy()
        case .hardcover: return HardcoverStrategy()
        case .manual: return ManualStrategy()
        }
    }()
    
    return selectionStrategy.selectPrimaryEdition(from: editions, for: self)
}
```

**Impact:** Without this fix, the entire "Find Different Edition" feature will not work - user selections will be ignored.

---

#### 2. ManualStrategy Incomplete Implementation

**Location:** `EditionSelectionStrategy.swift:164-167`

**Problem:** ManualStrategy code is commented out and doesn't handle owned edition fallback.

**Current Code (COMMENTED):**
```swift
public func selectPrimaryEdition(from editions: [Edition], for work: Work) -> Edition? {
    guard !editions.isEmpty else { return nil }
    
    // Prioritize user's manually selected edition
    // Note: preferredEdition property doesn't exist yet - future enhancement
    // if let preferred = work.userEntry?.preferredEdition {
    //     return preferred
    // }
    
    // Fallback to quality scoring
    return AutoStrategy().selectPrimaryEdition(from: editions, for: work)
}
```

**Fix Required:**
```swift
public func selectPrimaryEdition(from editions: [Edition], for work: Work) -> Edition? {
    guard !editions.isEmpty else { return nil }
    
    // 1. Prioritize user's manually selected edition
    if let preferred = work.userEntry?.preferredEdition {
        return preferred
    }
    
    // 2. Fallback to owned edition if no manual selection
    if let owned = work.userEntry?.edition {
        return owned
    }
    
    // 3. Final fallback to AutoStrategy
    return AutoStrategy().selectPrimaryEdition(from: editions, for: work)
}
```

**Impact:** This enables the feature - selected editions will be displayed in library views.

---

### MEDIUM PRIORITY - Enhance User Experience

#### 3. No Network Error Retry Mechanism

**Location:** `EditionPickerView.swift` (planned)

**Problem:** If the API call fails, users are stuck in error state with no recovery option.

**Fix Required:**
```swift
case .error(let message):
    VStack(spacing: 16) {
        Text("Error: \(message)")
            .foregroundStyle(.secondary)
        Button("Retry") {
            Task { await viewModel.loadEditions() }
        }
        .buttonStyle(.borderedProminent)
    }
```

**Impact:** Better UX for network failures or backend issues.

---

### LOW PRIORITY - Code Quality

#### 4. Protocol Abstraction Unnecessary

**Recommendation:** Instead of creating a separate `EditionSearchable` protocol, use dependency injection with the existing `BookSearchAPIService`.

**Simpler Approach:**
```swift
class EditionPickerViewModel {
    private let apiService: BookSearchAPIService
    
    init(apiService: BookSearchAPIService = .shared) {
        self.apiService = apiService
    }
}

// For tests:
let mockAPI = BookSearchAPIService(/* inject mock URLSession */)
```

**Impact:** Reduces code complexity while maintaining testability.

---

## Implementation Phases

### PHASE 1: API Service Layer (3-4h)

**Goal:** Add backend integration for edition search

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/BookSearchAPIService+EditionSearch.swift`

```swift
import Foundation

extension BookSearchAPIService {
    /// Search for all editions of a specific work
    /// Backend handles filtering by title/author match
    /// - Parameters:
    ///   - workTitle: Title of the work
    ///   - author: Primary author name
    ///   - limit: Maximum number of editions to return (default: 20)
    /// - Returns: Array of Edition objects (persisted to SwiftData)
    func searchEditions(
        workTitle: String,
        author: String,
        limit: Int = 20
    ) async throws -> [Edition] {
        // Build URL
        var components = URLComponents(string: "\(EnrichmentConfig.baseURL)/v1/editions/search")!
        components.queryItems = [
            URLQueryItem(name: "workTitle", value: workTitle),
            URLQueryItem(name: "author", value: author),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        
        guard let url = components.url else {
            throw SearchError.invalidURL
        }
        
        let startTime = Date()
        
        // Fetch
        let (data, response) = try await urlSession.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SearchError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw SearchError.httpError(httpResponse.statusCode)
        }
        
        let responseTime = Date().timeIntervalSince(startTime) * 1000
        
        // Update cache metrics
        let cacheStatus = httpResponse.allHeaderFields["X-Cache"] as? String ?? "MISS"
        await updateCacheMetrics(headers: httpResponse.allHeaderFields, responseTime: responseTime)
        
        // Parse CanonicalAPIResponse
        let decoder = JSONDecoder()
        let apiResponse = try decoder.decode(CanonicalAPIResponse.self, from: data)
        
        guard apiResponse.success else {
            let errorMessage = apiResponse.error?.message ?? "Unknown error"
            throw SearchError.apiError(errorMessage)
        }
        
        // Map EditionDTOs to Edition objects
        let editions = apiResponse.data?.editions.compactMap { editionDTO in
            do {
                return try dtoMapper.mapToEdition(editionDTO, persist: true)
            } catch {
                logger.warning("⚠️ Failed to map EditionDTO: \(error)")
                return nil
            }
        } ?? []
        
        logger.info("✅ Found \(editions.count) editions in \(Int(responseTime))ms")
        return editions
    }
}
```

**Mock Data File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/MockEditionData.swift`

```swift
import Foundation

/// Mock edition data for development/testing before backend ships
struct MockEditionData {
    static let theMartianEditions: [EditionDTO] = [
        // Hardcover
        EditionDTO(
            isbn: "9780553418026",
            isbns: ["9780553418026", "0553418025"],
            title: "The Martian",
            publisher: "Crown Publishing",
            publicationDate: "2014-02-11",
            pageCount: 369,
            format: .hardcover,
            coverImageURL: "https://covers.openlibrary.org/b/isbn/9780553418026-L.jpg",
            editionTitle: "First Edition",
            editionDescription: "First hardcover edition",
            language: "en",
            primaryProvider: "google-books",
            contributors: ["google-books"],
            amazonASINs: ["0553418025"],
            googleBooksVolumeIDs: ["beSP5CCpiGUC"],
            librarythingIDs: [],
            isbndbQuality: 95
        ),
        
        // Paperback
        EditionDTO(
            isbn: "9780553418026",
            isbns: ["9780553418026"],
            title: "The Martian",
            publisher: "Broadway Books",
            publicationDate: "2015-02-10",
            pageCount: 384,
            format: .paperback,
            coverImageURL: "https://covers.openlibrary.org/b/isbn/9780553418026-L.jpg",
            editionTitle: "Mass Market Edition",
            language: "en",
            primaryProvider: "google-books",
            contributors: ["google-books"],
            amazonASINs: [],
            googleBooksVolumeIDs: ["beSP5CCpiGUC"],
            librarythingIDs: [],
            isbndbQuality: 90
        ),
        
        // E-book
        EditionDTO(
            isbn: "B00EMXBDMA",
            isbns: ["B00EMXBDMA"],
            title: "The Martian",
            publisher: "Crown Publishing",
            publicationDate: "2014-02-11",
            pageCount: 369,
            format: .ebook,
            coverImageURL: "https://covers.openlibrary.org/b/isbn/9780553418026-L.jpg",
            editionTitle: "Kindle Edition",
            language: "en",
            primaryProvider: "google-books",
            contributors: ["google-books"],
            amazonASINs: ["B00EMXBDMA"],
            googleBooksVolumeIDs: [],
            librarythingIDs: [],
            isbndbQuality: 85
        ),
        
        // Audiobook
        EditionDTO(
            isbn: nil,
            isbns: [],
            title: "The Martian",
            publisher: "Audible Studios",
            publicationDate: "2014-03-07",
            pageCount: nil,
            format: .audiobook,
            coverImageURL: "https://covers.openlibrary.org/b/isbn/9780553418026-L.jpg",
            editionTitle: "Unabridged Audiobook",
            language: "en",
            primaryProvider: "google-books",
            contributors: ["google-books"],
            amazonASINs: [],
            googleBooksVolumeIDs: [],
            librarythingIDs: [],
            isbndbQuality: 80
        ),
        
        // Mass Market
        EditionDTO(
            isbn: "9780553418026",
            isbns: ["9780553418026"],
            title: "The Martian",
            publisher: "Del Rey",
            publicationDate: "2015-06-02",
            pageCount: 400,
            format: .massMarket,
            coverImageURL: "https://covers.openlibrary.org/b/isbn/9780553418026-L.jpg",
            editionTitle: "Movie Tie-In Edition",
            language: "en",
            primaryProvider: "google-books",
            contributors: ["google-books"],
            amazonASINs: [],
            googleBooksVolumeIDs: [],
            librarythingIDs: [],
            isbndbQuality: 88
        )
    ]
}
```

---

### PHASE 2: ViewModel Layer (2-3h)

**Goal:** State management for edition picker

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/ViewModels/EditionPickerViewModel.swift`

```swift
import SwiftUI
import SwiftData

/// ViewModel for EditionPickerView
/// Manages edition search, selection, and persistence
@MainActor
@Observable
class EditionPickerViewModel {
    
    // MARK: - View State
    
    enum ViewState: Equatable {
        case loading
        case loaded(editions: [Edition])
        case empty
        case error(String)
    }
    
    var state: ViewState = .loading
    
    // MARK: - Dependencies
    
    private let work: Work
    private let userEntry: UserLibraryEntry
    private let apiService: BookSearchAPIService
    private let modelContext: ModelContext
    
    // MARK: - Computed Properties
    
    /// Current edition (preferredEdition takes priority over owned edition)
    var currentEdition: Edition? {
        userEntry.preferredEdition ?? userEntry.edition
    }
    
    // MARK: - Initialization
    
    init(
        work: Work,
        userEntry: UserLibraryEntry,
        apiService: BookSearchAPIService,
        modelContext: ModelContext
    ) {
        self.work = work
        self.userEntry = userEntry
        self.apiService = apiService
        self.modelContext = modelContext
    }
    
    // MARK: - Actions
    
    /// Load editions from backend
    func loadEditions() async {
        state = .loading
        
        do {
            let editions = try await apiService.searchEditions(
                workTitle: work.title,
                author: work.primaryAuthor?.name ?? ""
            )
            
            if editions.isEmpty {
                state = .empty
            } else {
                state = .loaded(editions: editions)
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }
    
    /// User selected an edition
    func selectEdition(_ edition: Edition) {
        // Update relationship
        userEntry.preferredEdition = edition
        userEntry.touch()
        
        // Persist to SwiftData
        do {
            try modelContext.save()
        } catch {
            state = .error("Failed to save: \(error.localizedDescription)")
        }
    }
}
```

---

### PHASE 3: UI Layer (2-3h)

**Goal:** SwiftUI views for edition picker

See full implementation plan for detailed view code (EditionPickerView, EditionRowView, context menu updates).

---

### PHASE 4: Data Persistence (1h)

**Goal:** Activate ManualStrategy and fix Work.primaryEdition

**Critical fixes documented in Code Review Findings section above.**

---

### PHASE 5: Testing (1-2h)

**Goal:** Comprehensive test coverage

Integration tests for ManualStrategy, unit tests for ViewModel, UI tests for user flow.

---

## Files Summary

### Files to Create (7 files)

1. `BookSearchAPIService+EditionSearch.swift` (~80 lines)
2. `MockEditionData.swift` (~150 lines)
3. `EditionPickerViewModel.swift` (~120 lines)
4. `EditionPickerView.swift` (~200 lines)
5. `EditionRowView.swift` (~80 lines)
6. `EditionSearchServiceTests.swift` (~50 lines)
7. `ManualStrategyIntegrationTests.swift` (~150 lines)

### Files to Modify (3 files)

1. `iOS26LiquidListRow.swift` (~15 lines changed)
2. `EditionSelectionStrategy.swift` (~10 lines changed)
3. `Work.swift` (~5 lines removed)

**Total:** 10 files (7 new, 3 modified), ~850 lines of code

---

## Testing Strategy

- **Unit Tests:** BookSearchAPIService, EditionPickerViewModel, ManualStrategy
- **Integration Tests:** Work.primaryEdition delegation, preferredEdition persistence
- **UI Tests:** Context menu flow, sheet presentation, edition selection

**Framework:** Swift Testing (@Test, #expect)

---

## Rollout Plan

1. **Alpha (Mock Data):** TestFlight with MockEditionData
2. **Backend Integration:** Real API after Issue #63 ships
3. **Production:** Gradual rollout with monitoring

---

## Success Metrics

- Context menu appears on long-press ✅
- Sheet displays 5+ editions for popular books ✅
- Selection persists across app restarts ✅
- ManualStrategy shows selected edition ✅
- Zero SwiftData crashes ✅
- Backend response time < 2s ✅

---

**Last Updated:** November 14, 2025  
**Related:** [Backend Issue #63](https://github.com/jukasdrj/bookstrack-backend/issues/63)
