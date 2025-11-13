# BooksTrack System Architecture

**Version:** 3.0.0 (Build 47+)
**Last Updated:** November 13, 2025

This document outlines the high-level system design, architectural decisions, and trade-offs for BooksTrack.

---

## 🏗️ System Overview

### Three-Tier Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     iOS App (Swift/SwiftUI)                  │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │   SwiftUI   │  │   SwiftData  │  │  CloudKit Sync   │   │
│  │  Components │  │   (SQLite)   │  │   (Optional)     │   │
│  └─────────────┘  └──────────────┘  └──────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            ↓ HTTPS
┌─────────────────────────────────────────────────────────────┐
│              Cloudflare Workers API (Monolith)               │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │   Router    │  │   Services   │  │ Durable Objects  │   │
│  │  (RPC API)  │  │ (Business)   │  │  (WebSockets)    │   │
│  └─────────────┘  └──────────────┘  └──────────────────┘   │
│           ↓ KV Cache      ↓ R2 Storage    ↓ AI APIs         │
└─────────────────────────────────────────────────────────────┘
                            ↓ HTTPS
┌─────────────────────────────────────────────────────────────┐
│              External APIs & AI Providers                    │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │Google Books │  │ Open Library │  │  Gemini 2.0 Flash│   │
│  │     API     │  │     API      │  │   (Google AI)    │   │
│  └─────────────┘  └──────────────┘  └──────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## 📱 iOS App Architecture

### Package Structure

**Modular Package (`BooksTrackerPackage`):**
```
BooksTrackerPackage/
├── Sources/
│   ├── BooksTrackerFeature/        # UI + Feature logic
│   │   ├── Scanning/              # AI bookshelf scanner
│   │   ├── Search/                # Book search
│   │   ├── Library/               # User's collection
│   │   ├── Insights/              # Analytics
│   │   ├── Settings/              # Configuration
│   │   └── Shared/                # Reusable views + services
│   └── BooksTrackerCore/          # Models + backend
│       ├── Models/                # SwiftData @Model classes
│       ├── Services/              # API clients, enrichment
│       └── Utilities/             # Helpers, extensions
└── Tests/                         # Swift Testing suite
```

**App Shell (`BooksTracker/`):**
- Minimal wrapper around package
- Sets up ModelContainer, themes, environment
- Entry point: `BooksTrackerApp.swift`

**Design Decision:** Package-based architecture for:
- ✅ Faster compilation (incremental builds)
- ✅ Clear module boundaries
- ✅ Testability (unit test packages independently)
- ✅ Reusability (share Core across targets)

---

### Data Layer (SwiftData + CloudKit)

**SwiftData Models:**
- `Work` - Abstract creative work (book concept)
- `Edition` - Physical/digital manifestation (ISBN, cover, etc.)
- `Author` - Creator with diversity analytics
- `UserLibraryEntry` - User's reading record (status, rating, progress)

**Relationships:**
```
Work 1:many Edition
Work many:many Author
Work 1:many UserLibraryEntry
UserLibraryEntry many:1 Edition
```

**CloudKit Sync (Optional):**
- User can enable sync across devices
- Inverse relationships ONLY on to-many side (CloudKit requirement)
- All attributes have defaults (CloudKit requirement)
- All relationships optional (CloudKit requirement)

**Design Decision:** SwiftData over Core Data:
- ✅ Swift-first API (no NSManagedObject)
- ✅ @Model macro reduces boilerplate
- ✅ Predicate syntax more readable
- ✅ CloudKit sync built-in
- ❌ More restrictive relationship rules (trade-off)

---

### State Management (@Observable + @State)

**No ViewModels! Use `@Observable` models + `@State`.**

```swift
@Observable
class SearchModel {
    var state: SearchViewState = .initial(...)
    func search(_ query: String) async { ... }
}

struct SearchView: View {
    @State private var searchModel = SearchModel()
    // ...
}
```

**Design Decision:** @Observable over ObservableObject:
- ✅ Less boilerplate (no `@Published`)
- ✅ Swift 6 concurrency compatible
- ✅ More flexible (works outside SwiftUI)
- ✅ Better performance (fine-grained updates)

