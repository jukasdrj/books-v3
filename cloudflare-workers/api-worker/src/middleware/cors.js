/**
 * CORS Middleware
 *
 * Restricts API access to known origins only.
 *
 * Security: Prevents CSRF attacks from malicious websites.
 * Before: 'Access-Control-Allow-Origin: *' (any site can call API)
 * After: Whitelist of trusted domains only
 *
 * **Current Status:** DEFERRED for Phase 2
 * - Primary client is native iOS app (doesn't send Origin header)
 * - Rate limiting (10 req/min) is primary DoS defense
 * - CORS restrictions only needed if web interface is added
 *
 * **Migration Path:**
 * 1. Phase 1: Rate limiting + size validation (CURRENT)
 * 2. Phase 2: CORS restrictions when web app deployed
 * 3. Use getCorsHeaders() to replace '*' with whitelist
 *
 * @example
 * ```javascript
 * const corsHeaders = getCorsHeaders(request);
 * return new Response(json, { headers: { ...corsHeaders } });
 * ```
 */

/**
 * Allowed origins for CORS requests.
 *
 * Production: Official domain (when deployed)
 * Development: localhost for local testing
 * Mobile: Capacitor/Ionic schemes for iOS app
 */
const ALLOWED_ORIGINS = [
  'https://bookstrack.app',           // Production domain (when deployed)
  'https://www.bookstrack.app',       // Production with www
  'http://localhost:3000',            // Local web development
  'http://localhost:8080',            // Alternative local port
  'capacitor://localhost',            // iOS Capacitor (if using Capacitor bridge)
  'ionic://localhost'                 // iOS Ionic (if using Ionic framework)
];

/**
 * Get CORS headers based on request origin.
 *
 * @param {Request} request - Incoming request
 * @returns {object} - CORS headers object
 */
export function getCorsHeaders(request) {
  const origin = request.headers.get('Origin');
  const allowedOrigin = ALLOWED_ORIGINS.includes(origin) ? origin : null;

  // Log blocked origins for monitoring
  if (origin && !allowedOrigin) {
    console.warn(`[CORS] Blocked request from unauthorized origin: ${origin}`);
  }

  return {
    'Access-Control-Allow-Origin': allowedOrigin || 'null', // 'null' = blocked
    'Access-Control-Allow-Credentials': 'true',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-AI-Provider',
    'Access-Control-Max-Age': '86400' // 24 hours preflight cache
  };
}

/**
 * Check if request origin is allowed.
 *
 * @param {Request} request - Incoming request
 * @returns {boolean} - True if origin is allowed
 */
export function isOriginAllowed(request) {
  const origin = request.headers.get('Origin');
  return ALLOWED_ORIGINS.includes(origin);
}

/**
 * Get list of allowed origins (for documentation/debugging).
 *
 * @returns {string[]} - Array of allowed origin strings
 */
export function getAllowedOrigins() {
  return [...ALLOWED_ORIGINS];
}

/**
 * Add an origin to the allowlist dynamically (for testing/staging).
 *
 * ⚠️ WARNING: Only use this for temporary testing. Permanent origins
 * should be added to ALLOWED_ORIGINS constant above.
 *
 * @param {string} origin - Origin to add (e.g., "https://staging.bookstrack.app")
 * @returns {void}
 */
export function addAllowedOrigin(origin) {
  if (!ALLOWED_ORIGINS.includes(origin)) {
    ALLOWED_ORIGINS.push(origin);
    console.log(`[CORS] Added temporary origin: ${origin}`);
  }
}
