# Flutter Feature Parity Matrix

**iOS Version:** v3.7.5 (Build 189+)
**Target Flutter Version:** v1.0.0
**Last Updated:** January 5, 2026
**Parity Requirement:** Full feature parity before Flutter v1.0 launch

---

## Executive Summary

This document maps all 9 shipped iOS features to their Flutter equivalents, specifying required packages, implementation notes, and technical challenges. **Full parity is required** before Flutter v1.0 launch - no partial releases.

**Status:** Planning Phase (0/9 features implemented)

---

## Feature Parity Checklist

| # | Feature | iOS Status | Flutter Status | Priority | Complexity |
|---|---------|------------|----------------|----------|------------|
| 1 | Library Management | ✅ Shipped | ❌ Not Started | P0 - CRITICAL | Medium |
| 2 | Book Search & Enrichment | ✅ Shipped | ❌ Not Started | P0 - CRITICAL | High |
| 3 | Barcode Scanner | ✅ Shipped | ❌ Not Started | P0 - CRITICAL | Medium |
| 4 | Bookshelf AI Scanner | ✅ Shipped | ❌ Not Started | P1 - HIGH | High |
| 5 | CSV Import | ✅ Shipped | ❌ Not Started | P1 - HIGH | High |
| 6 | Review Queue | ✅ Shipped | ❌ Not Started | P1 - HIGH | Medium |
| 7 | Reading Statistics | ✅ Shipped | ❌ Not Started | P1 - HIGH | Medium |
| 8 | Diversity Insights | ✅ Shipped | ❌ Not Started | P1 - HIGH | Medium |
| 9 | Cloud Sync | ✅ Shipped | ❌ Not Started | P0 - CRITICAL | Very High |

---

## Feature 1: Library Management

### iOS Implementation

**Tech Stack:**
- SwiftData for local persistence
- CloudKit for cross-device sync
- SwiftUI for views

**Key Features:**
- Reading status tracking (Wishlist, Owned, Reading, Read)
- Filtering and sorting
- Search within library
- Library reset functionality

### Flutter Implementation

**Required Packages:**
```yaml
dependencies:
  # Local Database (Choose One)
  drift: ^2.14.0              # SQL-based, recommended for relational data
  isar: ^3.1.0                # NoSQL alternative, high performance

  # State Management
  riverpod: ^2.4.0            # Recommended (modern, compile-safe)
  bloc: ^8.1.0                # Alternative (popular, battle-tested)

  # Sync (CloudKit Alternative)
  firebase_core: ^2.24.0
  cloud_firestore: ^4.13.0    # Real-time sync

  # UI Components
  flutter_slidable: ^3.0.0    # Swipe actions (delete, edit)
```

**Implementation Notes:**
- **Database Choice:** Drift recommended (SQL queries match SwiftData predicates)
- **CloudKit Alternative:** Firebase Firestore (requires backend migration)
- **Challenge:** SwiftData's automatic CloudKit sync doesn't exist in Flutter
  - **Solution:** Implement custom sync logic with Firestore or build REST API wrapper

**Data Model Mapping:**
```dart
// Drift schema
@DataClassName('LibraryEntry')
class LibraryEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get workId => text()();
  TextColumn get status => text()();  // wishlist, owned, reading, read
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get completionDate => dateTime().nullable()();
  IntColumn get currentPage => integer().withDefault(const Constant(0))();
  IntColumn get personalRating => integer().nullable()();
}
```

**Estimated Effort:** 2-3 weeks (Medium complexity)

---

## Feature 2: Book Search & Enrichment

### iOS Implementation

**Tech Stack:**
- V3BooksService API client
- OpenAPI-generated Swift types
- Multi-provider orchestration (Google Books + OpenLibrary)

**Key Features:**
- Title/author/ISBN search
- Real-time search suggestions
- Multi-provider fallback
- Metadata enrichment pipeline

### Flutter Implementation

**Required Packages:**
```yaml
dependencies:
  dio: ^5.4.0                 # HTTP client (interceptors, retries)
  retrofit: ^4.0.0            # Type-safe REST client (auto-gen from OpenAPI)
  retrofit_generator: ^7.0.0
  json_annotation: ^4.8.0     # JSON serialization
  freezed: ^2.4.0             # Immutable data classes
  freezed_annotation: ^2.4.0
```

**Implementation Notes:**
- **OpenAPI Codegen:** Use `openapi-generator-cli` to generate Dart client from `docs/prd/Canonical-Data-Contracts-PRD.md` spec
- **API Base URL:** Same as iOS (`https://api.oooefam.net`)
- **Challenge:** Retrofit doesn't auto-generate WebSocket client (needed for CSV import progress)
  - **Solution:** Use `web_socket_channel` package separately

