# Cloudflare Workflows Testing Guide

**Date:** November 25, 2025
**Status:** Ready for Testing Tonight 🚀
**Implementation:** ✅ Complete (`src/workflows/import-book.ts`)

---

## 🎯 Quick Start - Test Workflows Tonight

### Prerequisites

```bash
# 1. Ensure you're in the project directory
cd /Users/justingardner/Downloads/xcode/bendv3

# 2. Check wrangler version (needs ≥3.78.0 for Workflows)
npx wrangler --version
# If < 3.78.0: npm install -g wrangler@latest

# 3. Verify Workflow binding in wrangler.jsonc
grep -A 5 "workflows" wrangler.jsonc
```

---

## 📋 Testing Checklist

### Phase 1: Local Testing (20 minutes)

**1. Start Local Dev Server**
```bash
npx wrangler dev

# Expected output:
# ⎔ Starting local server...
# [wrangler] Ready on http://localhost:8787
```

**2. Test Workflow Endpoint**
```bash
# Upload a test book via Workflow
curl -X POST http://localhost:8787/v2/import/workflow \
  -H "Content-Type: application/json" \
  -d '{
    "isbn": "9780747532743",
    "source": "google_books"
  }'

# Expected response (202 Accepted):
{
  "workflowId": "workflow_abc123",
  "status": "running",
  "created_at": "2025-11-25T22:00:00Z"
}
```

**3. Check Workflow Status**
```bash
# Poll workflow status
curl http://localhost:8787/v2/import/workflow/workflow_abc123

# Expected responses:

# While running:
{
  "workflowId": "workflow_abc123",
  "status": "running",
  "currentStep": "fetch-metadata"
}

# When complete:
{
  "workflowId": "workflow_abc123",
  "status": "complete",
  "result": {
    "isbn": "9780747532743",
    "title": "Harry Potter and the Philosopher's Stone",
    "success": true
  }
}
```

---

### Phase 2: Production Deployment (10 minutes)

**1. Deploy to Production**
```bash
# Deploy with Workflows enabled
npx wrangler deploy

# Expected output:
# ✨ Compiled Worker successfully
# ✨ Uploading...
# ✨ Deployment complete
# https://api.oooefam.net
```

**2. Test Production Workflow**
```bash
# Test against production
curl -X POST https://api.oooefam.net/v2/import/workflow \
  -H "Content-Type: application/json" \
  -d '{
    "isbn": "9780439708180",
    "source": "google_books"
  }'

# Save the workflowId from response
WORKFLOW_ID="workflow_xyz789"

# Check status
curl https://api.oooefam.net/v2/import/workflow/$WORKFLOW_ID
```

**3. Monitor in Cloudflare Dashboard**

1. Go to: https://dash.cloudflare.com
2. Navigate to: **Workers & Pages** → **BooksTrack API** → **Workflows**
3. Find your workflow instance
4. Click to see:
   - ✅ Step-by-step execution trace
   - ✅ Duration per step
   - ✅ Retry attempts (if any)
   - ✅ Error details (if failed)

---

### Phase 3: Load Testing (30 minutes)

**1. Batch Test Script**

Create `test-workflows.sh`:

```bash
#!/bin/bash

# Test 10 parallel book imports via Workflows
ISBNS=(
  "9780747532743"  # Harry Potter 1
  "9780439064866"  # Harry Potter 2
  "9780439136365"  # Harry Potter 3
  "9780439139601"  # Harry Potter 4
  "9780439358071"  # Harry Potter 5
  "9780439784542"  # Harry Potter 6
  "9780545139700"  # Harry Potter 7
  "9780061120084"  # To Kill a Mockingbird
  "9780451524935"  # 1984
  "9780060850524"  # Brave New World
)

echo "Starting parallel workflow tests..."

for isbn in "${ISBNS[@]}"; do
  (
    echo "Testing ISBN: $isbn"
    curl -X POST http://localhost:8787/v2/import/workflow \
      -H "Content-Type: application/json" \
      -d "{\"isbn\":\"$isbn\",\"source\":\"google_books\"}" \
      2>/dev/null | jq -r '.workflowId'
  ) &
done

wait
echo "All workflows submitted!"
```

**2. Run Load Test**
```bash
chmod +x test-workflows.sh
./test-workflows.sh

# Expected: 10 concurrent workflows, all succeed
```

**3. Check Dashboard**
- Go to Cloudflare Dashboard → Workflows
- Verify all 10 instances are visible
- Check for any failures or retries

---

## 🔍 What to Look For

### ✅ Success Indicators

1. **Fast Response (< 100ms)**
   - Workflow creation should be instant
   - Status polling should be < 50ms

