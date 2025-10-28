// test/kv-cache.test.js
import { describe, test, expect, beforeEach } from 'vitest';
import { KVCacheService } from '../src/services/kv-cache.js';

describe('KVCacheService', () => {
  let service;
  let mockEnv;

  beforeEach(() => {
    mockEnv = {
      CACHE: {
        get: async () => null,
        put: async () => {},
      }
    };
    service = new KVCacheService(mockEnv);
  });

  test('initializes with extended TTLs', () => {
    expect(service.ttls.title).toBe(24 * 60 * 60); // 24h
    expect(service.ttls.isbn).toBe(30 * 24 * 60 * 60); // 30d
    expect(service.ttls.author).toBe(7 * 24 * 60 * 60); // 7d
  });
});
