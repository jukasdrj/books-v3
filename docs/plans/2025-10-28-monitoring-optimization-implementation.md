# Monitoring & Optimization Implementation Plan - Phase 4

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build comprehensive monitoring, alerting, and continuous optimization system for hybrid cache architecture.

**Architecture:** Analytics Engine → Metrics Aggregator → /metrics API + Email Alerts + A/B Testing + Tuning Engine

**Tech Stack:** Cloudflare Workers, Analytics Engine, MailChannels, KV, Cron Triggers

**Prerequisites:**
- Phase 1-3 complete (Unified cache, warming, R2 storage)
- Analytics Engine datasets configured (`CACHE_ANALYTICS`, `PERFORMANCE_ANALYTICS`)
- MailChannels account for email alerts

---

## Task 1: Metrics Aggregation Service

**Files:**
- Create: `cloudflare-workers/api-worker/src/services/metrics-aggregator.js`
- Test: `cloudflare-workers/api-worker/tests/metrics-aggregator.test.js`

**Step 1: Write the failing test**

Create `tests/metrics-aggregator.test.js`:

```javascript
import { describe, it, expect, vi } from 'vitest';
import { aggregateMetrics } from '../src/services/metrics-aggregator.js';

describe('aggregateMetrics', () => {
  it('should calculate hit rates from Analytics Engine data', async () => {
    const mockEnv = {
      CACHE_ANALYTICS: {
        query: vi.fn().mockResolvedValue({
          results: [
            { cache_source: 'edge_hit', count: 78000, avg_latency: 8.2 },
            { cache_source: 'kv_hit', count: 16000, avg_latency: 42.1 },
            { cache_source: 'api_miss', count: 6000, avg_latency: 350.0 }
          ]
        })
      }
    };

    const metrics = await aggregateMetrics(mockEnv, '1h');

    expect(metrics.hitRates.edge).toBeCloseTo(78.0, 1);
    expect(metrics.hitRates.kv).toBeCloseTo(16.0, 1);
    expect(metrics.hitRates.combined).toBeCloseTo(94.0, 1);
    expect(metrics.volume.total_requests).toBe(100000);
  });
});
```

**Step 2: Run test to verify it fails**

Run: `npm test metrics-aggregator.test.js`

Expected: `FAIL - Cannot find module 'metrics-aggregator.js'`

**Step 3: Write minimal implementation**

Create `src/services/metrics-aggregator.js`:

```javascript
/**
 * Aggregate cache metrics from Analytics Engine
 *
 * @param {Object} env - Worker environment
 * @param {string} period - Time period ('1h', '24h', '7d')
 * @returns {Promise<Object>} Aggregated metrics
 */
export async function aggregateMetrics(env, period) {
  const periodMap = {
    '1h': '1 HOUR',
    '24h': '24 HOUR',
    '7d': '7 DAY'
  };

  const interval = periodMap[period] || '1 HOUR';

  // Query Analytics Engine
  const query = `
    SELECT
      index1 as cache_source,
      COUNT(*) as count,
      AVG(double1) as avg_latency,
      PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY double1) as p50,
      PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY double1) as p95,
      PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY double1) as p99
    FROM CACHE_ANALYTICS
    WHERE timestamp > NOW() - INTERVAL '${interval}'
    GROUP BY index1
  `;

  const result = await env.CACHE_ANALYTICS.query(query);

  // Calculate metrics
  let totalRequests = 0;
  let edgeHits = 0;
  let kvHits = 0;
  let r2Rehydrations = 0;
  let apiMisses = 0;

  const latencyData = {};

  for (const row of result.results || []) {
    const count = row.count || 0;
    totalRequests += count;

    if (row.cache_source === 'edge_hit') edgeHits = count;
    else if (row.cache_source === 'kv_hit') kvHits = count;
    else if (row.cache_source === 'r2_rehydrated') r2Rehydrations = count;
    else if (row.cache_source === 'api_miss') apiMisses = count;

    latencyData[row.cache_source] = {
      avg: row.avg_latency || 0,
      p50: row.p50 || 0,
      p95: row.p95 || 0,
      p99: row.p99 || 0
    };
  }

  return {
    timestamp: new Date().toISOString(),
    period: period,
    hitRates: {
      edge: totalRequests > 0 ? (edgeHits / totalRequests) * 100 : 0,
      kv: totalRequests > 0 ? (kvHits / totalRequests) * 100 : 0,
      r2_cold: totalRequests > 0 ? (r2Rehydrations / totalRequests) * 100 : 0,
      api: totalRequests > 0 ? (apiMisses / totalRequests) * 100 : 0,
      combined: totalRequests > 0 ? ((edgeHits + kvHits) / totalRequests) * 100 : 0
    },
    latency: latencyData,
    volume: {
      total_requests: totalRequests,
      edge_hits: edgeHits,
      kv_hits: kvHits,
      r2_rehydrations: r2Rehydrations,
      api_misses: apiMisses
    }
  };
}
```

**Step 4: Run test to verify it passes**

Run: `npm test metrics-aggregator.test.js`

Expected: `PASS`

**Step 5: Commit**

```bash
git add src/services/metrics-aggregator.js tests/metrics-aggregator.test.js
git commit -m "feat(monitoring): add metrics aggregation service"
```

---

## Task 2: Metrics API Endpoint

**Files:**
- Create: `cloudflare-workers/api-worker/src/handlers/metrics-handler.js`
- Modify: `cloudflare-workers/api-worker/src/index.js`

