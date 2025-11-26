# Cloudflare Workflows API Testing Guide

**Version:** 1.0.0  
**Last Updated:** November 26, 2024  
**Status:** Production Ready

---

## Overview

This guide provides instructions for testing the Cloudflare Workflows API integration in BooksTrack iOS app.

**Backend Endpoint:** `https://api.oooefam.net/v2/import/workflow`  
**Status:** ✅ Live (as of November 25, 2024)

---

## Prerequisites

1. **Network Access:** Internet connection to reach `api.oooefam.net`
2. **Backend Status:** Verify backend is online at `https://api.oooefam.net/health`
3. **iOS Device/Simulator:** iOS 26.0+ required

---

## Quick Start

### 1. Service-Level Testing

```swift
import BooksTrackerFeature

// Create service
let service = WorkflowImportService()

// Trigger workflow
let workflowId = try await service.createWorkflow(
    isbn: "9780747532743",
    source: .googleBooks
)

// Poll for completion
let result = try await service.pollUntilComplete(
    workflowId: workflowId
)

print("Status: \(result.status)")
print("Result: \(result.result?.title ?? "No result")")
```

### 2. UI-Level Testing

```swift
import SwiftUI
import BooksTrackerFeature

struct TestWorkflowView: View {
    var body: some View {
        WorkflowProgressView(isbn: "9780747532743")
    }
}
```

---

## Test ISBNs

Use these ISBNs for various test scenarios:

| ISBN | Expected Result | Use Case |
|------|----------------|----------|
| `9780747532743` | ✅ Success | Harry Potter 1 (reliable metadata) |
| `9780061120084` | ✅ Success | To Kill a Mockingbird (classic) |
| `9780451524935` | ✅ Success | 1984 by George Orwell |
| `9999999999999` | ❌ Fail | Invalid ISBN (fails at fetch-metadata) |
| `123` | ❌ Fail | Validation error (client-side reject) |
| `978074753274X` | ❌ Fail | Validation error (contains letters) |

---

## Workflow Steps

Each workflow executes 4 steps in sequence:

### Step 1: validate-isbn (~12ms)
- **Purpose:** Validate ISBN format (10 or 13 digits)
- **Success:** Proceeds to step 2
- **Failure:** Returns error immediately (no retry)

### Step 2: fetch-metadata (1-2s)
- **Purpose:** Fetch book data from Google Books API
- **Success:** Proceeds to step 3
- **Failure:** Retries 3x with linear backoff (1s, 2s, 3s)
- **Expected Duration:** 1-2 seconds (normal), up to 8s (with retries)

### Step 3: upload-cover (~300ms)
- **Purpose:** Download cover image and upload to R2 storage
- **Success:** Proceeds to step 4
- **Failure:** Retries 5x with exponential backoff (500ms, 1s, 2s, 4s, 8s)
- **Expected Duration:** 300ms (normal), up to 15.5s (with retries)

### Step 4: save-database (~50ms)
- **Purpose:** Save book data to D1 database
- **Success:** Workflow complete
- **Failure:** Retries 3x with exponential backoff
- **Expected Duration:** 50ms (normal), up to 200ms (with retries)

**Total Expected Duration:** 1.5-3 seconds (no retries), up to 30 seconds (worst case)

---

## Status Polling

### Polling Strategy

```swift
// Poll every 500ms with 30s timeout
let result = try await service.pollUntilComplete(
    workflowId: workflowId,
    pollingInterval: .milliseconds(500),
    timeout: .seconds(30),
    progressHandler: { status in
        print("Current step: \(status.currentStep ?? "unknown")")
    }
)
```

### Status Transitions

```
running (validate-isbn)
  ↓
running (fetch-metadata)
  ↓
running (upload-cover)
  ↓
running (save-database)
  ↓
complete (with result)
```

### Failure Scenarios

If a step fails after exhausting retries:
```
running (fetch-metadata)
  ↓ [retries: 3]
failed (currentStep: "fetch-metadata")
```

---

## Unit Tests

Run the test suite:

```bash
/test  # Using XcodeBuildMCP
```

### Test Coverage

- ✅ ISBN validation (10-digit, 13-digit, invalid formats)
- ✅ Source parameter (googleBooks, isbndb, openLibrary)
- ✅ Response parsing (WorkflowStatus enum, snake_case decoding)
- ✅ Error descriptions (user-friendly messages)

**Test File:** `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/Services/WorkflowImportServiceTests.swift`

---

## Integration Tests

### Manual Testing Steps

1. **Create Workflow:**
   ```
   - Run app in simulator/device
   - Navigate to Add Book flow
   - Use WorkflowProgressView with test ISBN
   - Verify workflow ID is returned
   ```

2. **Monitor Progress:**
   ```
   - Watch step indicators update in real-time
   - Each step should show checkmark when complete
   - Progress should complete in < 5 seconds
   ```

3. **Verify Completion:**
   ```
   - Success: Book title appears
   - Failure: Error message with retry option
   ```

### Testing Error Scenarios

**Network Failure:**
```swift
// Disconnect network, then trigger workflow
// Expected: WorkflowImportError.networkError
```

**Invalid ISBN:**
```swift
let service = WorkflowImportService()
do {
    _ = try await service.createWorkflow(isbn: "invalid")
} catch WorkflowImportError.invalidISBN {
    print("✅ Validation works")
}
```

