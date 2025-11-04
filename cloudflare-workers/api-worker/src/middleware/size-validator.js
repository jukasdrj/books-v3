/**
 * Request Size Validation Middleware
 *
 * Protects worker from memory exhaustion due to oversized requests.
 *
 * Security: Prevents 500MB CSV upload from crashing worker (256MB memory limit).
 * Performance: Fails fast before parsing, saving CPU and memory.
 *
 * @example
 * ```javascript
 * const sizeCheck = validateRequestSize(request, 10); // 10MB limit
 * if (sizeCheck) return sizeCheck; // 413 Payload Too Large
 * ```
 */

/**
 * Validate request size before parsing body.
 *
 * @param {Request} request - Incoming request
 * @param {number} maxSizeMB - Maximum allowed size in megabytes (default: 10MB)
 * @returns {Response|null} - 413 response if too large, null otherwise
 */
export function validateRequestSize(request, maxSizeMB = 10) {
  // Read Content-Length header (set by client or Cloudflare)
  const contentLength = parseInt(request.headers.get('Content-Length') || '0');
  const maxBytes = maxSizeMB * 1024 * 1024;

  if (contentLength > maxBytes) {
    const receivedMB = (contentLength / 1024 / 1024).toFixed(2);

    console.warn(`[Size Validator] Rejected request: ${receivedMB}MB exceeds ${maxSizeMB}MB limit`);

    return new Response(JSON.stringify({
      error: `File too large. Maximum ${maxSizeMB}MB allowed.`,
      code: 'FILE_TOO_LARGE',
      details: {
        receivedMB: parseFloat(receivedMB),
        maxMB: maxSizeMB,
        receivedBytes: contentLength,
        maxBytes: maxBytes
      }
    }), {
      status: 413, // Payload Too Large
      headers: {
        'Content-Type': 'application/json',
        'X-Max-Size-MB': maxSizeMB.toString(),
        'X-Received-Size-MB': receivedMB
      }
    });
  }

  // Size is within limit
  return null;
}

/**
 * Validate request size with custom error message.
 *
 * @param {Request} request - Incoming request
 * @param {number} maxSizeMB - Maximum allowed size in megabytes
 * @param {string} resourceType - Human-readable resource type (e.g., "CSV file", "image")
 * @returns {Response|null} - 413 response if too large, null otherwise
 */
export function validateResourceSize(request, maxSizeMB, resourceType = 'file') {
  const contentLength = parseInt(request.headers.get('Content-Length') || '0');
  const maxBytes = maxSizeMB * 1024 * 1024;

  if (contentLength > maxBytes) {
    const receivedMB = (contentLength / 1024 / 1024).toFixed(2);

    console.warn(`[Size Validator] Rejected ${resourceType}: ${receivedMB}MB exceeds ${maxSizeMB}MB limit`);

    return new Response(JSON.stringify({
      error: `${resourceType.charAt(0).toUpperCase() + resourceType.slice(1)} too large. Maximum ${maxSizeMB}MB allowed.`,
      code: 'FILE_TOO_LARGE',
      resourceType,
      details: {
        receivedMB: parseFloat(receivedMB),
        maxMB: maxSizeMB,
        receivedBytes: contentLength,
        maxBytes: maxBytes
      }
    }), {
      status: 413,
      headers: {
        'Content-Type': 'application/json',
        'X-Max-Size-MB': maxSizeMB.toString(),
        'X-Received-Size-MB': receivedMB,
        'X-Resource-Type': resourceType
      }
    });
  }

  return null;
}

/**
 * Get request size info for monitoring/debugging.
 *
 * @param {Request} request - Incoming request
 * @returns {object} - Size information
 */
export function getRequestSizeInfo(request) {
  const contentLength = parseInt(request.headers.get('Content-Length') || '0');
  const sizeMB = (contentLength / 1024 / 1024).toFixed(2);

  return {
    bytes: contentLength,
    megabytes: parseFloat(sizeMB),
    hasContentLength: request.headers.has('Content-Length')
  };
}
