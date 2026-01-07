# Cross-Repository Architecture

**BooksTrack Multi-Repository System**
**Last Updated: January 6, 2026**

---

## 🏗️ System Overview

BooksTrack is built as a **multi-repository microservices architecture** with three main components:

```
┌─────────────────────────────────────────────────────────────┐
│                        User Devices                          │
│                  (iOS, Flutter, Android)                     │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    books-v3 (This Repo)                      │
│                     iOS Frontend Client                      │
│  - SwiftUI views, SwiftData persistence, CloudKit sync      │
│  - Search, Collections, Reading Sessions, Statistics        │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                   bendv3 (API Gateway)                       │
│              https://api.oooefam.net                         │
│  - User data, authentication, book enrichment orchestration │
│  - WebSocket progress tracking, CSV import, search API      │
└────────────┬───────────────────────────────────────┬────────┘
             │                                       │
             ▼                                       ▼
┌────────────────────────────┐    ┌────────────────────────────┐
│  alex (Metadata Service)   │    │  External APIs             │
│  Book metadata + covers    │    │  - Google Books            │
│  - ISBN lookups            │    │  - Open Library            │
│  - Cover image CDN         │    │  - ISBNdb                  │
└────────────────────────────┘    └────────────────────────────┘
```

---

## 📦 Repository Details

### books-v3 (This Repository)
**Path:** `~/dev_repos/books-v3/`
**Role:** iOS Frontend Client
**Tech Stack:** SwiftUI, SwiftData, CloudKit, iOS 26+

**Responsibilities:**
- User interface and interactions
- Local data persistence (SwiftData)
- CloudKit synchronization
- Offline-first reading experience
- Statistics and reading session tracking

**Key Documentation:**
- `CLAUDE.md` - Claude Code workflows, MCP setup
- `AGENTS.md` - Universal AI agent guide
- `docs/` - Feature specs, architecture, guides

---

### bendv3 (API Gateway)
**Path:** `~/dev_repos/bendv3/`
**Role:** Backend API Gateway & User Data Service
**Tech Stack:** Node.js, PostgreSQL, Redis, WebSocket
**Endpoint:** `https://api.oooefam.net`

**Responsibilities:**
- User authentication and account management
- Book search orchestration (multi-provider)
- Metadata enrichment workflows
- CSV import processing
- WebSocket progress tracking
- Reading list and collection sync

**Key Documentation:**
- `~/dev_repos/bendv3/docs/SYSTEM_ARCHITECTURE.md` - **Authoritative system architecture**
- `~/dev_repos/bendv3/docs/API.md` - REST API reference
- `~/dev_repos/bendv3/docs/WEBSOCKET.md` - WebSocket protocol
- `~/dev_repos/bendv3/CLAUDE.md` - Backend development guide

**API Version:** v2.4 (current), v3.0 (planned)

---

### alex (Metadata Service)
**Path:** `~/dev_repos/alex/`
**Role:** Book Metadata & Cover Image Service
**Tech Stack:** Python, FastAPI, PostgreSQL, CDN

**Responsibilities:**
- ISBN metadata lookups
- Cover image storage and CDN
- Metadata normalization
- Batch enrichment processing

**Key Documentation:**
- `~/dev_repos/alex/CLAUDE.md` - Metadata service guide
- `~/dev_repos/alex/docs/` - API reference, integration guides

---

## 🔌 Integration Points

### books-v3 ← bendv3
**Protocol:** REST API + WebSocket
**Authentication:** Bearer tokens (OAuth 2.0)
**Key Endpoints:**
- `GET /api/v2/search` - Multi-provider book search
- `POST /api/v2/books/enrich` - Metadata enrichment
- `POST /api/v2/imports/csv` - CSV import
- `WS /api/v2/ws` - Real-time progress updates

**Data Flow:**
```
User Action (books-v3) → API Request (bendv3) → Response
                      ↓
              WebSocket Progress Updates
```

---

### bendv3 ← alex
**Protocol:** REST API (internal)
**Key Operations:**
- ISBN metadata lookup
- Cover image retrieval
- Batch metadata enrichment

---

## 📚 When to Consult Which Repo

