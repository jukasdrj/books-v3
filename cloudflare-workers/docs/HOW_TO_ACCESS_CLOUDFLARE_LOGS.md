# How to Access Cloudflare Worker Logs for Debugging

This guide covers accessing logs for the `api-worker` to debug enrichment issues or other backend problems.

## Method 1: Cloudflare Dashboard (Easiest)

### Steps

1. **Log in to Cloudflare Dashboard**
   - Go to: https://dash.cloudflare.com
   - Sign in with your account

2. **Navigate to Workers**
   - Left sidebar → Workers
   - Find and click "api-worker"

3. **View Logs**
   - In the worker page, find "Logs" tab
   - Click on "Live Tail" or "Tail"
   - Set time range to "Last 24 hours"

4. **Filter Logs**
   - Search field at top
   - Examples:
     - `enrichment` - All enrichment-related logs
     - `/api/enrichment/batch` - Batch enrichment requests
     - `google-books` - Google Books API calls
     - `openlibrary` - OpenLibrary API calls
     - `WebSocket` - Connection issues
     - `error` - Any errors
     - `jobId:your-job-id` - Specific job

5. **View Details**
   - Click any log entry to expand
   - See full request/response details
   - Check timestamps and error messages

## Method 2: Wrangler CLI (Real-time Streaming)

### Prerequisites

```bash
# Install Wrangler
npm install -g @cloudflare/wrangler

# Authenticate
wrangler login
# This opens browser to authorize
```

### Stream Live Logs

```bash
# Stream all logs
wrangler tail api-worker

# Stream with search filter
wrangler tail api-worker --search "enrichment"

# Search for specific terms
wrangler tail api-worker --search "google-books"

# Pretty format
wrangler tail api-worker --format pretty

# Combine filters and format
wrangler tail api-worker --search "error" --format pretty
```

### Useful Wrangler Commands

```bash
# Follow logs in real-time (like tail -f)
wrangler tail api-worker --follow

# Save logs to file
wrangler tail api-worker > logs.txt

# Search and save
wrangler tail api-worker --search "enrichment" > enrichment-logs.txt

# View last 100 requests
wrangler tail api-worker --limit 100
```

## Method 3: Direct API (Advanced)

Using Cloudflare API directly to fetch logs programmatically:

```bash
# Requires CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN

# Get recent logs
curl -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/workers/tail?limit=100" \
  | jq '.'

# Filter by status code
curl -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/workers/tail?limit=100&status_code=500" \
  | jq '.result[] | {timestamp, message}'
```

## Common Debug Queries

### Enrichment Debugging

```bash
# All enrichment requests
wrangler tail api-worker --search "/api/enrichment/batch"

# Enrichment errors
wrangler tail api-worker --search "enrichment AND error"

# Specific job status
wrangler tail api-worker --search "jobId:abc123def456"

# Google Books API issues
wrangler tail api-worker --search "searchGoogleBooks AND error"

# OpenLibrary API issues
wrangler tail api-worker --search "searchOpenLibrary AND error"

# WebSocket connection issues
wrangler tail api-worker --search "WebSocket AND (error OR failed)"

# Cover image extraction
wrangler tail api-worker --search "coverImageUrl OR imageLinks OR covers"
```

### Performance Debugging

```bash
# Slow requests
wrangler tail api-worker --search "processingTime:>5000"

# API rate limits
wrangler tail api-worker --search "rate limit OR quota"

# Timeout issues
wrangler tail api-worker --search "timeout OR deadline"
```

### Storage Debugging

```bash
# KV operations
wrangler tail api-worker --search "KV"

# R2 operations
wrangler tail api-worker --search "R2 OR uploadedTo OR storedIn"

# Storage errors
wrangler tail api-worker --search "KV AND error OR R2 AND error"
```

## Log Format Understanding

Typical log entries look like:

```json
{
  "timestamp": "2025-11-05T12:34:56Z",
  "request": {
    "url": "https://api-worker.dev/api/enrichment/batch",
    "method": "POST",
    "headers": {...}
  },
  "outcome": "ok",
  "status": 202,
  "response_time": 145,
  "message": "[jobId] WebSocket connection accepted",
  "exceptions": []
}
```

**Key Fields:**
- `timestamp` - When it happened
- `url` - The endpoint called
- `method` - HTTP method (GET, POST, etc.)
- `status` - HTTP status code (200, 202, 500, etc.)
- `outcome` - "ok", "error", "exception"
- `response_time` - How long it took (ms)
- `message` - Custom console.log output

## Troubleshooting Guide

### Issue: No logs appearing

1. **Check worker is deployed**
   ```bash
   wrangler list api-worker
   ```
   Should show worker exists

2. **Make sure traffic is reaching worker**
   - Test endpoint: `curl https://books-api-proxy.jukasdrj.workers.dev/health`
   - Should get response

