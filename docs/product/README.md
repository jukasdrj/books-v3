# Product Requirements Documents

This directory contains platform-agnostic PRDs for BooksTrack features. Each PRD defines the **WHAT** and **WHY** of a feature, with platform-specific implementation notes in separate sections.

**Last Updated:** December 2025

---

## PRD Index

### Core Features

| Document | Status | Description |
|----------|--------|-------------|
| [Barcode-Scanner-PRD.md](../archive/product/Barcode-Scanner-PRD.md) | Shipped | ISBN barcode scanning for quick book entry |
| [Bookshelf-Scanner-PRD.md](../archive/product/Bookshelf-Scanner-PRD.md) | Shipped | AI-powered bookshelf photo scanning |
| [Gemini-CSV-Import-PRD.md](../archive/product/Gemini-CSV-Import-PRD.md) | Shipped | AI-powered CSV import from Goodreads/LibraryThing |
| [Book-Enrichment-PRD.md](../archive/product/Book-Enrichment-PRD.md) | Shipped | Metadata enrichment and book search |
| [Review-Queue-PRD.md](../archive/product/Review-Queue-PRD.md) | Shipped | Human verification for low-confidence AI detections |

### Library Management

| Document | Status | Description |
|----------|--------|-------------|
| [Library-Management-PRD.md](../archive/product/Library-Management-PRD.md) | Shipped | Reading status, filtering, reset, settings |
| [Reading-Statistics-PRD.md](../archive/product/Reading-Statistics-PRD.md) | Shipped | Reading progress and habit tracking |
| [Diversity-Insights-PRD.md](../archive/product/Diversity-Insights-PRD.md) | Shipped | Cultural diversity analytics |
| [Cloud-Sync-PRD.md](../archive/product/Cloud-Sync-PRD.md) | Shipped | Cross-device synchronization |

### Technical Contracts

| Document | Status | Description |
|----------|--------|-------------|
| [Canonical-Data-Contracts-PRD.md](../archive/product/Canonical-Data-Contracts-PRD.md) | Active | API data models and contracts |
| [Genre-Normalization-PRD.md](../archive/product/Genre-Normalization-PRD.md) | Active | Genre taxonomy and mapping rules |
| [DTOMapper-PRD.md](../archive/product/DTOMapper-PRD.md) | Active | Client-side data mapping patterns |

### Templates

| Document | Description |
|----------|-------------|
| [PRD-Template.md](PRD-Template.md) | Template for creating new PRDs |

---

## PRD Structure

Each PRD follows this platform-agnostic structure:

```
# Feature Name - PRD

## Executive Summary           # What and why
## Problem Statement           # User pain point
## Target Users                # Who benefits
## Success Metrics             # How we measure success
## User Stories                # Acceptance criteria
## Functional Requirements     # What the system does
## Data Models                 # Platform-agnostic (TypeScript/JSON)
## API Contracts               # Backend endpoints
## Testing Strategy            # Test categories

## Platform Implementation Notes
### iOS Implementation         # SwiftUI/SwiftData specifics
### Flutter Implementation     # Dart/Flutter specifics
### Android Implementation     # Kotlin/Android specifics
```

---

## Platform Implementation Status

| Feature | iOS | Flutter | Android |
|---------|-----|---------|---------|
| Barcode Scanner | Completed | Not Started | Not Started |
| Bookshelf AI Scanner | Completed | Not Started | Not Started |
| CSV Import | Completed | Not Started | Not Started |
| Book Enrichment | Completed | Not Started | Not Started |
| Review Queue | Completed | Not Started | Not Started |
| Library Management | Completed | Not Started | Not Started |
| Reading Statistics | Completed | Not Started | Not Started |
| Diversity Insights | Completed | Not Started | Not Started |
| Cloud Sync | Completed | Not Started | Not Started |

---

## Using PRDs for Flutter Development

When implementing a feature in Flutter:

1. **Read the PRD** - Understand the product requirements
2. **Check Data Models** - Use TypeScript interfaces as reference
3. **Review API Contracts** - Backend is shared across platforms
4. **See iOS Implementation** - Reference for expected behavior
5. **Update Flutter Status** - Mark "In Progress" when starting

### Common Flutter Packages

| Feature | Recommended Packages |
|---------|---------------------|
| Barcode Scanning | `mobile_scanner`, `permission_handler` |
| Camera/Photos | `image_picker`, `image` |
| HTTP/SSE | `dio`, `eventsource` |
| Local Storage | `drift`, `isar`, `hive_flutter` |
| State Management | `riverpod`, `bloc` |
| File Picker | `file_picker` |

---

## Archived PRDs

Archived PRDs are in the `../archive/product/` subdirectory.

---

## Contributing

When adding a new feature:

1. Copy `PRD-Template.md` to `Feature-Name-PRD.md`
2. Fill in all sections (mark N/A if not applicable)
3. Use TypeScript for data models (platform-agnostic)
4. Include iOS implementation notes if available
5. Add Flutter section (even if "Not Started")
6. Update this README index
