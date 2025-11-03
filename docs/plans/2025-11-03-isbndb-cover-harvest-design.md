# ISBNdb Cover Harvest - Design Document

**Date:** 2025-11-03
**Issue:** [#202 - Harvest ISBNdb cover images before subscription expires](https://github.com/jukasdrj/books-tracker-v1/issues/202)
**Status:** Design Complete, Ready for Implementation
**Timeline:** Must complete before ISBNdb subscription expires (end of month)

## Executive Summary

One-time harvest of ~500-775 book cover images from ISBNdb API before subscription cancellation, targeting curated "top books" from 2015-2025 CSV datasets. Covers stored in R2 with KV metadata for fast lookups, enabling future edge caching (Issue #147) and cost reduction (Issue #201).

**Key Decisions:**
- **Architecture:** Wrangler CLI task (local control + Worker bindings)
- **Data Source:** CSV files in `docs/testImages/csv-expansion/` (2015-2025)
- **Edition Priority:** CSV ISBN-13 first, fallback to Google Books most popular edition
- **Storage:** R2 (`covers/isbn/{isbn13}.jpg`) + KV metadata (`cover:{isbn}`)
- **Error Handling:** Skip and log failures to `failed_isbns.json`
- **Rate Limits:** 1000ms between ISBNdb calls, 5000 calls/day quota

## Problem Statement

ISBNdb subscription provides high-quality book cover images but expires at end of month. Before cancellation:
1. **Harvest covers** for curated book lists (real user value, not random books)
2. **Store in R2** for permanent, low-cost hosting ($0.015/GB/month)
3. **Enable future features:** Edge caching (#147), ISBNdb removal (#201)

**Constraints:**
- ISBNdb API: 5000 calls/day, 1 req/second rate limit
- Timeline: ~2 weeks before subscription expires
- Budget: Minimize API calls, maximize coverage of high-value books

## Architecture

### Execution Model: Wrangler CLI Task

**Why Wrangler CLI?**
- Runs in Worker context (full R2/KV/secrets access)
- Local terminal output (easy progress monitoring)
- No deployment needed (temporary task)
- Fast iteration during development

**Execution:**
```bash
cd cloudflare-workers/api-worker
npx wrangler dev --remote --task harvest-covers
```

**File Location:** `cloudflare-workers/api-worker/src/tasks/harvest-covers.ts`

### Data Sources (Priority Order)

1. **CSV Files:** `docs/testImages/csv-expansion/` (Primary source)
   - `2015.csv` → `2025.csv` (yearly top books, ~50 books each)
   - `combined_library_expanded.csv` (775 books, comprehensive)
   - `goodreads_library_export.csv` (test data)

2. **Expected Coverage:** ~500-775 unique books (deduplicated by ISBN-13)

3. **CSV Format:**
   ```csv
   Title,Author,ISBN-13
   "The Women",Kristin Hannah,9780312577243
   "James",Percival Everett,9780385551540
   ```

### Data Flow Pipeline

```
┌─────────────────────────────────────────────────────────────┐
│ 1. CSV INGESTION                                            │
│  ├─ Read all CSVs from docs/testImages/csv-expansion/      │
│  ├─ Parse ISBN-13, Title, Author columns                   │
│  ├─ Deduplicate by ISBN-13 (use Set)                       │
│  └─ Output: ~500-775 unique BookEntry[]                    │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. HARVEST LOOP (For each ISBN)                            │
│                                                             │
│  ┌─────────────────────────────────────────────┐           │
│  │ 2a. Check KV Cache                          │           │
│  │  └─ If exists: Skip (already harvested)     │           │
│  └─────────────────────────────────────────────┘           │
│                  ↓ (not cached)                             │
│  ┌─────────────────────────────────────────────┐           │
│  │ 2b. Query ISBNdb API                        │           │
│  │  GET /book/{isbn13}                         │           │
│  │  Rate Limit: Sleep 1000ms between calls     │           │
│  └─────────────────────────────────────────────┘           │
│           ↓ SUCCESS              ↓ FAILURE                 │
│  ┌──────────────────┐   ┌──────────────────────┐           │
│  │ 2c. Download     │   │ 2d. Google Fallback  │           │
│  │  Cover Image     │   │  /volumes?q=isbn:... │           │
│  │  (ISBNdb URL)    │   │  Pick highest        │           │
│  └──────────────────┘   │  ratingsCount        │           │
│           ↓              └──────────────────────┘           │
│           └──────────────┬──────────────┘                   │
│                          ↓                                  │
│  ┌─────────────────────────────────────────────┐           │
│  │ 2e. Upload to R2                            │           │
│  │  Key: covers/isbn/{isbn13}.jpg              │           │
│  └─────────────────────────────────────────────┘           │
│                          ↓                                  │
│  ┌─────────────────────────────────────────────┐           │
│  │ 2f. Store KV Metadata                       │           │
│  │  Key: cover:{isbn}                          │           │
│  │  Value: {source, r2Key, timestamp, ...}     │           │
│  └─────────────────────────────────────────────┘           │
│                          ↓                                  │
│  ┌─────────────────────────────────────────────┐           │
│  │ 2g. Log Progress                            │           │
│  │  Every 10 books: "50/775 complete"          │           │
│  └─────────────────────────────────────────────┘           │
│                                                             │
│  If both ISBNdb + Google fail:                             │
│   └─ Log to failed_isbns.json (local file)                 │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. SUMMARY REPORT                                           │
│  ├─ Total harvested: X books                               │
│  ├─ ISBNdb covers: Y books                                 │
│  ├─ Google Books fallback: Z books                         │
│  ├─ Failed: N books (see failed_isbns.json)                │
│  └─ Execution time: ~13-15 minutes                         │
└─────────────────────────────────────────────────────────────┘
```

## Storage Architecture

### R2 Bucket Structure

**Bucket:** `LIBRARY_DATA` (existing)

**Directory Structure:**
```
LIBRARY_DATA/
└── covers/
    └── isbn/
        ├── 9780451524935.jpg  (1984 by George Orwell)
        ├── 9780312577243.jpg  (The Women by Kristin Hannah)
        ├── 9780385551540.jpg  (James by Percival Everett)
        └── ...
```

**Key Format:** `covers/isbn/{isbn13}.jpg`
- Always use ISBN-13 (13-digit, no hyphens)
- Consistent `.jpg` extension (convert PNG/WebP if needed)
- Lowercase for consistency

**Storage Estimate:**
- ~500-775 covers
- Average size: 50-200KB per cover
- Total: ~10-50MB
- Cost: ~$0.0002-$0.0008/month (R2 @ $0.015/GB/month)

### KV Metadata Schema

**Key Format:** `cover:{isbn13}`

**Value Schema:**
```typescript
interface CoverMetadata {
  isbn: string;              // ISBN-13 (e.g., "9780451524935")
  source: "isbndb" | "google-books";
  r2Key: string;             // R2 object key (e.g., "covers/isbn/9780451524935.jpg")
  harvestedAt: string;       // ISO 8601 timestamp
  fallback: boolean;         // true if Google Books fallback used
  originalUrl: string;       // Original cover URL from provider
}
```

**Example:**
```json
{
  "isbn": "9780451524935",
  "source": "isbndb",
  "r2Key": "covers/isbn/9780451524935.jpg",
  "harvestedAt": "2025-11-03T16:00:00Z",
  "fallback": false,
  "originalUrl": "https://images.isbndb.com/covers/49/35/9780451524935.jpg"
}
```

**KV Cost Estimate:**
- ~500-775 keys
- Read cost: ~$0.50/1M reads (negligible)
- Write cost: ~$5.00/1M writes (negligible for one-time harvest)

### Failed Books Log

**File:** `failed_isbns.json` (written to local filesystem)

**Schema:**
```json
{
  "timestamp": "2025-11-03T16:00:00Z",
  "totalFailed": 23,
  "failures": [
    {
      "isbn": "9780000000000",
      "title": "Book Title",
      "author": "Author Name",
      "isbndbError": "404 Not Found",
      "googleBooksError": "No results for title+author query"
    }
  ]
}
```

**Purpose:**
- Track books that couldn't be harvested
- Enable manual investigation (bad ISBN, out-of-print, etc.)
- Retry later if API issues were transient

## Implementation Details

### Core Functions

**File:** `cloudflare-workers/api-worker/src/tasks/harvest-covers.ts`

```typescript
// Main entry point
export async function harvestCovers(env: Env): Promise<HarvestReport>

// CSV processing
async function loadISBNsFromCSVs(): Promise<BookEntry[]>
async function parseCSV(filePath: string): Promise<BookEntry[]>
async function deduplicateISBNs(entries: BookEntry[]): BookEntry[]

// Cover harvesting
async function harvestSingleBook(
  entry: BookEntry,
  env: Env
): Promise<HarvestResult>

async function fetchFromISBNdb(
  isbn: string,
  env: Env
): Promise<CoverData | null>

async function fetchFromGoogleBooks(
  title: string,
  author: string
): Promise<CoverData | null>

async function downloadAndStoreImage(
  coverUrl: string,
  isbn: string,
  env: Env
): Promise<void>

async function storeMetadata(
  isbn: string,
  metadata: CoverMetadata,
  env: Env
): Promise<void>

// Progress tracking
function logProgress(current: number, total: number): void
function generateReport(results: HarvestResult[]): HarvestReport
```

### Edition Selection Strategy

**Priority Hierarchy:**
1. **Primary:** Use ISBN-13 from CSV (already curated, trust the list compiler)
2. **Fallback:** If ISBNdb 404 or no cover, query Google Books by title+author
   - Search: `GET /volumes?q=intitle:{title}+inauthor:{author}`
   - Pick edition with highest `volumeInfo.ratingsCount` (most popular)
   - Extract cover from `volumeInfo.imageLinks.thumbnail` (or `.large`)

**Rationale:**
- CSVs contain curated ISBNs (likely most recognizable editions)
- Google Books has good popularity data (`ratingsCount`)
- Avoid guessing "first published" vs "latest" (subjective)

### Rate Limiting

**ISBNdb:**
- Enforced by existing `enforceRateLimit()` function in `external-apis.js`
- 1000ms sleep between requests
- Quota: 5000 calls/day (more than enough for 775 books)

**Google Books:**
- No rate limiting (free API, allows bursts)
- Use sparingly (only as fallback)

**Expected Execution Time:**
- 775 books × 1 second/book = ~13 minutes
- Add overhead for downloads, R2 uploads: ~15-20 minutes total

### Error Handling

**Strategy:** Skip and log failures (maximize coverage)

**Per-Book Try-Catch:**
```typescript
for (const book of books) {
  try {
    await harvestSingleBook(book, env);
    successCount++;
  } catch (error) {
    failedBooks.push({ ...book, error: error.message });
    console.error(`Failed to harvest ${book.isbn}: ${error.message}`);
  }
}
```

**Why Skip vs Fail Fast?**
- Single bad ISBN shouldn't block entire harvest
- Can manually investigate failures later
- Maximizes coverage before subscription expires

**Failure Scenarios:**
- ISBNdb 404 (book not in their database) → Try Google fallback
- ISBNdb rate limit exceeded → Sleep and retry (handled by `enforceRateLimit()`)
- Cover URL 404 (broken image link) → Log as failed
- Google Books no results → Log as failed
- R2 upload failure → Retry once, then log as failed

## Testing & Validation

### Pre-Flight Checks

Before running harvest, verify:
1. `env.ISBNDB_API_KEY` is accessible (test with dummy call)
2. R2 bucket write permissions (`env.LIBRARY_DATA.put()` test)
3. KV write permissions (`env.KV_CACHE.put()` test)
4. CSV files exist and are readable
5. Daily ISBNdb quota hasn't been exhausted

### Dry Run Mode

**Flag:** `--dry-run`

**Behavior:**
- Load CSVs and deduplicate (real)
- Log what WOULD be harvested (no API calls)
- Validate CSV format and ISBN-13 structure
- Estimate execution time

**Example Output:**
```
[DRY RUN] Loaded 775 unique ISBNs from CSVs
[DRY RUN] Would call ISBNdb for: 9780451524935 (1984 by George Orwell)
[DRY RUN] Would call ISBNdb for: 9780312577243 (The Women by Kristin Hannah)
...
[DRY RUN] Estimated execution time: ~13 minutes
```

### Progress Monitoring

**Console Output:**
```
ISBNdb Cover Harvest Starting...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Loaded 775 unique ISBNs from CSVs

Harvest Progress:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 50/775 (6%)
✓ ISBNdb: 42 | ↻ Google: 5 | ✗ Failed: 3
Elapsed: 2m 15s | Remaining: ~13m

...

Harvest Complete!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ Total Harvested: 752 / 775 (97%)
✓ ISBNdb Covers: 680 (88%)
↻ Google Fallback: 72 (9%)
✗ Failed: 23 (3%)

Execution Time: 14m 32s
Failed ISBNs logged to: failed_isbns.json
```

### Post-Harvest Validation

**R2 Storage Check:**
```bash
# List all covers
wrangler r2 object list LIBRARY_DATA --prefix covers/isbn/ | wc -l

# Verify specific cover exists
wrangler r2 object get LIBRARY_DATA covers/isbn/9780451524935.jpg
```

**KV Metadata Check:**
```bash
# Sample metadata
wrangler kv:key get --binding=KV_CACHE "cover:9780451524935"

# Count stored covers
wrangler kv:key list --binding=KV_CACHE --prefix "cover:" | jq length
```

**Failed Books Review:**
```bash
# Check failures
cat failed_isbns.json | jq '.totalFailed'
cat failed_isbns.json | jq '.failures[] | {isbn, title, isbndbError}'
```

## Success Metrics

### Coverage Goals

- **Primary Goal:** ≥90% of CSV books harvested (700+ out of 775)
- **ISBNdb Primary:** ≥70% from ISBNdb (avoid excessive Google fallback)
- **Execution Time:** <20 minutes (acceptable for one-time task)
- **Zero Duplicates:** Each ISBN stored exactly once (enforce in code)

### Cost Analysis

**ISBNdb API Calls:**
- Best case: 775 calls (all ISBNs found)
- Worst case: 775 ISBNdb + 100 Google fallbacks = 875 calls
- Well within 5000 calls/day quota

**R2 Storage:**
- ~10-50MB total
- Cost: ~$0.0002-$0.0008/month (negligible)

**KV Storage:**
- ~500-775 keys
- Cost: ~$0.50/1M reads (negligible)

**Total Cost:** <$1/year for permanent cover hosting (vs ongoing ISBNdb subscription)

## Integration with Future Features

### Issue #147: Edge Caching for Book Cover Images

Once covers are in R2, we can:
1. **Public R2 URLs:** Make `LIBRARY_DATA` bucket public, serve covers directly
2. **Cloudflare Images:** Integrate with CF Images for automatic resizing/optimization
3. **CDN Caching:** Add `Cache-Control` headers for edge caching (CF CDN)
4. **iOS Client:** Update cover loading to prefer R2 URLs over external APIs

**Example Flow:**
```
iOS App → GET /api/covers/{isbn}
   ↓
Worker checks KV: cover:{isbn}
   ↓ (if exists)
Return R2 public URL or serve directly
   ↓ (if not exists)
Fallback to Google Books API (live lookup)
```

### Issue #201: Remove ISBNdb Dependency

After harvest completes:
1. Verify R2 covers exist for top books
2. Update enrichment service to skip ISBNdb (use Google Books only)
3. Cancel ISBNdb subscription (save recurring cost)
4. Remove `ISBNDB_API_KEY` from secrets

**Dependency Chain:**
```
#202 (Harvest) → #147 (Edge Caching) → #201 (Remove ISBNdb)
```

## Risk Mitigation

### Risk: ISBNdb Rate Limit Exceeded

**Mitigation:**
- Built-in 1000ms sleep between requests
- Daily quota: 5000 calls (6x our max usage)
- Monitor quota via ISBNdb dashboard

### Risk: CSV ISBNs are Outdated/Incorrect

**Mitigation:**
- Google Books fallback handles 404s
- Failed books logged for manual review
- Can re-run harvest after fixing CSV data

### Risk: R2 Upload Failures

**Mitigation:**
- Retry once on upload failure
- Log failures to `failed_isbns.json`
- Can re-run harvest (KV check skips duplicates)

### Risk: Subscription Expires Before Harvest

**Mitigation:**
- Timeline: ~2 weeks remaining
- Execution time: <20 minutes
- Can run harvest immediately (dry-run first)

## Timeline & Next Steps

### Phase 1: Setup (1 day)
- [ ] Create `harvest-covers.ts` file structure
- [ ] Implement CSV parsing functions
- [ ] Add wrangler.toml task configuration
- [ ] Test dry-run mode

### Phase 2: Core Implementation (1-2 days)
- [ ] Implement ISBNdb fetching (reuse `external-apis.js`)
- [ ] Implement Google Books fallback
- [ ] Add R2 upload logic
- [ ] Add KV metadata storage

### Phase 3: Testing (1 day)
- [ ] Dry-run with small CSV subset
- [ ] Live test with 10-20 books
- [ ] Validate R2 + KV storage
- [ ] Review failed_isbns.json format

### Phase 4: Production Harvest (1 day)
- [ ] Run full harvest (775 books)
- [ ] Monitor progress (~15 minutes)
- [ ] Validate coverage ≥90%
- [ ] Review failures, retry if needed

### Phase 5: Cleanup & Documentation (1 day)
- [ ] Update Issue #202 with harvest results
- [ ] Document R2 key format in CLAUDE.md
- [ ] Prepare for Issue #147 (edge caching)
- [ ] Update Issue #201 status (ready to remove ISBNdb)

**Total Estimated Time:** 4-6 days (including testing and validation)

**Critical Deadline:** End of month (ISBNdb subscription expires)

## References

- **Issue #202:** [Harvest ISBNdb cover images before subscription expires](https://github.com/jukasdrj/books-tracker-v1/issues/202)
- **Issue #147:** [Implement Edge Caching for Book Cover Images](https://github.com/jukasdrj/books-tracker-v1/issues/147)
- **Issue #201:** [Remove ISBNdb dependency to reduce costs](https://github.com/jukasdrj/books-tracker-v1/issues/201)
- **CSV Data:** `docs/testImages/csv-expansion/` (2015-2025 top books)
- **Backend Architecture:** `cloudflare-workers/MONOLITH_ARCHITECTURE.md`

---

**Design Status:** ✅ Complete
**Ready for Implementation:** Yes
**Approval Required:** No (one-time utility task)
**Breaking Changes:** None (additive feature)
