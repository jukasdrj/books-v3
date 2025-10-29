/**
 * Query cache access frequency from Analytics Engine
 *
 * @param {Object} env - Worker environment with CACHE_ANALYTICS binding
 * @param {number} days - Number of days to look back
 * @returns {Promise<Object>} Map of cacheKey → accessCount
 */
export async function queryAccessFrequency(env, days) {
  if (!env.CACHE_ANALYTICS) {
    console.warn('CACHE_ANALYTICS binding not available');
    return {};
  }

  try {
    const query = `
      SELECT
        blob2 as cacheKey,
        COUNT(*) as accessCount
      FROM CACHE_ANALYTICS
      WHERE timestamp > NOW() - INTERVAL '${days}' DAY
      GROUP BY blob2
    `;

    const result = await env.CACHE_ANALYTICS.query(query);

    const stats = {};
    for (const row of result.results || []) {
      stats[row.cacheKey] = row.accessCount;
    }

    return stats;

  } catch (error) {
    console.error('Failed to query Analytics Engine:', error);
    return {};
  }
}
