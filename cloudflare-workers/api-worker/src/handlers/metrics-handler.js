import { aggregateMetrics } from '../services/metrics-aggregator.js';

/**
 * GET /metrics - Cache metrics API endpoint
 *
 * Query params:
 *  - period: '15m' | '1h' | '24h' | '7d' (default: '1h')
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