2. **Automatic Retries**
   - If external API (Google Books) fails, Workflow should retry
   - Check Dashboard for retry attempts

3. **State Persistence**
   - Restart `wrangler dev` mid-workflow
   - Workflow should resume from last step (not restart)

4. **Parallel Execution**
   - 10 concurrent workflows should all succeed
   - No rate limit errors

5. **Error Handling**
   - Test invalid ISBN: `9999999999999`
   - Workflow should fail gracefully with error details

---

### ⚠️ Potential Issues

**Issue 1: "Workflow Not Found"**
```json
{
  "error": "Workflow binding not configured"
}
```

**Fix:** Check `wrangler.jsonc` has Workflow binding:
```jsonc
{
  "workflows": [
    {
      "binding": "BOOK_IMPORT_WORKFLOW",
      "name": "book-import-workflow",
      "class_name": "BookImportWorkflow"
    }
  ]
}
```

---

**Issue 2: "Step Timeout"**
```
Step 'fetch-metadata' timed out after 60s
```

**Fix:** External API slow - Workflow will auto-retry (check Dashboard)

---

**Issue 3: "Invalid ISBN"**
```json
{
  "error": {
    "code": "INVALID_ISBN",
    "message": "ISBN must be 10 or 13 digits"
  }
}
```

**Expected:** Workflow should fail fast (validation step)

---

## 📊 Performance Benchmarks

### Expected Results

| Metric | Target | Notes |
|--------|--------|-------|
| **Workflow Creation** | < 100ms | Instant response |
| **Total Duration** (valid ISBN) | 1-3 seconds | Depends on external API |
| **Retry Delay** (failed step) | 1s, 2s, 4s | Exponential backoff |
| **Max Retries** | 3 attempts | Then fail |
| **Concurrent Workflows** | 100+ | No limit |
| **State Persistence** | 100% | Survives restarts |

---

## 🧪 Advanced Testing Scenarios

### Scenario 1: Network Failure Simulation

**Test:** Simulate Google Books API down

```bash
# Use invalid API key temporarily
# Workflow should retry 3 times, then fail with clear error
```

**Expected:**
- ✅ Step 2 (fetch-metadata) retries 3 times
- ✅ Final status: `"status": "failed"`
- ✅ Error message: `"External API unavailable"`

---

### Scenario 2: Worker Restart Mid-Workflow

**Test:** Restart `wrangler dev` while workflow is running

```bash
# Terminal 1: Start workflow
curl -X POST http://localhost:8787/v2/import/workflow \
  -d '{"isbn":"9780747532743","source":"google_books"}'

# Terminal 1: Kill wrangler (Ctrl+C)

# Terminal 1: Restart wrangler
npx wrangler dev

# Terminal 2: Check workflow status (should resume!)
curl http://localhost:8787/v2/import/workflow/workflow_abc123
```

**Expected:**
- ✅ Workflow resumes from last completed step
- ✅ Does NOT re-execute earlier steps
- ✅ Completes successfully

---

### Scenario 3: Partial Failure Recovery

**Test:** R2 upload fails (simulate by removing R2 binding temporarily)

**Expected:**
- ✅ Steps 1-2 succeed (validation, metadata fetch)
- ✅ Step 3 fails (R2 upload)
- ✅ Workflow retries Step 3 only
- ✅ Clear error if all retries fail

---

## 📈 Monitoring & Observability

### Cloudflare Dashboard

**Navigate to:** Workflows → Select Instance

**Available Metrics:**
- ✅ Step-by-step execution trace
- ✅ Duration per step (identify bottlenecks)
- ✅ Retry history (with error messages)
- ✅ Input/output for each step
- ✅ Total execution time

**Screenshot Example:**
```
Step 1: validate-isbn        [✓]  12ms
Step 2: fetch-metadata       [✓]  1.2s (retry 1: 503 error)
Step 3: upload-cover         [✓]  345ms
Step 4: save-database        [✓]  67ms
Total: 1.62s
```

---

### Logs (via `wrangler tail`)

```bash
# Stream live logs
npx wrangler tail --format pretty

# Expected output:
[Workflow] Starting book import for ISBN 9780747532743
[Workflow] Step 1: validate-isbn - PASS
[Workflow] Step 2: fetch-metadata - Calling Google Books API
[Workflow] Step 2: fetch-metadata - PASS (1.1s)
[Workflow] Step 3: upload-cover - Uploading to R2
[Workflow] Step 3: upload-cover - PASS (234ms)
[Workflow] Step 4: save-database - Writing to D1
[Workflow] Step 4: save-database - PASS (45ms)
[Workflow] Book import complete: Harry Potter and the Philosopher's Stone
```

---

## 🔧 Debugging Tips

### Enable Verbose Logging

Edit `src/workflows/import-book.ts`:

