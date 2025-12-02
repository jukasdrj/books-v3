# Books-v3 Chanfana V3 Migration Plan

**Status:** Phase 2 In Progress ⚡ (50% Complete)
**Last Updated:** December 2, 2025, 1:35 PM PST
**Owner:** books-v3 iOS Team
**Dependencies:** ~~bendv3 v3 API deployment~~ ✅ UNBLOCKED (OpenAPI spec available), Alexandria ResponseEnvelope alignment

---

## 🎯 Executive Summary

Migration from bendv3 v2 API to chanfana-based v3 API with auto-generated types, unified endpoints, and D1-backed library sync.

**Phase 1 (COMPLETE):** ✅ UI improvements and infrastructure prep (8 hours actual)
**Phase 2 (IN PROGRESS):** ⚡ V3 API integration (6.5/10 hours invested) - **OpenAPI Codegen Complete!**
**Phase 3 (FUTURE):** 🔮 Legacy cleanup (1-2 hours)

**MAJOR UPDATE:** `docs/openapi-v3.json` discovered! Phase 2 no longer blocked by backend deployment.

---

## ✅ Phase 1: Infrastructure & UI Prep (COMPLETE)

### Completed Tasks (December 1, 2025)

#### 1. Critical ResponseEnvelope Bug Fix ✅
**Problem:** Inconsistent envelope decoding between `BookSearchAPIService` and `EnrichmentAPIClient`

**Changes:**
- Deleted custom `V2SearchEnvelope`, `V2SearchData`, `V2SearchQuery`, `V2ResponseMetadata`, `V2ApiError` structs
- Created `BookSearchResponseDTO` matching v2 API contract
- Updated `searchV2()` to use `ResponseEnvelope<BookSearchResponseDTO>`
- Propagate `metadata.provider` and `metadata.cached`

**Files Modified:**
- `BookSearchAPIService.swift` (major refactor, ~80 lines changed)

**Outcome:** ALL API clients now use canonical `ResponseEnvelope<T>` pattern

---

#### 2. Provider Attribution UI ✅
**Feature:** Show users data source (Alexandria, Google Books, etc.)

**Implementation:**
- **NEW FILE:** `Components/ProviderAttributionView.swift`
  - Maps provider strings to user-friendly names
  - SF Symbol icons per provider
  - Cached status indicator (refresh icon)
- **Model Changes:**
  - `Work.swift`: Added `cached: Bool?` field (line 108)
  - `Edition.swift`: Added `cached: Bool?` field (line 72)
- **Service Changes:**
  - `BookSearchAPIService.swift`: Propagate `provider` and `cached` to models
- **UI Integration:**
  - `WorkDetailView.swift`: Display attribution in footer

**Visual Examples:**
```
🏛️ Alexandria              [↻]
🔍 Google Books
⭐ Curated Collection
📈 Trending
```

**Outcome:** Builds user trust, aids debugging

---

#### 3. Deprecation Header Detection ✅
**Feature:** Track deprecated v2 endpoint usage

**Implementation:**
- Check `Deprecation: true` header (case-insensitive)
- Extract `Sunset` header (ISO 8601 sunset date)
- Log warning in DEBUG builds only
- TODO comment for analytics integration

**Code Location:**
- `BookSearchAPIService.swift` line 503-518

**Example Log:**
```
⚠️ API Deprecation Warning: Endpoint /api/v2/search is deprecated. Sunset date: 2026-01-31
```

**Outcome:** Proactive monitoring for v2 sunset

---

#### 4. Enhanced Error UI ✅
**Feature:** User-friendly error messages for API errors

**Implementation:**
- Extension on `ResponseEnvelope.ApiErrorInfo` (90 lines)
- `userMessage`: Maps 15+ error codes to friendly messages
- `isRetryable`: Determines if "Try Again" button should show
- `requiresUserAction`: Distinguishes "fix input" vs "try later"

**Supported Error Codes:**
- Book Search: `NOT_FOUND`, `INVALID_ISBN`, `INVALID_QUERY`
- Rate Limiting: `RATE_LIMITED`, `CIRCUIT_OPEN`, `PROVIDER_ERROR`, `SERVICE_UNAVAILABLE`
- Network: `TIMEOUT`, `NETWORK_ERROR`, `CORS_BLOCKED`
- Auth: `UNAUTHORIZED`, `FORBIDDEN`, `TOKEN_EXPIRED`
- Server: `INTERNAL_ERROR`, `SERVER_ERROR`, `DATABASE_ERROR`
- Validation: `VALIDATION_ERROR`, `MISSING_FIELD`