**Property Wrapper Usage:**
- `@State` - View-local state and model objects
- `@Observable` - Observable model classes
- `@Environment` - Dependency injection (ModelContext, ThemeStore)
- `@Bindable` - SwiftData models in child views (reactive updates)
- `@Query` - SwiftData queries (replaces `@FetchRequest`)

---

### Navigation (4-Tab Layout)

**Bottom Tab Bar:**
- Library (main collection, settings gear in toolbar)
- Search (book search + ISBN scanner)
- Shelf (AI bookshelf scanner)
- Insights (diversity analytics)

**Design Decision:** 4 tabs (not 5):
- ✅ iOS 26 HIG recommends 3-5 tabs (4 is optimal)
- ✅ Settings accessed via gear icon (Books.app pattern)
- ✅ Avoids "More" tab clutter
- ✅ Each tab has clear, distinct purpose

**Navigation Patterns:**
- Push navigation (`.navigationDestination`) for drill-down
- Sheet presentation (`.sheet`) for modals (Settings, etc.)
- NEVER use sheets for drill-down (breaks iOS 26 HIG)

---

## ☁️ Backend Architecture (Cloudflare Workers)

### Monolith Worker Pattern

**Single Worker (`api-worker`):**
```
api-worker/
├── index.js                       # Main router (RPC endpoints)
├── durable-objects/               # ProgressWebSocketDO
├── services/                      # Business logic
├── handlers/                      # Request handlers
└── utils/                         # Shared utilities
```

**Design Decision:** Monolith over microservices:
- ✅ Simpler deployment (single wrangler.toml)
- ✅ No network overhead (direct function calls)
- ✅ Easier debugging (single log stream)
- ✅ Lower latency (no inter-service HTTP)
- ✅ Cost-effective (single worker, not 5+)
- ❌ Less granular scaling (acceptable trade-off for current scale)

**Previous Architecture (Archived):**
- Distributed service bindings (rpc-api, image-proxy, ai-service, enrichment-service, books-api-proxy)
- Circular dependencies caused 520 errors
- Over-engineered for current scale
- See `cloudflare-workers/_archived/` for history

---

### Caching Strategy

**KV Cache:**
- `/v1/search/title` → 6 hours (frequent changes)
- `/v1/search/isbn` → 7 days (ISBN metadata stable)
- `/v1/search/advanced` → 6 hours
- Image URLs → 30 days (rarely change)

**R2 Storage:**
- Cover images (proxy + cache)
- AI scan job results (temporary, 7-day expiry)

**Cache Key Normalization:**
- `normalizeTitle()` - Remove articles (the/a/an), punctuation, lowercase
- `normalizeISBN()` - Strip hyphens and formatting
- `normalizeAuthor()` - Lowercase and trim
- `normalizeImageURL()` - Remove query params, force HTTPS
- Impact: +15-30% cache hit rate improvement

**Design Decision:** Aggressive caching for cost savings:
- ✅ Reduces API calls to Google Books (rate limits)
- ✅ Faster responses (KV < 10ms, R2 < 50ms)
- ✅ Lower costs ($0.50/million reads)
- ❌ Stale data risk (acceptable for book metadata)

---

### Real-Time Progress (Durable Objects)

**ProgressWebSocketDO:**
- Single Durable Object per background job
- WebSocket connection for real-time updates
- Shared by ALL background jobs (enrichment, bookshelf scan, CSV import)

**Protocol:**
```typescript
// Client → DO: Establish connection
GET /ws/progress?jobId={uuid}
Upgrade: websocket

// DO → Client: Progress updates
{ "type": "progress", "current": 5, "total": 10, "message": "Processing book 5..." }
{ "type": "complete", "result": {...} }
{ "type": "error", "message": "..." }
{ "type": "canceled" }
```

**Design Decision:** Durable Objects over polling:
- ✅ Real-time updates (8ms latency vs 2000ms polling)
- ✅ Battery-efficient (no repeated HTTP requests)
- ✅ Scalable (DO handles concurrency)
- ✅ Unified protocol (all jobs use same pattern)
- ❌ More complex (worth it for UX improvement)

