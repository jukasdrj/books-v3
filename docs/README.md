# BooksTrack Documentation Hub

Welcome to the central documentation for BooksTrack V3. This directory contains all product, technical, and process documentation for the project.

## 📂 Directory Structure

### `docs/api/`
**Contracts & Specs.** The source of truth for API interactions.
- `openapi-v3.json` - OpenAPI 3.1 Specification for REST API.
- `websocket-v2.md` - WebSocket protocol for real-time features (scanning, import).

### `docs/product/`
**Product Requirements (PRDs).** The "Why" and "What" of features.
- `Library-Management-PRD.md` - Core library functionality.
- `Diversity-Insights-PRD.md` - Analytics & representation logic.
- `Bookshelf-AI-Scanner-PRD.md` - Vision-based bulk import.
- `CSV-Import-PRD.md` - Data migration capabilities.
- ...and more.

### `docs/features/`
**Implementation Details.** The "How" of specific features, bridging PRDs and code.
- `book-details-redesign.md` - V3 detail view architecture.
- *(Coming Soon: Feature breakdowns for Scanner, Import, etc.)*

### `docs/architecture/`
**System Design.** High-level technical decisions and patterns.
- `cascade-metadata.md` - How we merge data from multiple providers.
- `ratings-system.md` - Logic behind user ratings.
- `reading-sessions.md` - Timer & session state management.
- `VISUAL_DESIGN_SUMMARY.md` - iOS 26 Liquid Glass design system.

### `docs/guides/`
**How-to Guides.** Instructions for developers and integrators.
- `FRONTEND_INTEGRATION.md` - Guide for web frontend integration.

### `docs/workflows/`
**Visual Flows.** Mermaid diagrams describing complex user or data flows.
*(Currently being populated)*

### `docs/archive/`
**Graveyard.** Obsolete PRDs, deprecated plans, and legacy V1/V2 docs.
- `v2-plans/` - Old sprint plans.
- Legacy PRDs (`Gemini-CSV-Import-PRD.md`, etc.).

---

## 🔍 How to find what you need

- **"I need to know how the API works."** -> `docs/api/`
- **"I'm building a new feature."** -> Check `docs/product/` for requirements, then `docs/architecture/` for constraints.
- **"I'm fixing a bug in the scanner."** -> Read `docs/product/Bookshelf-AI-Scanner-PRD.md` and check `docs/api/websocket-v2.md`.
- **"I'm confused about the project structure."** -> Read `AGENTS.md` in the root.

## 📝 Editing Documentation

1. **Keep it fresh.** If you change code, update the docs.
2. **Standardize.** Use the templates in `docs/product/PRD-Template.md`.
3. **Move, don't delete.** Move outdated docs to `docs/archive/` rather than deleting them, unless they are dangerously misleading.
