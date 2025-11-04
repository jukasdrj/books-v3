/**
 * Test Rate Limiter Middleware
 *
 * Tests basic functionality (logic tests only - no KV integration):
 * - Verify rate limit response format
 * - Verify error handling (fail-open behavior)
 */

import { checkRateLimit } from './src/middleware/rate-limiter.js';

async function testRateLimiter() {
  console.log('Testing Rate Limiter Middleware...\n');

  let passed = 0;
  let failed = 0;

  // Test 1: Error handling (fail-open)
  console.log('[TEST] Error handling (fail-open behavior)');
  const mockRequestError = {
    headers: {
      get: (key) => key === 'CF-Connecting-IP' ? '192.168.1.1' : null
    }
  };

  const mockEnvError = {
    KV_CACHE: {
      get: async () => { throw new Error('KV unavailable'); }
    }
  };

  const resultError = await checkRateLimit(mockRequestError, mockEnvError);
  if (resultError === null) {
    console.log('  ✅ PASS: Rate limiter fails open (allows request)\n');
    passed++;
  } else {
    console.log('  ❌ FAIL: Rate limiter did not fail open\n');
    failed++;
  }

  // Test 2: First request (should be allowed)
  console.log('[TEST] First request from new IP');
  const mockRequestFirst = {
    headers: {
      get: (key) => key === 'CF-Connecting-IP' ? '192.168.1.100' : null
    }
  };

  const mockEnvFirst = {
    KV_CACHE: {
      get: async () => null, // No counter exists yet
      put: async (key, value, options) => {
        console.log(`  KV PUT called: ${key} (TTL: ${options.expirationTtl}s)`);
      }
    }
  };

  const resultFirst = await checkRateLimit(mockRequestFirst, mockEnvFirst);
  if (resultFirst === null) {
    console.log('  ✅ PASS: First request allowed\n');
    passed++;
  } else {
    console.log('  ❌ FAIL: First request was blocked\n');
    failed++;
  }

  // Test 3: Rate limit exceeded (11th request)
  console.log('[TEST] Rate limit exceeded (11th request)');
  const mockRequestExceeded = {
    headers: {
      get: (key) => key === 'CF-Connecting-IP' ? '192.168.1.200' : null
    }
  };

  const mockEnvExceeded = {
    KV_CACHE: {
      get: async () => ({
        count: 10, // Already at limit
        resetAt: Date.now() + 30000 // Resets in 30 seconds
      }),
      put: async () => {}
    }
  };

  const resultExceeded = await checkRateLimit(mockRequestExceeded, mockEnvExceeded);
  if (resultExceeded && resultExceeded.status === 429) {
    const body = JSON.parse(await resultExceeded.text());
    if (body.code === 'RATE_LIMIT_EXCEEDED' && body.details.retryAfter) {
      console.log(`  ✅ PASS: Request blocked with 429 (retry after ${body.details.retryAfter}s)\n`);
      passed++;
    } else {
      console.log('  ❌ FAIL: Response body missing expected fields\n');
      failed++;
    }
  } else {
    console.log('  ❌ FAIL: Request was not blocked with 429\n');
    failed++;
  }

  console.log('='.repeat(50));
  console.log(`TOTAL: ${passed + failed} tests`);
  console.log(`✅ PASSED: ${passed}`);
  console.log(`❌ FAILED: ${failed}`);
  console.log('='.repeat(50));

  process.exit(failed > 0 ? 1 : 0);
}

testRateLimiter();
