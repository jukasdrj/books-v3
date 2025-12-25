# AI Shelf Scan Workflow - Product Requirements Document

**Status:** ✅ Shipped (Build 46+)
**Owner:** Product Team
**Last Updated:** November 25, 2025

---

## 1. Problem Statement

Users with large physical book collections face a significant hurdle when trying to digitize their libraries. Manually searching for and adding hundreds of books is a time-consuming and tedious process, leading to high rates of user drop-off during onboarding.

---

## 2. Solution Overview

The AI Shelf Scan feature allows users to take a photo of their bookshelf and have the app automatically identify and add the books to their library. The feature uses the Gemini 2.0 Flash AI for image analysis and provides real-time progress updates to the user via WebSockets, with a fallback to Server-Sent Events (SSE) for enhanced reliability.

---

## 3. User Stories

- **As a user with a large bookshelf**, I want to take a picture of my books and have them automatically added to my library, so that I can digitize my collection in minutes, not hours.
- **As a user scanning my books**, I want to see real-time progress of the scan, so I know the app is working and my books are being identified.
- **As a user reviewing the scan results**, I want to be able to correct any errors the AI made, so that my library is accurate.

---

## 4. Technical Implementation

### High-Level Workflow

```mermaid
flowchart TD
    A[User takes a photo of their bookshelf] --> B[Image is pre-processed on-device];
    B --> C[POST /api/scan-bookshelf/batch];
    C --> D{Backend: Start scan job};
    D --> E[Client connects to progress stream];
    E --> F[GET /api/v2/imports/{jobId}/stream];
    F --> G{Backend: Gemini AI analysis & enrichment};
    G -- SSE Events --> H[UI shows real-time progress];
    H --> I{User reviews scan results};
    I --> J[Save to library];
```

### API Endpoints

**V1 AI Shelf Scan API (Legacy):**

-   **Start Scan:** `POST /api/scan-bookshelf/batch`
    -   **Request:** `multipart/form-data` with up to 5 images.
    -   **Response:** A `jobId` and `token` to connect to the WebSocket.
-   **Get Progress:** `wss://api.oooefam.net/ws/progress`
    -   Real-time progress updates are sent over the WebSocket connection.
-   **Get Results:** `GET /v1/scan/results/{jobId}`
    -   Once the job is complete, the final results are retrieved from this endpoint.

**V2 Integration (Future):**

While the AI Shelf Scan workflow currently uses the v1 API for its real-time communication, it is a candidate for migration to the v2 SSE streaming API (`/api/v2/imports/{jobId}/stream`) to unify the real-time communication strategy across all import features. This would provide a more reliable and battery-efficient experience for users.

### Frontend

-   The frontend is responsible for the camera interface, on-device image pre-processing (resizing and compression), and uploading the images to the backend.
-   It connects to the WebSocket or SSE stream to receive progress updates and displays them to the user.
-   It provides a review screen where the user can correct any errors before saving the books to their library.

### Backend

-   The backend uses the Gemini 2.0 Flash AI to analyze the images and detect books.
-   It enriches the detected books with metadata from the Google Books and OpenLibrary APIs.
-   It publishes progress updates to the WebSocket and/or SSE stream.
-   It stores the final results for the user to review and import.

---

## 5. Success Metrics

-   **Adoption Rate:** A significant number of users with large libraries use the feature to onboard.
-   **Accuracy:** The AI correctly identifies 80%+ of the books in a clear, well-lit photo.
-   **Processing Time:** A photo with 20 books is fully processed in under 60 seconds.
-   **User Satisfaction:** The feature receives positive feedback and is a key driver of user acquisition and retention.