**Timeout:**
```swift
// Use custom timeout for testing
let result = try await service.pollUntilComplete(
    workflowId: workflowId,
    timeout: .seconds(5)  // Short timeout
)
// Expected: WorkflowImportError.timeout if workflow takes > 5s
```

---

## Backend Verification

### Check Backend Health

```bash
curl https://api.oooefam.net/health
# Expected: {"status": "ok"}
```

### Trigger Workflow via cURL

```bash
curl -X POST https://api.oooefam.net/v2/import/workflow \
  -H "Content-Type: application/json" \
  -d '{"isbn": "9780747532743", "source": "google_books"}'

# Expected Response (202 Accepted):
{
  "data": {
    "workflowId": "workflow_abc123...",
    "status": "running",
    "created_at": "2025-11-26T00:00:00Z"
  },
  "metadata": {
    "timestamp": "2025-11-26T00:00:00Z"
  }
}
```

### Check Workflow Status

```bash
curl https://api.oooefam.net/v2/import/workflow/{workflowId}

# Expected Response (200 OK):
# Running:
{
  "data": {
    "workflowId": "workflow_abc123",
    "status": "running",
    "currentStep": "fetch-metadata"
  }
}

# Complete:
{
  "data": {
    "workflowId": "workflow_abc123",
    "status": "complete",
    "result": {
      "isbn": "9780747532743",
      "title": "Harry Potter and the Philosopher's Stone",
      "success": true
    }
  }
}
```

---

## Performance Benchmarks

### Expected Latency (P95)

| Step | Normal | With Retries |
|------|--------|--------------|
| validate-isbn | < 20ms | N/A (no retry) |
| fetch-metadata | < 2s | < 8s (3 retries) |
| upload-cover | < 500ms | < 16s (5 retries) |
| save-database | < 100ms | < 500ms (3 retries) |
| **Total** | **< 3s** | **< 30s** |

### Polling Overhead

- **Polling Interval:** 500ms
- **Requests per Import:** ~6-10 (assuming 3s workflow)
- **Bandwidth per Poll:** ~200 bytes request, ~500 bytes response
- **Total Overhead:** ~5-7 KB per import

---

## Troubleshooting

### Issue: Workflow Times Out

**Symptoms:** `WorkflowImportError.timeout` after 30 seconds

**Causes:**
1. Backend workflow stuck on external API (Google Books slow)
2. Network latency high
3. Step retries exhausted

**Solutions:**
- Check backend logs in Cloudflare Dashboard
- Verify Google Books API status
- Increase timeout for slow networks: `.seconds(60)`

### Issue: Invalid Response Error

**Symptoms:** `WorkflowImportError.invalidResponse`

**Causes:**
1. Backend changed response format
2. Network proxy modified response
3. Response parsing failed

**Solutions:**
- Capture response data and inspect JSON structure
- Verify backend version matches API contract
- Check for CORS issues (X-Custom-Error header)

### Issue: Workflow Fails at fetch-metadata

**Symptoms:** Status shows `failed` with `currentStep: "fetch-metadata"`

**Causes:**
1. ISBN not found in Google Books
2. Google Books API rate limit
3. Network timeout

**Solutions:**
- Try different ISBN from test table
- Wait 1 minute for rate limit reset
- Check backend has valid Google Books API key

---

## Cloudflare Dashboard

### Viewing Workflow Execution

1. Login to Cloudflare Dashboard
2. Navigate to Workers & Pages
3. Select `bookstrack-api` worker
4. Click "Workflows" tab
5. Find workflow by ID (from iOS app)
6. View step-by-step execution trace

**Dashboard Features:**
- Real-time step progress
- Retry history per step
- Error stack traces
- Total execution time
- State snapshot (workflow input/output)

---

## API Contract Validation

### Backend Repository

**Source:** https://github.com/jukasdrj/bookstrack-backend  
**Implementation:** `src/workflows/import-book.ts`

### Contract Synchronization

The iOS types MUST match backend TypeScript types:

| iOS Type | Backend Type | Match? |
|----------|--------------|--------|
| `WorkflowSource` | `BookImportInput['source']` | ✅ |
| `WorkflowStatus` | `WorkflowStatus` | ✅ |
| `WorkflowCreateResponse` | `createSuccessResponse` payload | ✅ |
| `WorkflowStatusResponse` | Status handler response | ✅ |

**Validation:** Run backend integration tests in CI to ensure contract compatibility.

---

## Future Enhancements

1. **WebSocket Support:** Real-time progress instead of polling (reduces requests from 6-10 to 1)
2. **Batch Workflows:** Import multiple books in parallel (100+ concurrent workflows)
3. **Cancellation:** Cancel in-flight workflows via DELETE endpoint
4. **Retry from Step:** Resume failed workflow from specific step

---

## Related Documentation

- **Backend Implementation:** See [bookstrack-backend](https://github.com/jukasdrj/bookstrack-backend) repository
- **API Contract:** `docs/API_CONTRACT.md` Section 6.5.7
- **Sprint 3 Plan:** `docs/v2-plans/sprints/SPRINT_3_ORCHESTRATION.md`
- **Service Source:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Services/WorkflowImportService.swift`
- **UI Component:** `BooksTrackerPackage/Sources/BooksTrackerFeature/ProgressViews/WorkflowProgressView.swift`

---

**Document Owner:** iOS Team  
**Last Updated:** November 26, 2024  
**Status:** ✅ Ready for Testing
