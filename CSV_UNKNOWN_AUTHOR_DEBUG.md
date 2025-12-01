# CSV "Unknown Author" Issue - Debugging Guide

**Issue:** CSV imports showing "unknown author" despite having author data in the CSV file  
**Type:** Data Quality/Mapping Issue (NOT ResponseEnvelope parsing)  
**Status:** Requires investigation

---

## Problem Statement

User reports that CSV imports are completing successfully but books show "unknown author" in the app, even when the CSV file contains author information.

---

## Known Facts

1. ✅ **ResponseEnvelope Parsing:** CSV workflow uses ResponseEnvelope correctly
2. ✅ **API Communication:** No JSON decode errors, requests succeeding (200/202 status)
3. ❌ **Author Data:** Books imported without author information
4. ⚠️ **Data Flow:** Issue could be in CSV parsing, enrichment, or entity mapping

---

## Potential Root Causes

### 1. CSV Parsing Issue (Gemini AI Worker)

**Hypothesis:** Gemini Flash is not extracting author field from CSV

**Backend Location:** `bendv3/src/workers/csv-import.js` (or similar)

**Check:**
- Does CSV have "Author" or "author" column header?
- Is Gemini prompt instructing it to extract author field?
- Are author names in a parseable format?

**Expected Gemini Output:**
```json
{
  "books": [
    {
      "title": "Harry Potter and the Sorcerer's Stone",
      "authors": ["J.K. Rowling"],  // <-- Must be populated
      "isbn": "9780439064873"
    }
  ]
}
```

### 2. Enrichment Pipeline Issue (Alexandria/bendv3)

**Hypothesis:** Books enriched via Alexandria but author data not returned

**Flow:**
1. Gemini parses CSV → `{title, authors: ["Unknown"], isbn}`
2. bendv3 enriches via Alexandria → Alexandria has author data
3. bendv3 returns enriched book → **Author not included in response?**

**Check Backend Response:**
```bash
# Test Alexandria directly
curl -X POST https://alexandria.ooheynerds.com/api/enrich \
  -H "CF-Access-Client-Id: YOUR_ID" \
  -H "CF-Access-Client-Secret: YOUR_SECRET" \
  -d '{"isbn":"9780439064873"}' | jq .
```

**Expected Response:**
```json
{
  "success": true,
  "data": {
    "isbn": "9780439064873",
    "title": "Harry Potter and the Sorcerer's Stone",
    "authors": ["J.K. Rowling"],  // <-- Must be present
    "provider": "alexandria"
  }
}
```

### 3. DTO Mapping Issue (iOS ParsedBook → Book Entity)

**Hypothesis:** Author data in response but not mapped to SwiftData Book entity

**iOS Code to Check:**

**File:** `GeminiCSVImportService.swift` - ParsedBook Structure
```swift
public struct ParsedBook: Codable, Sendable, Equatable {
    public let title: String
    public let authors: [String]  // <-- Verify this is populated
    public let isbn: String?
    public let coverUrl: String?
    public let publisher: String?
    public let year: Int?
    public let pageCount: Int?
    public let enrichmentError: String?
}
```

**File:** Look for where ParsedBook is converted to SwiftData Book entity

**Search for:**
```bash
cd /Users/juju/dev_repos/books-v3
grep -r "ParsedBook" --include="*.swift" | grep -i "author"
```

### 4. Provider Chain Failure

**Hypothesis:** Alexandria cache miss, fallback providers also have no author data

**Provider Priority:**
1. Alexandria (PostgreSQL cache) - 78ms, 54.8M editions
2. Google Books (free fallback) - 200ms
3. OpenLibrary (free fallback) - 150ms
4. ISBNdb (premium, new books only) - $0.01/book

**Check:**
- Is ISBN valid and in Alexandria database?
- Do fallback providers have author data?
- Are there provider errors in bendv3 logs?

---

## Debugging Steps

### Step 1: Enable Debug Logging

**Add to GeminiCSVImportService.swift:**

```swift
// In fetchResults() method, after line 311
#if DEBUG
print("[CSV Results] ===== DETAILED BOOK DATA =====")
for (index, book) in results.books.enumerated() {
    print("[CSV Results] Book \(index + 1):")
    print("  Title: \(book.title)")
    print("  Authors: \(book.authors)")  // <-- KEY CHECK
    print("  ISBN: \(book.isbn ?? "none")")
    print("  Publisher: \(book.publisher ?? "none")")
    print("  Cover: \(book.coverUrl ?? "none")")
    print("  Enrichment Error: \(book.enrichmentError ?? "none")")
}
print("[CSV Results] ===============================")
#endif
```

### Step 2: Test CSV Import with Known Good Data

