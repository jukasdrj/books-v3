# ISBNdb Cover Harvest Task

One-time harvest of book cover images from ISBNdb API before subscription expires.

## Quick Start

```bash
cd cloudflare-workers/api-worker

# Dry run (test without API calls)
DRY_RUN=true npx wrangler dev --remote --task harvest-covers

# Production harvest
npx wrangler dev --remote --task harvest-covers
```

## What It Does

1. Reads curated book lists from `docs/testImages/csv-expansion/` (2015-2025)
2. Deduplicates by ISBN-13 (~500-775 unique books)
3. For each book:
   - Checks KV cache (skip if already harvested)
   - Queries ISBNdb API (with 1sec rate limit)
   - Falls back to Google Books if ISBNdb fails
   - Downloads cover image
   - Uploads to R2: `covers/isbn/{isbn13}.jpg`
   - Stores metadata in KV: `cover:{isbn}`
4. Logs failures to `failed_isbns.json`

## Expected Results

- **Coverage:** ~90% (700+/775 books)
- **ISBNdb Primary:** ~70% (avoid excessive fallback)
- **Execution Time:** ~13-15 minutes
- **Storage:** ~10-50MB in R2

## Post-Harvest Validation

```bash
# Verify R2 storage
npx wrangler r2 object list LIBRARY_DATA --prefix covers/isbn/ | wc -l

# Check KV metadata
npx wrangler kv:key get --binding=KV_CACHE "cover:9780451524935"

# Review failures
cat failed_isbns.json | jq '.totalFailed'
```

## Troubleshooting

**Rate limit errors:** ISBNdb has 5000 calls/day limit (should be fine for 775 books)

**R2 upload failures:** Check `LIBRARY_DATA` bucket exists and has write permissions

**No covers found:** Check ISBNdb subscription is still active

## Related Issues

- #202 - Harvest ISBNdb cover images before subscription expires
- #147 - Implement Edge Caching for Book Cover Images (R2 + Image Resizing)
- #201 - Remove ISBNdb dependency to reduce costs
