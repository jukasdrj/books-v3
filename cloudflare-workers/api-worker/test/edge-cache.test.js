// test/edge-cache.test.js
import { describe, test, expect, beforeEach } from 'vitest';
import { EdgeCacheService } from '../src/services/edge-cache.js';

describe('EdgeCacheService', () => {
  let service;

  beforeEach(() => {
    service = new EdgeCacheService();
  });

  test('get returns null on cache miss', async () => {
    const result = await service.get('nonexistent-key');
    expect(result).toBeNull();
  });
});