**Code Generation:**
```bash
# Generate Dart client from OpenAPI spec
openapi-generator-cli generate \
  -i openapi-v3.json \
  -g dart-dio \
  -o lib/api_client
```

**Estimated Effort:** 3-4 weeks (High complexity - multi-provider logic)

---

## Feature 3: Barcode Scanner

### iOS Implementation

**Tech Stack:**
- VisionKit DataScannerViewController
- Native iOS 16+ barcode scanning
- ISBN-specific symbologies (EAN-13, UPC-E)

**Key Features:**
- Real-time barcode detection
- Auto-highlighting
- Tap-to-scan gestures
- Built-in guidance UI

### Flutter Implementation

**Required Packages:**
```yaml
dependencies:
  mobile_scanner: ^4.0.0      # Cross-platform barcode scanning
  permission_handler: ^11.0.0 # Camera permissions
```

**Implementation Notes:**
- **mobile_scanner** provides iOS/Android barcode scanning (wraps native APIs)
- **Symbologies:** Supports EAN-13, UPC-E (same as iOS)
- **Challenge:** No built-in guidance UI like VisionKit
  - **Solution:** Custom overlay with "Move Closer" / "Hold Steady" messages

**Permissions:**
```xml
<!-- iOS: Info.plist -->
<key>NSCameraUsageDescription</key>
<string>Scan ISBN barcodes to quickly add books</string>

<!-- Android: AndroidManifest.xml -->
<uses-permission android:name="android.permission.CAMERA"/>
```

**Estimated Effort:** 1-2 weeks (Medium complexity)

---

## Feature 4: Bookshelf AI Scanner

### iOS Implementation

**Tech Stack:**
- UIImagePickerController for photo capture
- Gemini 2.0 Flash AI via backend API
- WebSocket for real-time progress (SSE alternative)

**Key Features:**
- Multi-photo capture (up to 5 photos per batch)
- Real-time OCR progress via WebSocket
- Confidence scoring (60% threshold)
- Image preprocessing (resize to 3072px, 90% quality)

### Flutter Implementation

**Required Packages:**
```yaml
dependencies:
  image_picker: ^1.0.0        # Photo/camera access
  image: ^4.1.0               # Image preprocessing (resize, compress)
  web_socket_channel: ^2.4.0  # WebSocket client
  http: ^1.1.0                # HTTP client (photo upload)
```

**Implementation Notes:**
- **WebSocket URL:** `wss://api.oooefam.net/ws/progress?jobId={uuid}`
- **Image Preprocessing:** Use `image` package to resize/compress before upload
- **Challenge:** No native iOS photo quality controls
  - **Solution:** Manual JPEG compression via `image` package

**WebSocket Flow:**
```dart
final channel = WebSocketChannel.connect(
  Uri.parse('wss://api.oooefam.net/ws/progress?jobId=$jobId'),
);

channel.stream.listen((message) {
  final event = jsonDecode(message);
  if (event['type'] == 'job_progress') {
    // Update UI: ${event['progress']}%
  }
});
```

**Estimated Effort:** 3-4 weeks (High complexity - WebSocket + image processing)

---

## Feature 5: CSV Import

### iOS Implementation

**Tech Stack:**
- UIDocumentPickerViewController for file selection
- Backend Gemini AI parsing (zero column mapping)
- WebSocket for real-time progress

**Key Features:**
- AI-powered CSV parsing (any format)
- Real-time progress updates
- Error tracking with row numbers
- 10MB file size limit

### Flutter Implementation

**Required Packages:**
```yaml
dependencies:
  file_picker: ^6.0.0         # Cross-platform file picker
  csv: ^5.1.0                 # CSV parsing (if client-side fallback needed)
  web_socket_channel: ^2.4.0  # Progress updates
```

**Implementation Notes:**
- **File Picker:** `file_picker` supports all platforms (iOS, Android, Web)
- **Backend API:** POST to `/v3/jobs/imports/csv` (same as iOS)
- **Challenge:** 10MB limit validation before upload
  - **Solution:** Check `file.lengthSync()` before upload

**File Upload:**
```dart
final result = await FilePicker.platform.pickFiles(
  type: FileType.custom,
  allowedExtensions: ['csv'],
  withData: true,  // Load file bytes
);

if (result != null && result.files.single.size <= 10 * 1024 * 1024) {
  // Upload to backend
}
```

**Estimated Effort:** 2-3 weeks (High complexity - WebSocket integration)

