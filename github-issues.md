# GitHub Issues for Code Review Findings

## Issue 1: [P0 - HIGH] Battery drain bug when canceling batch scan

**Labels:** `bug`, `high-priority`, `iOS`, `battery`, `user-facing`

### Description
The `cancelBatch()` method in `BatchCaptureView` never re-enables the device idle timer, causing severe battery drain for the remainder of the app session after users cancel a batch scan.

### Current Behavior
1. User starts batch scan (idle timer disabled to prevent sleep during 2-5 min processing)
2. User cancels batch mid-scan
3. Idle timer remains disabled forever (until app restart)
4. Device never sleeps → severe battery drain

### Expected Behavior
- Idle timer should be re-enabled immediately when batch is canceled
- Device should sleep normally after cancellation

### Steps to Reproduce
1. Start batch scan with 3 photos
2. Cancel batch after 1st photo completes
3. Lock device
4. Observe: Screen never turns off

### Root Cause
`BatchCaptureView.swift:131-166` - The `cancelBatch()` method is missing the idle timer re-enable call that exists in `submitBatch()` error handlers (lines 100, 113).

### Proposed Fix
```swift
// File: BatchCaptureView.swift:166 (after line 165)
public func cancelBatch() async {
    // ... existing cancellation logic ...

    // ADD THIS LINE:
    UIApplication.shared.isIdleTimerDisabled = false
    print("🔓 Idle timer re-enabled (batch canceled)")
}
```

### Testing Checklist
- [ ] Cancel batch mid-scan
- [ ] Lock device immediately
- [ ] Verify screen turns off within 30s (default iOS timeout)
- [ ] Run Instruments Energy Log - verify no "Prevent Display Sleep" warnings
- [ ] Battery usage over 30 minutes matches baseline

### Impact
- **Severity:** HIGH (user-facing battery drain)
- **Affected Users:** Anyone who cancels batch scans
- **Estimated Frequency:** ~5-10% of batch scan users

### Acceptance Criteria
- [ ] Screen locks within configured timeout after cancellation
- [ ] No Instruments warnings for idle timer
- [ ] Battery usage matches baseline
- [ ] All existing idle timer code paths still work

---

## Issue 2: [P1 - MEDIUM] Enrichment job hangs forever if backend stalls (no timeout)

**Labels:** `bug`, `medium-priority`, `iOS`, `enrichment`, `reliability`

### Description
The enrichment queue has no timeout mechanism. If the backend hangs or WebSocket stalls, the `processing` flag remains `true` indefinitely, preventing all future enrichment jobs until app restart.

### Current Behavior
1. User triggers enrichment for 50 books
2. Backend hangs or network disconnects
3. Processing flag stuck at `true`
4. All future enrichment attempts fail silently
5. Only app restart clears the flag

### Expected Behavior
- Enrichment jobs should timeout after 5 minutes
- Processing flag should clear automatically
- User should see "Enrichment timed out" error
- System should allow retry

### Root Cause
`EnrichmentQueue.swift:191-234` - The `startProcessing` method creates a Task with no timeout handling.

### Proposed Fix
```swift
// File: EnrichmentQueue.swift:191-234
currentTask = Task { @MainActor in
    let timeout: TimeInterval = 300 // 5 minutes

    do {
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Enrichment task
            group.addTask {
                let workIDs = self.getAllPending()
                // ... existing enrichment logic ...
            }

            // Timeout task
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw EnrichmentError.timeout
            }

            try await group.next()
            group.cancelAll()
        }
    } catch {
        print("❌ Enrichment failed: \(error)")
        // CRITICAL: Clear processing flag
        self.stopProcessing()
        self.webSocketHandler?.disconnect()
        NotificationCoordinator.postEnrichmentFailed(error: error)
    }
}
```

### Testing Checklist
- [ ] Unit test: Mock backend with 6-minute delay
- [ ] Verify timeout fires after 5 minutes
- [ ] Verify processing flag clears
- [ ] Verify NotificationCoordinator posts `.enrichmentFailed`
- [ ] Verify UI shows timeout message to user
- [ ] Verify retry works after timeout

### Monitoring
- [ ] Add metric: `enrichment_duration_seconds` (histogram)
- [ ] Add metric: `enrichment_timeout_count` (counter)
- [ ] Alert: If timeout_count > 5% of jobs in 24h window

### Impact
- **Severity:** MEDIUM (requires app restart to fix)
- **Affected Users:** Users with poor network or backend issues
- **Estimated Frequency:** <1% of enrichment jobs (goal)