---

### Canonical Data Contracts (v1.0.0)

**TypeScript-first API contracts:**

**DTOs:**
- `WorkDTO` - Mirrors SwiftData Work model
- `EditionDTO` - Multi-ISBN support (ISBN-10 + ISBN-13)
- `AuthorDTO` - Includes diversity analytics

**Response Envelope:**
```typescript
{
  success: boolean,
  data?: { works: WorkDTO[], authors: AuthorDTO[] },
  error?: { message: string, code: ApiErrorCode, details?: any },
  meta: { timestamp: string, processingTime: number, provider: string, cached: boolean }
}
```

**Provenance Tracking:**
- `primaryProvider` - Which API contributed the data ("google-books", etc.)
- `contributors` - Array of all enrichment providers
- `synthetic` - True if Work inferred from Edition data (enables iOS deduplication)

**Design Decision:** Canonical contracts for consistency:
- ✅ Single source of truth (TypeScript types)
- ✅ iOS Swift DTOs codegen from TypeScript
- ✅ Easier refactoring (changes in one place)
- ✅ Better error handling (typed errors)
- ✅ Provenance tracking (know data sources)

---

## 🤖 AI Integration

### Gemini 2.0 Flash (Google)

**Usage:**
- Bookshelf scanning (ISBN detection from camera images)
- CSV import (intelligent parsing with zero config)

**Why Gemini 2.0 Flash?**
- ✅ 2M token context window (handles large images)
- ✅ 25-40s processing time (acceptable for background jobs)
- ✅ High accuracy (0.7-0.95 confidence scores)
- ✅ Optimized for small text (ISBN detection on spines)
- ✅ Cost-effective ($0.075/1M tokens vs GPT-4 Vision $10/1M)

**Previous Providers (Removed):**
- Cloudflare Workers AI (Llama, LLaVA, UForm) → Too small context (8K-128K tokens)
- See GitHub Issue #134 for details

**Best Practices:**
- System instructions separated from dynamic content
- Image-first ordering in prompts
- Temperature: 0.2 (CSV), 0.4 (bookshelf)
- JSON output via `responseMimeType`
- Token usage logging (all responses include metrics)

---

### Multi-Model AI (Zen MCP)

**Zen MCP Integration:**
- Multi-provider AI (Google, OpenAI, X.AI)
- Cost-optimized model selection
- 10+ specialized tools (codereview, debug, planner, etc.)

**Model Selection Strategy:**
| Task Type | Preferred Models |
|-----------|-----------------|
| Code Review | Gemini 2.5 Pro, Claude Sonnet 4, GPT-5 |
| Debugging | Gemini 2.5 Pro, DeepSeek, Claude Sonnet 4 |
| Refactoring | Qwen Coder, DeepSeek, Claude Sonnet 4 |
| Architecture | Claude Opus 4, GPT-5, Gemini 2.5 Pro |
| Quick Tasks | Flash Thinking, DeepSeek, Llama |

**Cost Optimization:**
- 80% of tasks use local Haiku (free with Claude Max)
- 15% use cost-effective models (Grok Code, Gemini PC)
- 5% use premium models (O3 Pro, Gemini 2.5 Pro)
- Result: ~$2-5/month vs $50-100/month unoptimized

---

## ⚡ Performance Optimizations

### App Launch (600ms - Nov 2025)

**Optimization Strategy:**
1. **Lazy ModelContainer Init** - Created on first access (not at app init)
2. **Background Task Deferral** - 2-second delay with low priority
3. **Micro-optimizations** - Early exits, caching, predicate filtering

**Results:**
- Before: 1500ms cold launch
- After: 600ms cold launch (60% faster!)

**Components:**
- `ModelContainerFactory` - Lazy singleton pattern
- `BackgroundTaskScheduler` - Task deferral coordinator
- `LaunchMetrics` - Performance tracking (debug builds)

**Task Prioritization:**
- **Immediate:** UI rendering, ModelContainer (on-demand)
- **Deferred (2s):** EnrichmentQueue, ImageCleanup, SampleData, Notifications

---

### Database Query Optimization

