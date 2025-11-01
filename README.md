# 📚 BooksTrack by oooe

**Version 3.0.0** | **iOS 26.0+** | **Swift 6.1+**

A modern iOS book tracking application with cultural diversity insights, powered by SwiftUI, SwiftData, and Cloudflare Workers. Track your reading journey, discover diverse voices, and gain insights into your literary preferences.

**🎉 NOW AVAILABLE ON THE APP STORE!**

---

## ✨ Features

### 📖 Core Book Tracking
- **Smart Library Management** - Track books with Work/Edition architecture for proper handling of multiple formats
- **Reading Status Workflow** - Wishlist → Owned → Reading → Read with progress tracking
- **ISBN Barcode Scanner** - VisionKit-powered scanning for instant book lookup
- **Advanced Search** - Multi-field search across titles, authors, and ISBNs

### 🤖 AI-Powered Features
- **Bookshelf Scanner** - Photograph your bookshelf and let Gemini 2.0 Flash identify books automatically
- **Batch Scanning** - Process up to 5 photos in one session with real-time progress tracking
- **AI CSV Import** - Zero-configuration CSV import using Gemini to intelligently parse any format
- **Smart Enrichment** - Automatic metadata enhancement from multiple data providers

### 📊 Cultural Insights
- **Diversity Analytics** - Track representation across gender, cultural regions, and marginalized voices
- **Reading Statistics** - Visualize your reading patterns and preferences
- **Author Demographics** - Automatic detection and categorization

### 🎨 Design & Accessibility
- **iOS 26 Liquid Glass** - Modern design system with 5 built-in themes
- **WCAG AA Compliant** - 4.5:1+ contrast ratios for optimal readability
- **CloudKit Sync** - Seamless syncing across all your Apple devices
- **Dark Mode Support** - Full light/dark theme adaptation

---

## 🚀 Getting Started

### Prerequisites

**iOS Development:**
- Xcode 16.0+
- iOS 26.0+ SDK
- Swift 6.1+
- Apple Developer Account (for device testing)