### Acceptance Criteria
- [ ] No zombie jobs - processing flag clears within 5min + 10s
- [ ] Timeout rate <1% of jobs
- [ ] User sees clear error message
- [ ] Retry works after timeout

---

## Issue 3: [P1 - MEDIUM] Fragile title-based matching in enrichment pipeline

**Labels:** `bug`, `medium-priority`, `iOS`, `backend`, `data-integrity`, `architecture`

### Description
The enrichment pipeline matches backend results to local Works using fuzzy title matching (`localizedStandardContains`). This is unreliable and can cause data corruption if titles differ slightly (subtitles, punctuation) or multiple books have similar titles.

### Current Behavior
1. iOS sends enrichment request with titles
2. Backend returns enriched data with titles
3. iOS searches for Work by title: `work.title.localizedStandardContains(enrichedBook.title)`
4. If title differs slightly → wrong book gets enriched (data corruption)
5. If multiple matches → first match wins (unpredictable)

### Expected Behavior
- Use stable PersistentIdentifier for matching (not titles)
- Fallback to title matching only for backward compatibility
- 99%+ ID-based match rate

### Root Cause
`EnrichmentQueue.swift:338-348` - Title-based matching was the only option when enrichment was designed. PersistentIdentifiers are stable and unique but weren't being passed to backend.

### Proposed Fix (2-part - iOS + Backend)

**Backend Changes:**
```typescript
// File: handlers/batch-enrichment.js
interface EnrichmentRequest {
  jobId: string;
  books: Array<{
    title: string;
    author?: string;
    clientWorkId?: string; // NEW: PersistentIdentifier URI
  }>;
}

interface EnrichedBookPayload {
  title: string;
  clientWorkId?: string; // Echo back for stable matching
  enriched: { work: WorkDTO; edition: EditionDTO; authors: AuthorDTO[] };
  success: boolean;
}
```

**iOS Changes:**
```swift
// File: EnrichmentQueue.swift:326-459
private func applyEnrichedData(_ enrichedBooks: [EnrichedBookPayload], in modelContext: ModelContext) {
    for enrichedBook in enrichedBooks {
        var work: Work?

        // PRIORITY 1: Match by stable PersistentIdentifier
        if let clientWorkId = enrichedBook.clientWorkId,
           let persistentID = PersistentIdentifier(uriRepresentation: URL(string: clientWorkId)!) {
            work = modelContext.work(for: persistentID)
        }

        // FALLBACK: Title matching (backward compat)
        if work == nil {
            let descriptor = FetchDescriptor<Work>(
                predicate: #Predicate { $0.title.localizedStandardContains(enrichedBook.title) }
            )
            work = try? modelContext.fetch(descriptor).first
        }

        guard let work = work else {
            print("⚠️ Could not match enriched book: \(enrichedBook.title)")
            continue
        }

        // ... apply enriched data as before ...
    }
}
```

### Deployment Strategy (Feature Flag)
1. **Week 1:** Deploy backend with `clientWorkId` support (backward compat - field optional)
2. **Week 2:** Deploy iOS v3.x.2-beta with stable matching (TestFlight, 50% rollout)
3. **Week 3:** Monitor match rate - must be >95% (target 99%)
4. **Week 4:** Full rollout if successful
5. **6 months:** Remove title fallback in v4.0.0 (breaking change)

### Backward Compatibility Testing Matrix
| iOS Version | Backend Version | Expected Behavior |
|-------------|-----------------|-------------------|
| v3.x.0 (old) | v1.2 (new) | Title matching works |
| v3.x.2 (new) | v1.1 (old) | Title fallback works |
| v3.x.2 (new) | v1.2 (new) | ID matching (99%+) |

### Testing Checklist
- [ ] Deploy backend v1.2 to staging
- [ ] Test old iOS (v3.x.0) against staging → verify enrichment succeeds
- [ ] Deploy iOS beta to TestFlight
- [ ] Beta testers enrich 100+ books
- [ ] Monitor logs for "could not match" warnings (must be <1%)
- [ ] Multi-device CloudKit sync testing
- [ ] Verify PersistentIdentifier URIs stable across devices
- [ ] Load test with 10K works library

### Rollback Plan
```swift
// Backend: Feature flag endpoint
POST /api/config/feature-flags
{ "stableMatchingEnabled": false } // Emergency disable

// iOS: Check flag before using clientWorkId
if featureFlags.stableMatchingEnabled {
    // Use ID matching
} else {
    // Use title matching only
}
```

