# Enrichment Job Cover Image Investigation

## Executive Summary

**Issue:** CSV import enrichment jobs are accepted by the backend (202 response) but books are not receiving cover images after background enrichment completes.

**Status:** Investigation requires Cloudflare Logpush analysis - code review identifies potential root causes.

---

## Architecture Overview

### Enrichment Pipeline

```
iOS App (CSV Import)
   ↓
POST /api/enrichment/batch (batch-enrichment.js)
   ├─ Validates books array
   ├─ Gets WebSocket DO stub for jobId
   ├─ Returns 202 Accepted immediately
   └─ Spawns: ctx.waitUntil(processBatchEnrichment())
        ↓
   processBatchEnrichment() (batch-enrichment.js:70-115)
   ├─ Calls enrichBooksParallel() with 10 concurrency
   ├─ Enrichment function: enrichSingleBook() from enrichment.ts
   ├─ Progress callback: doStub.updateProgress()
   └─ Final: doStub.complete() or doStub.fail()
        ↓
   enrichSingleBook() (enrichment.ts:213-257)
   ├─ Strategy 1: ISBN search (Google Books → OpenLibrary)
   ├─ Strategy 2: Title+Author search (Google Books)
   └─ Strategy 3: Fallback (OpenLibrary)
        ↓
   Returns: WorkDTO with canonical fields
   - title, authors[], isbn, coverImageUrl, description, etc.
```

### What Should Happen

1. **enrichSingleBook()** returns `WorkDTO` with `coverImageUrl` field populated
   - Google Books API returns `volumeInfo.imageLinks.thumbnail` or `smallThumbnail`
   - OpenLibrary API returns `covers` field with cover IDs
   - Both are normalized to full URLs

2. **Return Format** (from enrichment.ts:350-357):
   ```typescript
   {
     ...normalizedWork,
     primaryProvider: "google-books" | "openlibrary",
     contributors: ["provider"],
     synthetic: false
   }
   ```

3. **R2 Storage** is NOT happening at backend level
   - Code does NOT download/store covers to R2 in batch enrichment
   - Only metadata is returned to iOS
   - iOS is responsible for fetching and storing cover images via:
     - `/images/proxy` endpoint (handler: src/handlers/image-proxy.ts)
     - Caching happens client-side in SwiftData

---

## Code Analysis: Missing Cover Image Flow

### 1. **Batch Enrichment Handler** (batch-enrichment.js)

```javascript
// Lines 86-88: enrichSingleBook() returns enhanced work
if (enriched) {
  return { ...book, enriched, success: true };
}
```

**Issue:** No cover image extraction or storage happening here. The response is just relayed to iOS via WebSocket.

### 2. **Enrichment Service** (enrichment.ts)

The service calls external APIs (Google Books, OpenLibrary) which should return cover URLs:

```typescript
// enrichment.ts:223-240
if (isbn) {
  const result = await searchByISBN(isbn, env);
  if (result) return result;
}

const googleResult = await searchGoogleBooks({ title, author }, env);
if (googleResult) return googleResult;

const openLibResult = await searchOpenLibrary({ title, author }, env);
if (openLibResult) return openLibResult;
```

**Expected:** Each provider normalizer should include `coverImageUrl` field.

### 3. **External APIs** (external-apis.js)

**Critical Question:** Are the normalizers properly extracting cover images from:
- `volumeInfo.imageLinks.thumbnail` (Google Books)
- `covers` field (OpenLibrary)

Need to check: `/cloudflare-workers/api-worker/src/services/external-apis.js`

### 4. **Image Proxy** (image-proxy.ts)

The endpoint exists at `/images/proxy` but is NOT called by batch enrichment:
- This is for iOS to fetch cover images on-demand
- Backend enrichment should NOT download/store covers
- iOS should call proxy endpoint with `imageUrl` parameter

**Hypothesis:** Cover image URLs are being returned but iOS is not rendering them or the URLs are malformed.

---

## Root Cause Identified

### CRITICAL BUG: Cover Images Stored in Edition, Not Work

**Status:** CONFIRMED ROOT CAUSE

**Problem:**
The enrichment pipeline returns `WorkDTO` objects, but cover image URLs are only being extracted into `EditionDTO` objects!

**Evidence:**

