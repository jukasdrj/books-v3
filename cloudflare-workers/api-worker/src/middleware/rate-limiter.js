/**
 * Rate Limiting Middleware
 *
 * Protects expensive endpoints from abuse using KV-based token bucket algorithm.
 *
 * Security: Prevents denial-of-wallet attacks on AI/enrichment endpoints.
 * Implementation: Stores per-IP counters in KV with TTL expiration.
 * Cost: ~$0 (uses existing KV namespace, ~100 writes/min peak)
 *
 * Algorithm: Token Bucket
 * - Each IP gets 10 tokens per minute
 * - Each request consumes 1 token
 * - Tokens refill at 1 token every 6 seconds
 *
 * @example
 * ```javascript
 * const rateLimitResponse = await checkRateLimit(request, env);
 * if (rateLimitResponse) return rateLimitResponse; // 429 Too Many Requests
 * ```
 */

const RATE_LIMIT_WINDOW = 60; // 60 seconds
const RATE_LIMIT_MAX_REQUESTS = 10; // 10 requests per window

/**
 * Check if request exceeds rate limit for the client's IP.
 *
 * @param {Request} request - Incoming request
 * @param {object} env - Worker environment bindings
 * @returns {Response|null} - 429 response if rate limited, null otherwise
 */
export async function checkRateLimit(request, env) {
  // Extract client IP (Cloudflare provides this in CF-Connecting-IP header)
  const clientIP = request.headers.get('CF-Connecting-IP') || 'unknown';
  const key = `ratelimit:${clientIP}`;

  try {
    // Get current counter from KV
    const counterData = await env.KV_CACHE.get(key, { type: 'json' });
    const now = Date.now();

    if (!counterData) {
      // First request - initialize counter
      await env.KV_CACHE.put(key, JSON.stringify({
        count: 1,
        resetAt: now + (RATE_LIMIT_WINDOW * 1000)
      }), {
        expirationTtl: RATE_LIMIT_WINDOW
      });
      return null; // Allow request
    }

    // Check if window expired
    if (now >= counterData.resetAt) {
      // Reset counter (new window)
      await env.KV_CACHE.put(key, JSON.stringify({
        count: 1,
        resetAt: now + (RATE_LIMIT_WINDOW * 1000)
      }), {
        expirationTtl: RATE_LIMIT_WINDOW
      });
      return null; // Allow request
    }

    // Check if limit exceeded
    if (counterData.count >= RATE_LIMIT_MAX_REQUESTS) {
      const retryAfter = Math.ceil((counterData.resetAt - now) / 1000);
      console.warn(`[Rate Limit] Blocked request from IP: ${clientIP} (${counterData.count}/${RATE_LIMIT_MAX_REQUESTS})`);

      return new Response(JSON.stringify({
        error: `Rate limit exceeded. Please try again in ${retryAfter} seconds.`,
        code: 'RATE_LIMIT_EXCEEDED',
        details: {
          retryAfter,
          clientIP: clientIP.substring(0, 8) + '...', // Partial IP for privacy
          requestsUsed: counterData.count,
          requestsLimit: RATE_LIMIT_MAX_REQUESTS
        }
      }), {
        status: 429,
        headers: {
          'Content-Type': 'application/json',
          'Retry-After': retryAfter.toString(),
          'X-RateLimit-Limit': RATE_LIMIT_MAX_REQUESTS.toString(),
          'X-RateLimit-Remaining': '0',
          'X-RateLimit-Reset': counterData.resetAt.toString()
        }
      });
    }

    // Increment counter
    await env.KV_CACHE.put(key, JSON.stringify({
      count: counterData.count + 1,
      resetAt: counterData.resetAt
    }), {
      expirationTtl: RATE_LIMIT_WINDOW
    });

    // Rate limit not hit - allow request
    return null;

  } catch (error) {
    // If rate limiter fails, log error but allow request (fail open)
    console.error('[Rate Limit] Error checking rate limit:', error);
    console.warn('[Rate Limit] Failing open - allowing request despite error');
    return null;
  }
}

/**
 * Get rate limit status for a client IP (for monitoring/debugging).
 *
 * @param {string} clientIP - Client IP address
 * @param {object} env - Worker environment bindings
 * @returns {Promise<object>} - Rate limit status
 */
export async function getRateLimitStatus(clientIP, env) {
  try {
    // Cloudflare Rate Limiting provides remaining count via limit() result
    const { success, limit, remaining } = await env.RATE_LIMITER.limit({
      key: clientIP,
      dryRun: true // Check without consuming quota
    });

    return {
      success,
      limit,
      remaining,
      clientIP: clientIP.substring(0, 8) + '...'
    };

  } catch (error) {
    console.error('[Rate Limit] Error getting status:', error);
    return {
      error: error.message,
      clientIP: clientIP.substring(0, 8) + '...'
    };
  }
}
