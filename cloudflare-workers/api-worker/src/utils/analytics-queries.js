/**
 * Query cache access frequency from Analytics Engine
 *
 * NOTE: Analytics Engine bindings in Workers are WRITE-ONLY.
 * The .query() method is not available in Worker environment bindings.
 * To query Analytics Engine, you must use the GraphQL API with authentication.
 *
 * For now, this function returns empty stats and logs a warning.
 * TODO: Implement KV-based access tracking or GraphQL API integration.
 *
 * @param {Object} env - Worker environment with CACHE_ANALYTICS binding
 * @param {number} days - Number of days to look back
 * @returns {Promise<Object>} Map of cacheKey → accessCount
 */
export async function queryAccessFrequency(env, days) {
  console.warn('[Analytics] Analytics Engine bindings are write-only in Workers. Query functionality requires GraphQL API integration.');
  console.warn('[Analytics] Returning empty access stats. Consider implementing KV-based tracking for archival decisions.');

  // Return empty stats - archival process will proceed without access frequency data
  // This means all candidates will have equal priority (no frequency-based filtering)
  return {};
}