```typescript
// Add at top of run() method
console.log('[DEBUG] Workflow input:', event.payload)
console.log('[DEBUG] Environment bindings:', Object.keys(this.env))
```

---

### Inspect Step State

```typescript
// In any step
await step.do('my-step', async () => {
  console.log('[DEBUG] Step state:', JSON.stringify({
    isbn,
    metadata,
    coverUrl
  }))

  return result
})
```

---

### Test Individual Steps

```typescript
// Create test file: test-workflow-steps.ts
import { BookImportWorkflow } from './src/workflows/import-book.js'

// Test validation step only
const result = await validateISBN('9780747532743')
console.log('Validation result:', result)
```

---

## ✅ Testing Checklist for Tonight

### Local Testing (Must Complete)

- [ ] `wrangler dev` starts without errors
- [ ] POST `/v2/import/workflow` returns 202 with workflowId
- [ ] GET `/v2/import/workflow/:id` shows status changes
- [ ] Valid ISBN completes successfully
- [ ] Invalid ISBN fails with clear error
- [ ] Parallel requests (10 concurrent) all succeed

### Production Testing (Optional)

- [ ] `wrangler deploy` succeeds
- [ ] Production workflow endpoint works
- [ ] Cloudflare Dashboard shows workflow instances
- [ ] Logs visible in `wrangler tail`

### Advanced Testing (If Time)

- [ ] Network failure retry test
- [ ] Worker restart mid-workflow test
- [ ] Performance benchmark (< 3s for valid ISBN)

---

## 📞 Quick Reference

### Endpoints

**Local:**
- Create: `POST http://localhost:8787/v2/import/workflow`
- Status: `GET http://localhost:8787/v2/import/workflow/:id`

**Production:**
- Create: `POST https://api.oooefam.net/v2/import/workflow`
- Status: `GET https://api.oooefam.net/v2/import/workflow/:id`

### Test ISBNs

```
Valid:
- 9780747532743 (Harry Potter 1 - always works)
- 9780439708180 (Harry Potter 1 - US edition)
- 9780061120084 (To Kill a Mockingbird)

Invalid:
- 9999999999999 (fake ISBN - should fail validation)
- 123 (too short - should fail validation)
```

### Commands

```bash
# Start dev server
npx wrangler dev

# Deploy to production
npx wrangler deploy

# Stream logs
npx wrangler tail --format pretty

# Check wrangler version
npx wrangler --version
```

---

## 🎯 Expected Timeline for Tonight

| Task | Duration | Result |
|------|----------|--------|
| **Local Setup** | 5 min | Dev server running |
| **Single Workflow Test** | 10 min | Valid ISBN imports |
| **Error Handling Test** | 10 min | Invalid ISBN fails gracefully |
| **Parallel Test** | 15 min | 10 concurrent workflows |
| **Production Deploy** | 10 min | Live on api.oooefam.net |
| **Dashboard Review** | 10 min | Verify observability |
| **Total** | **60 min** | Workflows fully validated! |

---

## 🚀 Next Steps After Testing

### If Tests Pass ✅

1. **Document Results**
   - Screenshot Cloudflare Dashboard workflow trace
   - Save logs showing successful parallel execution
   - Note any performance bottlenecks

2. **Enable Feature Flag**
   ```jsonc
   // wrangler.jsonc
   {
     "vars": {
       "ENABLE_WORKFLOWS": "true",  // Make Workflows the default
       "WORKFLOW_ROLLOUT_PERCENTAGE": "10"  // Start with 10% of traffic
     }
   }
   ```

3. **Monitor Production**
   - Watch error rates in Dashboard
   - Check retry patterns
   - Verify no regressions

### If Tests Fail ❌

1. **Capture Error Details**
   - Screenshot error in Dashboard
   - Save full stack trace
   - Note which step failed

2. **Rollback**
   ```bash
   # Disable Workflows temporarily
   ENABLE_WORKFLOWS=false npx wrangler deploy
   ```

3. **Debug Offline**
   - Review logs
   - Test individual steps
   - Fix and re-test locally

---

## 📚 Additional Resources

- **Cloudflare Workflows Docs:** https://developers.cloudflare.com/workflows/
- **Implementation:** `src/workflows/import-book.ts`
- **Handler:** `src/handlers/workflow-trigger-handler.ts`
- **Types:** `src/types/workflow-events.ts`
- **API Contract:** `docs/API_CONTRACT.md` (Section 6.5.7)

---

**Good luck with testing tonight! 🚀**

**Questions?** Check logs first, then review `src/workflows/import-book.ts` implementation.

**Document Owner:** Backend Team
**Last Updated:** November 25, 2025
**Status:** Ready for Testing ✅
