# BooksTrack Documentation Hub

**Version 3.7.5 (Build 189+)** | **Last Updated: January 6, 2026**

Welcome to the central documentation for BooksTrack V3. This directory contains all product, technical, and process documentation for the project.

---

## 🚀 Getting Started

- **[README.md](../README.md)** - Project overview, features, requirements
- **[AGENTS.md](../AGENTS.md)** - Universal AI agent guide (code style, architecture, contracts)
- **[CLAUDE.md](../CLAUDE.md)** - Claude Code workflows, MCP setup, testing commands
- **[TODO.md](../TODO.md)** - Current sprint tasks and priorities

---

## 📂 Directory Structure

### `docs/product/`
**Product Requirements (PRDs).** The "Why" and "What" of features.
- `Library-Management-PRD.md` - Core library functionality.
- `Diversity-Insights-PRD.md` - Analytics & representation logic.
- `Review-Queue-PRD.md` - Manual review process for AI features.

### `docs/features/`
**Implementation Details.** The "How" of specific features, bridging PRDs and code.
- **[GEMINI_CSV_IMPORT.md](./features/GEMINI_CSV_IMPORT.md)** - AI-powered CSV import.
- **[BOOKSHELF_SCANNER.md](./features/BOOKSHELF_SCANNER.md)** - Vision-based bulk import.
- **[BATCH_BOOKSHELF_SCANNING.md](./features/BATCH_BOOKSHELF_SCANNING.md)** - Concurrency logic for scanner.
- **[GOALS_ENGINE.md](./features/GOALS_ENGINE.md)** - Reading goals and progress tracking.
- **[FEATURE_FLAGS.md](./features/FEATURE_FLAGS.md)** - Feature flag system.

### `docs/architecture/`
**System Design.** High-level technical decisions and patterns.
- `VISUAL_DESIGN_SUMMARY.md` - iOS 26 Liquid Glass design system.
- `cascade-metadata.md` - How we merge data from multiple providers.
- `ratings-system.md` - Logic behind user ratings.
- `reading-sessions.md` - Timer & session state management.

### `docs/workflows/`
**Visual Flows.** Mermaid diagrams describing complex user or data flows.

### `docs/archive/`
**Archive.** Deprecated docs, shipped PRDs, and historical references.
- `CSV-Import-PRD.md` (Shipped)
- `Bookshelf-AI-Scanner-PRD.md` (Shipped)
- `Reading-Goals-PRD.md` (Shipped)
- `openapi-v3.json` (Legacy)

---

## 🔌 Integration & APIs

- **[Cross-Repository Architecture](./CROSS_REPO.md)** - Multi-repo system overview
- **[bendv3 API Documentation](~/dev_repos/bendv3/docs/)** - REST API, WebSocket, contracts (Authoritative Source)
- **[alex Metadata Service](~/dev_repos/alex/)** - Book metadata and cover images

---

## 🔍 How to find what you need

- **"I need to know how the API works."** -> `~/dev_repos/bendv3/docs/`
- **"I'm building a new feature."** -> Check `docs/product/` for requirements, then `docs/architecture/` for constraints.
- **"I'm fixing a bug in the scanner."** -> Read `docs/features/BOOKSHELF_SCANNER.md`.
- **"I'm confused about the project structure."** -> Read `AGENTS.md` in the root.

## 📝 Editing Documentation

1. **Keep it fresh.** If you change code, update the docs immediately.
2. **Standardize.** Use the templates in `docs/product/PRD-Template.md`.
3. **Move, don't delete.** Move outdated docs to `docs/archive/` rather than deleting them.
