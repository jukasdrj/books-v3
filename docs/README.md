# BooksTrack Documentation Hub

Welcome to the central documentation for BooksTrack V3. This directory contains all product, technical, and process documentation for the project.

## 📂 Directory Structure

### `docs/INDEX.md`
**Documentation Hub.** Quick navigation to all documentation resources.

### `docs/product/`
**Product Requirements (PRDs).** The "Why" and "What" of features.
- `Library-Management-PRD.md` - Core library functionality.
- `Diversity-Insights-PRD.md` - Analytics & representation logic.
- `Bookshelf-AI-Scanner-PRD.md` - Vision-based bulk import.
- `CSV-Import-PRD.md` - Data migration capabilities.
- `FLUTTER_PARITY.md` - Flutter parity roadmap and feature matrix.

### `docs/features/`
**Implementation Details.** The "How" of specific features, bridging PRDs and code.
- `book-details-redesign.md` - V3 detail view architecture.

### `docs/architecture/`
**System Design.** High-level technical decisions and patterns.
- `cascade-metadata.md` - How we merge data from multiple providers.
- `ratings-system.md` - Logic behind user ratings.
- `reading-sessions.md` - Timer & session state management.
- `VISUAL_DESIGN_SUMMARY.md` - iOS 26 Liquid Glass design system.

### `docs/api/`
**API Specifications.** Local snapshots of API contracts.
- `openapi-v3.json` - The OpenAPI spec used for Swift client generation.

### `docs/project/`
**Project Management.** Status, planning, and process.
- `STATUS.md` - Current sprint progress, active development, and blockers.

### `docs/CROSS_REPO.md`
**Multi-Repo Architecture.** Guide to BooksTrack's multi-repository system (books-v3, bendv3, alex).

### `docs/workflows/`
**Visual Flows.** Mermaid diagrams describing complex user or data flows.
- See `docs/workflows/README.md` for available workflows and templates.

---

## 🔍 How to find what you need

- **"I need to know how the API works."** -> Check `docs/api/` for the local spec or `~/dev_repos/bendv3/docs/` for authoritative backend docs.
- **"I'm building a new feature."** -> Check `docs/product/` for requirements, then `docs/architecture/` for constraints.
- **"I'm fixing a bug in the scanner."** -> Read `docs/product/Bookshelf-AI-Scanner-PRD.md` and check `~/dev_repos/bendv3/docs/WEBSOCKET.md`.
- **"I'm confused about the project structure."** -> Read `AGENTS.md` in the root or `docs/CROSS_REPO.md`.
- **"Where's the documentation hub?"** -> Start with `docs/INDEX.md`.

## 📝 Editing Documentation

1. **Keep it fresh.** If you change code, update the docs.
2. **Standardize.** Use the templates in `docs/product/PRD-Template.md`.
3. **Move, don't delete.** Move outdated docs to `docs/archive/` rather than deleting them, unless they are dangerously misleading.
