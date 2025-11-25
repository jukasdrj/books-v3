# Search & Discovery Workflows

This document illustrates the primary user workflows for searching for books and discovering new ones.

## Unified Search Workflow

This diagram covers standard text search, ISBN barcode scanning, and the new AI-powered semantic search.

```mermaid
flowchart TD
    subgraph User Interaction
        A[User opens Search tab] --> B{Selects search mode};
        B --> BA[Types in search bar];
        B --> BB[Taps Scan ISBN];
    end

    subgraph API Calls
        BA --> C1[GET /api/v2/search?q=...&mode=text];
        BA --> C2[GET /api/v2/search?q=...&mode=semantic];
        BB --> D[GET /v1/search/isbn?isbn=...];
    end

    subgraph System Logic
        C1 --> E{Backend: Text Search};
        C2 --> F{Backend: Semantic Search using Vectorize};
        D --> G{Backend: ISBN Lookup};
    end

    subgraph UI Response
        E --> H[Display list of matching books];
        F --> H;
        G --> I[Display single book details];
    end

    A --> J[GET /api/v2/recommendations/weekly];
    J --> K{Backend: Fetch cached weekly picks};
    K --> L[Display Weekly Recommendations];

    H --> M{User selects a book};
    I --> M;
    M --> N[View book details];
    N --> O[GET /v1/search/similar?isbn=...];
    O --> P{Backend: Find similar books using Vectorize};
    P --> Q[Display list of similar books];

    style H fill:#c9f,stroke:#333,stroke-width:2px
    style I fill:#c9f,stroke:#333,stroke-width:2px
    style L fill:#c9f,stroke:#333,stroke-width:2px
    style Q fill:#c9f,stroke:#333,stroke-width:2px
```
