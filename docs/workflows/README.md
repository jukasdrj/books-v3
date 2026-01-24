# BooksTrack Workflows

**Visual flow diagrams for complex user and data flows**

This directory is intended for Mermaid diagrams describing key workflows.

---

## Planned Workflows (Pending Migration)

The following workflows are planned for documentation:

- **Search and Enrichment** - Book search, multi-provider fallback, metadata enrichment
- **CSV Import** - CSV upload, parsing, validation, book matching
- **Bookshelf Scanning** - Photo upload, AI processing, review queue
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

**Last Updated:** January 2026
