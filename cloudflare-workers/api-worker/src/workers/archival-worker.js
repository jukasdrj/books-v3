/**
 * Select cache entries that qualify for R2 archival
 *
 * Criteria: age > 30 days AND accessCount < 10/month
 *
 * @param {Object} env - Worker environment
 * @param {Object} accessStats - Map of cacheKey → accessCount
 * @returns {Promise<Array>} Archival candidates
 */
export async function selectArchivalCandidates(env, accessStats) {
  const candidates = [];

  // List all KV keys (excluding cold-index and warming metadata)
  const kvKeys = await env.CACHE.list();

  for (const key of kvKeys.keys) {
    // Skip internal keys
    if (key.name.startsWith('cold-index:') ||
        key.name.startsWith('warming:') ||
        key.name.startsWith('config:')) {
      continue;
    }

    // Get metadata
    const entry = await env.CACHE.getWithMetadata(key.name);
    if (!entry || !entry.metadata || !entry.metadata.cachedAt) {
      continue;
    }

    const age = Date.now() - entry.metadata.cachedAt;
    const accessCount = accessStats[key.name] || 0;

    // Hybrid archival criteria
    const thirtyDaysMs = 30 * 24 * 60 * 60 * 1000;
    if (age > thirtyDaysMs && accessCount < 10) {
      candidates.push({
        key: key.name,
        data: entry.value,
        age: age,
        accessCount: accessCount
      });
    }
  }

  return candidates;
}
