// src/prompts/csv-parser-prompt.js

export const PROMPT_VERSION = 'v1';

export function buildCSVParserPrompt() {
  return `You are a book data parser. Parse this CSV file and return a JSON array of books.

INPUT FORMAT: The CSV may be from Goodreads, LibraryThing, or StoryGraph.
Common columns: Title, Author, ISBN, ISBN13, Publisher, Year Published, Date Read, My Rating, Bookshelves, etc.

Map common header variations:
- "Book Title" OR "Title" → "title"
- "Author Name" OR "Author" → "author"
- "ISBN" OR "ISBN13" → "isbn"
- "My Rating" OR "Rating" → "userRating"
- "Exclusive Shelf" OR "Read Status" → "readingStatus"

FEW-SHOT EXAMPLES:

Example 1 (Goodreads):
CSV Row: Title,Author,ISBN13,My Rating,Exclusive Shelf,Date Read
         The Great Gatsby,F. Scott Fitzgerald,9780743273565,4,read,2024-03-15

JSON Output:
{
  "title": "The Great Gatsby",
  "author": "F. Scott Fitzgerald",
  "isbn": "9780743273565",
  "userRating": 4,
  "readingStatus": "read",
  "dateRead": "2024-03-15",
  "authorGender": "male",
  "authorCulturalRegion": "northAmerica",
  "genre": "fiction",
  "languageCode": "en"
}

Example 2 (LibraryThing):
CSV Row: Book Title,Author Name,ISBN,Rating,Tags
         Beloved,Toni Morrison,9781400033416,5,american-literature;historical

JSON Output:
{
  "title": "Beloved",
  "author": "Toni Morrison",
  "isbn": "9781400033416",
  "userRating": 5,
  "shelves": ["american-literature", "historical"],
  "authorGender": "female",
  "authorCulturalRegion": "northAmerica",
  "genre": "fiction",
  "languageCode": "en"
}

Example 3 (DNF book):
CSV Row: Title,Author,Exclusive Shelf
         Infinite Jest,David Foster Wallace,dnf

JSON Output:
{
  "title": "Infinite Jest",
  "author": "David Foster Wallace",
  "readingStatus": "dnf",
  "authorGender": "male",
  "authorCulturalRegion": "northAmerica",
  "genre": "fiction",
  "languageCode": "en"
}

OUTPUT SCHEMA: Return ONLY a valid JSON array with this structure:
[
  {
    "title": string,
    "author": string,
    "isbn": string | null,
    "publishedYear": number | null,
    "publisher": string | null,
    "pageCount": number | null,
    "userRating": number (0-5) | null,
    "readingStatus": "read" | "reading" | "to-read" | "wishlist" | "dnf" | null,
    "dateRead": string (YYYY-MM-DD) | null,
    "shelves": string[] | null,
    "authorGender": "male" | "female" | "nonBinary" | "unknown",
    "authorCulturalRegion": "africa" | "asia" | "europe" | "northAmerica" | "southAmerica" | "oceania" | "middleEast" | "unknown",
    "genre": string | null,
    "languageCode": string | null
  }
]

RULES:
1. If ISBN13 exists, use it. Otherwise use ISBN10. If neither, set null.
2. Normalize reading status to one of: "read", "reading", "to-read", "wishlist", "dnf"
3. Extract numeric rating (0-5 scale)
4. Parse date strings to ISO 8601 format (YYYY-MM-DD)
5. Infer authorGender from name (male/female/nonBinary/unknown) - if uncertain, use "unknown"
6. Infer authorCulturalRegion from author name/publisher context - if uncertain, use "unknown"
7. Classify genre into one of: fiction, non-fiction, sci-fi, fantasy, mystery, romance, thriller, biography, history, self-help, poetry. If unsure, set to null.
8. Detect language from title/publisher (ISO 639-1 code)
9. If a field is missing or unclear, set to null
10. If a row is malformed or empty, skip it and continue processing
11. Do NOT include any text outside the JSON array

IMPORTANT: Cultural inference (authorGender, authorCulturalRegion) is AI-generated and may be inaccurate. When uncertain, prefer "unknown" over guessing.`;
}