**Step 1: Create metrics endpoint handler**

Create `src/handlers/metrics-handler.js`:

```javascript
import { aggregateMetrics } from '../services/metrics-aggregator.js';

/**
 * GET /metrics - Cache metrics API endpoint
 *
 * Query params:
 *  - period: '1h' | '24h' | '7d' (default: '1h')
 *  - format: 'json' | 'prometheus' (default: 'json')
 *
 * @param {Request} request
 * @param {Object} env
 * @param {ExecutionContext} ctx
 * @returns {Response} Metrics data
 */
export async function handleMetricsRequest(request, env, ctx) {
  try {
    const url = new URL(request.url);
    const period = url.searchParams.get('period') || '1h';
    const format = url.searchParams.get('format') || 'json';

    // Check cache first (5min TTL)
    const cacheKey = `metrics:${period}`;
    const cached = await env.CACHE.get(cacheKey);
    if (cached) {
      return new Response(cached, {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Aggregate fresh metrics
    const metrics = await aggregateMetrics(env, period);

    // Add cost estimates
    metrics.costs = estimateCosts(metrics.volume);

    // Add health assessment
    metrics.health = assessHealth(metrics);

    // Format response
    const body = format === 'prometheus' ?
      formatPrometheus(metrics) :
      JSON.stringify(metrics, null, 2);

    // Cache for 5 minutes
    ctx.waitUntil(
      env.CACHE.put(cacheKey, body, {
        expirationTtl: 300
      })
    );

    return new Response(body, {
      headers: {
        'Content-Type': format === 'prometheus' ?
          'text/plain; version=0.0.4' :
          'application/json'
      }
    });

  } catch (error) {
    return new Response(JSON.stringify({
      error: 'Failed to fetch metrics',
      message: error.message
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

/**
 * Estimate operational costs from volume data
 * @param {Object} volume - Request volume data
 * @returns {Object} Cost estimates
 */
function estimateCosts(volume) {
  const kvReadCost = (volume.kv_hits * 0.50) / 1000000;
  const r2ReadCost = (volume.r2_rehydrations * 0.36) / 1000000;

  return {
    kv_reads_estimate: `$${kvReadCost.toFixed(4)}/period`,
    r2_reads: `$${r2ReadCost.toFixed(4)}/period`,
    total_estimate: `$${(kvReadCost + r2ReadCost).toFixed(4)}/period`
  };
}

/**
 * Assess cache health based on thresholds
 * @param {Object} metrics - Aggregated metrics
 * @returns {Object} Health status and issues
 */
function assessHealth(metrics) {
  const issues = [];

  // Check combined hit rate
  if (metrics.hitRates.combined < 90) {
    issues.push({
      severity: 'warning',
      message: `Combined hit rate below target (${metrics.hitRates.combined.toFixed(1)}% vs 95% target)`,
      since: metrics.timestamp
    });
  }

  // Check edge hit rate
  if (metrics.hitRates.edge < 75) {
    issues.push({
      severity: 'warning',
      message: `Edge hit rate low (${metrics.hitRates.edge.toFixed(1)}% vs 80% target)`,
      since: metrics.timestamp
    });
  }

  return {
    status: issues.length === 0 ? 'healthy' : 'degraded',
    issues: issues
  };
}

/**
 * Format metrics for Prometheus scraping
 * @param {Object} metrics - Aggregated metrics
 * @returns {string} Prometheus-formatted metrics
 */
function formatPrometheus(metrics) {
  return `
# HELP cache_hit_rate Cache hit rate by tier
# TYPE cache_hit_rate gauge
cache_hit_rate{tier="edge"} ${metrics.hitRates.edge}
cache_hit_rate{tier="kv"} ${metrics.hitRates.kv}
cache_hit_rate{tier="combined"} ${metrics.hitRates.combined}

# HELP cache_requests_total Total cache requests by tier
# TYPE cache_requests_total counter
cache_requests_total{tier="edge"} ${metrics.volume.edge_hits}
cache_requests_total{tier="kv"} ${metrics.volume.kv_hits}
cache_requests_total{tier="api_miss"} ${metrics.volume.api_misses}
  `.trim();
}
```

**Step 2: Add route to index.js**

Modify `src/index.js`:

```javascript
import { handleMetricsRequest } from './handlers/metrics-handler.js';

// GET /metrics - Cache metrics API
if (url.pathname === '/metrics' && request.method === 'GET') {
  return handleMetricsRequest(request, env, ctx);
}
```

**Step 3: Deploy and test**

Run: `npx wrangler deploy`

Test:
```bash
curl "https://api-worker.YOUR-DOMAIN.workers.dev/metrics?period=1h"
curl "https://api-worker.YOUR-DOMAIN.workers.dev/metrics?period=24h&format=prometheus"
```

Expected: JSON with hit rates, latency, costs, health

**Step 4: Commit**

```bash
git add src/handlers/metrics-handler.js src/index.js
git commit -m "feat(monitoring): add /metrics API endpoint"
```

---

## Task 3: Alert Monitor - Threshold Checking

**Files:**
- Create: `cloudflare-workers/api-worker/src/services/alert-monitor.js`
- Test: `cloudflare-workers/api-worker/tests/alert-monitor.test.js`

**Step 1: Write the failing test**

Create `tests/alert-monitor.test.js`:

