# Monitoring & Optimization Design - Phase 4

**Date:** 2025-10-28
**Status:** Design Approved
**Prerequisites:** Phase 1 (Foundation), Phase 2 (Warming), Phase 3 (R2 Storage)

## Overview

Comprehensive monitoring, alerting, and continuous optimization system for the hybrid cache architecture. Provides real-time metrics, proactive alerts, and automated performance tuning.

## Goals

1. **Proactive alerting:** Detect and notify on performance degradation before users notice
2. **Cost visibility:** Track KV/R2 costs, identify expensive patterns
3. **Performance tuning:** A/B test strategies, auto-promote winners
4. **Developer experience:** Easy debugging, clear error messages

## Architecture

```
Analytics Engine → Metrics Aggregator → /metrics API + Email Alerts + Tuning Engine
```

### Components

#### 1. Metrics API Endpoint

**Endpoint:** `GET /metrics`

**Query Parameters:**
- `?period=1h|24h|7d` (default: 1h)
- `?format=json|prometheus` (default: json)

**Response:**
```json
{
  "timestamp": "2025-10-28T15:30:00Z",
  "period": "1h",
  "hitRates": {
    "edge": 78.2,
    "kv": 16.5,
    "r2_cold": 0.8,
    "api": 4.5,
    "combined": 95.5
  },
  "latency": {
    "p50": 8.2,
    "p95": 42.1,
    "p99": 180.5,
    "avg": 15.3
  },
  "volume": {
    "total_requests": 125000,
    "edge_hits": 97750,
    "kv_hits": 20625,
    "r2_rehydrations": 1000,
    "api_misses": 5625
  },
  "costs": {
    "kv_reads_estimate": "$2.15/day",
    "kv_writes_estimate": "$0.45/day",
    "kv_storage": "350MB ($0.175/month)",
    "r2_storage": "150MB ($0.002/month)",
    "r2_reads": "$0.001/day",
    "total_estimate": "$2.62/day ($78.60/month)"
  },
  "health": {
    "status": "healthy|degraded|critical",
    "issues": [
      {
        "severity": "warning",
        "message": "Edge hit rate below target (78.2% vs 80% target)",
        "since": "2025-10-28T14:00:00Z"
      }
    ]
  },
  "topKeys": [
    {
      "key": "search:title:q=hamlet",
      "requests": 1250,
      "hitRate": 98.5,
      "tier": "edge"
    }
  ]
}
```