**Backend Development:**
- Node.js 18.0+
- npm or yarn
- Cloudflare account (for Workers deployment)
- Wrangler CLI

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/jukasdrj/books_tracker_v1.git
   cd books-tracker-v1
   ```

2. **Install dependencies:**
   ```bash
   npm install
   ```

3. **Open the Xcode workspace:**
   ```bash
   open BooksTracker.xcworkspace
   ```

4. **Configure signing:**
   - Select the BooksTracker target
   - Update Team and Bundle Identifier in Signing & Capabilities
   - Bundle ID: `Z67H8Y8DW.com.oooefam.booksV3`

5. **Build and run:**
   - Select your target device or simulator
   - Press `Cmd + R` to build and run

### Backend Setup

1. **Navigate to workers directory:**
   ```bash
   cd cloudflare-workers
   ```

2. **Configure Wrangler:**
   ```bash
   npx wrangler login
   ```

3. **Deploy the API worker:**
   ```bash
   npm run deploy:all
   ```

4. **Verify deployment:**
   ```bash
   curl "https://books-api-proxy.jukasdrj.workers.dev/health"
   ```

---

## 💡 Usage

### Adding Books

**Manual Search:**
1. Tap the **Search** tab
2. Enter book title, author, or ISBN
3. Select from results
4. Choose reading status and edition

**ISBN Scanner:**
1. Tap the **Search** tab
2. Tap the barcode icon
3. Point camera at book's ISBN barcode
4. Confirm the detected book

**Bookshelf Scanner:**
1. Tap the **Shelf** tab
2. Photograph your bookshelf
3. Review AI-detected books (60%+ confidence)
4. Confirm or correct detections
5. Books auto-import to your library

**CSV Import:**
1. Settings → Library Management → "AI-Powered CSV Import"
2. Select CSV file (Goodreads export supported)
3. Gemini AI auto-detects columns
4. Books import instantly, enrich in background

### Managing Your Library

**Update Reading Status:**
- Tap any book in Library tab
- Use status picker: Wishlist → Owned → Reading → Read
- Track current page for in-progress books

**Add Ratings & Reviews:**
- Open book detail view
- Tap star rating (1-5 stars)
- Add personal notes
- Save to sync across devices

**View Insights:**
- Tap **Insights** tab
- Explore reading statistics
- Review diversity analytics
- Track reading goals

---

## 🛠 Tech Stack

### iOS Application
- **SwiftUI** - Modern declarative UI framework
- **SwiftData** - Persistent data storage with CloudKit sync
- **Swift 6.1** - Strict concurrency with actors and @MainActor
- **Swift Testing** - Modern testing framework with @Test and #expect
- **VisionKit** - Native barcode scanning
- **AVFoundation** - Camera integration for bookshelf scanner

### Backend Services
- **Cloudflare Workers** - Serverless edge computing
- **Durable Objects** - Stateful WebSocket connections for real-time progress
- **KV Storage** - Distributed caching (6h-7d TTL)
- **R2 Object Storage** - Image storage for bookshelf scans
- **Gemini 2.0 Flash** - AI vision model for image recognition and CSV parsing

### APIs & Data Providers
- **Google Books API** - Primary book metadata source
- **OpenLibrary** - Secondary enrichment data
- **Canonical Data Contracts** - TypeScript-first API contracts (v1.0.0)

---

## 📁 Project Structure


books-tracker-v1/
├── BooksTracker/                      # iOS app shell
│   ├── BooksTrackerApp.swift         # App entry point
│   └── Assets.xcassets/              # App icons & colors
│
├── BooksTrackerPackage/              # Swift Package
│   ├── Sources/
│   │   └── BooksTrackerFeature/      # Main feature module
│   │       ├── Models/               # SwiftData models (Work, Edition, Author)
│   │       ├── Views/                # SwiftUI views (Library, Search, Shelf, Insights)
│   │       ├── Services/             # Business logic (API clients, enrichment)
│   │       └── Utilities/            # Helpers & extensions
│   └── Tests/
│       └── BooksTrackerFeatureTests/ # Swift Testing suite
│
├── cloudflare-workers/
│   ├── api-worker/                   # Monolith Worker
│   │   ├── src/
│   │   │   ├── index.js              # Main router
│   │   │   ├── handlers/             # Request handlers (search, enrichment)
│   │   │   ├── services/             # Business logic (AI, APIs)
│   │   │   ├── providers/            # AI providers (Gemini)
│   │   │   ├── durable-objects/      # WebSocket DO
│   │   │   └── utils/                # Shared utilities
│   │   └── test/                     # Worker tests
│   └── _archived/                    # Legacy distributed architecture
│
├── docs/                             # Documentation hub
│   ├── README.md                     # Documentation navigation
│   ├── product/                      # PRDs & requirements
│   ├── workflows/                    # Mermaid flow diagrams
│   ├── features/                     # Technical deep-dives
│   ├── architecture/                 # System design docs
│   └── guides/                       # How-to guides
│
├── .claude/                          # Claude Code configuration
│   └── commands/                     # Slash commands (iOS + backend ops)
│
├── CLAUDE.md                         # Developer quick reference (<500 lines)
├── MCP_SETUP.md                      # XcodeBuildMCP workflows
├── CHANGELOG.md                      # Project history & lessons
└── package.json                      # Root npm scripts


---

## 🧪 Testing

### iOS Tests

**Run Swift Testing suite:**

# Via XcodeBuildMCP (recommended)
/test

# Via Xcode
Cmd + U

# Via command line
xcodebuild test -scheme BooksTracker -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'


**Test Coverage:**
- SwiftData model relationships
- DTOMapper deduplication logic
- Canonical API response parsing
- ISBN validation & normalization
- Enrichment queue management

### Backend Tests

**Run Worker tests:**

cd cloudflare-workers
npm test


**Test Coverage:**
- CSV validation logic
- Gemini prompt generation
- Canonical DTO normalization
- Genre standardization
- WebSocket progress tracking

---

## 🚢 Deployment

### iOS App Store

**Complete validation pipeline:**

/gogo  # Runs: clean → build → test → archive validation


**Manual steps:**
1. Update version in `BooksTrackerApp.swift`
2. Build with Release configuration
3. Archive (`Product → Archive`)
4. Upload to App Store Connect
5. Submit for review

### Cloudflare Workers

**Deploy backend:**

npm run deploy:workers


**Health check:**

curl "https://books-api-proxy.jukasdrj.workers.dev/health"


**Stream logs:**

/logs  # Real-time Worker logs via XcodeBuildMCP


---

## 🤝 Contributing

We welcome contributions! Please follow these guidelines:

### Development Workflow

1. **Fork the repository**
2. **Create a feature branch:**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Follow coding standards:**
   - Zero warnings policy (Swift 6 strict concurrency)
   - Use `@MainActor` for UI, `nonisolated` for pure functions
   - Insert SwiftData models before setting relationships
   - Use `@Bindable` for SwiftData models in child views
   - AST-grep for Swift code searches (not ripgrep)

4. **Write tests:**
   - Swift Testing (`@Test`, `#expect`) for iOS
   - Vitest for Cloudflare Workers