```javascript
import { describe, it, expect } from 'vitest';
import { checkAlertThresholds } from '../src/services/alert-monitor.js';

describe('checkAlertThresholds', () => {
  it('should generate critical alert for high miss rate', () => {
    const metrics = {
      hitRates: { combined: 80 }, // < 85% threshold
      latency: { p99: 300 },
      volume: { total_requests: 10000 }
    };

    const alerts = checkAlertThresholds(metrics);

    expect(alerts).toHaveLength(1);
    expect(alerts[0].severity).toBe('critical');
    expect(alerts[0].type).toBe('miss_rate');
  });

  it('should generate warning for low edge hit rate', () => {
    const metrics = {
      hitRates: { combined: 95, edge: 70 }, // < 75% threshold
      latency: { p99: 50 },
      volume: { total_requests: 10000 }
    };

    const alerts = checkAlertThresholds(metrics);

    expect(alerts).toHaveLength(1);
    expect(alerts[0].severity).toBe('warning');
    expect(alerts[0].type).toBe('edge_hit_rate');
  });

  it('should return no alerts for healthy metrics', () => {
    const metrics = {
      hitRates: { combined: 96, edge: 82 },
      latency: { p99: 100 },
      volume: { total_requests: 10000 }
    };

    const alerts = checkAlertThresholds(metrics);

    expect(alerts).toHaveLength(0);
  });
});
```

**Step 2: Run test to verify it fails**

Run: `npm test alert-monitor.test.js`

Expected: `FAIL - Cannot find module 'alert-monitor.js'`

**Step 3: Write minimal implementation**

Create `src/services/alert-monitor.js`:

```javascript
/**
 * Alert thresholds configuration
 */
const ALERT_THRESHOLDS = {
  critical: {
    miss_rate: 15,          // > 15% miss rate
    p99_latency: 500,       // > 500ms P99
    error_rate: 5           // > 5% errors
  },
  warning: {
    miss_rate: 10,          // > 10% miss rate
    p95_latency: 100,       // > 100ms P95
    edge_hit_rate: 75,      // < 75% edge hits
    kv_storage: 1000        // > 1GB KV storage
  }
};

/**
 * Check metrics against alert thresholds
 *
 * @param {Object} metrics - Aggregated metrics
 * @returns {Array<Object>} Array of alerts
 */
export function checkAlertThresholds(metrics) {
  const alerts = [];

  // Critical: High miss rate
  const missRate = 100 - metrics.hitRates.combined;
  if (missRate > ALERT_THRESHOLDS.critical.miss_rate) {
    alerts.push({
      severity: 'critical',
      type: 'miss_rate',
      value: missRate,
      threshold: ALERT_THRESHOLDS.critical.miss_rate,
      message: `Cache miss rate critically high: ${missRate.toFixed(1)}%`
    });
  } else if (missRate > ALERT_THRESHOLDS.warning.miss_rate) {
    alerts.push({
      severity: 'warning',
      type: 'miss_rate',
      value: missRate,
      threshold: ALERT_THRESHOLDS.warning.miss_rate,
      message: `Cache miss rate elevated: ${missRate.toFixed(1)}%`
    });
  }

  // Warning: Low edge hit rate
  if (metrics.hitRates.edge < ALERT_THRESHOLDS.warning.edge_hit_rate) {
    alerts.push({
      severity: 'warning',
      type: 'edge_hit_rate',
      value: metrics.hitRates.edge,
      threshold: ALERT_THRESHOLDS.warning.edge_hit_rate,
      message: `Edge hit rate below target: ${metrics.hitRates.edge.toFixed(1)}%`
    });
  }

  // Critical: High P99 latency
  const p99 = metrics.latency?.edge_hit?.p99 || metrics.latency?.kv_hit?.p99 || 0;
  if (p99 > ALERT_THRESHOLDS.critical.p99_latency) {
    alerts.push({
      severity: 'critical',
      type: 'p99_latency',
      value: p99,
      threshold: ALERT_THRESHOLDS.critical.p99_latency,
      message: `P99 latency critically high: ${p99.toFixed(0)}ms`
    });
  }

  return alerts;
}

/**
 * Check if alert should be sent (deduplication)
 *
 * @param {Array<Object>} alerts - Alerts to check
 * @param {Object} env - Worker environment
 * @returns {Promise<boolean>} True if should send
 */
export async function shouldSendAlert(alerts, env) {
  if (alerts.length === 0) return false;

  // Generate alert key from alert types
  const alertKey = alerts.map(a => a.type).sort().join(':');
  const cacheKey = `alert:${alertKey}`;

  // Check last alert time
  const lastAlert = await env.CACHE.get(cacheKey);
  if (lastAlert) {
    const timeSince = Date.now() - parseInt(lastAlert);
    const fourHours = 4 * 60 * 60 * 1000;

    if (timeSince < fourHours) {
      console.log(`Skipping duplicate alert (sent ${Math.floor(timeSince / 1000 / 60)}min ago)`);
      return false;
    }
  }

  return true;
}

/**
 * Mark alert as sent
 *
 * @param {Array<Object>} alerts - Alerts that were sent
 * @param {Object} env - Worker environment
 */
export async function markAlertSent(alerts, env) {
  const alertKey = alerts.map(a => a.type).sort().join(':');
  const cacheKey = `alert:${alertKey}`;

  await env.CACHE.put(cacheKey, Date.now().toString(), {
    expirationTtl: 4 * 60 * 60 // 4 hours
  });
}
```

**Step 4: Run test to verify it passes**

Run: `npm test alert-monitor.test.js`

Expected: `PASS`

**Step 5: Commit**

```bash
git add src/services/alert-monitor.js tests/alert-monitor.test.js
git commit -m "feat(monitoring): add alert threshold checking"
```

