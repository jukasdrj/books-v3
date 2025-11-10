# ISBNdb Cover Harvest - E2E Test Guide

## Overview

End-to-end test script that validates the complete ISBNdb cover harvest workflow before production deployment.

## What It Tests

1. **ISBNdb API Integration** - Fetches cover URLs from ISBNdb API
2. **Image Download** - Downloads cover images with redirect support
3. **WebP Compression** - Simulates Cloudflare Image Resizing compression
4. **R2 Storage** - Uploads compressed images to R2 with metadata
5. **KV Index** - Creates ISBN → R2 key mappings
6. **Rate Limiting** - Token bucket with 10 req/sec + jitter

## Prerequisites

### Environment Variables

```bash
export CF_ACCOUNT_ID="your-cloudflare-account-id"
export CF_API_TOKEN="your-cloudflare-api-token"
export ISBNDB_API_KEY="your-isbndb-api-key"
```

**API Token Permissions Required:**
- R2: Read + Write
- KV: Read + Write

### Test ISBNs

Default test ISBNs (if not specified):
- `9780545010221` - Harry Potter (should have cover)
- `9780439023481` - The Hunger Games (should have cover)
- `9780316769174` - The Catcher in the Rye (should have cover)

## Usage

### Dry Run (Recommended First)

No R2/KV writes, simulates all operations:

```bash
node scripts/test-harvest.js --dry-run
```

**Output Example:**
```
🧪 ISBNdb Cover Harvest - E2E Test
   Mode: DRY RUN (no R2/KV writes)
   ISBNs: 9780545010221, 9780439023481, 9780316769174

🚀 Starting E2E harvest test...

📖 Processing ISBN: 9780545010221
   ⏱️  Acquiring rate limit token...
   ✅ Rate limit acquired (waited 0ms)
   🔍 Fetching cover from ISBNdb...
   [DRY RUN] Would fetch from ISBNdb: /book/9780545010221
   ✅ Cover URL: https://images.isbndb.com/covers/21/9780545010221.jpg (0ms)
   ℹ️  Title: Test Book 9780545010221
   ℹ️  Authors: Test Author
   📥 Downloading image...
   [DRY RUN] Would download: https://images.isbndb.com/covers/21/9780545010221.jpg
   ✅ Downloaded 15 bytes (0ms)
   🗜️  Compressing to WebP...
   [DRY RUN] Would compress to WebP (quality: 85)
   ✅ Compressed: 15 → 6 bytes (60% savings, 0ms)
   ☁️  Storing in R2...
   [DRY RUN] Would store in R2: covers/9780545010221
   [DRY RUN] Metadata: { ... }
   ✅ Stored in R2: covers/9780545010221 (0ms)
   🗂️  Creating KV index...
   [DRY RUN] Would create KV index: cover:9780545010221 → covers/9780545010221
   ✅ KV index created (0ms)
   ✅ Complete! Total time: 0ms
```

### Custom ISBNs (Dry Run)

```bash
node scripts/test-harvest.js --dry-run --isbn "9780545010221,9780439023481"
```

### Live Test (Real R2/KV Writes)

⚠️ **Warning:** This will make real API calls and write to R2/KV!

```bash
node scripts/test-harvest.js --isbn "9780545010221,9780439023481"
```

## Test Phases

### Phase 1: Rate Limiting Test
- Validates token bucket algorithm
- Checks jitter randomization (±100ms)
- Ensures 10 req/sec compliance

### Phase 2: ISBNdb API Test
- Fetches book metadata + cover URL
- Handles 404 responses (book not found)
- Handles API errors gracefully

### Phase 3: Image Download Test
- Downloads cover from ISBNdb CDN
- Follows HTTP redirects (301/302)
- Handles timeouts (10s)

### Phase 4: WebP Compression Test
- Simulates Cloudflare Image Resizing
- Reports compression savings (typically 60%)
- **Note:** Uses simulated compression for test (production will use CF Image Resizing API)

### Phase 5: R2 Storage Test
- Uploads to `covers/{isbn13}` key
- Stores metadata (title, authors, sizes, harvest timestamp)
- Uses human-readable keys (no hashing)

### Phase 6: KV Index Test
- Creates `cover:{isbn}` → `covers/{isbn}` mapping
- Stores harvest metadata for deduplication
- Sets TTL for cache invalidation

## Expected Output

