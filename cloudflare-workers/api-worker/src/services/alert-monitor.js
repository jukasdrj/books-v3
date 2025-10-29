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