**Techniques:**
1. **`fetchCount()` over `fetch().count`** - 10x faster for counts
2. **Predicate filtering** - Filter at database level, not in-memory
3. **Batch fetching** - Reduce N+1 queries

**Examples:**
```swift
// ✅ FAST: fetchCount() - 0.5ms for 1000 books
let count = try modelContext.fetchCount(FetchDescriptor<Work>())

// ❌ SLOW: fetch().count - 50ms for 1000 books
let works = try modelContext.fetch(FetchDescriptor<Work>())
let count = works.count

// ✅ FAST: Predicate filtering - 3-5x faster
let descriptor = FetchDescriptor<UserLibraryEntry>(
    predicate: #Predicate { $0.status == .reading }
)
let reading = try modelContext.fetch(descriptor)

// ❌ SLOW: In-memory filtering
let all = try modelContext.fetch(FetchDescriptor<UserLibraryEntry>())
let reading = all.filter { $0.status == .reading }
```

---

### Image Loading Optimization

**Image Proxy (#147):**
- All covers routed through `/images/proxy` endpoint
- R2 caching (50%+ faster loads)
- Backend normalization + caching

**Cache Key Normalization (#197):**
- Shared utilities normalize URLs, ISBNs, titles
- +15-30% cache hit rate improvement (60-70% → 75-90%)

**Client-Side:**
- `CachedAsyncImage` for automatic memory + disk caching
- Intelligent fallback (Edition → Work → placeholder)
- `CoverImageService` centralizes logic

---

## 🔐 Security Architecture

### API Keys & Secrets

**Storage:**
- iOS: Environment variables (debug), Keychain (release)
- Backend: Cloudflare Secrets (wrangler secret put)
- NEVER hardcode in source code

**Rotation:**
- Gemini API keys rotated quarterly
- Cloudflare API tokens rotated semi-annually
- Documented in `docs/security/key-rotation.md`

---

### Data Privacy

**User Data:**
- All reading data stored locally (SwiftData)
- CloudKit sync optional (user opt-in)
- No analytics without consent
- GDPR-compliant data export (Settings → Export Library)

**API Data:**
- Book metadata cached (KV/R2) for performance
- No PII stored in backend
- Cover images proxied (no direct user IP to Google Books)

---

## 🚀 Deployment Architecture

### iOS App Distribution

**App Store:**
- Bundle ID: `Z67H8Y8DW.com.oooefam.booksV3`
- TestFlight beta program (50 testers)
- Auto-updates via App Store Connect

**Build Pipeline:**
- Manual builds via Xcode (for now)
- Future: GitHub Actions CI/CD (planned)

---

### Cloudflare Workers Deployment

**Wrangler CLI:**
```bash
# Deploy to production
wrangler deploy

# Deploy with secrets
wrangler secret put GEMINI_API_KEY

# Tail logs
wrangler tail api-worker
```

**GitHub Actions (Future):**
- Auto-deploy on merge to main
- Preview deployments for PRs
- Health checks post-deploy

---

## 📊 Monitoring & Observability

### iOS App

**Metrics:**
- Launch time (LaunchMetrics in debug builds)
- Query performance (database timings)
- Image load times (network metrics)

**Logging:**
- OSLog framework (structured logging)
- Log levels: debug, info, warning, error
- Redacted PII (ISBN, titles, authors)

**Future:**
- Crashlytics (planned)
- Firebase Analytics (opt-in)

---

### Backend

**Cloudflare Analytics:**
- Request volume (RPM, RPS)
- Error rates (4xx, 5xx)
- Cache hit ratios (KV, R2)
- Latency (p50, p95, p99)

**Logging:**
- `wrangler tail` for real-time logs
- `console.log()` for debugging
- Structured logs (JSON format)

**Future:**
- Sentry error tracking (planned)
- Custom dashboards (Grafana)

---

## 🔄 Data Flow Examples

### Adding a Book (Manual)

```
User enters ISBN
    ↓
SearchView calls APIClient.searchISBN(isbn)
    ↓
Cloudflare Worker /v1/search/isbn
    ↓
Check KV cache (hit: return cached, miss: continue)
    ↓
Google Books API (fetch metadata)
    ↓
Normalize to WorkDTO/EditionDTO/AuthorDTO
    ↓
Cache in KV (7 days)
    ↓
Return canonical response
    ↓
iOS DTOMapper converts to SwiftData models
    ↓
Insert Work, Edition, Author, UserLibraryEntry
    ↓
Save to SwiftData (permanent IDs assigned)
    ↓
EnrichmentQueue.enqueue(work.persistentModelID)
    ↓
Background: POST /v1/enrichment/batch
    ↓
WebSocket progress updates (real-time)
    ↓
iOS applies enriched data (genres, covers, etc.)
    ↓
Save to SwiftData (updates existing models)
    ↓
UI reflects updates (SwiftData @Query reactive)
```

---

### AI Bookshelf Scan

```
User captures photo
    ↓
ShelfScannerView preprocesses (resize to 3072px @ 90% quality)
    ↓
POST /api/scan-bookshelf with photo + jobId
    ↓
Cloudflare Worker uploads to R2
    ↓
WebSocket connection established (GET /ws/progress?jobId=...)
    ↓
Worker calls Gemini 2.0 Flash API (vision + JSON schema)
    ↓
Gemini processes image (25-40s)
    ↓
Returns DetectedBook[] with confidence scores
    ↓
Worker enriches each ISBN via /v1/search/isbn
    ↓
WebSocket sends progress updates (8ms latency)
    ↓
iOS receives results (WorkDTO[])
    ↓
DTOMapper converts to SwiftData models
    ↓
Low confidence (<0.6) → Review Queue
    ↓
High confidence (≥0.6) → Library directly
    ↓
EnrichmentQueue processes all books in background
    ↓
UI updates reactively (SwiftData @Query)
```

---

## 🛠️ Architectural Decisions

### ADR-001: Monolith Worker Over Microservices
**Context:** Previous distributed architecture (5 workers) had circular dependencies and 520 errors.
**Decision:** Consolidate to single monolith worker.
**Rationale:** Simpler deployment, lower latency, easier debugging, cost-effective.
**Status:** Implemented (Oct 2025)

---

### ADR-002: SwiftData Over Core Data
**Context:** Need persistent storage with CloudKit sync.
**Decision:** Use SwiftData exclusively.
**Rationale:** Swift-first API, less boilerplate, CloudKit sync built-in.
**Trade-offs:** More restrictive relationship rules (acceptable).
**Status:** Implemented (v1.0.0)

---

### ADR-003: @Observable Over ObservableObject
**Context:** Need reactive state management in Swift 6.
**Decision:** Use `@Observable` + `@State`, not `ObservableObject` + `@Published`.
**Rationale:** Less boilerplate, better concurrency support, more flexible.
**Status:** Implemented (v3.0.0)

---

### ADR-004: Durable Objects Over Polling
**Context:** Need real-time progress for background jobs.
**Decision:** Use WebSocket via Durable Objects.
**Rationale:** 8ms latency (vs 2000ms polling), battery-efficient, scalable.
**Trade-offs:** More complex implementation (worth it for UX).
**Status:** Implemented (v3.0.0)

---

### ADR-005: Gemini 2.0 Flash Over Cloudflare AI
**Context:** Need vision AI for bookshelf scanning.
**Decision:** Use Gemini 2.0 Flash (Google), remove Cloudflare AI.
**Rationale:** 2M token context (vs 8K-128K), better accuracy, handles large images.
**Status:** Implemented (v3.1.0)

---

## 🚀 Future Architectural Improvements

### Planned (2025)
- [ ] GitHub Actions CI/CD for iOS builds
- [ ] Sentry error tracking (iOS + backend)
- [ ] Firebase Analytics (opt-in)
- [ ] Custom domain for backend (api.bookstrack.com)

### Under Consideration
- [ ] Multi-tenant backend (support multiple apps)
- [ ] Edge caching with Cloudflare Pages (static assets)
- [ ] Background sync with CloudKit (automatic, not manual)
- [ ] Offline mode (queue changes, sync when online)

---

**This architecture is optimized for a single developer + AI team. Scale decisions deferred until needed.**
