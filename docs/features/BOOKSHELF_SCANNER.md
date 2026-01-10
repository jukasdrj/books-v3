# Bookshelf AI Scanner

**Status:** Beta | **AI Model:** Gemini 2.0 Flash | **Latency:** 25-40s/scan

The Bookshelf AI Scanner allows users to digitize their physical library by taking a photo of their bookshelf. It uses Google's Gemini 2.0 Flash model to detect book spines, extract titles and authors, and match them against the ISBNdb database.

---

## 📸 Core Features

### 1. Single-Shot Scanning
- **Input:** Single photo captured via `VisionKit` camera or selected from Photos picker.
- **Processing:** Image is resized to 3072px (max dim) @ 90% quality (400-600KB payload).
- **Feedback:** Real-time progress updates via WebSocket/SSE (8ms latency).
- **Result:** Interactive list of detected books with confidence scores.

### 2. Detection & Confidence
The AI assigns a confidence score to each detected spine:
- **Confirmed:** High confidence match. Ready for import.
- **Uncertain:** AI detected a spine but low confidence on title/author match. Requires user review.
- **Detected:** Raw detection before enrichment.

### 3. Review Queue
Users can review detection results before importing:
- **Edit Metadata:** Correct mistyped titles or authors.
- **Confirm/Reject:** Accept valid matches, discard false positives.
- **Bulk Import:** Add all confirmed books to the library in one action.

---

## 🏗️ Architecture

### Client-Side (iOS)
- **`BookshelfScannerView`**: Main UI container. Handles camera/picker presentation and state management.
- **`BookshelfScanModel`**: `@Observable` class managing scan state (`idle`, `processing`, `completed`, `error`).
    - Prevents device sleep during scanning (`isIdleTimerDisabled = true`).
    - Handles "Per-Session" temp file cleanup to avoid storage bloat.
- **`BookshelfAIService`**: Networking layer.
    - Uploads image to backend.
    - Connects to WebSocket for `job_progress` events.
    - Polling fallback if WebSocket fails.

### Backend (Cloudflare Workers)
- **Endpoint:** `POST /api/scan-bookshelf/batch` (supports single image as batch of 1).
- **AI Processing:** Gemini 2.0 Flash analyzes the image for bounding boxes and text.
- **Enrichment:** Detected text is cross-referenced with ISBNdb to find metadata.
- **Optimization:** Results are cached for 24 hours.

---

## 🚦 Constraints & Limits

- **Rate Limit:** 5 scans / minute per IP.
- **Image Size:** Max 10MB (client compresses before upload).
- **Concurrency:** Single active scan per user session.

---

## 🛠️ Usage Example

```swift
// Trigger scan from View
Button("Scan Bookshelf") {
    showCamera = true
}

// Handle results
.fullScreenCover(isPresented: $showCamera) {
    BookshelfCameraView { capturedImage in
        Task {
            await scanModel.processImage(capturedImage)
        }
    }
}
```

## ⚠️ Known Issues
- **Glare:** Highly reflective book spines can confuse the OCR.
- **Angle:** Extreme angles may cause bounding box misalignment.
- **Handwriting:** Handwritten titles on spines are rarely detected accurately.
