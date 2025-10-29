import { queryAccessFrequency } from '../utils/analytics-queries.js';
import { selectArchivalCandidates, archiveCandidates } from '../workers/archival-worker.js';

/**
 * Scheduled handler for daily archival process
 *
 * @param {Object} env - Worker environment
 * @param {ExecutionContext} ctx - Execution context
 */
export async function handleScheduledArchival(env, ctx) {
  const startTime = Date.now();

  try {
    console.log('Starting scheduled archival process...');

    // 1. Query Analytics Engine for access stats (last 30 days)
    const accessStats = await queryAccessFrequency(env, 30);

    // 2. Select archival candidates
    const candidates = await selectArchivalCandidates(env, accessStats);

    console.log(`Found ${candidates.length} archival candidates`);

    if (candidates.length === 0) {
      console.log('No entries to archive');
      return;
    }

    // 3. Archive to R2
    const archivedCount = await archiveCandidates(candidates, env);

    // 4. Log metrics
    const duration = Date.now() - startTime;
    console.log(`Archived ${archivedCount}/${candidates.length} entries in ${duration}ms`);

    // Log to Analytics Engine
    if (env.CACHE_ANALYTICS) {
      env.CACHE_ANALYTICS.writeDataPoint({
        blobs: ['archival_completed', ''],
        doubles: [archivedCount, duration],
        indexes: ['archival_completed']
      });
    }

  } catch (error) {
    console.error('Scheduled archival failed:', error);

    // Log error metric
    if (env.CACHE_ANALYTICS) {
      env.CACHE_ANALYTICS.writeDataPoint({
        blobs: ['archival_failed', error.message],
        doubles: [Date.now() - startTime],
        indexes: ['archival_failed']
      });
    }
  }
}
