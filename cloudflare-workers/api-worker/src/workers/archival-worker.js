import { generateR2Path } from '../utils/r2-paths.js';

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

/**
 * Archive candidates to R2 and create cold index
 *
 * @param {Array} candidates - Archival candidates
 * @param {Object} env - Worker environment
 * @returns {Promise<number>} Count of archived entries
 */
export async function archiveCandidates(candidates, env) {
  let archivedCount = 0;

  for (const candidate of candidates) {
    try {
      const r2Path = generateR2Path(candidate.key);

      // 1. Write to R2
      await env.LIBRARY_DATA.put(r2Path, candidate.data, {
        customMetadata: {
          originalKey: candidate.key,
          archivedAt: Date.now().toString(),
          originalTTL: '86400',
          accessCount: candidate.accessCount.toString()
        }
      });

      // 2. Create cold storage index in KV
      await env.CACHE.put(`cold-index:${candidate.key}`, JSON.stringify({
        r2Path: r2Path,
        archivedAt: Date.now(),
        originalTTL: 86400,
        archiveReason: `age=${Math.floor(candidate.age / (24 * 60 * 60 * 1000))}d, access=${candidate.accessCount}/month`
      }));

      // 3. Delete from KV
      await env.CACHE.delete(candidate.key);

      archivedCount++;

    } catch (error) {
      console.error(`Failed to archive ${candidate.key}:`, error);
      // Continue with next candidate (don't fail entire batch)
    }
  }

  return archivedCount;
}