### books-v3 (This Repo)
**Use for:**
- SwiftUI view implementation
- SwiftData schema and persistence
- iOS-specific UI/UX questions
- CloudKit synchronization
- Reading session tracking
- Frontend feature specifications

---

### bendv3 Repo
**Use for:**
- **API contracts and endpoints** (authoritative source)
- **System architecture** (multi-repo overview)
- Authentication flows
- Search orchestration logic
- WebSocket protocol specifications
- CSV import format and processing
- Backend business logic
- Database schema (user data)

**⚠️ IMPORTANT:** All API documentation should reference bendv3 as the authoritative source. Do not duplicate API specs in books-v3.

---

### alex Repo
**Use for:**
- Metadata provider integration
- ISBN lookup specifications
- Cover image CDN usage
- Batch enrichment APIs

---

## 🔗 Documentation Cross-References

### From books-v3 to bendv3
- API contracts → `~/dev_repos/bendv3/docs/API.md`
- WebSocket protocol → `~/dev_repos/bendv3/docs/WEBSOCKET.md`
- System architecture → `~/dev_repos/bendv3/docs/SYSTEM_ARCHITECTURE.md`

### From books-v3 to alex
- Metadata lookups → `~/dev_repos/alex/docs/API.md`
- Cover images → `~/dev_repos/alex/docs/CDN.md`

### Shared Knowledge Base
**Path:** `~/.claude/knowledge-base/`

**Contents:**
- `patterns/` - SwiftData, Swift 6 concurrency patterns
- `architectures/` - API orchestration, multi-provider patterns
- `debugging/` - Real device testing, troubleshooting
- `decisions/` - Zero warnings policy, architectural decisions

---

## 🚀 Development Workflow

### Adding a New Feature

1. **Check cross-repo dependencies:**
   - Does it need new API endpoints? → Plan in bendv3 first
   - Does it need new metadata? → Consult alex repo

2. **Update documentation in correct repo:**
   - Frontend UI → books-v3 docs/
   - API changes → bendv3 docs/
   - Metadata changes → alex docs/

3. **Coordinate releases:**
   - Backend changes deploy first (bendv3/alex)
   - Frontend updates follow (books-v3)
   - Version compatibility maintained via API versioning

---

### Debugging Cross-Repo Issues

**Network issues:**
- Check bendv3 API logs first
- Verify authentication tokens
- Test WebSocket connections

**Data sync issues:**
- Check CloudKit sync (books-v3)
- Verify API responses (bendv3)
- Check metadata availability (alex)

---

## 📊 Version Compatibility

| books-v3 | bendv3 API | alex | Notes |
|----------|-----------|------|-------|
| v3.7.5 (Build 189+) | v2.4 | Current | Stable |
| v3.8.x (Planned) | v3.0 | Current | API v3 migration |

---

## 🔐 Environment Configuration

### books-v3 Configuration
```swift
// API endpoint configured in app
let apiBaseURL = "https://api.oooefam.net"
let apiVersion = "v2"
```

### Cross-Repo Environment Variables
- See bendv3 `.env.example` for backend configuration
- See alex `.env.example` for metadata service configuration

---

## 📝 Contributing Across Repos

### Making Changes That Span Multiple Repos

1. **Create feature branches in each repo:**
   ```bash
   # books-v3
   git checkout -b feature/new-search-ui

   # bendv3
   git checkout -b feature/search-api-v3
   ```

2. **Document dependencies:**
   - Note cross-repo PRs in PR descriptions
   - Link related PRs across repositories

3. **Test integration:**
   - Use bendv3 staging environment for frontend testing
   - Coordinate deployment timing

---

## 🆘 Getting Help

### Documentation Issues
- books-v3 docs: Update this repo
- bendv3 docs: Check `~/dev_repos/bendv3/docs/`
- alex docs: Check `~/dev_repos/alex/docs/`

### Cross-Repo Questions
- System architecture: `~/dev_repos/bendv3/docs/SYSTEM_ARCHITECTURE.md`
- API integration: `~/dev_repos/bendv3/docs/API.md`
- This guide: `docs/CROSS_REPO.md`

---

**Last Updated:** January 6, 2026
**Maintained by:** BooksTrack development team
