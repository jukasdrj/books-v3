# BooksTracker Documentation

Welcome to the documentation for BooksTracker. This directory is the central hub for all technical, product, and architectural documentation.

## Directory Structure

*   **[`api/`](./api/)**: API contracts and OpenAPI specifications.
    *   `openapi-v3.json`: The authoritative V3 API spec.
*   **[`architecture/`](./architecture/)**: High-level technical designs and decision records.
    *   `VISUAL_DESIGN_SUMMARY.md`: Overview of the "Liquid Glass" design system.
    *   `ratings-system.md`: Implementation of the 5-star rating system.
*   **[`features/`](./features/)**: Detailed implementation guides for specific features.
    *   `FEATURE_FLAGS.md`: Current state of feature flags.
    *   `GEMINI_CSV_IMPORT.md`: AI-driven CSV import logic.
    *   `GOALS_ENGINE.md`: Reading goals and statistics engine.
    *   `BOOKSHELF_SCANNER.md`: Vision-based bookshelf scanning.
*   **[`product/`](./product/)**: Product Requirement Documents (PRDs) for active and planned work.
    *   *Note: PRDs for shipped features are archived.*
*   **[`workflows/`](./workflows/)**: (Planned) Diagrams and workflow descriptions.
*   **[`archive/`](./archive/)**: Deprecated documentation and legacy files.

## Key Files

*   **[`CURRENT-STATUS.md`](./CURRENT-STATUS.md)**: The current health and progress of the project.
*   **[`CROSS_REPO.md`](./CROSS_REPO.md)**: Information about cross-repository dependencies.

## Contributing

*   **Source of Truth**: The code is the ultimate source of truth. Documentation should be updated to match the code.
*   **YOLO Mode**: Documentation updates are performed proactively to ensure sync.
