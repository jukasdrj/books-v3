/**
 * Test Size Validator Middleware
 *
 * Tests request size validation:
 * - Accept requests within size limit
 * - Reject oversized requests with 413
 * - Provide helpful error messages
 */

import { validateRequestSize, validateResourceSize } from './src/middleware/size-validator.js';

async function testSizeValidator() {
  console.log('Testing Size Validator Middleware...\n');

  let passed = 0;
  let failed = 0;

  // Test 1: Request within limit (valid)
  console.log('[TEST] Request within size limit (5MB)');
  const mockRequestValid = {
    headers: {
      get: (key) => key === 'Content-Length' ? '3000000' : null // 3MB
    }
  };

  const resultValid = validateRequestSize(mockRequestValid, 5);
  if (resultValid === null) {
    console.log('  ✅ PASS: Request allowed (3MB < 5MB limit)\n');
    passed++;
  } else {
    console.log('  ❌ FAIL: Valid request was blocked\n');
    failed++;
  }

  // Test 2: Request exceeding limit (invalid)
  console.log('[TEST] Request exceeding size limit (10MB)');
  const mockRequestOversized = {
    headers: {
      get: (key) => key === 'Content-Length' ? '12000000' : null // 12MB
    }
  };

  const resultOversized = validateRequestSize(mockRequestOversized, 10);
  if (resultOversized && resultOversized.status === 413) {
    const body = JSON.parse(await resultOversized.text());
    if (body.code === 'FILE_TOO_LARGE' && body.details) {
      console.log(`  ✅ PASS: Request blocked with 413 (${body.details.receivedMB}MB > ${body.details.maxMB}MB)\n`);
      passed++;
    } else {
      console.log('  ❌ FAIL: Response missing expected fields\n');
      failed++;
    }
  } else {
    console.log('  ❌ FAIL: Oversized request was not blocked\n');
    failed++;
  }

  // Test 3: Missing Content-Length header
  console.log('[TEST] Missing Content-Length header');
  const mockRequestNoHeader = {
    headers: {
      get: () => null
    }
  };

  const resultNoHeader = validateRequestSize(mockRequestNoHeader, 5);
  if (resultNoHeader === null) {
    console.log('  ✅ PASS: Request allowed (missing header treated as 0 bytes)\n');
    passed++;
  } else {
    console.log('  ❌ FAIL: Request with missing header was blocked\n');
    failed++;
  }

  // Test 4: validateResourceSize with custom resource name
  console.log('[TEST] validateResourceSize with custom resource name');
  const mockResourceOversized = {
    headers: {
      get: (key) => key === 'Content-Length' ? '6000000' : null // 6MB
    }
  };

  const resultResource = validateResourceSize(mockResourceOversized, 5, 'image');
  if (resultResource && resultResource.status === 413) {
    const body = JSON.parse(await resultResource.text());
    if (body.error.includes('Image') || body.resourceType === 'image') {
      console.log(`  ✅ PASS: Custom resource name included (${body.error})\n`);
      passed++;
    } else {
      console.log(`  ❌ FAIL: Resource name not in error message (got: ${body.error})\n`);
      failed++;
    }
  } else {
    console.log('  ❌ FAIL: Oversized resource was not blocked\n');
    failed++;
  }

  console.log('='.repeat(50));
  console.log(`TOTAL: ${passed + failed} tests`);
  console.log(`✅ PASSED: ${passed}`);
  console.log(`❌ FAILED: ${failed}`);
  console.log('='.repeat(50));

  process.exit(failed > 0 ? 1 : 0);
}

testSizeValidator();
