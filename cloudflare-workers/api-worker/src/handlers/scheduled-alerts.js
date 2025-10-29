import { aggregateMetrics } from '../services/metrics-aggregator.js';
import { checkAlertThresholds, shouldSendAlert, markAlertSent } from '../services/alert-monitor.js';

/**
 * Scheduled handler for alert monitoring
 *
 * NOTE: This implementation logs alerts only. Email alerts are disabled.
 * To enable email alerts, implement sendAlertEmail() and uncomment email logic.
 *
 * @param {Object} env - Worker environment
 * @param {ExecutionContext} ctx - Execution context
 */
export async function handleScheduledAlerts(env, ctx) {
  try {
    console.log('[Alert Monitor] Running alert check...');

    // 1. Get recent metrics (last 15 minutes)
    const metrics = await aggregateMetrics(env, '15m');

    // 2. Check thresholds
    const alerts = checkAlertThresholds(metrics);

    if (alerts.length === 0) {
      console.log('[Alert Monitor] ✅ No alerts triggered - system healthy');
      return;
    }

    console.log(`[Alert Monitor] ⚠️  Generated ${alerts.length} alerts:`, alerts.map(a => a.type));

    // 3. Check deduplication
    const shouldSend = await shouldSendAlert(alerts, env);
    if (!shouldSend) {
      console.log('[Alert Monitor] Alert suppressed (duplicate within 4h window)');
      return;
    }

    // 4. Log alert details (email disabled)
    console.log('[Alert Monitor] 🚨 NEW ALERTS DETECTED:');
    alerts.forEach(alert => {
      console.log(`  [${alert.severity.toUpperCase()}] ${alert.message}`);
      console.log(`    Current: ${alert.value.toFixed(1)} | Threshold: ${alert.threshold}`);
    });

    console.log('[Alert Monitor] Recent metrics (15min):');
    console.log(`  Hit Rate: ${metrics.hitRates.combined.toFixed(1)}% (Edge: ${metrics.hitRates.edge.toFixed(1)}%, KV: ${metrics.hitRates.kv.toFixed(1)}%)`);
    console.log(`  Volume: ${metrics.volume.total_requests} requests`);

    // 5. Mark as sent to prevent duplicates
    await markAlertSent(alerts, env);

    console.log('[Alert Monitor] Alert logged and marked as sent');

    // TODO: Uncomment when email alerts are needed
    // const alertEmail = env.ALERT_EMAIL || 'nerd@ooheynerds.com';
    // await sendAlertEmail(alerts, metrics, alertEmail);
    // console.log(`[Alert Monitor] Alert email sent to ${alertEmail}`);

  } catch (error) {
    console.error('[Alert Monitor] Alert check failed:', error);
    console.error(error.stack);
  }
}
