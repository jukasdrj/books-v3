# Product Requirements Documents

This directory contains platform-agnostic PRDs for BooksTrack features. Each PRD defines the **WHAT** and **WHY** of a feature.

**Last Updated:** January 2026

---

## PRD Index

### Active PRDs (In Development / Planned)

| Document | Description |
|----------|-------------|
| [Award-Tracking-PRD.md](Award-Tracking-PRD.md) | Track literary awards and nominations |
| [Reading-Goals-PRD.md](Reading-Goals-PRD.md) | Set and track reading goals |
| [Series-Tracking-PRD.md](Series-Tracking-PRD.md) | Manage book series and reading order |

### Technical Contracts

| Document | Status | Description |
|----------|--------|-------------|
| [Canonical-Data-Contracts-PRD.md](Canonical-Data-Contracts-PRD.md) | Active | API data models and contracts |

### Templates

| Document | Description |
|----------|-------------|
| [PRD-Template.md](PRD-Template.md) | Template for creating new PRDs |

---

## Implemented Features

Shipped features have been refactored into **Feature Documentation** and **Technical Designs**.

### Feature Documentation (`docs/features/`)

- **[Barcode Scanner](../features/ISBN_SCANNER.md)** - ISBN barcode scanning
- **[Bookshelf AI Scanner](../features/BOOKSHELF_SCANNER.md)** - AI-powered photo scanning
- **[CSV Import](../features/GEMINI_CSV_IMPORT.md)** - AI-powered CSV import
- **[Book Enrichment](../features/BOOK_ENRICHMENT.md)** - Metadata enrichment
- **[Review Queue](../features/REVIEW_QUEUE.md)** - Human verification for AI
- **[Library Management](../features/LIBRARY_MANAGEMENT.md)** - Core library features
- **[Reading Statistics](../features/READING_STATISTICS.md)** - Progress tracking
- **[Diversity Insights](../features/DIVERSITY_INSIGHTS.md)** - Cultural analytics
- **[Cloud Sync](../features/CLOUD_SYNC.md)** - Cross-device synchronization

### Technical Designs (`docs/architecture/`)

- **[DTO Mapper](../architecture/dto-mapper.md)** - Client-side data mapping
- **[Genre Normalization](../architecture/genre-normalization.md)** - Taxonomy rules

---

## Platform Implementation Status

See **[FLUTTER_FEATURE_PARITY.md](../FLUTTER_FEATURE_PARITY.md)** for detailed implementation status across iOS and Flutter.

---

## Archived PRDs

Archived PRDs are in the `archive/` subdirectory.