**Implementation:**
```javascript
export async function handleMetricsRequest(request, env, ctx) {
  const url = new URL(request.url);
  const period = url.searchParams.get('period') || '1h';

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
    WHERE timestamp > NOW() - INTERVAL '${period}'
    GROUP BY index1
  `;

  const results = await queryAnalyticsEngine(query, env);

  // Aggregate metrics
  const metrics = {
    timestamp: new Date().toISOString(),
    period: period,
    hitRates: calculateHitRates(results),
    latency: extractLatency(results),
    volume: extractVolume(results),
    costs: estimateCosts(results, env),
    health: assessHealth(results),
    topKeys: await getTopKeys(env, period)
  };

  // Cache for 5 minutes
  ctx.waitUntil(
    env.CACHE.put(`metrics:${period}`, JSON.stringify(metrics), {
      expirationTtl: 300
    })
  );

  return new Response(JSON.stringify(metrics, null, 2), {
    headers: { 'Content-Type': 'application/json' }
  });
}
```

**Caching:** Metrics responses cached for 5 minutes to reduce Analytics Engine queries

#### 2. Alert Monitor

**Schedule:** Cron every 15 minutes

**Thresholds:**
```javascript
const ALERT_THRESHOLDS = {
  critical: {
    miss_rate: 15,          // > 15% miss rate
    p99_latency: 500,       // > 500ms P99
    error_rate: 5,          // > 5% errors
    queue_depth: 1000       // > 1000 pending warming jobs
  },
  warning: {
    miss_rate: 10,          // > 10% miss rate
    p95_latency: 100,       // > 100ms P95
    edge_hit_rate: 75,      // < 75% edge hits
    kv_storage: 1000        // > 1GB KV storage
  }
};
```

**Monitoring Logic:**
```javascript
async function checkAlerts(env, ctx) {
  const metrics = await getMetrics('15m', env);

  const alerts = [];

  // Critical: High miss rate
  if ((100 - metrics.hitRates.combined) > ALERT_THRESHOLDS.critical.miss_rate) {
    alerts.push({
      severity: 'critical',
      type: 'miss_rate',
      value: 100 - metrics.hitRates.combined,
      threshold: ALERT_THRESHOLDS.critical.miss_rate,
      message: `Cache miss rate critically high: ${(100 - metrics.hitRates.combined).toFixed(1)}%`
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
  if (metrics.latency.p99 > ALERT_THRESHOLDS.critical.p99_latency) {
    alerts.push({
      severity: 'critical',
      type: 'p99_latency',
      value: metrics.latency.p99,
      threshold: ALERT_THRESHOLDS.critical.p99_latency,
      message: `P99 latency critically high: ${metrics.latency.p99.toFixed(0)}ms`
    });
  }

  // Send alerts (deduplicated)
  if (alerts.length > 0) {
    await sendAlertsEmail(alerts, metrics, env, ctx);
  }
}
```

**Deduplication:**
```javascript
async function sendAlertsEmail(alerts, metrics, env, ctx) {
  // Check if we've alerted for this issue recently
  const alertKey = alerts.map(a => a.type).sort().join(':');
  const lastAlert = await env.CACHE.get(`alert:${alertKey}`);

  if (lastAlert) {
    const timeSince = Date.now() - parseInt(lastAlert);
    if (timeSince < 4 * 60 * 60 * 1000) { // 4 hours
      return; // Skip duplicate
    }
  }

  // Send email via MailChannels
  await sendEmail(env, {
    to: env.ALERT_EMAIL || 'nerd@ooheynerds.com',
    subject: `[BooksTrack Cache] ${alerts[0].severity.toUpperCase()}: ${alerts[0].type}`,
    body: formatAlertEmail(alerts, metrics)
  });

  // Mark as alerted
  await env.CACHE.put(`alert:${alertKey}`, Date.now().toString(), {
    expirationTtl: 4 * 60 * 60 // 4 hours
  });
}
```

**Email Template:**
```html
<!DOCTYPE html>
<html>
<head>
  <style>
    .critical { color: #dc2626; font-weight: bold; }
    .warning { color: #f59e0b; font-weight: bold; }
    .metric { font-family: monospace; background: #f3f4f6; padding: 4px 8px; }
  </style>
</head>
<body>
  <h2 class="{{severity}}">Cache {{severity}}: {{type}}</h2>

  <h3>Alert Details</h3>
  <ul>
    {{#each alerts}}
    <li class="{{severity}}">
      {{message}}<br>
      <span class="metric">Current: {{value}} | Threshold: {{threshold}}</span>
    </li>
    {{/each}}
  </ul>

  <h3>Recent Metrics (Last 15 minutes)</h3>
  <ul>
    <li>Hit Rate: <span class="metric">{{hitRates.combined}}%</span> (Edge: {{hitRates.edge}}%, KV: {{hitRates.kv}}%)</li>
    <li>Latency: <span class="metric">P50: {{latency.p50}}ms, P95: {{latency.p95}}ms, P99: {{latency.p99}}ms</span></li>
    <li>Volume: <span class="metric">{{volume.total_requests}} requests</span></li>
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
  <small>Auto-generated by Cache Monitor | Timestamp: {{timestamp}}</small>
</body>
</html>
```

#### 3. Cost Optimization Analyzer

**Schedule:** Cron daily at 3:00 AM UTC

**Analysis:**
```javascript
async function analyzeCosts(env, ctx) {
  // 1. Query top cache keys by access frequency
  const topKeys = await queryTopKeys(env, 1000);

  // 2. Categorize keys
  const categories = {
    hot: [],   // >100 req/day (should be in Edge)
    warm: [],  // 10-100 req/day (good for KV)
    cold: []   // <10 req/month (R2 candidates)
  };

  for (const key of topKeys) {
    if (key.requestsPerDay > 100) {
      categories.hot.push(key);
    } else if (key.requestsPerDay > 10/30) {
      categories.warm.push(key);
    } else {
      categories.cold.push(key);
    }
  }

  // 3. Calculate potential savings
  const recommendations = [];

  // Check if hot keys are in Edge
  for (const key of categories.hot) {
    const edgeHitRate = await getEdgeHitRate(key.name, env);
    if (edgeHitRate < 90) {
      recommendations.push({
        type: 'edge_optimization',
        key: key.name,
        current: `${edgeHitRate}% edge hit rate`,
        recommendation: 'Increase edge TTL or pre-warm',
        estimatedSavings: '$0.05/day'
      });
    }
  }

  // Check if cold keys should be archived
  const archiveCandidates = categories.cold.filter(k => {
    const age = getKeyAge(k.name, env);
    return age > 30 * 24 * 60 * 60 * 1000; // > 30 days
  });

  if (archiveCandidates.length > 0) {
    recommendations.push({
      type: 'r2_archival',
      count: archiveCandidates.length,
      recommendation: `Archive ${archiveCandidates.length} rarely-accessed entries to R2`,
      estimatedSavings: `$${(archiveCandidates.length * 0.00005).toFixed(2)}/month`
    });
  }

  // 4. Send daily report
  await sendDailyReport(recommendations, categories, env, ctx);
}
```

**Daily Report Email:**
```
Subject: [BooksTrack Cache] Daily Cost Optimization Report

Cache Health Summary:
- Total entries: 9,850
- Hot (>100 req/day): 450 entries (4.6%)
- Warm (10-100 req/day): 3,200 entries (32.5%)
- Cold (<10 req/month): 6,200 entries (62.9%)

Cost Breakdown:
- KV storage: 492MB ($0.246/month)
- KV reads: 98K/day ($1.47/month)
- R2 storage: 0MB ($0/month) [Phase 3 not deployed yet]
- Total: $1.72/month

Recommendations (3):

1. [R2 Archival] Archive 2,100 cold entries to R2
   - Estimated savings: $1.05/month
   - Action: Deploy Phase 3 (R2 Cold Storage)

2. [Edge Optimization] 15 hot keys have low edge hit rate (<90%)
   - Top offender: search:title:q=popular-book (72% edge rate)
   - Recommendation: Increase edge TTL from 6h to 12h
   - Estimated savings: $0.15/day

3. [TTL Tuning] 50 warm keys being refreshed too frequently
   - Increase KV TTL from 24h to 48h for stable content
   - Estimated savings: $0.30/day

Total Potential Savings: $1.50/month (87% of current costs)

View details: https://api-worker.your-domain.workers.dev/metrics?period=24h
```

#### 4. Performance Tuning Engine

**Goal:** A/B test TTL strategies, auto-promote winners

**Architecture:**
```javascript
// Tuning experiment configuration
const ACTIVE_EXPERIMENTS = [
  {
    name: 'extended-title-ttl',
    description: 'Test 48h TTL for title search vs baseline 24h',
    cohorts: [
      { name: 'control', ttl: 24 * 60 * 60, weight: 0.5 },
      { name: 'treatment', ttl: 48 * 60 * 60, weight: 0.5 }
    ],
    metrics: ['hit_rate', 'cost_per_request', 'latency_p95'],
    duration: 7 * 24 * 60 * 60 * 1000, // 7 days
    startedAt: 1730160000000
  }
];

async function assignCohort(cacheKey, experimentName) {
  // Stable assignment based on hash
  const hash = await crypto.subtle.digest('SHA-256',
    new TextEncoder().encode(cacheKey + experimentName)
  );
  const hashValue = new Uint8Array(hash)[0] / 255;

  const experiment = ACTIVE_EXPERIMENTS.find(e => e.name === experimentName);
  let cumWeight = 0;
  for (const cohort of experiment.cohorts) {
    cumWeight += cohort.weight;
    if (hashValue < cumWeight) {
      return cohort;
    }
  }
  return experiment.cohorts[0]; // Fallback
}

// In KVCacheService.set()
async set(cacheKey, data, endpoint, options = {}) {
  let baseTTL = options.ttl || this.ttls[endpoint] || this.ttls.title;

  // Check for active experiments
  const experiment = ACTIVE_EXPERIMENTS.find(e =>
    e.name === 'extended-title-ttl' && endpoint === 'title'
  );

  if (experiment) {
    const cohort = await assignCohort(cacheKey, experiment.name);
    baseTTL = cohort.ttl;

    // Log assignment for analysis
    this.logExperiment(experiment.name, cohort.name, cacheKey);
  }

  // ... rest of set() logic
}
```

**Experiment Analysis (Cron: daily):**
```javascript
async function analyzeExperiments(env, ctx) {
  for (const experiment of ACTIVE_EXPERIMENTS) {
    if (Date.now() - experiment.startedAt < experiment.duration) {
      continue; // Not done yet
    }

    // Query metrics for each cohort
    const controlMetrics = await getCohortMetrics('control', experiment, env);
    const treatmentMetrics = await getCohortMetrics('treatment', experiment, env);

    // Statistical significance test (t-test)
    const result = {
      experiment: experiment.name,
      control: controlMetrics,
      treatment: treatmentMetrics,
      winner: null,
      confidence: 0
    };

    // Compare hit rates
    const hitRateDiff = treatmentMetrics.hit_rate - controlMetrics.hit_rate;
    const pValue = calculatePValue(controlMetrics.hit_rate, treatmentMetrics.hit_rate);

    if (pValue < 0.05 && hitRateDiff > 0) {
      result.winner = 'treatment';
      result.confidence = (1 - pValue) * 100;

      // Auto-promote if improvement is significant
      if (hitRateDiff > 2) { // > 2% improvement
        await promoteTreatment(experiment, env);
        await sendPromotionEmail(experiment, result, env);
      }
    } else if (pValue < 0.05 && hitRateDiff < 0) {
      result.winner = 'control';
      result.confidence = (1 - pValue) * 100;
    } else {
      result.winner = 'inconclusive';
    }

    // Log results
    await logExperimentResults(experiment, result, env);
  }
}
```

**Auto-Promotion:**
```javascript
async function promoteTreatment(experiment, env) {
  // Update default TTL in KVCacheService
  const treatmentTTL = experiment.cohorts.find(c => c.name === 'treatment').ttl;

  // Write new config to KV
  await env.CACHE.put('config:kv-ttls', JSON.stringify({
    title: treatmentTTL,
    isbn: 30 * 24 * 60 * 60,
    author: 7 * 24 * 60 * 60
  }));

  // Notify
  console.log(`Promoted ${experiment.name}: TTL ${treatmentTTL}s now default`);
}
```

## Monitoring Dashboard

**URL:** `https://api-worker.your-domain.workers.dev/dashboard`

**Features:**
- Real-time metrics (auto-refresh every 30s)
- 7-day trend graphs (hit rates, latency, costs)
- Top cache keys table
- Active experiments status
- Recent alerts history

**Tech Stack:**
- Static HTML + Vanilla JS (no framework)
- Chart.js for graphs
- Fetch API for metrics endpoint
- Served directly from Worker

## Cost Estimates

**Analytics Engine Queries:**
- Metrics endpoint: ~100 queries/day
- Alert monitor: 96 queries/day (15min intervals)
- Cost analyzer: 1 query/day
- Total: ~200 queries/day (<10M/month = free)

**MailChannels Emails:**
- Alerts: ~5 emails/day (worst case)
- Daily reports: 1 email/day
- Experiment results: ~1 email/week
- Total: <200 emails/month (free tier: 1000/day)

**Cron CPU:**
- Alert monitor: 96 × 10ms = 960ms/day
- Cost analyzer: 1 × 50ms = 50ms/day
- Experiment analysis: 1 × 100ms = 100ms/day
- Total: ~1.1s/day (~50ms average per invocation)

**Total Phase 4 Cost:** ~$0.05/month

## Error Handling

| Error | Resolution |
|-------|------------|
| Analytics Engine timeout | Retry 3x, fallback to cached metrics |
| Email send failure | Log error, retry next cycle |
| Metrics API overload | Rate limit to 10 req/min per IP |
| Experiment config corruption | Rollback to default TTLs, alert |

## Future Enhancements

1. **ML-based optimization:** Predict optimal TTLs per cache key
2. **Multi-variate testing:** Test multiple parameters simultaneously
3. **Grafana integration:** Native dashboards via Prometheus endpoint
4. **Slack/Discord webhooks:** Real-time alerts to team channels
5. **Custom alert rules:** User-defined thresholds and notification preferences

## Dependencies

- Phase 1: UnifiedCacheService, Analytics Engine integration
- Phase 2: Warming queue depth monitoring
- Phase 3: R2 storage metrics
- MailChannels Workers API (for email alerts)
- KV namespace: `CACHE` (for config, deduplication)
