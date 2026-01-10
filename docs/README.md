# BooksTrack Documentation Hub

**Version:** 3.7.5 | **Last Updated:** January 6, 2026

Welcome to the central documentation for BooksTrack V3. This directory contains all product, technical, and process documentation for the project.

## 🚀 Getting Started

- **[AGENTS.md](../AGENTS.md)** - **Crucial.** Universal AI agent guide (code style, architecture, contracts).
- **[CLAUDE.md](../CLAUDE.md)** - Claude Code workflows, MCP setup, testing commands.
- **[TODO.md](../TODO.md)** - Current sprint tasks and priorities.
- **[CURRENT-STATUS.md](./CURRENT-STATUS.md)** - Active sprint progress and blockers.

---

## 📋 Product Documentation (`docs/product/`)
**The "Why" and "What" of features.**

- **[Library Management](./product/Library-Management-PRD.md)** - Core library functionality.
- **[Diversity Insights](./product/Diversity-Insights-PRD.md)** - Analytics & representation logic.
- **[Bookshelf AI Scanner](./product/Bookshelf-AI-Scanner-PRD.md)** - Vision-based bulk import requirements.
- **[CSV Import](./product/CSV-Import-PRD.md)** - Data migration capabilities.

---

## 🛠️ Feature Implementation (`docs/features/`)
**The "How" of specific features.**

- **[Bookshelf Scanner](./features/BOOKSHELF_SCANNER.md)** - Implementation details for the Vision+Gemini scanner.
- **[Batch Scanning](./features/BATCH_BOOKSHELF_SCANNING.md)** - Multi-image scanning architecture.
- **[Gemini CSV Import](./features/GEMINI_CSV_IMPORT.md)** - AI-driven CSV parsing logic.
- **[Feature Flags](./features/FEATURE_FLAGS.md)** - Flag management and rollout status.

---

## 🏗️ Architecture (`docs/architecture/`)
**System Design & Decisions.**

- **[Visual Design](./architecture/VISUAL_DESIGN_SUMMARY.md)** - iOS 26 Liquid Glass design system.
- **[Cascade Metadata](./architecture/cascade-metadata.md)** - Data merging strategy (Google Books -> OpenLibrary -> ISBNdb).
- **[Ratings System](./architecture/ratings-system.md)** - User rating logic.
- **[Reading Sessions](./architecture/reading-sessions.md)** - Session state machine.

---

## 🔌 Integration & APIs

- **[Cross-Repo Guide](./CROSS_REPO.md)** - Managing the `books-v3`, `bendv3`, and `alex` ecosystem.
- **[Backend API](~/dev_repos/bendv3/docs/)** - **Authoritative** source for REST & WebSocket contracts.

---

## 📚 Archive & Reference

- **[CHANGELOG.md](../CHANGELOG.md)** - Version history.
- **[Archive](./archive/)** - Deprecated documentation and completed PRDs.

---

## 📝 Editing Guidelines

1.  **Sync Reality:** If code changes, update the docs immediately.
2.  **Move, Don't Delete:** Archive outdated docs to `docs/archive/` instead of deleting.
3.  **Standardize:** Ensure new docs follow the project's header conventions.
