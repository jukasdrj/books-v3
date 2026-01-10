# Batch Bookshelf Scanning

**Status:** Beta | **AI Model:** Gemini 2.0 Flash

Batch Bookshelf Scanning extends the single-shot [Bookshelf Scanner](./BOOKSHELF_SCANNER.md) to support processing multiple images in a continuous session. This is ideal for digitizing entire libraries or large bookcases spanning multiple shelves.

---

## ⚡ Key Capabilities

### 1. Multi-Image Capture
- **Queue:** Users can snap up to 5 photos in rapid succession.
- **UI:** A "tray" interface shows captured thumbnails ready for processing.
- **Workflow:** "Capture All -> Process All" model reduces friction compared to one-by-one scanning.

### 2. Parallel Processing
- **Upload:** Images are uploaded in parallel to maximize bandwidth.
- **Queuing:** The backend queues AI jobs to process images sequentially (to respect rate limits) but reports progress via a single aggregated channel.
- **Deduplication:** The system automatically checks for duplicate ISBNs across the batch and existing library to prevent double-entries.

---

## 🏗️ Architecture Differences

Unlike the single-scanner which uses a simple request/response + socket flow, the batch scanner relies on a **Job Manager** pattern.

1.  **Job Creation:** Client requests a `batchId`.
2.  **Uploads:** Client uploads N images associated with `batchId`.
3.  **Coordination:** Backend aggregates results from N sub-jobs.
4.  **Completion:** Client receives a consolidated list of detected books.

---

## 🚦 Constraints

- **Batch Size:** Max 5 photos per batch.
- **Timeout:** 5 minutes per batch total processing time.
- **Rate Limit:** 1 batch request every 2 minutes.

---

## 📱 UI/UX

- **Camera Mode:** "Burst" style capture interface.
- **Progress:** Aggregate progress bar (e.g., "Processing photo 2 of 5...").
- **Review:** Consolidated review screen merging findings from all photos.
