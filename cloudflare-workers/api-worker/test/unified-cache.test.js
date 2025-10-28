// test/unified-cache.test.js
import { describe, test, expect, beforeEach, vi } from 'vitest';
import { UnifiedCacheService } from '../src/services/unified-cache.js';

describe('UnifiedCacheService', () => {
  let service;
  let mockEnv;
  let mockCtx;

  beforeEach(() => {
    mockEnv = {
      CACHE: {
        get: vi.fn(async () => null),
        put: vi.fn(async () => {})
      },
      CACHE_ANALYTICS: {
        writeDataPoint: vi.fn(async () => {})
      }
    };
    mockCtx = {
      waitUntil: vi.fn((promise) => promise)
    };

    service = new UnifiedCacheService(mockEnv, mockCtx);
  });

  test('initializes with edge, KV, and external API services', () => {
    expect(service.edgeCache).toBeDefined();
    expect(service.kvCache).toBeDefined();
    expect(service.env).toBe(mockEnv);
    expect(service.ctx).toBe(mockCtx);
  });
});
