/**
 * Test CORS Middleware
 *
 * Tests that getCorsHeaders() properly validates origins:
 * - Allowed origins return the origin
 * - Blocked origins return 'null'
 */

import { getCorsHeaders } from './src/middleware/cors.js';

function testCorsHeaders() {
  console.log('Testing CORS Middleware...\n');

  const testCases = [
    {
      name: 'Production domain (allowed)',
      origin: 'https://bookstrack.app',
      expectAllowed: true
    },
    {
      name: 'Production www (allowed)',
      origin: 'https://www.bookstrack.app',
      expectAllowed: true
    },
    {
      name: 'Localhost development (allowed)',
      origin: 'http://localhost:3000',
      expectAllowed: true
    },
    {
      name: 'Evil domain (blocked)',
      origin: 'https://evil.com',
      expectAllowed: false
    },
    {
      name: 'No origin header (blocked)',
      origin: null,
      expectAllowed: false
    }
  ];

  let passed = 0;
  let failed = 0;

  for (const testCase of testCases) {
    const mockRequest = {
      headers: {
        get: (key) => key === 'Origin' ? testCase.origin : null
      }
    };

    const headers = getCorsHeaders(mockRequest);
    const allowedOrigin = headers['Access-Control-Allow-Origin'];

    const isAllowed = allowedOrigin !== 'null' && allowedOrigin !== null;
    const success = isAllowed === testCase.expectAllowed;

    console.log(`[${success ? '✅ PASS' : '❌ FAIL'}] ${testCase.name}`);
    console.log(`  Origin: ${testCase.origin || 'null'}`);
    console.log(`  Result: ${allowedOrigin}`);
    console.log(`  Expected: ${testCase.expectAllowed ? 'allowed' : 'blocked'}\n`);

    if (success) {
      passed++;
    } else {
      failed++;
    }
  }

  console.log('='.repeat(50));
  console.log(`TOTAL: ${passed + failed} tests`);
  console.log(`✅ PASSED: ${passed}`);
  console.log(`❌ FAILED: ${failed}`);
  console.log('='.repeat(50));

  process.exit(failed > 0 ? 1 : 0);
}

testCorsHeaders();