---

## Task 4: Email Alert Service (MailChannels)

**Files:**
- Create: `cloudflare-workers/api-worker/src/services/email-alerts.js`
- Test: `cloudflare-workers/api-worker/tests/email-alerts.test.js`

**Step 1: Write the failing test**

Create `tests/email-alerts.test.js`:

```javascript
import { describe, it, expect, vi } from 'vitest';
import { sendAlertEmail } from '../src/services/email-alerts.js';

describe('sendAlertEmail', () => {
  it('should send email via MailChannels API', async () => {
    global.fetch = vi.fn().mockResolvedValue({
      ok: true,
      status: 202
    });

    const alerts = [{
      severity: 'critical',
      type: 'miss_rate',
      value: 18,
      threshold: 15,
      message: 'Cache miss rate critically high: 18.0%'
    }];

    const metrics = {
      hitRates: { combined: 82, edge: 70 },
      volume: { total_requests: 10000 }
    };

    await sendAlertEmail(alerts, metrics, 'test@example.com');

    expect(fetch).toHaveBeenCalledWith(
      'https://api.mailchannels.net/tx/v1/send',
      expect.objectContaining({
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: expect.stringContaining('Cache miss rate critically high')
      })
    );
  });
});
```

**Step 2: Run test to verify it fails**

Run: `npm test email-alerts.test.js`

Expected: `FAIL - Cannot find module 'email-alerts.js'`

**Step 3: Write minimal implementation**

Create `src/services/email-alerts.js`:

```javascript
/**
 * Send alert email via MailChannels API
 *
 * @param {Array<Object>} alerts - Alerts to send
 * @param {Object} metrics - Recent metrics
 * @param {string} toEmail - Recipient email address
 * @returns {Promise<void>}
 */
export async function sendAlertEmail(alerts, metrics, toEmail) {
  const subject = `[BooksTrack Cache] ${alerts[0].severity.toUpperCase()}: ${alerts[0].type}`;

  const htmlBody = `
