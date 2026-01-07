# BooksTrack Workflows

**Visual flow diagrams for complex user and data flows**

This directory contains Mermaid diagrams describing key workflows in the BooksTrack application.

---

## Available Workflows

### User Workflows
- **[Search and Enrichment](./search-enrichment-flow.md)** - Book search, multi-provider fallback, metadata enrichment
- **[CSV Import](./csv-import-flow.md)** - CSV upload, parsing, validation, book matching
- **[Bookshelf Scanning](./bookshelf-scan-flow.md)** - Photo upload, AI processing, review queue

### Technical Workflows
- **[WebSocket Progress](./websocket-progress-flow.md)** - Real-time progress tracking, reconnection handling
- **[Authentication](./auth-flow.md)** - User login, token refresh, session management

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

### Diagram Types
- **Flowcharts** (`graph TD`, `graph LR`) - User flows, decision trees
- **Sequence Diagrams** (`sequenceDiagram`) - API interactions, WebSocket protocol
- **State Diagrams** (`stateDiagram-v2`) - State machines, lifecycle management

---

## Workflow Template

When creating a new workflow diagram, use this template:

```markdown
# [Workflow Name]

**Last Updated:** [Date]
**Related Features:** [Link to relevant PRDs/docs]

## Overview
[Brief description of what this workflow accomplishes]

## Participants
- **User:** [Role/actions]
- **Frontend (books-v3):** [Responsibilities]
- **Backend (bendv3):** [API endpoints involved]
- **External Services:** [Third-party APIs]

## Flow Diagram

\`\`\`mermaid
[Your diagram here]
\`\`\`

## Key Decision Points
1. **[Decision]:** [Criteria and outcomes]
2. **[Decision]:** [Criteria and outcomes]

## Error Handling
- **[Error Type]:** [Resolution strategy]
- **[Error Type]:** [Resolution strategy]

## Performance Considerations
- [Optimization notes]
- [Caching strategy]
- [Rate limiting]

## Related Documentation
- [Link to API docs in bendv3]
- [Link to feature specs]
- [Link to architecture docs]
```

---

## Planned Workflows

### High Priority
- [ ] Search and enrichment flow
- [ ] CSV import workflow
- [ ] Bookshelf scanning flow
- [ ] WebSocket progress tracking

### Medium Priority
- [ ] Authentication flow
- [ ] Reading session lifecycle
- [ ] CloudKit sync strategy
- [ ] Offline data handling

### Low Priority
- [ ] Statistics calculation
- [ ] Collection management
- [ ] Export functionality

---

## Tools

**Mermaid Live Editor:** https://mermaid.live/
Use for testing and previewing diagrams before committing.

**VS Code Extensions:**
- Markdown Preview Mermaid Support
- Mermaid Markdown Syntax Highlighting

**GitHub Rendering:**
GitHub automatically renders Mermaid diagrams in markdown files.

---

## Contributing

1. Create workflow diagram using template above
2. Test rendering in Mermaid Live Editor
3. Add to this README's "Available Workflows" section
4. Update "Planned Workflows" checklist
5. Link from relevant feature docs

---

**Last Updated:** January 6, 2026
**Maintained by:** BooksTrack development team