**Google Books Normalizer** (`google-books.ts:48-75`):
```typescript
export function normalizeGoogleBooksToWork(item: any): WorkDTO {
  return {
    title: volumeInfo.title,
    subjectTags: [...],
    // ❌ NO coverImageURL field in Work!
  };
}

export function normalizeGoogleBooksToEdition(item: any): EditionDTO {
  return {
    isbn: isbn13 || isbn10,
    title: volumeInfo.title,
    coverImageURL: volumeInfo.imageLinks?.thumbnail?.replace('http:', 'https:'),
    // ✅ Cover image is HERE in Edition
  };
}
```

**OpenLibrary Normalizer** (`openlibrary.ts:29-79`):
```typescript
export function normalizeOpenLibraryToWork(doc: any): WorkDTO {
  return {
    title: doc.title,
    subjectTags: [...],
    // ❌ NO coverImageURL field in Work!
  };
}

export function normalizeOpenLibraryToEdition(doc: any): EditionDTO {
  return {
    isbn: isbn13 || isbn10,
    coverImageURL: doc.cover_i
      ? `https://covers.openlibrary.org/b/id/${doc.cover_i}-L.jpg`
      : undefined,
    // ✅ Cover image is HERE in Edition
  };
}
```

**Data Flow Problem:**

1. `enrichSingleBook()` calls external APIs
2. APIs return both Work and Edition data (via `normalizeGoogleBooksResponse()`)
3. `enrichSingleBook()` returns only the **Work** DTO (see enrichment.ts line 237-240)
4. **Edition** DTOs with cover images are discarded!

```typescript
// enrichment.ts:237-240
const googleResult: WorkDTO | null = await searchGoogleBooks({ title, author }, env);
if (googleResult) {
  return googleResult;  // ❌ Only returns Work, Edition is lost!
}
```

**Result:**
- iOS receives enriched books with title, author, ISBN
- But **NO `coverImageURL`** in the response
- iOS cannot display cover images

---

## Root Cause Candidates (Validated)

### A. Cover URLs Not Being Returned ✅ CONFIRMED

The normalizers ARE extracting cover images correctly, but they're stored in the Edition DTO, which is discarded by the enrichment pipeline.

---

## Solution

### Fix 1: Add coverImageURL to WorkDTO

**File:** `cloudflare-workers/api-worker/src/types/canonical.ts`

Add to `WorkDTO` interface (around line 26):
```typescript
export interface WorkDTO {
  // Required fields
  title: string;
  subjectTags: string[];

  // NEW: Cover image from primary edition
  coverImageURL?: string;

  // Optional metadata
  originalLanguage?: string;
  firstPublicationYear?: number;
  description?: string;
  ...
}
```

### Fix 2: Extract Cover Image in Google Books Normalizer

**File:** `cloudflare-workers/api-worker/src/services/normalizers/google-books.ts`

Modify `normalizeGoogleBooksToWork()` (lines 24-43):
```typescript
export function normalizeGoogleBooksToWork(item: any): WorkDTO {
  const volumeInfo = item.volumeInfo || {};
  const coverImageUrl = volumeInfo.imageLinks?.thumbnail?.replace('http:', 'https:');

  return {
    title: volumeInfo.title || 'Unknown',
    subjectTags: genreNormalizer.normalize(volumeInfo.categories || [], 'google-books'),
    coverImageURL: coverImageUrl,  // NEW!
    originalLanguage: volumeInfo.language,
    firstPublicationYear: extractYear(volumeInfo.publishedDate),
    description: volumeInfo.description,
    synthetic: false,
    primaryProvider: 'google-books',
    contributors: ['google-books'],
    goodreadsWorkIDs: [],
    amazonASINs: [],
    librarythingIDs: [],
    googleBooksVolumeIDs: [item.id],
    isbndbQuality: 0,
    reviewStatus: 'verified',
  };
}
```

### Fix 3: Extract Cover Image in OpenLibrary Normalizer

**File:** `cloudflare-workers/api-worker/src/services/normalizers/openlibrary.ts`

Modify `normalizeOpenLibraryToWork()` (lines 29-47):
```typescript
export function normalizeOpenLibraryToWork(doc: any): WorkDTO {
  const coverImageUrl = doc.cover_i
    ? `https://covers.openlibrary.org/b/id/${doc.cover_i}-L.jpg`
    : undefined;

  return {
    title: doc.title || 'Unknown',
    subjectTags: genreNormalizer.normalize(doc.subject || [], 'openlibrary'),
    coverImageURL: coverImageUrl,  // NEW!
    originalLanguage: doc.language?.[0],
    firstPublicationYear: extractYear(doc.first_publish_year),
    description: undefined,
    synthetic: false,
    primaryProvider: 'openlibrary',
    contributors: ['openlibrary'],
    openLibraryWorkID: extractWorkId(doc.key),
    goodreadsWorkIDs: doc.id_goodreads || [],
    amazonASINs: doc.id_amazon || [],
    librarythingIDs: doc.id_librarything || [],
    googleBooksVolumeIDs: doc.id_google || [],
    isbndbQuality: 0,
    reviewStatus: 'verified',
  };
}
```

### Fix 4: Update iOS Swift Codable (if using automatic Codable)

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/API/DTOs/WorkDTO.swift`