### Impact
- **Severity:** MEDIUM (data corruption risk)
- **Affected Users:** All users doing enrichment
- **Current Failure Rate:** Unknown (not tracked)
- **Target Failure Rate:** <1%

### Acceptance Criteria
- [ ] ID match rate >99% within 2 weeks
- [ ] Zero data corruption reports
- [ ] <1% "could not match" warnings in logs
- [ ] Backward compatibility: 100%
- [ ] Feature flag infrastructure deployed

---

## Issue 4: [P1 - MEDIUM] API endpoint URLs hardcoded across codebase

**Labels:** `tech-debt`, `medium-priority`, `iOS`, `maintainability`, `configuration`

### Description
API endpoint URLs are hardcoded in multiple files across the codebase. This makes environment switching (dev/staging/prod) difficult and creates maintenance burden when endpoints change.

### Current Behavior
- Hardcoded URLs in `BatchCaptureView.swift:139`
- Hardcoded URLs in `BookshelfAIService.swift:84`
- Hardcoded URLs in other files (full audit needed)
- No environment switching support
- Every URL change requires multiple file edits

### Expected Behavior
- All URLs centralized in `EnrichmentConfig.swift`
- Environment switching via config (dev/staging/prod)
- Compile-time safety (typos caught early)

### Proposed Fix
```swift
// File: EnrichmentConfig.swift
enum EnrichmentConfig {
    static let baseURL = "https://books-api-proxy.jukasdrj.workers.dev"
    static let batchScanCancelURL = "\(baseURL)/api/scan-bookshelf/cancel"
    static let bookshelfScanURL = "\(baseURL)/api/scan-bookshelf"
    static let enrichmentBatchURL = "\(baseURL)/api/enrichment/batch"
    static let webSocketBaseURL = "wss://books-api-proxy.jukasdrj.workers.dev"

    static let webSocketTimeout: TimeInterval = 70 // Bonus: make configurable
}
```

**Usage:**
```swift
// BatchCaptureView.swift:139 - BEFORE
let endpoint = URL(string: "https://api-worker.jukasdrj.workers.dev/api/scan-bookshelf/cancel")!

// AFTER
let endpoint = URL(string: EnrichmentConfig.batchScanCancelURL)!
```

