# BooksTrack Workflows

**Visual flow diagrams for complex user and data flows**

This directory contains Mermaid diagrams describing key workflows in the BooksTrack application.

*Note: As of Jan 7, 2026, specific diagram files are still in development. Please refer to feature documentation for logic details.*

---

## Planned Workflows

### User Workflows
- **Search and Enrichment** - Book search, multi-provider fallback, metadata enrichment
- **CSV Import** - CSV upload, parsing, validation, book matching
- **Bookshelf Scanning** - Photo upload, AI processing, review queue

### Technical Workflows
- **WebSocket Progress** - Real-time progress tracking, reconnection handling
- **Authentication** - User login, token refresh, session management

---

## Creating Workflow Diagrams

### Mermaid Syntax
Use Mermaid diagram syntax for all workflows:

```markdown
\`\`\`mermaid
graph TD
    A[Start] --> B[Process]
    B --> C{Decision}
    C -->|Yes| D[Action 1]
    C -->|No| E[Action 2]
\`\`\`
```

---

**Last Updated:** January 7, 2026
