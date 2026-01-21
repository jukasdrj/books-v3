# BooksTrack API Documentation

**Status:** Synced Mirror
**Source:** `BooksTrackerPackage/Sources/BooksTrackerFeature/openapi.json`
**Authoritative Backend Docs:** `~/dev_repos/bendv3/docs/`

This directory contains the client-side representation of the BooksTrack API.

## Files

- **[openapi-v3.json](./openapi-v3.json)**: The OpenAPI Specification (v3) used to generate the Swift client code. This file is synced from the source code.

## Usage

This spec is used by the `DTOs` in `BooksTrackerPackage/Sources/BooksTrackerFeature/DTOs/`.
(Note: Helper scripts are currently unavailable in this environment).

## Key Endpoints (Summary)

*   `GET /v1/search/title`: Search for books by title.
*   `GET /v1/search/isbn`: Lookup book by ISBN.
*   `POST /api/scan-bookshelf/batch`: Upload photos for AI scanning.
*   `GET /ws/progress`: WebSocket for real-time job progress (CSV import, Bookshelf scan).

For full backend details, refer to the backend repository documentation.