**Code Location:**
- `ResponseEnvelope.swift` line 58-147

**Usage Example:**
```swift
if let error = apiResponse.error {
    Text(error.userMessage) // "Book not found. Try searching by a different ISBN or title."
    if error.isRetryable {
        Button("Try Again") { retryAction() }
    }
}
```

**Outcome:** Better UX, clearer guidance for users

---

### Build Status: ✅ SUCCESS

- **Warnings:** 0 (Zero Warnings Policy enforced)
- **Errors:** 0
- **Swift Version:** 6.2+
- **iOS Target:** 18.0+
- **Concurrency:** Swift 6 actor isolation compliant

---

## ⚡ Phase 2: V3 API Integration (IN PROGRESS - 50% Complete)

**BREAKTHROUGH:** ✅ OpenAPI spec found at `docs/openapi-v3.json` - Phase 2 UNBLOCKED!

**Completed Tasks:**
- ✅ Task 4: Error & Loading State Components (ErrorView.swift, LoadingStateView.swift)
- ✅ Task 1: OpenAPI Codegen Setup (748 lines of generated Swift code!)

**In Progress:**
- 🔄 Task 2: Unified V3 Search Service (next up!)

### Task 1: OpenAPI Codegen Setup ✅ COMPLETE
**Priority:** HIGH
**Effort:** 2-3 hours (actual: 1.5 hours)
**Status:** ✅ COMPLETE - Generated 748 lines of type-safe Swift code (December 2, 2025)
**Dependencies:** ~~bendv3 v3 deployed~~ ✅ UNBLOCKED (`docs/openapi-v3.json` available)