```swift
struct WorkDTO: Codable {
    let title: String
    let subjectTags: [String]
    let coverImageURL: String?  // NEW!
    let originalLanguage: String?
    let firstPublicationYear: Int?
    let description: String?
    // ... other fields
}
```

---

## Verification Steps

After implementing fixes:

1. **Build backend:**
   ```bash
   cd cloudflare-workers/api-worker
   npm run build
   /deploy-backend
   ```

2. **Test via curl:**
   ```bash
   curl "https://books-api-proxy.jukasdrj.workers.dev/v1/search/title?q=The+Great+Gatsby" | jq '.data.works[0].coverImageURL'
   ```
   Should return: `https://books.google.com/...` or `https://covers.openlibrary.org/...`

3. **Test enrichment batch:**
   - Submit CSV import
   - Check WebSocket messages for `coverImageURL` in enriched books
   - Verify iOS receives and displays cover images

4. **Run tests:**
   ```bash
   npm test
   ```

---

### C. iOS Not Processing Cover URLs from WebSocket ❌ NOT CONFIRMED

**Issue:** WebSocket message format from `doStub.complete()` might not include cover images.

Current format (progress-socket.js:310-315):
```javascript
{
  type: 'complete',
  jobId,
  timestamp,
  data: { books: enrichedBooks }
}
```

**Question:** Does iOS check `books[].enriched.coverImageUrl`?

### D. Cover Image Caching Not Triggered ⚠️ LESS LIKELY

**Evidence:** iOS might need to call `/images/proxy` to cache covers.

Current flow:
1. Enrichment returns `coverImageUrl`
2. iOS receives it via WebSocket
3. iOS MUST download via `/images/proxy?imageUrl=...`
4. SwiftData stores the downloaded image

**Question:** Is step 3 happening?

---

## How to Access Cloudflare Logpush

### Option 1: Cloudflare Dashboard (Easiest)

1. **Log in** to Cloudflare dashboard (cloudflare.com)
2. **Go to:** Workers → "api-worker" → Logs
3. **Time range:** Last 24 hours
4. **Search for:** `enrichment` or `/api/enrichment/batch`

### Option 2: Logpush via CLI (More Powerful)

```bash
# Install Wrangler if not already installed
npm install -g @cloudflare/wrangler

# Authenticate with Cloudflare
wrangler login

# Tail logs in real-time
wrangler tail api-worker --search "enrichment" --format pretty

# To see specific search term
wrangler tail api-worker --search "google-books" --format pretty
```

### Option 3: Logpush Configuration (Advanced)

If you need to export logs to external service:

1. **Go to:** Cloudflare Dashboard → Logs → Logpush
2. **Create dataset:** Configure to export Worker logs
3. **Destination:** S3, Datadog, Splunk, etc.

---

## Debugging: What to Look For in Logs

### 1. **Enrichment Job Acceptance**

```
[ProgressDO] Incoming request { url: ..., upgradeHeader: websocket }
[ProgressDO] Creating WebSocket for job {jobId}
[{jobId}] ✅ Client ready signal received
```

**Success indicators:**
- WebSocket upgrade is successful
- Client sends ready signal
- DO creates storage for job

### 2. **Book Enrichment Process**

```
enrichSingleBook: Searching Google Books by ISBN "..."
enrichSingleBook: Google Books returned results
enrichMultipleBooks: ... (maxResults: 20)
[Progress] updateProgress called: Enriching (1/48): {title}
```

**Success indicators:**
- API calls to Google Books/OpenLibrary working
- Results being returned for each book
- Progress updates being sent every 1-2 seconds

### 3. **Cover Image Extraction** ⚠️ CRITICAL

Look for in normalizer output:

```
Google Books normalizer output:
{
  isbn: "...",
  title: "...",
  coverImageUrl: "https://books.google.com/...",  // ← Should be present!
  ...
}
```

**If missing, search logs for:**
- `imageLinks` (Google Books)
- `covers` (OpenLibrary)
- Any parsing errors in normalizers

