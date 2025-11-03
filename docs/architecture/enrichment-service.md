# Enrichment Service Architecture

## Overview

The Enrichment Service is a core component of the backend, responsible for augmenting book data with information from various external providers. It provides a unified interface for fetching comprehensive book details, ensuring data consistency and richness. The service is designed to be resilient, with a multi-provider fallback strategy to maximize data availability.

## Core Methods

### `enrichSingleBook`

- **Use Case:** This function is used for real-time, single-book enrichment. It's the ideal choice for operations like scanning a single ISBN or tapping on a book to get more details.
- **Priority:** Low latency. The goal is to return data to the user as quickly as possible.
- **Mechanism:** It queries providers sequentially until a definitive result is found.

### `enrichMultipleBooks`

- **Use Case:** This function is designed for asynchronous, batch-enrichment scenarios, such as importing a CSV of books or processing a newly-scanned bookshelf.
- **Priority:** High throughput and reliability. The system can take more time to process the batch, but it must be robust.
- **Mechanism:** It orchestrates multiple calls to `enrichSingleBook` and reports progress back to the client, often via WebSockets.

## Multi-Provider Fallback Strategy

The service queries multiple data providers to assemble the most complete record for a book. The current strategy is as follows:

1.  **Google Books API:** This is the primary data source. The service first attempts to fetch all available information from Google Books.
2.  **OpenLibrary API:** If the Google Books API fails or returns incomplete data, the service will then query the OpenLibrary API to fill in any missing fields (e.g., genres, author details, description).

This layered approach ensures that we can still provide a rich data set even if one provider has an incomplete entry for a particular book.

## Provenance Tracking

To maintain data integrity and for easier debugging, the service tracks the source of each piece of information. The final enriched book object includes a `provenance` map, which indicates which provider supplied the data for each field.

**Example:**

```json
{
  "title": "The Hobbit",
  "author": "J.R.R. Tolkien",
  "provenance": {
    "title": "GoogleBooks",
    "author": "OpenLibrary"
  }
}
```

This allows us to trace the origin of the data, understand which providers are most effective, and diagnose issues with specific data sources.