<!DOCTYPE html>
<html>
<head>
  <style>
    .critical { color: #dc2626; font-weight: bold; }
    .warning { color: #f59e0b; font-weight: bold; }
    .metric { font-family: monospace; background: #f3f4f6; padding: 4px 8px; border-radius: 4px; }
    body { font-family: system-ui, sans-serif; }
    h2 { margin-top: 24px; }
    ul { line-height: 1.8; }
  </style>
</head>
<body>
  <h2 class="${alerts[0].severity}">Cache ${alerts[0].severity}: ${alerts[0].type}</h2>

  <h3>Alert Details</h3>
  <ul>
    ${alerts.map(alert => `
      <li class="${alert.severity}">
        ${alert.message}<br>
        <span class="metric">Current: ${alert.value.toFixed(1)} | Threshold: ${alert.threshold}</span>
      </li>
    `).join('')}
  </ul>

  <h3>Recent Metrics (Last 15 minutes)</h3>
  <ul>
    <li>Hit Rate: <span class="metric">${metrics.hitRates.combined.toFixed(1)}%</span> (Edge: ${metrics.hitRates.edge.toFixed(1)}%, KV: ${metrics.hitRates.kv.toFixed(1)}%)</li>
    <li>Volume: <span class="metric">${metrics.volume.total_requests} requests</span></li>
  </ul>

  <h3>Possible Causes</h3>
  <ul>
    <li>Edge cache purge/restart</li>
    <li>Traffic spike to new content</li>
    <li>External API slowness/rate limiting</li>
    <li>R2 archival too aggressive</li>
  </ul>

  <p><a href="https://api-worker.your-domain.workers.dev/metrics?period=1h">View detailed metrics</a></p>

  <hr>
  <small>Auto-generated by Cache Monitor | Timestamp: ${new Date().toISOString()}</small>
</body>
</html>
  `;

  const payload = {
    personalizations: [{
      to: [{ email: toEmail }]
    }],
    from: {
      email: 'alerts@bookstrack.app',
      name: 'BooksTrack Cache Monitor'
    },
    subject: subject,
    content: [{
      type: 'text/html',
      value: htmlBody
    }]
  };

  const response = await fetch('https://api.mailchannels.net/tx/v1/send', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(payload)
  });

  if (!response.ok) {
    throw new Error(`MailChannels API failed: ${response.status}`);
  }

  console.log(`Alert email sent to ${toEmail}`);
}
```

**Step 4: Run test to verify it passes**

Run: `npm test email-alerts.test.js`

Expected: `PASS`

**Step 5: Commit**

```bash
git add src/services/email-alerts.js tests/email-alerts.test.js
git commit -m "feat(monitoring): add email alert service via MailChannels"
```

---

## Task 5: Scheduled Alert Monitor Cron

**Files:**
- Create: `cloudflare-workers/api-worker/src/handlers/scheduled-alerts.js`
- Modify: `cloudflare-workers/api-worker/src/index.js`
- Modify: `cloudflare-workers/api-worker/wrangler.toml`

**Step 1: Update cron triggers**

Modify `wrangler.toml`:

```toml
[triggers]
crons = [
  "0 2 * * *",      # Daily archival at 2:00 AM UTC
  "*/15 * * * *"    # Alert checks every 15 minutes
]
```

**Step 2: Create alert cron handler**

Create `src/handlers/scheduled-alerts.js`:

```javascript
import { aggregateMetrics } from '../services/metrics-aggregator.js';
import { checkAlertThresholds, shouldSendAlert, markAlertSent } from '../services/alert-monitor.js';
import { sendAlertEmail } from '../services/email-alerts.js';

/**
 * Scheduled handler for alert monitoring
 *
 * @param {Object} env - Worker environment
 * @param {ExecutionContext} ctx - Execution context
 */
export async function handleScheduledAlerts(env, ctx) {
  try {
    console.log('Running alert check...');

    // 1. Get recent metrics (last 15 minutes)
    const metrics = await aggregateMetrics(env, '15m');

    // 2. Check thresholds
    const alerts = checkAlertThresholds(metrics);

    if (alerts.length === 0) {
      console.log('No alerts triggered');
      return;
    }

    console.log(`Generated ${alerts.length} alerts:`, alerts.map(a => a.type));

    // 3. Check deduplication
    const shouldSend = await shouldSendAlert(alerts, env);
    if (!shouldSend) {
      console.log('Alert suppressed (duplicate)');
      return;
    }

    // 4. Send email
    const alertEmail = env.ALERT_EMAIL || 'nerd@ooheynerds.com';
    await sendAlertEmail(alerts, metrics, alertEmail);

    // 5. Mark as sent
    await markAlertSent(alerts, env);

    console.log(`Alert email sent to ${alertEmail}`);

  } catch (error) {
    console.error('Alert check failed:', error);
  }
}
```

**Step 3: Update scheduled handler router**

Modify `src/index.js`:

```javascript
import { handleScheduledArchival } from './handlers/scheduled-archival.js';
import { handleScheduledAlerts } from './handlers/scheduled-alerts.js';

export default {
  async fetch(request, env, ctx) {
    // ... existing HTTP routing ...
  },

  async queue(batch, env, ctx) {
    // ... existing queue routing ...
  },

  async scheduled(event, env, ctx) {
    // Route by cron pattern
    if (event.cron === '0 2 * * *') {
      // Daily archival at 2:00 AM UTC
      await handleScheduledArchival(env, ctx);
    } else if (event.cron === '*/15 * * * *') {
      // Alert checks every 15 minutes
      await handleScheduledAlerts(env, ctx);
    }
  }
};
```

**Step 4: Add environment variable for alert email**

Modify `wrangler.toml`:

```toml
[vars]
# ... existing vars ...
ALERT_EMAIL = "nerd@ooheynerds.com"
```

**Step 5: Deploy and test**

Run: `npx wrangler deploy`

Test manually (trigger cron via Cloudflare dashboard or wait 15min):
```bash
npx wrangler tail api-worker --format pretty
```

Expected: Logs showing `Running alert check...`

**Step 6: Commit**

```bash
git add src/handlers/scheduled-alerts.js src/index.js wrangler.toml
git commit -m "feat(monitoring): add scheduled alert monitoring cron"
```

---

## Task 6: Performance Tuning Engine - A/B Testing Framework

**Files:**
- Create: `cloudflare-workers/api-worker/src/services/tuning-engine.js`
- Test: `cloudflare-workers/api-worker/tests/tuning-engine.test.js`

**Step 1: Write the failing test**

Create `tests/tuning-engine.test.js`:

```javascript
import { describe, it, expect } from 'vitest';
import { assignCohort, analyzeExperiment } from '../src/services/tuning-engine.js';

describe('Tuning Engine', () => {
  it('should consistently assign cache keys to cohorts', async () => {
    const experiment = {
      name: 'extended-title-ttl',
      cohorts: [
        { name: 'control', ttl: 24 * 60 * 60, weight: 0.5 },
        { name: 'treatment', ttl: 48 * 60 * 60, weight: 0.5 }
      ]
    };

    const cacheKey = 'search:title:q=hamlet';

    const cohort1 = await assignCohort(cacheKey, experiment);
    const cohort2 = await assignCohort(cacheKey, experiment);

    expect(cohort1.name).toBe(cohort2.name); // Consistent
  });

  it('should identify winner with statistical significance', () => {
    const experiment = {
      name: 'extended-title-ttl',
      cohorts: [
        { name: 'control', ttl: 24 * 60 * 60 },
        { name: 'treatment', ttl: 48 * 60 * 60 }
      ]
    };

    const controlMetrics = { hit_rate: 92.0, sample_size: 10000 };
    const treatmentMetrics = { hit_rate: 95.5, sample_size: 10000 };

    const result = analyzeExperiment(experiment, controlMetrics, treatmentMetrics);

    expect(result.winner).toBe('treatment');
    expect(result.confidence).toBeGreaterThan(95);
  });
});
```

**Step 2: Run test to verify it fails**

Run: `npm test tuning-engine.test.js`

Expected: `FAIL - Cannot find module 'tuning-engine.js'`

**Step 3: Write minimal implementation**

Create `src/services/tuning-engine.js`:

```javascript
/**
 * Active tuning experiments
 */
export const ACTIVE_EXPERIMENTS = [];

/**
 * Assign cache key to experiment cohort (stable hash-based)
 *
 * @param {string} cacheKey - Cache key
 * @param {Object} experiment - Experiment configuration
 * @returns {Promise<Object>} Assigned cohort
 */
export async function assignCohort(cacheKey, experiment) {
  // Hash cache key + experiment name for stable assignment
  const encoder = new TextEncoder();
  const data = encoder.encode(cacheKey + experiment.name);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = new Uint8Array(hashBuffer);
  const hashValue = hashArray[0] / 255; // 0.0 to 1.0

  // Assign to cohort based on weight distribution
  let cumWeight = 0;
  for (const cohort of experiment.cohorts) {
    cumWeight += cohort.weight;
    if (hashValue < cumWeight) {
      return cohort;
    }
  }

  return experiment.cohorts[0]; // Fallback to first cohort
}

/**
 * Analyze experiment and determine winner
 *
 * @param {Object} experiment - Experiment configuration
 * @param {Object} controlMetrics - Control cohort metrics
 * @param {Object} treatmentMetrics - Treatment cohort metrics
 * @returns {Object} Analysis result with winner and confidence
 */
export function analyzeExperiment(experiment, controlMetrics, treatmentMetrics) {
  const hitRateDiff = treatmentMetrics.hit_rate - controlMetrics.hit_rate;

  // Simple t-test for significance (simplified)
  const pooledStdDev = Math.sqrt(
    (controlMetrics.hit_rate * (100 - controlMetrics.hit_rate)) / controlMetrics.sample_size +
    (treatmentMetrics.hit_rate * (100 - treatmentMetrics.hit_rate)) / treatmentMetrics.sample_size
  );

  const tStat = Math.abs(hitRateDiff) / pooledStdDev;
  const pValue = calculatePValue(tStat);

  const result = {
    experiment: experiment.name,
    control: controlMetrics,
    treatment: treatmentMetrics,
    hitRateDiff: hitRateDiff,
    pValue: pValue,
    winner: null,
    confidence: 0
  };

  if (pValue < 0.05 && hitRateDiff > 0) {
    result.winner = 'treatment';
    result.confidence = (1 - pValue) * 100;
  } else if (pValue < 0.05 && hitRateDiff < 0) {
    result.winner = 'control';
    result.confidence = (1 - pValue) * 100;
  } else {
    result.winner = 'inconclusive';
  }

  return result;
}

/**
 * Calculate p-value from t-statistic (simplified approximation)
 * @param {number} tStat - T-statistic
 * @returns {number} P-value
 */
function calculatePValue(tStat) {
  // Simplified normal approximation (for large samples)
  // Real implementation would use t-distribution
  const z = tStat;
  return 2 * (1 - normalCDF(Math.abs(z)));
}

/**
 * Normal cumulative distribution function
 * @param {number} z - Z-score
 * @returns {number} Cumulative probability
 */
function normalCDF(z) {
  const t = 1 / (1 + 0.2316419 * z);
  const d = 0.3989423 * Math.exp(-z * z / 2);
  const p = d * t * (0.3193815 + t * (-0.3565638 + t * (1.781478 + t * (-1.821256 + t * 1.330274))));
  return 1 - p;
}

/**
 * Promote winning treatment to default configuration
 *
 * @param {Object} experiment - Experiment
 * @param {Object} env - Worker environment
 */
export async function promoteTreatment(experiment, env) {
  const treatmentCohort = experiment.cohorts.find(c => c.name === 'treatment');

  // Write new TTL config to KV
  const config = {
    title: treatmentCohort.ttl,
    isbn: 30 * 24 * 60 * 60,
    author: 7 * 24 * 60 * 60
  };

  await env.CACHE.put('config:kv-ttls', JSON.stringify(config));

  console.log(`Promoted ${experiment.name}: TTL ${treatmentCohort.ttl}s now default`);
}
```

**Step 4: Run test to verify it passes**

Run: `npm test tuning-engine.test.js`

Expected: `PASS`

**Step 5: Commit**

```bash
git add src/services/tuning-engine.js tests/tuning-engine.test.js
git commit -m "feat(monitoring): add A/B testing tuning engine"
```

---

## Task 7: Integrate A/B Testing into KVCacheService

**Files:**
- Modify: `cloudflare-workers/api-worker/src/services/kv-cache.js`

**Step 1: Add experiment integration**

Modify `src/services/kv-cache.js`:

```javascript
import { ACTIVE_EXPERIMENTS, assignCohort } from './tuning-engine.js';

async set(cacheKey, data, endpoint, options = {}) {
  try {
    let baseTTL = options.ttl || this.ttls[endpoint] || this.ttls.title;

    // Check for active experiments
    const experiment = ACTIVE_EXPERIMENTS.find(e =>
      e.targetEndpoint === endpoint && e.status === 'active'
    );

    if (experiment) {
      const cohort = await assignCohort(cacheKey, experiment);
      baseTTL = cohort.ttl;

      // Log experiment assignment (for later analysis)
      if (this.env.CACHE_ANALYTICS) {
        this.env.CACHE_ANALYTICS.writeDataPoint({
          blobs: ['experiment_assignment', experiment.name, cohort.name],
          doubles: [cohort.ttl],
          indexes: ['experiment_assignment']
        });
      }
    }

    await this.env.CACHE.put(cacheKey, JSON.stringify(data), {
      expirationTtl: baseTTL,
      metadata: {
        cachedAt: Date.now(),
        endpoint: endpoint,
        experiment: experiment?.name || null,
        cohort: experiment ? (await assignCohort(cacheKey, experiment)).name : null
      }
    });

  } catch (error) {
    console.error(`KV cache set failed for ${cacheKey}:`, error);
  }
}
```

**Step 2: Commit**

```bash
git add src/services/kv-cache.js
git commit -m "feat(monitoring): integrate A/B testing into KVCacheService"
```

---

## Task 8: Experiment Analysis Cron

**Files:**
- Create: `cloudflare-workers/api-worker/src/handlers/scheduled-experiments.js`
- Modify: `cloudflare-workers/api-worker/src/index.js`
- Modify: `wrangler.toml`

**Step 1: Add daily experiment analysis cron**

Modify `wrangler.toml`:

```toml
[triggers]
crons = [
  "0 2 * * *",      # Daily archival at 2:00 AM UTC
  "*/15 * * * *",   # Alert checks every 15 minutes
  "0 3 * * *"       # Experiment analysis at 3:00 AM UTC
]
```

**Step 2: Create experiment analysis handler**

Create `src/handlers/scheduled-experiments.js`:

```javascript
import { ACTIVE_EXPERIMENTS, analyzeExperiment, promoteTreatment } from '../services/tuning-engine.js';
import { sendAlertEmail } from '../services/email-alerts.js';

/**
 * Scheduled handler for experiment analysis
 *
 * @param {Object} env - Worker environment
 * @param {ExecutionContext} ctx - Execution context
 */
export async function handleScheduledExperiments(env, ctx) {
  try {
    console.log('Analyzing experiments...');

    for (const experiment of ACTIVE_EXPERIMENTS) {
      // Check if experiment duration complete
      const runningTime = Date.now() - experiment.startedAt;
      if (runningTime < experiment.duration) {
        console.log(`Experiment ${experiment.name} still running (${Math.floor(runningTime / 1000 / 60 / 60)}h / ${experiment.duration / 1000 / 60 / 60}h)`);
        continue;
      }

      console.log(`Analyzing completed experiment: ${experiment.name}`);

      // Query metrics for each cohort
      const controlMetrics = await getCohortMetrics('control', experiment, env);
      const treatmentMetrics = await getCohortMetrics('treatment', experiment, env);

      // Analyze
      const result = analyzeExperiment(experiment, controlMetrics, treatmentMetrics);

      console.log(`Experiment ${experiment.name} result:`, result);

      // Auto-promote if treatment wins with high confidence
      if (result.winner === 'treatment' && result.confidence > 95 && result.hitRateDiff > 2) {
        await promoteTreatment(experiment, env);

        // Send notification email
        const alertEmail = env.ALERT_EMAIL || 'nerd@ooheynerds.com';
        await sendPromotionEmail(experiment, result, alertEmail);

        // Mark experiment as completed
        experiment.status = 'completed';
      }

      // Log results to KV
      await env.CACHE.put(`experiment:result:${experiment.name}`, JSON.stringify({
        ...result,
        analyzedAt: Date.now()
      }));
    }

  } catch (error) {
    console.error('Experiment analysis failed:', error);
  }
}

/**
 * Get metrics for specific cohort
 * @param {string} cohortName - Cohort name
 * @param {Object} experiment - Experiment configuration
 * @param {Object} env - Worker environment
 * @returns {Promise<Object>} Cohort metrics
 */
async function getCohortMetrics(cohortName, experiment, env) {
  const query = `
    SELECT
      COUNT(*) as sample_size,
      AVG(CASE WHEN index1 IN ('edge_hit', 'kv_hit') THEN 100.0 ELSE 0.0 END) as hit_rate
    FROM CACHE_ANALYTICS
    WHERE
      blob2 = '${experiment.name}' AND
      blob3 = '${cohortName}' AND
      timestamp > FROM_UNIXTIME(${experiment.startedAt / 1000})
  `;

  const result = await env.CACHE_ANALYTICS.query(query);

  return {
    hit_rate: result.results[0]?.hit_rate || 0,
    sample_size: result.results[0]?.sample_size || 0
  };
}

/**
 * Send experiment promotion email
 * @param {Object} experiment - Experiment
 * @param {Object} result - Analysis result
 * @param {string} toEmail - Recipient email
 */
async function sendPromotionEmail(experiment, result, toEmail) {
  const payload = {
    personalizations: [{ to: [{ email: toEmail }] }],
    from: { email: 'alerts@bookstrack.app', name: 'BooksTrack Tuning Engine' },
    subject: `[BooksTrack Cache] Experiment Promoted: ${experiment.name}`,
    content: [{
      type: 'text/html',
      value: `
        <h2>Experiment Promoted: ${experiment.name}</h2>
        <p>Treatment has been promoted to default configuration!</p>
        <ul>
          <li>Hit Rate Improvement: <strong>+${result.hitRateDiff.toFixed(1)}%</strong></li>
          <li>Confidence: <strong>${result.confidence.toFixed(1)}%</strong></li>
          <li>Control Hit Rate: ${result.control.hit_rate.toFixed(1)}%</li>
          <li>Treatment Hit Rate: ${result.treatment.hit_rate.toFixed(1)}%</li>
        </ul>
        <p>New TTL: ${experiment.cohorts.find(c => c.name === 'treatment').ttl}s</p>
      `
    }]
  };

  await fetch('https://api.mailchannels.net/tx/v1/send', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload)
  });
}
```

**Step 3: Update scheduled router**

Modify `src/index.js`:

```javascript
import { handleScheduledExperiments } from './handlers/scheduled-experiments.js';

async scheduled(event, env, ctx) {
  if (event.cron === '0 2 * * *') {
    await handleScheduledArchival(env, ctx);
  } else if (event.cron === '*/15 * * * *') {
    await handleScheduledAlerts(env, ctx);
  } else if (event.cron === '0 3 * * *') {
    await handleScheduledExperiments(env, ctx);
  }
}
```

**Step 4: Deploy**

Run: `npx wrangler deploy`

**Step 5: Commit**

```bash
git add src/handlers/scheduled-experiments.js src/index.js wrangler.toml
git commit -m "feat(monitoring): add scheduled experiment analysis"
```

---

## Task 9: Documentation

**Files:**
- Create: `cloudflare-workers/api-worker/docs/MONITORING_OPTIMIZATION.md`

**Step 1: Write comprehensive documentation**

Create `docs/MONITORING_OPTIMIZATION.md`:

```markdown
# Monitoring & Optimization - Phase 4

## Overview

Comprehensive monitoring, alerting, and continuous optimization system for hybrid cache architecture.

## Components

### 1. Metrics API

**Endpoint:** `GET /metrics?period=1h&format=json`

**Response:**
\`\`\`json
{
  "hitRates": {
    "edge": 78.2,
    "kv": 16.5,
    "combined": 94.7
  },
  "latency": {
    "edge_hit": { "p50": 8.2, "p95": 12.5, "p99": 18.0 }
  },
  "costs": {
    "total_estimate": "$0.0025/period"
  },
  "health": {
    "status": "healthy",
    "issues": []
  }
}
\`\`\`

**Prometheus Format:**
\`\`\`bash
curl "https://api-worker.YOUR-DOMAIN.workers.dev/metrics?format=prometheus"
\`\`\`

### 2. Alert Monitor

**Schedule:** Every 15 minutes

**Thresholds:**
- **Critical:** Miss rate > 15%, P99 latency > 500ms
- **Warning:** Edge hit rate < 75%, P95 latency > 100ms

**Deduplication:** 4-hour window (same alert suppressed)

**Email Format:** HTML with metrics, health status, troubleshooting tips

### 3. A/B Testing Framework

**Define Experiment:**
\`\`\`javascript
ACTIVE_EXPERIMENTS.push({
  name: 'extended-title-ttl',
  targetEndpoint: 'title',
  cohorts: [
    { name: 'control', ttl: 24 * 60 * 60, weight: 0.5 },
    { name: 'treatment', ttl: 48 * 60 * 60, weight: 0.5 }
  ],
  duration: 7 * 24 * 60 * 60 * 1000, // 7 days
  startedAt: Date.now(),
  status: 'active'
});
\`\`\`

**Auto-Promotion Criteria:**
- Winner confidence > 95%
- Hit rate improvement > 2%
- Both cohorts have > 1000 samples

### 4. Cost Analysis

**Daily Report:** Sent at 3:00 AM UTC

**Content:**
- Cache tier distribution
- Cost breakdown (KV reads, R2 reads, storage)
- Optimization recommendations
- Potential savings estimates

## Analytics Engine Queries

**Hit Rate Trend (7 days):**
\`\`\`sql
SELECT
  DATE_TRUNC('day', timestamp) as day,
  COUNT(CASE WHEN index1 = 'edge_hit' THEN 1 END) as edge_hits,
  COUNT(CASE WHEN index1 = 'kv_hit' THEN 1 END) as kv_hits,
  COUNT(*) as total
FROM CACHE_ANALYTICS
WHERE timestamp > NOW() - INTERVAL '7' DAY
GROUP BY day
ORDER BY day DESC;
\`\`\`

**Experiment Cohort Comparison:**
\`\`\`sql
SELECT
  blob3 as cohort,
  COUNT(*) as sample_size,
  AVG(CASE WHEN index1 IN ('edge_hit', 'kv_hit') THEN 100.0 ELSE 0.0 END) as hit_rate
FROM CACHE_ANALYTICS
WHERE
  blob2 = 'extended-title-ttl' AND
  timestamp > NOW() - INTERVAL '7' DAY
GROUP BY blob3;
\`\`\`

## Troubleshooting

**No alerts received:**
1. Check scheduled cron is running: `wrangler deployments list`
2. Verify MailChannels integration: Send test email
3. Check alert suppression cache: `wrangler kv:key list CACHE --prefix="alert:"`

**Experiment not analyzing:**
1. Verify experiment is in `ACTIVE_EXPERIMENTS`
2. Check experiment duration elapsed
3. Ensure cohort metrics exist in Analytics Engine
4. Check logs: `wrangler tail api-worker`

**High costs:**
1. Review metrics API for cost breakdown
2. Check KV hit rate (should be > 15%)
3. Verify R2 archival is working
4. Consider increasing cache TTLs

## Cost Estimates

**Phase 4 Operational Costs:**
- Analytics Engine queries: ~200/day (free tier)
- MailChannels emails: ~10/day (free tier)
- Cron CPU time: ~2s/day (negligible)
- **Total: ~$0.05/month**
```

**Step 2: Commit**

```bash
git add docs/MONITORING_OPTIMIZATION.md
git commit -m "docs(monitoring): add monitoring & optimization guide"
```

---

## Verification Checklist

Before considering Phase 4 complete, verify:

- [ ] `/metrics` endpoint returns valid JSON
- [ ] Prometheus format works (`?format=prometheus`)
- [ ] Alert cron runs every 15 minutes
- [ ] Test alert email received successfully
- [ ] A/B testing assigns cohorts consistently
- [ ] Experiment analysis cron runs daily
- [ ] Promotion email sent on experiment win
- [ ] Analytics Engine queries return data
- [ ] All tests pass: `npm test`
- [ ] Documentation complete

---

## Next Steps

After Phase 4 deployment:

1. **Create first experiment:** Test 48h TTL for title searches
2. **Set up Grafana:** Import Prometheus metrics for dashboards
3. **Add Slack webhooks:** Real-time alerts to team channels
4. **ML-based optimization:** Predict optimal TTLs per cache key
5. **Multi-variate testing:** Test multiple parameters simultaneously