---

## Feature 6: Review Queue

### iOS Implementation

**Tech Stack:**
- SwiftUI forms with editable fields
- Low-confidence detections (<60%)
- Cropped spine images

**Key Features:**
- Review low-confidence AI scans
- Edit title/author inline
- Approve/reject books
- Bulk operations

### Flutter Implementation

**Required Packages:**
```yaml
dependencies:
  flutter_form_builder: ^9.0.0  # Form management
  image_cropper: ^5.0.0          # Image cropping (if needed)
```

**Implementation Notes:**
- **UI Pattern:** ListView with editable TextFormField widgets
- **State Management:** Riverpod for form state + validation
- **Challenge:** None (standard CRUD UI)

**Estimated Effort:** 1-2 weeks (Medium complexity)

---

## Feature 7: Reading Statistics

### iOS Implementation

**Tech Stack:**
- SwiftData aggregations (fetchCount, predicates)
- Chart library (Swift Charts)
- Reading pace calculations

**Key Features:**
- Books read per month
- Pages read
- Reading streaks
- Completion rates

### Flutter Implementation

**Required Packages:**
```yaml
dependencies:
  fl_chart: ^0.66.0           # Chart library (recommended)
  syncfusion_flutter_charts: ^24.1.0  # Alternative (more features, paid license)
```

**Implementation Notes:**
- **Charts:** `fl_chart` is free and powerful (line, bar, pie charts)
- **Aggregations:** SQL queries via Drift `SELECT COUNT(*), SUM(pages)...`
- **Challenge:** None (standard data visualization)

**Estimated Effort:** 2 weeks (Medium complexity)

---

## Feature 8: Diversity Insights

### iOS Implementation

**Tech Stack:**
- Radar chart visualization (custom SwiftUI)
- 5-dimension diversity tracking (gender, region, etc.)
- Percentage calculations

**Key Features:**
- Radar chart with 5 dimensions
- Diversity score calculation
- Filter by dimension
- Marginalized voice detection

### Flutter Implementation

**Required Packages:**
```yaml
dependencies:
  fl_chart: ^0.66.0           # Has radar chart support
  # OR custom implementation with CustomPaint
```

**Implementation Notes:**
- **Radar Chart:** `fl_chart` supports radar charts (5 dimensions)
- **Calculations:** Same logic as iOS (percentage by dimension)
- **Challenge:** Custom radar chart styling to match iOS
  - **Solution:** Use `fl_chart` RadarChart widget

**Estimated Effort:** 2 weeks (Medium complexity)

---

## Feature 9: Cloud Sync

### iOS Implementation

**Tech Stack:**
- CloudKit (automatic SwiftData sync)
- Private database
- CKRecord reconciliation

**Key Features:**
- Automatic sync across devices
- Conflict resolution (last-write-wins)
- Offline-first architecture
- Zero-config for users

### Flutter Implementation

**Required Packages:**
```yaml
dependencies:
  firebase_core: ^2.24.0
  cloud_firestore: ^4.13.0    # Real-time sync
  connectivity_plus: ^5.0.0   # Network detection
```

**Implementation Notes:**
- **CloudKit Alternative:** Firebase Firestore (no native CloudKit support in Flutter)
- **Backend Migration:** iOS must also support Firestore OR build sync API
- **Challenge:** CloudKit is iOS-exclusive
  - **Option 1:** Migrate iOS to Firestore (breaking change, requires backend work)
  - **Option 2:** Build custom sync API (REST endpoints for CRUD + timestamp tracking)
  - **Option 3:** Use hybrid approach (CloudKit for iOS, Firestore for Flutter, sync bridge in backend)

**Recommended Approach:**
Custom Sync API (Option 2) to preserve iOS CloudKit while adding Flutter support

**Backend Endpoints:**
```
POST /v1/sync/push        # Upload local changes
GET  /v1/sync/pull        # Fetch remote changes since timestamp
GET  /v1/sync/conflicts   # Resolve conflicts
```

**Estimated Effort:** 4-6 weeks (Very High complexity - requires backend work)

---

## Total Estimated Effort

| Feature | Effort (Weeks) | Dependencies |
|---------|----------------|--------------|
| Library Management | 2-3 | None |
| Book Search & Enrichment | 3-4 | OpenAPI client generation |
| Barcode Scanner | 1-2 | Camera permissions |
| Bookshelf AI Scanner | 3-4 | WebSocket + image processing |
| CSV Import | 2-3 | WebSocket |
| Review Queue | 1-2 | None |
| Reading Statistics | 2 | Charts |
| Diversity Insights | 2 | Charts |
| Cloud Sync | 4-6 | **Backend API development** |