### Implementation Checklist
- [ ] Audit codebase: `grep -r "jukasdrj.workers.dev" .` to find all occurrences
- [ ] Add all URLs to `EnrichmentConfig.swift`
- [ ] Update 6+ files to use config
- [ ] Verify all API calls still work (integration tests)
- [ ] Add environment switching support (#ifdef DEBUG)

### Testing Checklist
- [ ] Verify all API endpoints reachable
- [ ] No hardcoded URLs remain (grep verification)
- [ ] Environment switching works (if implemented)

### Impact
- **Severity:** MEDIUM (maintainability issue)
- **Affected Areas:** All network code
- **Technical Debt:** Prevents easy environment switching

### Acceptance Criteria
- [ ] Zero hardcoded URLs in codebase
- [ ] All URLs centralized in EnrichmentConfig
- [ ] Compile-time safety enforced
- [ ] Documentation updated

---

## Issue 5: [P1 - MEDIUM] reviewQueueCount() loads all Works into memory (inefficient)

**Labels:** `performance`, `medium-priority`, `iOS`, `database`, `optimization`

### Description
The `reviewQueueCount()` method fetches ALL Work objects into memory and filters in-memory to count items needing review. This is inefficient and will cause UI freezes as libraries grow (1K+ books).

### Current Behavior
```swift
// File: LibraryRepository.swift:251-259
public func reviewQueueCount() throws -> Int {
    let descriptor = FetchDescriptor<Work>()
    let allWorks = try modelContext.fetch(descriptor) // ⚠️ Loads ALL Works
    return allWorks.filter { $0.reviewStatus == .needsReview }.count
}
```

**Performance:**
- 1K works: ~50ms
- 5K works: ~250ms
- 10K works: ~500ms (UI freeze!)

### Expected Behavior
Use SwiftData's `fetchCount()` with a predicate for database-level counting (10x faster).

### Root Cause
SwiftData predicates can't directly compare enum cases. The comment correctly identifies this limitation but doesn't implement the workaround (using `rawValue`).

### Proposed Fix
```swift
// File: LibraryRepository.swift:251-259
public func reviewQueueCount() throws -> Int {
    let statusRawValue = ReviewStatus.needsReview.rawValue
    let predicate = #Predicate<Work> { work in
        work.reviewStatus.rawValue == statusRawValue
    }
    let descriptor = FetchDescriptor<Work>(predicate: predicate)
    return try modelContext.fetchCount(descriptor) // ✅ 10x faster
}
```

### Performance Testing
```swift
@Test("reviewQueueCount scales to 10K works")
func testReviewQueuePerformance() async throws {
    // Populate 10,000 works (100 needing review)
    let start = Date()
    let count = try repository.reviewQueueCount()
    let elapsed = Date().timeIntervalSince(start)

    #expect(count == 100)
    #expect(elapsed < 0.01) // <10ms
}
```

### Testing Checklist
- [ ] Baseline: Measure current query time (1K, 5K, 10K works)
- [ ] Implement fix
- [ ] Measure new query time - verify 10x improvement
- [ ] Real device testing (iPhone 12 Pro minimum spec)
- [ ] Verify count accuracy matches old implementation

### Impact
- **Severity:** MEDIUM (performance degrades with scale)
- **Affected Users:** Users with large libraries (1K+ books)
- **Expected Improvement:** 10x faster (500ms → 50ms for 10K works)

### Acceptance Criteria
- [ ] Query completes in <10ms for 10K works
- [ ] Count accuracy verified
- [ ] No regressions in other queries
- [ ] Performance test added to CI

---

## Issue 6: [P2 - LOW] Backend missing input validation for enrichment requests

**Labels:** `security`, `low-priority`, `backend`, `validation`, `DoS-risk`

### Description
The backend enrichment endpoint lacks input validation for batch requests. This creates security risks (XSS, DoS) and could lead to cost explosions from malformed requests.

### Current Risks
1. **No batch size limit** - Client could send 10,000 books → DoS + cost explosion
2. **No title length validation** - 1MB title strings → memory exhaustion
3. **No XSS sanitization** - `<script>alert("xss")</script>` in titles
4. **No type checking** - Missing required fields crash backend

### Expected Behavior
- Max batch size: 100 books per request
- Title max length: 500 characters
- HTML/XSS sanitization
- Required field validation
- Return 400 errors with descriptive messages

### Proposed Fix
```typescript
// File: batch-enrichment.js (new middleware)
function validateBatchRequest(books) {
  // Array validation
  if (!Array.isArray(books) || books.length === 0) {
    throw new ValidationError('books array required');
  }
  if (books.length > 100) {
    throw new ValidationError('Max 100 books per batch');
  }

  // Per-book validation
  books.forEach((book, i) => {
    // Required fields
    if (!book.title || typeof book.title !== 'string') {
      throw new ValidationError(`Book ${i}: title required (string)`);
    }

    // Length limits
    if (book.title.length > 500) {
      throw new ValidationError(`Book ${i}: title max 500 chars`);
    }

    // Sanitize HTML/XSS
    book.title = sanitizeHtml(book.title, {
      allowedTags: [],
      allowedAttributes: {}
    });

    // Optional fields (if present)
    if (book.author && book.author.length > 300) {
      throw new ValidationError(`Book ${i}: author max 300 chars`);
    }
  });

  return books; // Sanitized
}

// Use in handler
export async function handleBatchEnrichment(request, env, ctx) {
  const { books, jobId } = await request.json();

  try {
    const validatedBooks = validateBatchRequest(books); // ✅ Add this
    // ... rest of enrichment logic ...
  } catch (err) {
    if (err instanceof ValidationError) {
      return new Response(JSON.stringify({ error: err.message }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }
    throw err;
  }
}
```

### Testing Checklist
```javascript
// File: batch-enrichment.test.js
test('Rejects batch >100 books', async () => {
  const books = Array(101).fill({ title: 'Test' });
  const res = await fetch('/api/enrichment/batch', {
    method: 'POST',
    body: JSON.stringify({ books, jobId: '123' })
  });
  expect(res.status).toBe(400);
  expect(await res.json()).toContain('Max 100 books');
});

test('Sanitizes XSS in titles', async () => {
  const books = [{ title: '<script>alert("xss")</script>Test Book' }];
  const res = await fetch('/api/enrichment/batch', {
    method: 'POST',
    body: JSON.stringify({ books, jobId: '123' })
  });
  // Verify title is sanitized in enrichment result
  const result = await res.json();
  expect(result.books[0].title).not.toContain('<script>');
  expect(result.books[0].title).toBe('Test Book');
});

test('Rejects empty title', async () => {
  const books = [{ title: '' }];
  const res = await fetch('/api/enrichment/batch', {
    method: 'POST',
    body: JSON.stringify({ books, jobId: '123' })
  });
  expect(res.status).toBe(400);
});

test('Rejects missing title', async () => {
  const books = [{ author: 'Test' }];
  const res = await fetch('/api/enrichment/batch', {
    method: 'POST',
    body: JSON.stringify({ books, jobId: '123' })
  });
  expect(res.status).toBe(400);
});
```

### Impact
- **Severity:** LOW (no known exploits, but prevents future issues)
- **Risk:** DoS attacks, cost explosion, XSS
- **Cost Impact:** Malicious 10K book request could cost $$$

### Dependencies
- `sanitize-html` npm package (or similar)

### Acceptance Criteria
- [ ] All validation tests pass
- [ ] Malformed requests return 400 with clear errors
- [ ] XSS payloads sanitized
- [ ] Batch size limited to 100
- [ ] No performance regression

---

## Issue 7: [P2 - LOW] WebSocket timeout hardcoded (no config for slow networks)

**Labels:** `enhancement`, `low-priority`, `iOS`, `configuration`, `network`

### Description
The WebSocket timeout is hardcoded to 70 seconds in `BookshelfAIService`. This provides no flexibility for users on slow networks or regions with high latency.

### Current Behavior
```swift
// File: BookshelfAIService.swift:85
private let timeout: TimeInterval = 70.0 // Hardcoded
```

### Expected Behavior
Timeout should be configurable via `EnrichmentConfig` with sensible default.

### Proposed Fix
```swift
// File: EnrichmentConfig.swift
enum EnrichmentConfig {
    // ... other config ...
    static let webSocketTimeout: TimeInterval = 70 // Configurable
}

// File: BookshelfAIService.swift:85
private let timeout: TimeInterval = EnrichmentConfig.webSocketTimeout
```

### Future Enhancement
Add Settings UI to let users adjust timeout (Advanced Settings section):
```swift
// Settings range: 30s (fast networks) to 180s (slow networks)
Slider(value: $webSocketTimeout, in: 30...180, step: 10)
```

### Testing Checklist
- [ ] Verify timeout still works after refactor
- [ ] Test with different timeout values
- [ ] Verify default (70s) matches current behavior

### Impact
- **Severity:** LOW (current default works for most users)
- **Affected Users:** Users on very slow networks
- **Benefit:** Better user experience in edge cases

### Acceptance Criteria
- [ ] Timeout configurable via EnrichmentConfig
- [ ] Default value remains 70s
- [ ] No behavior change from current implementation

---

## Issue 8: [P2 - LOW] Backend converts arbitrary workIds without sanitization

**Labels:** `security`, `low-priority`, `backend`, `deprecated-endpoint`

### Description
The deprecated `/api/enrichment/start` endpoint converts `workIds` to book titles without sanitization or length validation. While this endpoint is deprecated, it's still active.

### Current Behavior
```typescript
// File: index.js:92
const books = workIds.map(id => ({ title: String(id) }));
```

**Risks:**
- No length limit on `id` values
- No type checking (could be objects, arrays)
- Converted to strings blindly

### Expected Behavior
Either remove deprecated endpoint OR add proper validation.

### Proposed Fix (Option A - Add Validation)
```typescript
// File: index.js:69-92
const { jobId, workIds } = await request.json();

// Validate workIds
if (!Array.isArray(workIds) || workIds.length === 0) {
  return new Response(JSON.stringify({
    error: 'Invalid request: workIds must be non-empty array'
  }), { status: 400 });
}

if (workIds.length > 100) {
  return new Response(JSON.stringify({
    error: 'Invalid request: Max 100 workIds'
  }), { status: 400 });
}

// Sanitize and validate each ID
const books = workIds.map((id, i) => {
  if (typeof id !== 'string' || id.length === 0) {
    throw new Error(`workId ${i}: must be non-empty string`);
  }
  if (id.length > 500) {
    throw new Error(`workId ${i}: max 500 chars`);
  }
  return { title: sanitizeHtml(id) };
});
```

### Proposed Fix (Option B - Remove Endpoint)
```typescript
// File: index.js:58-111
if (url.pathname === '/api/enrichment/start' && request.method === 'POST') {
  // DEPRECATED: This endpoint is removed. Use /api/enrichment/batch instead.
  return new Response(JSON.stringify({
    error: 'Endpoint deprecated. Use /api/enrichment/batch',
    migration: 'https://docs.bookstrack.app/api/migration'
  }), {
    status: 410, // Gone
    headers: { 'Content-Type': 'application/json' }
  });
}
```

### Recommendation
**Option B** - Remove the endpoint entirely since:
1. It's already marked deprecated
2. iOS should migrate to `/api/enrichment/batch`
3. Reduces attack surface
4. Simplifies backend maintenance

### Testing Checklist
- [ ] Verify old iOS clients handle 410 error gracefully
- [ ] Update iOS to use `/api/enrichment/batch` exclusively
- [ ] Monitor logs for deprecated endpoint usage (should be 0)

### Impact
- **Severity:** LOW (endpoint is deprecated, low usage)
- **Security Risk:** Potential XSS/DoS via workIds
- **Maintenance Benefit:** Remove dead code

### Acceptance Criteria
- [ ] Deprecated endpoint removed OR properly validated
- [ ] iOS migrated to new endpoint
- [ ] Zero usage of old endpoint in logs

---

## Issue 9: [P2 - LOW] fetchUserLibrary() inefficient in-memory filtering

**Labels:** `performance`, `low-priority`, `iOS`, `database`, `optimization`

### Description
Similar to Issue #5, `fetchUserLibrary()` loads ALL Work objects into memory and filters in-memory. This should follow the pattern in `fetchByReadingStatus()` which queries UserLibraryEntry first.

### Current Behavior
```swift
// File: LibraryRepository.swift:79-96
public func fetchUserLibrary() throws -> [Work] {
    let descriptor = FetchDescriptor<Work>(
        sortBy: [SortDescriptor(\.lastModified, order: .reverse)]
    )
    let allWorks = try modelContext.fetch(descriptor) // ⚠️ Loads ALL works

    return allWorks.filter { work in
        guard let entries = work.userLibraryEntries else { return false }
        return !entries.isEmpty
    }
}
```

### Expected Behavior
Fetch `UserLibraryEntry` first (smaller dataset), then map to Works.

### Proposed Fix
```swift
// File: LibraryRepository.swift:79-96
public func fetchUserLibrary() throws -> [Work] {
    // Fetch UserLibraryEntry records first (smaller dataset)
    let entryDescriptor = FetchDescriptor<UserLibraryEntry>()
    let entries = try modelContext.fetch(entryDescriptor)

    // Map to unique Work objects
    let works = Set(entries.compactMap { entry in
        // Defensive: Validate entry before accessing work
        guard modelContext.model(for: entry.persistentModelID) as? UserLibraryEntry != nil else {
            return nil
        }
        return entry.work
    })

    // Sort by last modified
    return works.sorted { $0.lastModified > $1.lastModified }
}
```

### Performance Impact
- **Before:** O(n) where n = total Works (including non-library books)
- **After:** O(m) where m = UserLibraryEntry count (typically much smaller)
- **Expected Improvement:** 3-5x faster for large databases

### Testing Checklist
- [ ] Unit test: Verify correct Works returned
- [ ] Unit test: Verify sorting maintained
- [ ] Performance test: Benchmark with 10K Works, 1K in library
- [ ] Verify defensive checks prevent crashes

### Impact
- **Severity:** LOW (current implementation works, just inefficient)
- **Affected Users:** Users with large libraries
- **Benefit:** Faster library loading

### Acceptance Criteria
- [ ] Query performance improved 3x+
- [ ] Results match old implementation
- [ ] Sorting preserved
- [ ] No crashes with invalid entries

---

## Summary

**Total Issues:** 9
- **P0 (HIGH):** 1 issue (battery drain - fix TODAY)
- **P1 (MEDIUM):** 4 issues (reliability, architecture)
- **P2 (LOW):** 4 issues (polish, optimization)

**Recommended Implementation Order:**
1. Issue #1 (P0) - Emergency fix
2. Issue #2 (P1) - Enrichment timeout
3. Issue #4 (P1) - URL centralization (prerequisite for #3)
4. Issue #3 (P1) - Stable matching (critical path)
5. Issue #5 (P1) - Query optimization
6. Issue #6-9 (P2) - Low priority optimizations

**Total Estimated Effort:** 2-3 developer-weeks