**Create Test CSV:** `test_csv_authors.csv`
```csv
Title,Author,ISBN
Harry Potter and the Sorcerer's Stone,J.K. Rowling,9780439064873
The Great Gatsby,F. Scott Fitzgerald,9780743273565
To Kill a Mockingbird,Harper Lee,9780061120084
```

**Import and Check Console:**
- Look for "Authors: [...]" in debug output
- Verify authors array is populated with actual names
- Check if enrichmentError field has any values

### Step 3: Verify Backend Enrichment Response

**Add Logging to Backend (if accessible):**

In bendv3 CSV import handler:
```javascript
console.log('CSV Import - Book Data:', {
  title: book.title,
  authors: book.authors,  // <-- Check this
  isbn: book.isbn,
  enrichmentProvider: book.provider
});
```

### Step 4: Check Author Mapping in iOS

**Find where CSV books are saved to SwiftData:**

```bash
cd /Users/juju/dev_repos/books-v3
grep -r "ParsedBook" --include="*.swift" -A 10 | grep -i "Book("
```

**Verify Author Assignment:**
```swift
// Expected pattern (example)
let book = Book(
    title: parsedBook.title,
    authors: parsedBook.authors.map { Author(name: $0) },  // <-- Must map authors
    isbn: parsedBook.isbn,
    // ...
)
```

---

## Test Cases

### Test Case 1: CSV with Valid Authors
```csv
Title,Author,ISBN
Harry Potter,J.K. Rowling,9780439064873
```

**Expected Result:** Book imported with author "J.K. Rowling"  
**Actual Result:** _[TO BE FILLED]_

### Test Case 2: CSV with Multiple Authors
```csv
Title,Author,ISBN
Good Omens,"Neil Gaiman, Terry Pratchett",9780060853983
```

**Expected Result:** Book with authors ["Neil Gaiman", "Terry Pratchett"]  
**Actual Result:** _[TO BE FILLED]_

### Test Case 3: CSV Missing Author Column
```csv
Title,ISBN
Some Book,9781234567890
```

**Expected Result:** Book imported, enrichment should fetch author from Alexandria  
**Actual Result:** _[TO BE FILLED]_

---

## Backend Investigation Commands

### Check Alexandria Database for Author Data
```bash
ssh root@Tower.local "docker exec postgres psql -U openlibrary -d openlibrary -c \"
  SELECT 
    ee.isbn,
    ee.title,
    ea.name as author_name,
    wae.author_order
  FROM enriched_editions ee
  JOIN work_authors_enriched wae ON ee.work_key = wae.work_key
  JOIN enriched_authors ea ON wae.author_key = ea.author_key
  WHERE ee.isbn = '9780439064873'
  ORDER BY wae.author_order;
\""
```

**Expected Output:**
```
     isbn      |                  title                  | author_name  | author_order
---------------+-----------------------------------------+--------------+--------------
 9780439064873 | Harry Potter and the Sorcerer's Stone  | J.K. Rowling |           0
```

### Check bendv3 Logs for CSV Import
```bash
# If using Cloudflare Workers
wrangler tail --format pretty | grep -i "csv\|author"

# Look for enrichment responses
```

---

## Quick Fixes (If Root Cause Found)

### If Gemini Parsing Issue:
1. Update Gemini prompt in bendv3 to emphasize author extraction
2. Add author field validation before storing results

### If Alexandria Enrichment Issue:
1. Verify Alexandria author query joins are correct
2. Check if `enriched_authors` table is populated
3. Verify `work_authors_enriched` relationships exist

### If iOS Mapping Issue:
1. Update ParsedBook → Book entity conversion
2. Ensure authors array is properly mapped to Author entities
3. Add default "Unknown Author" fallback if array is empty

### If Provider Chain Issue:
1. Add fallback to Google Books API for author data
2. Implement author extraction from OpenLibrary
3. Log which provider returned author data

---

## Success Criteria

✅ CSV import completes successfully  
✅ Debug logs show `Authors: ["J.K. Rowling"]` (not empty)  
✅ Book entity in SwiftData has populated authors array  
✅ UI displays author name correctly  
✅ All three test cases pass

---

## Related Files

**iOS:**
- `GeminiCSVImportService.swift` - CSV parsing response handling
- `EnrichedBookDTO.swift` - DTO structure (may need authors field)
- SwiftData Book entity - Final storage

**Backend:**
- `bendv3/src/workers/csv-import.js` - Gemini CSV parsing
- `bendv3/src/services/book-service.ts` - Alexandria enrichment
- `alex/src/index.ts` - Alexandria worker

**Database:**
- `enriched_authors` table - Author data
- `work_authors_enriched` table - Work↔Author relationships
- `enriched_editions` table - Edition metadata

---

**Created:** November 30, 2025, 21:15 CST  
**Priority:** P1 - Data Quality Issue  
**Impact:** All CSV imports affected
