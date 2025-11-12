---
description: Query Worker logs using Cloudflare Observability MCP with smart filtering
---

🔍 **Intelligent Log Query** 🔍

Query api-worker logs using Cloudflare Observability MCP with structured filtering, calculations, and advanced analytics.

**Available Query Types:**

1. **Events View** - Browse individual request logs
2. **Calculations View** - Compute metrics (avg, p99, count, etc.)
3. **Invocations View** - Find specific request invocations

**Common Query Patterns:**

**Error Investigation:**
- "Show me all errors in the last 30 minutes"
- "Find 500 errors for the enrichment service"
- "What errors occurred during the last bookshelf scan?"

**Performance Analysis:**
- "What is the p99 response time for search endpoints?"
- "Show average Gemini API response times"
- "Calculate request count by status code"

**Feature Debugging:**
- "Find all Gemini API calls in the last hour"
- "Show WebSocket connection errors"
- "List enrichment service logs with errors"
- "Find requests to /search/isbn endpoint"

**Workflow:**

1. **Understand the Request**
   - Identify query intent (errors, performance, specific feature)
   - Determine appropriate view type (events/calculations/invocations)
   - Select optimal time range (default: last hour, max: 7 days)

2. **Build Query Using MCP Tools**

   **Step A: Discover Available Keys**
   ```
   Use mcp__cloudflare-observability__observability_keys with:
   - High limit (1000+) to see all available log fields
   - Filter by $metadata.service:"api-worker" to narrow results
   - Search for relevant keys using keyNeedle (case-insensitive)
   ```

   **Step B: Find Valid Values** (if filtering)
   ```
   Use mcp__cloudflare-observability__observability_values with:
   - Specific key from Step A
   - Same timeframe as main query
   - Verify actual values in logs (avoid guessing!)
   ```

   **Step C: Execute Main Query**
   ```
   Use mcp__cloudflare-observability__query_worker_observability with:
   - Verified keys and values from Steps A & B
   - Appropriate filters based on intent
   - Correct view type (events/calculations/invocations)
   ```

3. **Present Results**
   - Format response in human-readable way
   - Highlight key findings (errors, anomalies, patterns)
   - Suggest follow-up queries if needed
   - Include timestamps and metadata

**Key Metadata Fields (Fast & Always Available):**
- `$metadata.service` - Worker name ("api-worker")
- `$metadata.origin` - Trigger type ("fetch", "scheduled")
- `$metadata.trigger` - Route pattern ("GET /search/title", "POST /api/enrichment/start")
- `$metadata.message` - Log message text (present in most logs)
- `$metadata.error` - Error message (when errors occur)
- `$metadata.requestId` - Unique request identifier
- `$metadata.level` - Log level ("info", "error", "warn", "debug")

**Custom Log Fields (Feature-Specific):**
- `provider` - API provider ("google-books", "gemini", "openlibrary")
- `isbn` - ISBN being processed
- `jobId` - Background job identifier
- `confidence` - AI confidence score
- `tokensUsed` - Gemini API token consumption
- `cacheHit` - Cache status (true/false)
- `processingTime` - Request duration (ms)

**Filter Operations:**
- `eq` / `neq` - Equals / Not equals
- `gt` / `gte` / `lt` / `lte` - Comparisons (numbers)
- `includes` / `not_includes` - Substring match
- `starts_with` - Prefix match
- `regex` - ClickHouse RE2 regex (no lookaheads)
- `exists` / `is_null` - Field presence check
- `in` / `not_in` - Array membership

**Calculation Operators:**
- `count` - Count occurrences
- `uniq` - Unique values
- `sum` / `avg` / `median` - Aggregations
- `min` / `max` - Extremes
- `p001` / `p01` / `p05` / `p10` / `p25` / `p75` / `p90` / `p95` / `p99` / `p999` - Percentiles
- `stddev` / `variance` - Statistical measures

**Example Queries:**

**1. Recent Errors**
```
View: events
Filters:
  - $metadata.level = "error"
Timeframe: Last 30 minutes
Limit: 10
```

**2. Gemini Performance**
```
View: calculations
Filters:
  - $metadata.message includes "Gemini"
Calculations:
  - avg(processingTime)
  - p99(processingTime)
  - count()
GroupBy: None
Timeframe: Last 6 hours
```

**3. Search Endpoint Usage**
```
View: calculations
Filters:
  - $metadata.trigger starts_with "GET /search"
Calculations:
  - count()
GroupBy: $metadata.trigger
OrderBy: count DESC
Limit: 10
Timeframe: Last 24 hours
```

**Best Practices:**

1. **Always verify keys and values first** - Don't guess field names or values
2. **Use preferred keys** - `$metadata.*` fields are faster and always available
3. **Start broad, then narrow** - Begin with simple filters, add complexity gradually
4. **Appropriate time ranges** - Narrower = faster queries, more specific results
5. **Leverage groupBy** - For calculations, group by relevant dimensions
6. **Check token limits** - Gemini usage can be tracked via `tokensUsed` field

**Troubleshooting:**

- **No results?** → Broaden time range or relax filters
- **Invalid field error?** → Use observability_keys to see available options
- **Wrong values?** → Use observability_values to verify actual log values
- **Slow query?** → Reduce time range or use preferred $metadata.* fields

**Output Format:**

Present results clearly with:
- Query summary (time range, filters, view type)
- Total results count
- Key findings/patterns
- Formatted data (tables for calculations, lists for events)
- Actionable insights
- Follow-up suggestions

**Note:** This command requires the Cloudflare Observability MCP server to be active. All queries run against live Worker logs with structured querying capabilities.