**Total:** 20-28 weeks (5-7 months) for full parity

**Critical Path:** Cloud Sync (requires backend work) + Book Search (OpenAPI codegen)

---

## Recommended Implementation Order

### Phase 1: Core Functionality (8-10 weeks)
1. Library Management (2-3 weeks)
2. Book Search & Enrichment (3-4 weeks)
3. Barcode Scanner (1-2 weeks)
4. Reading Statistics (2 weeks)

**Milestone:** MVP - Users can add books, search, scan, track reading

---

### Phase 2: Advanced Features (6-8 weeks)
5. Review Queue (1-2 weeks)
6. Diversity Insights (2 weeks)
7. CSV Import (2-3 weeks)
8. Bookshelf AI Scanner (3-4 weeks)

**Milestone:** Feature parity for power users (bulk import, AI scanning)

---

### Phase 3: Sync & Polish (4-6 weeks)
9. Cloud Sync (4-6 weeks - includes backend API)
10. UI polish and performance optimization
11. End-to-end testing

**Milestone:** Flutter v1.0 - Full parity with iOS

---

## Technical Challenges & Solutions

### Challenge 1: CloudKit → Firestore Migration

**Problem:** Flutter doesn't support CloudKit

**Solutions:**
| Option | Pros | Cons | Effort |
|--------|------|------|--------|
| **Firestore for all** | Single backend, real-time, free tier | iOS refactor required, vendor lock-in | Very High |
| **Custom Sync API** | Platform-agnostic, control | Build + maintain API | High |
| **Dual sync (CloudKit + Firestore)** | No iOS changes | Complex sync bridge | Very High |

**Recommendation:** Custom Sync API (Option 2) - preserves iOS CloudKit, adds Flutter support

---

### Challenge 2: OpenAPI Client Generation

**Problem:** iOS uses Swift client, Flutter needs Dart client

**Solution:** Use `openapi-generator-cli` to auto-generate Dart client from same spec

**Benefits:**
- Type-safe API calls
- Automatic serialization
- Shared contract (iOS + Flutter use same spec)

---

### Challenge 3: WebSocket Integration

**Problem:** Multiple features use WebSocket (CSV import, bookshelf scanning)

**Solution:** Create reusable `WebSocketService` class

```dart
class WebSocketService {
  late WebSocketChannel _channel;

  void connect(String jobId, Function(Map<String, dynamic>) onEvent) {
    _channel = WebSocketChannel.connect(
      Uri.parse('wss://api.oooefam.net/ws/progress?jobId=$jobId'),
    );
    _channel.stream.listen((message) {
      final event = jsonDecode(message);
      onEvent(event);
    });
  }

  void disconnect() => _channel.sink.close();
}
```

---

## Package Version Lock

**Lock file:** `pubspec.lock` (committed to Git)

**Critical Packages:**
- `drift: 2.14.0` (database schema migrations)
- `riverpod: 2.4.0` (state management)
- `dio: 5.4.0` (HTTP client)
- `mobile_scanner: 4.0.0` (barcode scanning)

**Update Strategy:** Pin major versions, allow minor/patch updates

---

## Testing Strategy

### Unit Tests
- Drift database queries
- API client methods
- State management logic (Riverpod providers)

### Integration Tests
- End-to-end workflows (add book → search → scan)
- Sync conflicts resolution
- WebSocket event handling

### Manual QA Checklist
- [ ] Real device: iOS + Android parity testing
- [ ] Camera permissions flow
- [ ] Offline mode (all features work without network)
- [ ] CloudKit sync (iOS ↔ Flutter via backend bridge)

---

## Related Documentation

- **PRD Index:** `docs/product/README.md` (platform-agnostic feature specs)
- **API Contracts:** `docs/product/Canonical-Data-Contracts-PRD.md`
- **Backend Repo:** https://github.com/jukasdrj/bookstrack-backend

---

## Approval Checklist

**Before starting Flutter development:**

- [ ] Product Manager sign-off on feature priority (P0 first)
- [ ] Engineering Lead confirms package choices (Drift vs Isar, Riverpod vs Bloc)
- [ ] Backend Lead confirms sync API feasibility (4-6 week estimate)
- [ ] Design Lead provides Flutter UI mockups (match iOS design system)
- [ ] Budget approved for 5-7 months development + 2 months testing

---

**Last Updated:** January 5, 2026
**Next Review:** February 1, 2026 (after package POCs)
**Maintained by:** Product + Engineering Teams
