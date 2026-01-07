# API Documentation

This directory contains the API specifications and contracts used by the BooksTrack iOS application.

## Specifications

- **[openapi-v3.json](./openapi-v3.json)**: The OpenAPI V3 specification used to generate the Swift client code. This file is a snapshot of `BooksTrackerPackage/Sources/BooksTrackerFeature/openapi.json` and defines the contract with the `bendv3` backend.

## Sources

- **Local Source**: `BooksTrackerPackage/Sources/BooksTrackerFeature/openapi.json` (Used by Swift OpenAPI Generator)
- **Backend Source**: `~/dev_repos/bendv3/docs/` (Authoritative backend documentation)

## Usage

The iOS app uses the Swift OpenAPI Generator plugin to generate type-safe networking code from `BooksTrackerPackage/Sources/BooksTrackerFeature/openapi.json`.

This `docs/api/openapi-v3.json` file is a **documentation snapshot only** and is not used by code generation. When the source OpenAPI spec changes:
1. Update `BooksTrackerPackage/Sources/BooksTrackerFeature/openapi.json` (triggers code regeneration)
2. Refresh `docs/api/openapi-v3.json` to keep this documentation current
