# API Documentation

This directory contains documentation related to the backend API contracts and specifications.

## Files

- **[openapi-v3.json](./openapi-v3.json)**: The OpenAPI specification for the V3 API. This is a copy of the authoritative source located at `BooksTrackerPackage/Sources/BooksTrackerFeature/openapi.json`.
- **[ENRICHMENT_API_CONTRACT.md](./ENRICHMENT_API_CONTRACT.md)**: Details on the enrichment API contract.

## Source of Truth

The authoritative OpenAPI specification is maintained in the `BooksTrackerPackage` source code:
`BooksTrackerPackage/Sources/BooksTrackerFeature/openapi.json`

Clients are generated using the `./Scripts/generate-api-client.sh` script (if available).