### Successful Harvest
```
📖 Processing ISBN: 9780545010221
   ⏱️  Acquiring rate limit token...
   ✅ Rate limit acquired (waited 0ms)
   🔍 Fetching cover from ISBNdb...
   ✅ Cover URL: https://images.isbndb.com/covers/21/9780545010221.jpg (234ms)
   ℹ️  Title: Harry Potter and the Sorcerer's Stone
   ℹ️  Authors: J.K. Rowling
   📥 Downloading image...
   ✅ Downloaded 45231 bytes (567ms)
   🗜️  Compressing to WebP...
   ℹ️  Note: WebP compression simulated (would use CF Image Resizing in production)
   ✅ Compressed: 45231 → 18092 bytes (60% savings, 12ms)
   ☁️  Storing in R2...
   ✅ Stored in R2: covers/9780545010221 (789ms)
   🗂️  Creating KV index...
   ✅ KV index created (123ms)
   ✅ Complete! Total time: 1725ms
```

### No Cover Available
```
📖 Processing ISBN: 9999999999999
   ⏱️  Acquiring rate limit token...
   ✅ Rate limit acquired (waited 100ms)
   🔍 Fetching cover from ISBNdb...
   ⚠️  No cover found for ISBN 9999999999999 (234ms)
```

### API Error
```
📖 Processing ISBN: 9780545010221
   ⏱️  Acquiring rate limit token...
   ✅ Rate limit acquired (waited 0ms)
   🔍 Fetching cover from ISBNdb...
   ❌ Error: ISBNdb API error: 429 - Rate limit exceeded
```

## Summary Report

After all ISBNs are processed:

```
============================================================
📊 Test Summary
============================================================
Total ISBNs: 3
Successful: 2
No cover: 0
Errors: 1

Average processing time: 1543ms
Average compression savings: 62%

✅ E2E test complete!

Next steps:
1. Review results above
2. If dry-run, test with real R2/KV writes
3. Implement production cron handler (src/handlers/scheduled-harvest.js)
```

## Troubleshooting

### ISBNdb API Errors

**403 Forbidden:**
- Check `ISBNDB_API_KEY` is valid
- Verify API key has not expired

**429 Rate Limit:**
- ISBNdb free tier: 5 req/day
- ISBNdb paid tier: 1000 req/day
- Test uses rate limiter to prevent this

**404 Not Found:**
- ISBN not in ISBNdb database
- Expected for some ISBNs (not an error)

### R2 Errors

**404 Bucket Not Found:**
- Create R2 bucket: `npx wrangler r2 bucket create book-covers`

**403 Forbidden:**
- Check `CF_API_TOKEN` has R2 write permissions

### KV Errors

**KV Namespace Not Found:**
- Update `YOUR_KV_NAMESPACE_ID` in script
- Get ID: `npx wrangler kv:namespace list`

## Production Implementation Notes

### WebP Compression
- Test uses **simulated compression** (60% reduction estimate)
- Production will use **Cloudflare Image Resizing API** (`cf.image.format = 'webp'`)
- Actual savings: 60-70% typical

### R2 Keys
- Human-readable: `covers/{isbn13}`
- No hashing (user requested simplicity)
- Enables manual debugging and inspection

### Error Recovery
- Simple "fail and retry next day" approach
- No complex retry logic (keep it simple)
- Idempotent by design (checks if cover already exists)

### Rate Limiting
- 10 req/sec for ISBNdb API
- ±100ms jitter to smooth traffic
- Token bucket algorithm prevents bursts

## Next Steps

1. **Run dry-run test** - Validate logic without R2/KV writes
2. **Run live test with 2-3 ISBNs** - Verify R2/KV integration
3. **Review results** - Check compression savings, timings
4. **Implement production handler** - `src/handlers/scheduled-harvest.js`
5. **Add to wrangler.toml** - Cron trigger (3 AM UTC daily)

## Related Files

- **Test Script:** `scripts/test-harvest.js`
- **Production Handler:** `src/handlers/scheduled-harvest.js` (to be created)
- **Image Proxy:** `src/handlers/image-proxy.ts` (reusable WebP compression)
- **Consensus Report:** Multi-model approval (GPT-5-Codex 7/10, Gemini-2.5-Pro 9/10)

---

**Status:** ✅ E2E test ready for validation
**Last Updated:** January 2025