5. **Commit with semantic messages:**
   ```bash
   git commit -m "feat: add bookshelf batch scanning"
   git commit -m "fix: resolve ISBN validation edge case"
   git commit -m "docs: update architecture diagrams"
   ```

6. **Push and create PR:**
   ```bash
   git push origin feature/your-feature-name
   ```

### PR Checklist

- [ ] Zero build warnings
- [ ] All tests passing
- [ ] WCAG AA contrast compliance (4.5:1+)
- [ ] Real device testing (not just simulator)
- [ ] Documentation updated (`CLAUDE.md` + `docs/features/`)
- [ ] CHANGELOG.md entry added

### Code Review Standards

- HIG compliance for UI changes
- Swift 6 concurrency correctness
- No Timer.publish in actors (use Task.sleep)
- Proper error handling with typed throws
- Accessibility labels for all interactive elements

---

## 📚 Documentation

**Full documentation hub:** [`docs/README.md`](docs/README.md)

**Quick Reference:**
- **CLAUDE.md** - Developer quick reference for active development
- **MCP_SETUP.md** - XcodeBuildMCP workflows & slash commands
- **CHANGELOG.md** - Version history & debugging lessons
- **docs/product/** - Product requirements & user stories
- **docs/workflows/** - Mermaid flow diagrams (visual guides)
- **docs/features/** - Technical implementation deep-dives
- **docs/architecture/** - System design decisions

**Learning Path:**
1. New contributor? → [`docs/README.md`](docs/README.md) → [`docs/workflows/`](docs/workflows/)
2. Planning feature? → Use [`docs/product/PRD-Template.md`](docs/product/PRD-Template.md)
3. Implementing? → Study [`docs/features/`](docs/features/) + workflow diagrams
4. Quick question? → Check **CLAUDE.md**

---

## 📄 License

This project is proprietary software. All rights reserved.

---

## 🙏 Acknowledgments

- **Apple** - SwiftUI, SwiftData, VisionKit frameworks
- **Cloudflare** - Workers platform & Durable Objects
- **Google** - Gemini 2.0 Flash AI & Books API
- **OpenLibrary** - Open book metadata

---

## 📞 Support

- **Issues:** [GitHub Issues](https://github.com/jukasdrj/books_tracker_v1/issues)
- **Discussions:** [GitHub Discussions](https://github.com/jukasdrj/books_tracker_v1/discussions)
- **Documentation:** [`docs/README.md`](docs/README.md)

---

**Built with ❤️ using Swift, SwiftUI, and Cloudflare Workers**
