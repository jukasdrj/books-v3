# BooksTrack Documentation Hub

Welcome to the central documentation for BooksTrack V3. This directory contains all product, technical, and process documentation for the project.

## 📂 Directory Structure

### `docs/product/`
**Product Requirements (PRDs).** The "Why" and "What" of features.
- `Library-Management-PRD.md` - Core library functionality.
- `Diversity-Insights-PRD.md` - Analytics & representation logic.
- `Bookshelf-AI-Scanner-PRD.md` - Vision-based bulk import.
- `CSV-Import-PRD.md` - Data migration capabilities.
- ...and more.

### `docs/features/`
**Implementation Details.** The "How" of specific features, bridging PRDs and code.
- `GEMINI_CSV_IMPORT.md` - AI-powered CSV import details.
- `BOOKSHELF_SCANNER.md` - Single-shot bookshelf scanning.
- `BATCH_BOOKSHELF_SCANNING.md` - Multi-shot parallel scanning.
- `FEATURE_FLAGS.md` - Feature flag documentation.
- `book-details-redesign.md` - V3 detail view architecture.

### `docs/architecture/`
**System Design.** High-level technical decisions and patterns.
- `cascade-metadata.md` - How we merge data from multiple providers.
- `ratings-system.md` - Logic behind user ratings.
- `reading-sessions.md` - Timer & session state management.
- `VISUAL_DESIGN_SUMMARY.md` - iOS 26 Liquid Glass design system.

### `docs/CROSS_REPO.md`
**Multi-Repo Architecture.** Guide to BooksTrack's multi-repository system (books-v3, bendv3, alex).

### `docs/CURRENT-STATUS.md`
**Project Status.** Current sprint progress, active development, and blockers.

### `docs/workflows/`
**Visual Flows.** Mermaid diagrams describing complex user or data flows.
- See `docs/workflows/README.md` for available workflows and templates.

### `docs/archive/`
**Legacy & Deprecated.** Old PRDs, completed specs, and obsolete files.
- `openapi-v3.json` - Obsolete API spec (use bendv3 repo).

---

## 🔍 How to find what you need

- **"I need to know how the API works."** -> `~/dev_repos/bendv3/docs/` (authoritative source)
- **"I'm building a new feature."** -> Check `docs/product/` for requirements, then `docs/architecture/` for constraints.
- **"I'm fixing a bug in the scanner."** -> Read `docs/features/BOOKSHELF_SCANNER.md` and check `~/dev_repos/bendv3/docs/WEBSOCKET.md`.
- **"I'm confused about the project structure."** -> Read `AGENTS.md` in the root or `docs/CROSS_REPO.md`.

## 📝 Editing Documentation

1. **Keep it fresh.** If you change code, update the docs.
2. **Standardize.** Use the templates in `docs/product/PRD-Template.md`.
3. **Move, don't delete.** Move outdated docs to `docs/archive/` rather than deleting them, unless they are dangerously misleading.