**Completed Steps:**
1. ✅ Fetched OpenAPI spec from `https://api.oooefam.net/v3/openapi.json` → `docs/openapi-v3.json`
2. ✅ Configured Package.swift with OpenAPI Generator plugin (PR #144 merged)
3. ✅ Fixed spec compatibility (OpenAPI 3.1.0 → 3.0.3, `exclusiveMinimum` boolean → numeric)
4. ✅ Generated Swift types via `swift-openapi-generator` plugin:
   - **Types.swift**: 600 lines (request/response types, enums, schemas)
   - **Client.swift**: 148 lines (API client protocol)
5. ✅ Verified generated types follow `ResponseEnvelope<T>` pattern

**Generated Files:**
```
.build/plugins/outputs/.../OpenAPIGenerator/GeneratedSources/
├── Types.swift   (600 lines) - Request/response types
├── Client.swift  (148 lines) - API client protocol
└── Server.swift  (0 lines)   - Server stubs (not needed)
```

**Current API Coverage:**
- ✅ `GET /v3/books/:isbn` - Book metadata lookup with provider tags

**Limitations:**
- OpenAPI spec only has 1 endpoint (book lookup by ISBN)
- Missing search endpoints (`/v3/books/search`) - will be added by backend team
- Library CRUD endpoints not yet in spec

**Next Steps:**
- Wait for backend to add search/library endpoints to OpenAPI spec, OR
- Manually implement v3 search service using generated types as reference

**Outcome:** ✅ Type-safe API client with 748 lines of auto-generated Swift code

---

### Task 2: Unified V3 Search Service
**Priority:** HIGH
**Effort:** 3-4 hours
**Dependencies:** Task 1 complete

**Current State (v2):**
```swift
// Prefix-based search
GET /api/v2/search?q=isbn:9780134685991&mode=text
GET /api/v2/search?q=author:rowling&mode=text
```

**Target State (v3):**
```swift
// Parameter-based search
GET /v3/books/search?q=9780134685991&type=isbn&limit=20
GET /v3/books/search?q=rowling&type=author&limit=20
GET /v3/books/search?q=harry+potter&type=semantic&limit=10
```

**Implementation Plan:**

1. **Create SearchType enum**
   ```swift
   enum SearchType: String {
       case isbn, title, author, semantic
   }
   ```

2. **Add searchV3() method to BookSearchAPIService**
   ```swift
   func searchV3(query: String, type: SearchType = .title, limit: Int = 20) async throws -> SearchResponse {
       let url = URL(string: "\(baseURL)/v3/books/search")!
           .appending(queryItems: [
               URLQueryItem(name: "q", value: query),
               URLQueryItem(name: "type", value: type.rawValue),
               URLQueryItem(name: "limit", value: String(limit))
           ])

       // Use ResponseEnvelope<BookSearchResponseDTO>
       let (data, response) = try await urlSession.data(from: url)
       let envelope = try JSONDecoder().decode(ResponseEnvelope<BookSearchResponseDTO>.self, from: data)

       guard envelope.success, let searchData = envelope.data else {
           throw SearchError.apiError(envelope.error?.userMessage ?? "Unknown error")
       }

       // ... rest of implementation
   }
   ```

3. **Add feature flag for v2/v3 toggle**
   ```swift
   @MainActor
   func search(query: String, ...) async throws -> SearchResponse {
       if await FeatureFlags.shared.useV3API {
           return try await searchV3(query: query, type: inferType(from: query), ...)
       } else {
           return try await searchV2(query: query, ...)
       }
   }
   ```

4. **Update search() wrapper to route correctly**
   - Keep existing `transformQueryForV2()` for v2
   - Add `inferSearchType()` for v3

**Files Modified:**
- `BookSearchAPIService.swift` (add `searchV3()`, feature flag routing)
- `FeatureFlags.swift` (add `useV3API: Bool`)

**Testing:**
- Toggle feature flag on/off
- Verify both v2 and v3 paths work
- Gradual rollout: 10% → 50% → 100%

**Outcome:** Seamless v2 → v3 migration with rollback capability

---

### Task 3: Library CRUD Service for V3 D1 Endpoints
**Priority:** HIGH
**Effort:** 4-5 hours
**Dependencies:** Task 1 complete

**New V3 Endpoints:**
```
GET    /v3/library              → List user's books
POST   /v3/library              → Add book to library
GET    /v3/library/:isbn        → Get specific book
PATCH  /v3/library/:isbn        → Update reading status
DELETE /v3/library/:isbn        → Remove from library
```

**Implementation Plan:**

1. **Create LibraryAPIService.swift**
   ```swift
   @MainActor
   class LibraryAPIService {
       private let baseURL = EnrichmentConfig.baseURL
       private let urlSession: URLSession

       func listBooks(shelf: String? = nil, status: ReadingStatus? = nil) async throws -> [UserBook]
       func addBook(_ isbn: String, shelf: String? = nil) async throws -> UserBook
       func updateStatus(_ isbn: String, status: ReadingStatus) async throws -> UserBook
       func removeBook(_ isbn: String) async throws
   }
   ```

2. **Create UserBook DTO**
   ```swift
   struct UserBook: Codable, Sendable {
       let isbn: String
       let addedAt: Date
       let status: ReadingStatus
       let shelf: String?
       let progress: Int?  // Page or percentage

       enum ReadingStatus: String, Codable {
           case unread, reading, finished, dnf, wishlist
       }
   }
   ```

3. **Integrate with SwiftData**
   - Sync v3 library state to local SwiftData
   - Bidirectional sync: local changes → POST/PATCH, remote changes → GET
   - Conflict resolution: server wins (last-write-wins)

4. **Add to existing LibraryView**
   - Replace local-only operations with API calls
   - Optimistic UI updates (update UI immediately, sync in background)
   - Rollback on error

**Files to Create:**
- `Services/LibraryAPIService.swift` (NEW)
- `DTOs/UserBook.swift` (NEW)

**Files Modified:**
- `LibraryView.swift` (integrate API calls)
- `UserLibraryEntry.swift` (add sync metadata: `lastSyncedAt`, `syncStatus`)

**Data Flow:**
```
User Action (UI)
  ↓
SwiftData Update (optimistic)
  ↓
API Call (POST/PATCH/DELETE)
  ↓
Success: Mark synced | Failure: Rollback SwiftData
```

**Outcome:** Cloud-backed library with offline support

---

### Task 4: Enhanced Error View Components ✅ COMPLETE
**Priority:** MEDIUM
**Effort:** 2 hours (actual: 1.5 hours)
**Status:** ✅ COMPLETE - Components built, validated, zero warnings
**Dependencies:** None

**Completed (December 1, 2025):**
- ✅ Created `ErrorView.swift` (125 lines) - Reusable error display with SF Symbol icons
- ✅ Created `LoadingStateView.swift` (109 lines) - Generic `APILoadingState<T>` wrapper
- ✅ Fixed naming conflict (renamed `LoadingState` → `APILoadingState`)
- ✅ Fixed generic type issues (`ResponseEnvelope<AnyCodable>.ApiErrorInfo`)
- ✅ Build validation: **BUILD SUCCEEDED** (Zero Warnings)

**Features:**
- Error code → SF Symbol icon mapping (9 error types)
- Retry button for retryable errors
- User action guidance text
- SwiftUI previews for all states
- Swift 6 concurrency compliant

**Implementation Plan:**

1. **Create ErrorView.swift component**
   ```swift
   struct ErrorView: View {
       let error: ResponseEnvelope.ApiErrorInfo
       let retryAction: (() -> Void)?

       var body: some View {
           VStack(spacing: 16) {
               Image(systemName: errorIcon)
                   .font(.system(size: 48))
                   .foregroundColor(.red.opacity(0.8))

               Text(error.userMessage)
                   .font(.body)
                   .multilineTextAlignment(.center)

               if error.isRetryable, let retryAction = retryAction {
                   Button("Try Again") {
                       retryAction()
                   }
                   .buttonStyle(.borderedProminent)
               }

               if error.requiresUserAction {
                   Text("Please check your input and try again")
                       .font(.caption)
                       .foregroundColor(.secondary)
               }
           }
           .padding()
       }

       private var errorIcon: String {
           switch error.code {
           case "NOT_FOUND": return "magnifyingglass"
           case "NETWORK_ERROR", "TIMEOUT": return "wifi.slash"
           case "UNAUTHORIZED", "FORBIDDEN": return "lock.shield"
           default: return "exclamationmark.triangle"
           }
       }
   }
   ```

2. **Create LoadingStateView.swift wrapper**
   ```swift
   enum LoadingState<T> {
       case idle
       case loading
       case success(T)
       case error(ResponseEnvelope.ApiErrorInfo)
   }

   struct LoadingStateView<Content: View, T>: View {
       let state: LoadingState<T>
       let retryAction: (() -> Void)?
       @ViewBuilder let content: (T) -> Content

       var body: some View {
           switch state {
           case .idle:
               Text("Ready")
           case .loading:
               ProgressView()
           case .success(let data):
               content(data)
           case .error(let error):
               ErrorView(error: error, retryAction: retryAction)
           }
       }
   }
   ```

3. **Integrate into existing views**
   - Replace custom loading/error states with `LoadingStateView`
   - Use `error.userMessage` instead of raw error descriptions
   - Show "Try Again" button only for retryable errors

**Files to Create:**
- `Components/ErrorView.swift` (NEW)
- `Components/LoadingStateView.swift` (NEW)

**Files Modified:**
- `LibraryView.swift` (use `LoadingStateView`)
- `SearchView.swift` (use `ErrorView`)
- `WorkDetailView.swift` (use `ErrorView` for similar books, etc.)

**Outcome:** Consistent error UI across entire app

---

### Task 5: Loading State Optimization for Cached Responses
**Priority:** LOW
**Effort:** 1-2 hours
**Dependencies:** None

**Current Behavior:**
- Always show loading spinner, even for cached responses
- User sees flash of loading state for instant cache hits

**Target Behavior:**
- If `metadata.cached == true`, skip loading animation
- Instant display for sub-100ms cached responses

**Implementation Plan:**

1. **Add cache-aware loading logic**
   ```swift
   @State private var isLoading = false
   @State private var showLoadingDelay = false

   func loadData() async {
       isLoading = true

       // Delay showing spinner for 200ms (in case of cache hit)
       Task {
           try? await Task.sleep(for: .milliseconds(200))
           showLoadingDelay = true
       }

       let response = try await searchService.search(...)

       isLoading = false
       showLoadingDelay = false

       // Check if response was cached
       if response.metadata.cached == true {
           // Instant display - spinner never showed
       }
   }

   var body: some View {
       ZStack {
           contentView
           if isLoading && showLoadingDelay {
               ProgressView()
           }
       }
   }
   ```

2. **Update SearchView, LibraryView**
   - Replace immediate loading spinners with delayed spinners
   - Only show if request takes >200ms

**Files Modified:**
- `SearchView.swift`
- `LibraryView.swift`

**Outcome:** Smoother UX for cached responses (perceived performance improvement)

---

### Task 6: Integration Testing
**Priority:** HIGH
**Effort:** 2-3 hours
**Dependencies:** All above tasks complete

**Test Plan:**

**Test 1: V3 Search Flow**
1. Search for book by ISBN → Verify v3 endpoint called
2. Search by title → Verify v3 endpoint with `type=title`
3. Search by author → Verify v3 endpoint with `type=author`
4. Semantic search → Verify v3 endpoint with `type=semantic`
5. Check provider attribution displayed correctly
6. Verify cached responses show refresh icon

**Test 2: V3 Library CRUD Flow**
1. Add book to library → POST /v3/library
2. Verify book appears in library list → GET /v3/library
3. Update reading status → PATCH /v3/library/:isbn
4. Verify status updated in UI
5. Remove book → DELETE /v3/library/:isbn
6. Verify book removed from UI

**Test 3: Error Handling**
1. Search for invalid ISBN → Verify `NOT_FOUND` error shows friendly message
2. Rate limit test → Verify "Try Again" button shows
3. Network offline → Verify network error message
4. Invalid auth token → Verify auth error message

**Test 4: Deprecation Detection**
1. Hit v2 endpoint with `Deprecation: true` header (mock)
2. Verify warning logged in DEBUG console
3. Verify app continues to work (non-blocking)

**Test 5: Feature Flag Toggle**
1. Set `useV3API = false` → Verify v2 endpoints used
2. Set `useV3API = true` → Verify v3 endpoints used
3. Toggle mid-session → Verify no crashes

**Test Environments:**
- iOS Simulator (iPhone 16 Pro, iOS 18+)
- Real device (recommended for keyboard input, networking)

**Outcome:** Confidence in v3 migration, no regressions

---

## 🗑️ Phase 3: Legacy Cleanup (FUTURE)

**When:** After v3 stable for 30+ days, v2 sunset date announced

### Task 1: Remove Legacy Provider Clients
**Priority:** LOW
**Effort:** 1 hour

**Files to DELETE:**
```
Services/ISBNSearchService.swift      → Merged into BookSearchAPIService
Services/TitleSearchService.swift     → Merged into BookSearchAPIService
Services/OpenLibraryClient.swift      → iOS never calls external APIs directly
Services/GoogleBooksClient.swift      → All goes through bendv3
Services/ISBNdbClient.swift           → All goes through bendv3
```

**Reason:** Single point of orchestration (bendv3 → Alexandria)

**Steps:**
1. Verify no imports of deleted files in codebase
   ```bash
   grep -r "import.*ISBNSearchService" .
   grep -r "OpenLibraryClient" .
   ```
2. Delete files
3. Update imports in remaining files
4. Build and test

**Outcome:** Reduced codebase complexity, single source of truth

---

### Task 2: Remove V2 API Code
**Priority:** LOW
**Effort:** 30 minutes
**Dependencies:** V2 sunset date reached, all users on v3

**Files to MODIFY:**
- `BookSearchAPIService.swift` - Remove `searchV2()` method
- `FeatureFlags.swift` - Remove `useV3API` flag (always true)

**Steps:**
1. Verify feature flag analytics show 100% v3 usage
2. Remove `searchV2()` method
3. Remove feature flag
4. Rename `searchV3()` to `search()` (canonical)

**Outcome:** Clean codebase, no dead code

---

### Task 3: Update Documentation
**Priority:** LOW
**Effort:** 30 minutes

**Files to UPDATE:**
- `README.md` - Update API version references
- `AGENTS.md` - Update API contract section
- `CLAUDE.md` - Remove v2 migration notes
- This file (`V3_MIGRATION_PLAN.md`) - Mark as complete

**Outcome:** Accurate documentation for future developers

---

## 📊 Effort Summary

| Phase | Task | Effort | Status |
|-------|------|--------|--------|
| **Phase 1** | ResponseEnvelope fix | 2h | ✅ COMPLETE |
| | Provider attribution UI | 3h | ✅ COMPLETE |
| | Deprecation detection | 1h | ✅ COMPLETE |
| | Enhanced error UI | 2h | ✅ COMPLETE |
| **Phase 2** | OpenAPI codegen setup | 2-3h | ✅ COMPLETE (1.5h) |
| | V3 search service | 3-4h | ⏸️ BLOCKED |
| | Library CRUD service | 4-5h | ⏸️ BLOCKED |
| | Error view components | 2h | ⏸️ OPTIONAL |
| | Loading optimization | 1-2h | ⏸️ OPTIONAL |
| | Integration testing | 2-3h | ⏸️ BLOCKED |
| **Phase 3** | Remove legacy clients | 1h | 🔮 FUTURE |
| | Remove v2 code | 30m | 🔮 FUTURE |
| | Update docs | 30m | 🔮 FUTURE |
| **TOTAL** | | **24-29h** | **33% COMPLETE** |

---

## 🎯 Critical Path

**Blocking Dependencies:**
1. bendv3 v3 API deployed → Enables Phase 2
2. `/v3/openapi.json` available → Enables codegen
3. v3 endpoints stable → Enables integration testing
4. V2 sunset date announced → Enables Phase 3

**Parallel Work Opportunities:**
- Error view components (can do now)
- Loading optimization (can do now)
- Documentation updates (can do anytime)

---

## 🚦 Risks & Mitigations

### Risk 1: OpenAPI Schema Mismatch
**Impact:** Generated types don't match our DTOs
**Likelihood:** Medium
**Mitigation:**
- Review OpenAPI schema before generation
- Coordinate with backend team on DTO structure
- Add validation tests for generated types

### Risk 2: Breaking Changes in V3
**Impact:** App breaks when v3 deploys
**Likelihood:** Low (chanfana enforces schema)
**Mitigation:**
- Feature flag for v2/v3 toggle
- Gradual rollout (10% → 50% → 100%)
- Monitoring & rollback plan

### Risk 3: Library Sync Conflicts
**Impact:** User data lost or duplicated
**Likelihood:** Medium
**Mitigation:**
- Server-wins conflict resolution
- Last-write-wins timestamp
- Audit log for debugging

### Risk 4: Performance Regression
**Impact:** V3 slower than v2
**Likelihood:** Low (D1 faster than KV)
**Mitigation:**
- Benchmark v2 vs v3 response times
- Monitor P50, P95, P99 latencies
- Keep v2 fallback for 30 days

---

## 📈 Success Metrics

**Phase 1 (COMPLETE):**
- ✅ Zero build warnings
- ✅ Zero build errors
- ✅ All code Swift 6 concurrency-safe
- ✅ Provider attribution visible in UI
- ✅ Enhanced error messages tested

**Phase 2 (TARGET):**
- [ ] 100% v3 endpoint coverage (search, library CRUD)
- [ ] <200ms P95 latency for cached responses
- [ ] <1s P95 latency for uncached responses
- [ ] Zero regressions in existing features
- [ ] Feature flag rollout: 10% → 50% → 100% over 7 days

**Phase 3 (TARGET):**
- [ ] Zero legacy code remaining
- [ ] Zero v2 API calls
- [ ] Documentation 100% accurate
- [ ] Codebase 20% smaller (LOC)

---

## 🔗 References

**Documentation:**
- Main migration plan (this file): `V3_MIGRATION_PLAN.md`
- Backend API contract: `docs/API_CONTRACT.md`
- OpenAPI spec (when available): `https://api.oooefam.net/v3/openapi.json`
- Alexandria API: `https://alexandria.ooheynerds.com/health`

**Code Locations:**
- ResponseEnvelope: `BooksTrackerPackage/Sources/BooksTrackerFeature/DTOs/ResponseEnvelope.swift`
- BookSearchAPIService: `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/BookSearchAPIService.swift`
- ProviderAttributionView: `BooksTrackerPackage/Sources/BooksTrackerFeature/Components/ProviderAttributionView.swift`

**External Resources:**
- Swift OpenAPI Generator: https://github.com/apple/swift-openapi-generator
- Chanfana Documentation: https://github.com/cloudflare/chanfana

---

## 📝 Change Log

| Date | Phase | Changes | Author |
|------|-------|---------|--------|
| 2025-12-01 | 1 | Phase 1 complete (ResponseEnvelope fix, provider UI, deprecation detection, enhanced errors) | Claude Code (Sonnet 4.5) + Gemini 2.5 Flash |
| 2025-12-01 | - | Created migration plan | Claude Code (Sonnet 4.5) |

---

## 🤝 Coordination

**iOS Team (books-v3):**
- ✅ Phase 1 complete
- ⏸️ Waiting for backend v3 deployment
- Ready to start Phase 2 within 1 week of v3 availability

**Backend Team (bendv3):**
- 🚧 Working on chanfana migration
- Target: `/v3/openapi.json` endpoint
- Target: `/v3/books/search` and `/v3/library/*` endpoints

**Backend Team (Alexandria - alex):**
- 🔄 Needs ResponseEnvelope alignment
- Target: Match bendv3's envelope format
- Target: Expose OpenAPI schema endpoint

---

**END OF PLAN**
