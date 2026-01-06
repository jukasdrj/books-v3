# AI-Powered CSV Import Workflow - Product Requirements Document

**Status:** ✅ Shipped (v3.1.0+)
**Owner:** Product Team
**Last Updated:** November 25, 2025

---

## 1. Problem Statement

Migrating from other book tracking platforms is a major friction point for new users. The legacy CSV import process required manual column mapping, which was confusing, error-prone, and led to a high rate of onboarding abandonment. Users need a "fire and forget" solution to import their existing library without needing technical knowledge of CSV formats.

---

## 2. Solution Overview

The AI-Powered CSV Import workflow uses Google's Gemini 2.0 Flash API to automatically parse any CSV file, regardless of its column structure. This zero-configuration approach removes the need for manual column mapping. The workflow provides real-time progress updates via WebSockets, with a fallback to Server-Sent Events (SSE) for improved reliability, and enriches the imported data with metadata from the BooksTrack API.

---

## 3. User Stories

- **As a new user**, I want to import my Goodreads library by simply uploading the CSV file, so that I can get my library set up in under a minute.
- **As a user with a custom spreadsheet of my books**, I want the system to intelligently understand my column names like "Book Title" or "Author's Name", so that I don't have to reformat my file.
- **As a user importing a large library**, I want to see real-time progress of the import, so I know the system is working and how long it will take.
- **As a user with books already in my library**, I want the import to automatically skip duplicates, so I don't have to clean up my library afterward.

---

## 4. Technical Implementation

### High-Level Workflow

```mermaid
flowchart TD
    A[User selects CSV file in app] --> B{File < 10MB?};
    B -->|Yes| C[POST /api/v2/imports];
    B -->|No| D[Show error: "File too large"];
    C --> E{Backend: Start import job};
    E --> F[Client connects to progress stream];
    F --> G[GET /api/v2/imports/{jobId}/stream];
    G --> H{Backend: Gemini parsing & enrichment};
    H -- SSE Events --> I[UI shows real-time progress];
    I --> J{User reviews results};
    J --> K[Save to library];
```

### API Endpoints

**V2 CSV Import API:**

-   **Initiate Import:** `POST /api/v2/imports`
    -   **Request:** `multipart/form-data` with the CSV file.
    -   **Response:** `202 Accepted` with a `job_id` and URLs for status polling and SSE streaming.
-   **Get Import Status:** `GET /api/v2/imports/{jobId}`
    -   **Response:** JSON object with the current status and progress of the import job.
-   **Stream Import Progress:** `GET /api/v2/imports/{jobId}/stream`
    -   **Response:** A Server-Sent Events (SSE) stream that pushes progress updates to the client in real-time.

**V1 WebSocket API (Legacy):**

-   The V1 WebSocket API (`wss://api.oooefam.net/ws/progress`) is still supported for older clients but the V2 SSE stream is the preferred method for real-time updates.

### Frontend

The frontend is responsible for:
-   Validating the file size before upload.
-   Making the initial `POST` request to start the import.
-   Connecting to the SSE endpoint to receive progress updates.
-   Displaying the progress to the user in a clear and informative way.
-   Handling the final results and allowing the user to save the imported books to their library.

### Backend

The backend is responsible for:
-   Validating the uploaded CSV file.
-   Using the Gemini 2.0 Flash API to parse the CSV and extract book data.
-   Enriching the book data with metadata from the Google Books and OpenLibrary APIs.
-   Publishing progress updates to the SSE stream.
-   Storing the final results for the user to review and import.

---

## 5. Success Metrics

-   **Completion Rate:** 90%+ of users who start a CSV import complete the process.
-   **Processing Time:** A 100-book CSV is imported and enriched in under 60 seconds.
-   **Accuracy:** 95%+ of fields are correctly detected and mapped by the Gemini API.
-   **User Satisfaction:** A significant reduction in support tickets related to CSV import issues.
