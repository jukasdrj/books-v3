# Backend Canonical Format Validation

Date: 2025-10-30

## Local Dev Validation (Limited)

**Status:** ✅ Server running, endpoints responding with 200 OK

**Limitations:** Google Books API secret not available in local dev
- Local server responds correctly but can't complete API calls
- Error handling working correctly (catches missing secret)

**Manual Test Commands:**
```bash
# v1 title search
curl "http://localhost:8787/v1/search/title?q=1984" | jq

# v1 ISBN search
curl "http://localhost:8787/v1/search/isbn?isbn=9780451524935" | jq

# v1 advanced search
curl "http://localhost:8787/v1/search/advanced?title=1984&author=Orwell" | jq
```

**Expected Structure (Production):**
```json
{
  "success": true,
  "data": {
    "works": [
      {
        "title": "1984",
        "googleBooksVolumeIDs": ["..."],
        "primaryProvider": "google-books",
        "contributors": ["google-books"],
        "synthetic": false
      }
    ],
    "authors": [
      { "name": "George Orwell", "gender": "Unknown" }
    ]
  },
  "meta": {
    "provider": "google-books",
    "cached": false,
    "timestamp": "2025-10-30T...",
    "processingTime": 123
  }
}
```

## Production Validation (Required)

**After deployment, verify:**

✅ /v1/search/title returns ApiResponse<BookSearchResponse>
✅ WorkDTO structure: title, authors, googleBooksVolumeIDs
✅ Enrichment WebSocket sends canonical format
✅ AI scanner WebSocket sends canonical format

**WebSocket Testing (Manual with wscat):**
```bash
# Terminal 1: Connect to WebSocket
wscat -c "wss://books-api-proxy.jukasdrj.workers.dev/ws/progress?jobId=test-enrichment"

# Terminal 2: Trigger enrichment
curl -X POST https://books-api-proxy.jukasdrj.workers.dev/api/enrichment/start \
  -H "Content-Type: application/json" \
  -d '{"jobId":"test-enrichment","workIds":["isbn:9780451524935"]}'
```

**Expected WebSocket Message:**
```json
{
  "progress": 1.0,
  "jobId": "test-enrichment",
  "result": {
    "success": true,
    "works": [WorkDTO],
    "editions": [EditionDTO],
    "authors": [AuthorDTO],
    "errors": []
  }
}
```

## Status

**Local:** ✅ Routing verified, error handling working
**Production:** ⏳ Awaiting deployment for full validation
