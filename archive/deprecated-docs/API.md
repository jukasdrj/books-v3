# BooksTrack API Documentation

**Version:** V3 (Active) / V2.4 (Legacy/Stable)

This document provides an overview of the BooksTrack API. The primary contract is defined using OpenAPI.

## API Specifications

- **OpenAPI V3 Spec:** [openapi-v3.json](./openapi-v3.json)
  - This is the source of truth for the V3 API.
  - Live spec available at: `https://api.oooefam.net/v3/openapi.json`

## Key API Concepts

### Base URLs
- **Production:** `https://api.oooefam.net`
- **Staging:** `https://staging-api.oooefam.net`
- **Local:** `http://localhost:8787`

### Authentication
- API calls typically require a Bearer token or specific headers depending on the endpoint.
- WebSocket connections use the `Sec-WebSocket-Protocol` header for authentication (see [AGENTS.md](../AGENTS.md) for details).

### Response Envelope (V2)
Standard response format for V1/V2 endpoints:
```swift
struct ResponseEnvelope<T: Codable>: Codable {
    let data: T?
    let metadata: ResponseMetadata
    let error: APIError?
}
```

### Real-time Updates
- **WebSockets:** Used for legacy progress tracking (being migrated to SSE).
- **Server-Sent Events (SSE):** The preferred method for real-time updates (e.g., CSV Import, Photo Scanning).
  - Protocol: HTTP/1.1 required.

## Endpoints Summary

### Search & Books
- `GET /v3/books/search`: Unified search (text, semantic).
- `GET /v3/books/{isbn}`: fast ISBN lookup.
- `POST /v3/books/enrich`: Batch metadata enrichment.

### Scanning & Imports
- `POST /api/scan-bookshelf/batch`: Upload photos for AI processing.
- `GET /ws/progress`: WebSocket progress tracking.
- `GET /v3/jobs/imports/{jobId}/results`: Fetch results for async jobs.

For detailed implementation guides, refer to:
- [Frontend Integration Guide](FRONTEND_INTEGRATION.md)
- [AGENTS.md](../AGENTS.md) (Backend API Contract section)