### 4. **Completion Signal**

```
[{jobId}] complete called: { books: [{...}, {...}] }
[{jobId}] Completion message sent
```

**Success indicator:**
- `books` array includes enriched data with `coverImageUrl`

### 5. **Errors to Watch For**

```
[{jobId}] Failed to parse message
[{jobId}] No WebSocket connection
[{jobId}] Failed to send progress
enrichMultipleBooks error: ...
PROVIDER_ERROR
INVALID_RESPONSE
```

---

## Investigation Checklist

- [ ] **Verify WebSocket Connection**
  - Search logs: `WebSocket connection accepted`
  - Check: `Client ready signal received`

- [ ] **Verify API Calls**
  - Search: `searchGoogleBooksByISBN` or `searchGoogleBooks`
  - Check: Response status code (should be 200)
  - Check: `volumeInfo` present in response

- [ ] **Verify Cover URL Extraction**
  - Search: `imageLinks` or `covers`
  - Check: URLs are proper format (HTTPS)
  - Check: URLs not null/undefined after normalization

- [ ] **Verify Progress Updates**
  - Search: `updateProgress`
  - Count: Should be ~48 updates for 48 books
  - Check: Progress value increasing (0.0 → 1.0)

- [ ] **Verify Job Completion**
  - Search: `complete` type message
  - Check: Message includes `books` array
  - Check: Each book has `enriched` object with `coverImageUrl`

- [ ] **Verify iOS Reception**
  - Check: iOS app logs show WebSocket messages received
  - Check: Books in SwiftData have `coverImageUrl` after enrichment

---

## Specific Log Query Examples

### Search for enrichment batch requests:
```
status_code:202 path:/api/enrichment/batch
```

### Search for Google Books API calls:
```
"searchGoogleBooks" OR "Google Books" OR "googleapis.com"
```

### Search for OpenLibrary API calls:
```
"searchOpenLibrary" OR "openlibrary.org"
```

### Search for WebSocket errors:
```
"WebSocket" AND ("error" OR "failed" OR "closed")
```

### Search for cover-related logs:
```
"coverImageUrl" OR "imageLinks" OR "covers"
```

### Search for specific jobId:
```
jobId:{your-job-id-here}
```

---

## Next Steps

1. **Access Logpush** using one of the methods above
2. **Run investigation checklist** against recent enrichment job
3. **Capture sample log output** for all 5 sections above
4. **Identify failure point:**
   - Before enrichment starts? (WebSocket/connection issue)
   - During API calls? (Provider API failure)
   - In normalization? (Cover URL extraction failing)
   - After completion? (iOS not processing WebSocket data)
5. **Report findings** with specific error messages and log timestamps

---

## Code Files to Review

If you need to investigate further:

- **Main enrichment logic:** `cloudflare-workers/api-worker/src/services/enrichment.ts`
- **Batch handler:** `cloudflare-workers/api-worker/src/handlers/batch-enrichment.js`
- **Durable Object WebSocket:** `cloudflare-workers/api-worker/src/durable-objects/progress-socket.js`
- **Google Books normalizer:** `cloudflare-workers/api-worker/src/services/normalizers/google-books.ts`
- **OpenLibrary normalizer:** `cloudflare-workers/api-worker/src/services/normalizers/openlibrary.ts`
- **External APIs:** `cloudflare-workers/api-worker/src/services/external-apis.js`
- **Image proxy:** `cloudflare-workers/api-worker/src/handlers/image-proxy.ts`

---

## Important Architecture Notes

### Cover Images Are NOT Stored Backend-Side

The `harvest-covers.ts` task is separate and manual:
- Used for pre-loading covers from ISBNdb
- NOT part of automated enrichment pipeline
- Stores covers in R2 with key: `covers/isbn/{isbn}.jpg`

### Enrichment Pipeline Returns Metadata Only

Backend job:
1. ✅ Enriches book metadata (title, author, ISBN, description, etc.)
2. ✅ Returns cover image URLs (not the images themselves)
3. ❌ Does NOT download/store cover images to R2

iOS job:
1. ✅ Receives enrichment results via WebSocket
2. ✅ Extracts `coverImageUrl` from each book
3. ✅ Calls `/images/proxy?imageUrl=...` to fetch and cache image
4. ✅ Stores image URL/reference in SwiftData

---

## Contact/Questions

For detailed investigation support, check:
- iOS app logs (`/sim` command with log streaming)
- Backend logs (Cloudflare Logpush as documented above)
- Network trace (check if `/images/proxy` requests are being made)
