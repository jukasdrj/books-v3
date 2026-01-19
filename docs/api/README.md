# BooksTrack API Documentation

**Authoritative Source:** `~/dev_repos/bendv3/docs/`

> **Note:** The backend API documentation in the `bendv3` repository is the single source of truth for API contracts, WebSocket protocols, and system architecture.

## Resources

- **[OpenAPI Specification (v3)](./openapi-v3.json)** - Local copy of the OpenAPI spec used for client generation.
- **[Cross-Repository Architecture](../CROSS_REPO.md)** - Overview of how the iOS app interacts with the backend services.

## Local Development

The local copy of `openapi-v3.json` in this directory is used by the iOS project to generate the API client code. It should be kept in sync with the backend specification.

To regenerate the client:
```bash
./Scripts/generate-api-client.sh
```

## API Endpoint Summary

See `openapi-v3.json` for full details.

- **Discovery:** `/v3/capabilities`, `/v3/recommendations/weekly`
- **Books:** `/v3/books/search`, `/v3/books/{isbn}`, `/v3/books/enrich`
- **Jobs:** `/v3/jobs/imports` (CSV), `/v3/jobs/scans` (Vision), `/v3/jobs/enrichment`
- **Webhooks:** `/v3/webhooks/alexandria/enrichment-complete`
