/**
 * Generate R2 path for cold cache entry
 *
 * Format: cold-cache/YYYY/MM/cache-key.json
 *
 * @param {string} cacheKey - Original cache key
 * @returns {string} R2 object path
 */
export function generateR2Path(cacheKey) {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');

  return `cold-cache/${year}/${month}/${cacheKey}.json`;
}

/**
 * Parse cache key from R2 path
 *
 * @param {string} r2Path - R2 object path
 * @returns {string} Original cache key
 */
export function parseR2Path(r2Path) {
  // Remove prefix and .json suffix
  const filename = r2Path.split('/').pop();
  return filename.replace(/\.json$/, '');
}