3. **Check log level**
   - In wrangler.toml: `LOG_LEVEL = "DEBUG"`
   - Set to "DEBUG" for maximum detail

### Issue: Logs are truncated

1. **Use pretty format**
   ```bash
   wrangler tail api-worker --format pretty
   ```

2. **Increase output**
   ```bash
   wrangler tail api-worker --limit 500
   ```

3. **Save to file**
   ```bash
   wrangler tail api-worker > full-logs.txt
   ```

### Issue: Can't find specific log entries

1. **Broader search**
   - Instead of "coverImageURL", search "cover"
   - Instead of specific jobId, search partial ID

2. **Use AND/OR operators**
   ```bash
   wrangler tail api-worker --search "enrichment AND google-books"
   wrangler tail api-worker --search "error OR warning"
   ```

3. **Check time range**
   - Logs may have expired (depending on Cloudflare plan)
   - Default is 24 hours
   - Enterprise plans keep 30 days

## Setting Up Log Exports (Enterprise)

If you need to archive or analyze logs:

### Option 1: Logpush (Recommended)

1. **Go to Cloudflare Dashboard**
   - Account Home → Logs → Logpush
   - Click "Create Dataset"

2. **Configure**
   - Select "Workers" dataset
   - Choose destination (S3, Datadog, etc.)
   - Configure frequency (hourly, daily)

3. **Verify**
   - Logs will be pushed to your storage service
   - Can then analyze with tools like Splunk, ELK, etc.

### Option 2: CloudFlare Logpull (Curl)

```bash
# Requires API token and account ID
ACCOUNT_ID="your-account-id"
API_TOKEN="your-api-token"
START_TIME="$(date -u -d '1 hour ago' +%s)"
END_TIME="$(date -u +%s)"

curl -s \
  -H "X-Auth-Email: your-email@example.com" \
  -H "X-Auth-Key: $API_TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/logs/workers?start=$START_TIME&end=$END_TIME&count=1000" \
  | jq '.'
```

## Integration with Monitoring Tools

### Datadog Integration

1. **Create Datadog API key**
   - Datadog → Settings → API Keys

2. **Configure Logpush**
   - Go to Cloudflare Logpush
   - Select Datadog as destination
   - Enter API endpoint and key

3. **View in Datadog**
   - Create custom dashboards
   - Set up alerts for error patterns
   - Monitor performance metrics

### Splunk Integration

1. **Create Splunk HTTP Event Collector**
   - Splunk → Settings → Data Inputs → HTTP Event Collector
   - Generate token

2. **Configure Logpush**
   - Set Splunk as destination
   - Enter collector URL and token

3. **Query in Splunk**
   - Search "source=cloudflare_workers"
   - Create SPL queries for enrichment analysis

## Performance Monitoring

### Check Slow Enrichments

```bash
# Find requests taking > 5 seconds
wrangler tail api-worker --search "/api/enrichment/batch AND processingTime:>5000"

# Average response time
wrangler tail api-worker --search "/api/enrichment/batch" \
  | jq '.[] | .response_time' | awk '{sum+=$1; count++} END {print "Avg:", sum/count}'
```

### Check Error Rates

```bash
# Count errors
wrangler tail api-worker --search "outcome:error" --limit 1000 \
  | jq '.[] | .status' | sort | uniq -c

# Error distribution
wrangler tail api-worker --search "error OR exception" --limit 500 \
  | jq '.[] | {timestamp, status, message}' | jq -s 'group_by(.status) | map({status: .[0].status, count: length})'
```

## Debugging the Specific Issue

For the cover image problem, search for:

```bash
# Check cover image extraction
wrangler tail api-worker --search "coverImageUrl OR imageLinks OR covers"

# Check normalizer output
wrangler tail api-worker --search "normalizeGoogleBooks OR normalizeOpenLibrary"

# Check enrichment completion
wrangler tail api-worker --search "complete called"

# Check enriched data returned to iOS
wrangler tail api-worker --search "Completion message sent"

# All together
wrangler tail api-worker --search "enrichment" | grep -E "cover|imageLinks|complete"
```

## Quick Reference

| Task | Command |
|------|---------|
| View live logs | `wrangler tail api-worker` |
| Search logs | `wrangler tail api-worker --search "term"` |
| Follow updates | `wrangler tail api-worker --follow` |
| Pretty format | `wrangler tail api-worker --format pretty` |
| Save to file | `wrangler tail api-worker > logs.txt` |
| View dashboard | https://dash.cloudflare.com → Workers → api-worker → Logs |
| Set log level | Edit `wrangler.toml`: `LOG_LEVEL = "DEBUG"` |
| View specific job | `wrangler tail api-worker --search "jobId:..."` |
| Search errors | `wrangler tail api-worker --search "error"` |

---

**Note:** For the root cause of the missing cover images issue, see `INVESTIGATION_RESULTS.md` - it was identified through code analysis rather than log inspection. However, these log access methods are useful for verifying the fix is working after deployment.
