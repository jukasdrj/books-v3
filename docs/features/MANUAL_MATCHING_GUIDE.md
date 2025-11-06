# Manual Book Matching Feature

## What is it?

When BooksTrack can't automatically find the right information for a book (like when scanning a blurry spine or importing from CSV), you can now search for and select the correct match yourself.

## When to use it

Use manual matching when:
- 📸 **Bookshelf scan** detected a book but got the title/author wrong
- 📊 **CSV import** failed to find metadata for some books
- 🔍 The auto-enrichment couldn't find a match

## How to use it

### From Review Queue

1. Open your **Library** tab
2. Look for the ⚠️ **Review Queue** button (with orange triangle icon)
3. Tap a book that needs review
4. Tap the blue **"Search for Match"** button
5. Search by:
   - **All** - Search everything (default)
   - **Title** - Search by book title only
   - **Author** - Search by author name only  
   - **ISBN** - Look up by ISBN number
6. Browse the results (with cover images!)
7. Tap the book that matches
8. Confirm the replacement
9. ✨ Your book is updated with the correct cover and metadata!

## What gets updated?

When you select a match, BooksTrack updates:
- ✅ Book title
- ✅ Author(s)
- ✅ Cover image
- ✅ Publication year
- ✅ Publisher info
- ✅ ISBN(s)
- ✅ Page count

**Don't worry!** Your personal data is safe:
- ❌ Reading status (Reading, To Read, etc.)
- ❌ Your rating
- ❌ Your notes
- ❌ Progress tracking

## Tips

- **Pre-filled search**: The search starts with your book's current title
- **Multiple scopes**: Can't find it with Title? Try searching by Author
- **Confirmation required**: You'll always see a confirmation dialog before replacing data
- **Undo-proof**: Once confirmed, the change can't be undone (but you can search again!)

## Example Scenarios

### Scenario 1: Blurry Bookshelf Scan
```
AI detected: "The Greet Gatsby" by "F. Scot Fitzgerald" ❌
You search: "Great Gatsby"
You select: "The Great Gatsby" by "F. Scott Fitzgerald" ✅
Result: Cover image + correct metadata!
```

### Scenario 2: CSV Import Failure  
```
CSV row: "Dune, Frank Herbert, 1965" ❌ No match found
You search: "Dune Herbert"
You select: "Dune" by "Frank Herbert" (1965) ✅
Result: Beautiful cover + all metadata populated!
```

### Scenario 3: Wrong Edition
```
AI found: Wrong cover image for your specific edition ❌
You search ISBN: "9780441013593"
You select: Exact edition with correct cover ✅
Result: Perfect match!
```

## Technical Details

### Search Sources
The feature searches across:
- **OpenLibrary** - Free, open book database
- **ISBNdb** - ISBN database with 7-day cache
- **Google Books** - Comprehensive book metadata

### Performance
- ⚡ Results appear in ~500ms (cached)
- 🌐 Up to 2 seconds for fresh searches
- 📦 Search results are cached for speed

### Data Safety
- All matches are applied **locally first**
- Changes sync to CloudKit **after** confirmation
- Your library entries are **never deleted**
- Failed matches **don't corrupt** your data

## Frequently Asked Questions

**Q: Can I undo a match?**  
A: No, but you can search again and select a different match.

**Q: What if I can't find my book?**  
A: Try different search scopes (Title, Author, ISBN) or search for a different edition.

**Q: Do I need internet?**  
A: Yes, manual matching requires internet to search book databases.

**Q: Is my data safe?**  
A: Absolutely! Personal data (ratings, notes, progress) is never touched.

**Q: Can I match multiple books at once?**  
A: Not yet! Currently one book at a time. Batch matching is planned for a future update.

## Future Enhancements

Coming soon:
- 🔄 Batch matching for CSV import failures
- 🎨 "Find Alternative Cover" in book detail view
- 🔍 Filter library by "Missing Covers"
- 📱 Quick match from library view

---

**Need help?** Check the main documentation at `docs/features/REVIEW_QUEUE.md` or file an issue on GitHub.
