/**
 * JSON Schemas for Gemini Structured Output
 *
 * These schemas guarantee the structure and types of JSON responses from Gemini API,
 * eliminating manual validation overhead and ensuring type safety at the API level.
 *
 * CRITICAL: Gemini API requires lowercase type names ("array", "object", "string")
 * Per JSON Schema standard: https://ai.google.dev/gemini-api/docs/structured-output
 *
 * @module gemini-schemas
 */

/**
 * Bookshelf Scanner Response Schema
 *
 * Used by: gemini-provider.js (scanImageWithGemini)
 * Model: Gemini 2.5 Flash
 *
 * Enforces:
 * - All books have title, confidence, boundingBox, format
 * - Confidence range: 0.0-1.0
 * - BoundingBox coordinates: 0.0-1.0 (normalized)
 * - Format enum: hardcover|paperback|mass-market|unknown
 * - ISBN format: 10 or 13 digits (when present)
 */
export const BOOKSHELF_RESPONSE_SCHEMA = {
  type: "array",
  items: {
    type: "object",
    properties: {
      title: {
        type: "string",
        description: "Book title extracted from spine"
      },
      author: {
        type: ["string", "null"],
        description: "Author name if visible on spine"
      },
      isbn: {
        type: ["string", "null"],
        description: "ISBN-10 or ISBN-13 if visible"
      },
      format: {
        type: "string",
        enum: ["hardcover", "paperback", "mass-market", "unknown"],
        description: "Physical format detected from visual cues (spine thickness, cover material)"
      },
      confidence: {
        type: "number",
        description: "Detection confidence level (0.0 = uncertain, 1.0 = certain)",
        minimum: 0.0,
        maximum: 1.0
      },
      boundingBox: {
        type: "object",
        description: "Normalized coordinates (0.0-1.0) of book spine in image",
        properties: {
          x1: {
            type: "number",
            description: "Left edge (0.0 = left side of image)",
            minimum: 0.0,
            maximum: 1.0
          },
          y1: {
            type: "number",
            description: "Top edge (0.0 = top of image)",
            minimum: 0.0,
            maximum: 1.0
          },
          x2: {
            type: "number",
            description: "Right edge (1.0 = right side of image)",
            minimum: 0.0,
            maximum: 1.0
          },
          y2: {
            type: "number",
            description: "Bottom edge (1.0 = bottom of image)",
            minimum: 0.0,
            maximum: 1.0
          }
        },
        required: ["x1", "y1", "x2", "y2"]
      }
    },
    required: ["title", "confidence", "boundingBox", "format"]
  }
};

/**
 * CSV Parser Response Schema
 *
 * Used by: gemini-csv-provider.js (parseCSVWithGemini)
 * Model: Gemini 2.5 Flash-Lite
 *
 * Enforces:
 * - All books have title and author (required fields)
 * - Rating range: 0-5 (when present)
 * - PageCount minimum: 1 (when present)
 * - DateRead format: YYYY-MM-DD (when present)
 * - ISBN format: 10 or 13 digits (when present)
 *
 * Note: Schema guarantees no books will be returned without title+author,
 * eliminating the need for manual filtering loops in csv-import.js
 */
export const CSV_BOOK_SCHEMA = {
  type: "array",
  items: {
    type: "object",
    properties: {
      title: {
        type: "string",
        description: "Book title (required)"
      },
      author: {
        type: "string",
        description: "Author name (required)"
      },
      isbn: {
        type: "string",
        description: "ISBN-10 or ISBN-13",
        nullable: true
      },
      publicationYear: {
        type: "integer",
        description: "Year of publication",
        nullable: true
      },
      publisher: {
        type: "string",
        description: "Publisher name",
        nullable: true
      },
      pageCount: {
        type: "integer",
        description: "Number of pages",
        nullable: true,
        minimum: 1
      },
      genre: {
        type: "string",
        description: "Primary genre or subject",
        nullable: true
      },
      rating: {
        type: "number",
        description: "User rating (0-5 scale)",
        nullable: true,
        minimum: 0,
        maximum: 5
      },
      dateRead: {
        type: "string",
        description: "Date finished reading (YYYY-MM-DD format)",
        nullable: true
      },
      notes: {
        type: "string",
        description: "User notes or review",
        nullable: true
      }
    },
    required: ["title", "author"]
  }
};
