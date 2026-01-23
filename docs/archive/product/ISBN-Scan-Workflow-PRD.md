# ISBN Scan Workflow - Product Requirements Document

**Status:** ✅ Shipped (v3.0.0+)
**Owner:** Product Team
**Last Updated:** November 25, 2025

---

## 1. Problem Statement

Manually typing in a 13-digit ISBN is slow and prone to errors. Users, especially when in a bookstore or library, need a fast and accurate way to add books to their digital library.

---

## 2. Solution Overview

The ISBN Scan workflow leverages Apple's VisionKit framework to provide a native, high-performance barcode scanner. The scanner is optimized for ISBN barcodes (EAN-13, EAN-8, UPC-E) and is integrated directly into the search view. Once an ISBN is scanned, the app makes a request to the `/v1/search/isbn` endpoint to retrieve the book's metadata.

---

## 3. User Stories

- **As a user in a bookstore**, I want to scan a book's barcode to instantly see its details and add it to my wishlist.
- **As a user cataloging my home library**, I want to be able to scan multiple books in a row without having to navigate through multiple screens for each book.
- **As a user with an older iPhone**, I want to be clearly informed if my device does not support the scanning feature.

---

## 4. Technical Implementation

### High-Level Workflow

```mermaid
flowchart TD
    A[User taps "Scan ISBN" in Search view] --> B{Camera permission?};
    B -->|Granted| C[Present VisionKit DataScanner];
    B -->|Denied| D[Show permission error];
    C --> E{User scans a barcode};
    E --> F{Is it a valid ISBN?};
    F -->|Yes| G[GET /v1/search/isbn?isbn=...];
    F -->|No| H[Ignore and continue scanning];
    G --> I[Display book details];
```

### API Endpoints

-   **ISBN Search:** `GET /v1/search/isbn`
    -   **Request:** Takes a single query parameter, `isbn`, with the scanned ISBN.
    -   **Response:** A `BookSearchResponse` object containing the Work, Edition, and Author DTOs for the matching book.

### Frontend

-   The frontend uses Apple's `DataScannerViewController` from the VisionKit framework to implement the barcode scanner.
-   The scanner is configured to only recognize ISBN-specific barcode symbologies.
-   Upon a successful scan, the app makes a GET request to the `/v1/search/isbn` endpoint.
-   The response is then used to populate the book details view.
-   The feature includes graceful error handling for devices that don't support VisionKit or if the user has denied camera access.

### Backend

-   The backend is responsible for validating the ISBN and looking up the book in its database.
-   The endpoint is heavily cached (7-day TTL) to ensure fast response times for popular books.

---

## 5. Success Metrics

-   **Speed:** A successful scan and API lookup should take less than 3 seconds.
-   **Accuracy:** The scanner should have a 99%+ success rate on clear, undamaged barcodes.
-   **Adoption:** A significant percentage of new book additions come from the barcode scanner, indicating that it is a preferred method for adding books.
