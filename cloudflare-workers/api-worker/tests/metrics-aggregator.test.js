import { describe, it, expect, vi } from 'vitest';
import { aggregateMetrics } from '../src/services/metrics-aggregator.js';

describe('aggregateMetrics', () => {
  it('should calculate hit rates from Analytics Engine data', async () => {
    const mockEnv = {
      CACHE_ANALYTICS: {
        query: vi.fn().mockResolvedValue({
          results: [
            { cache_source: 'edge_hit', count: 78000, avg_latency: 8.2 },
            { cache_source: 'kv_hit', count: 16000, avg_latency: 42.1 },
            { cache_source: 'api_miss', count: 6000, avg_latency: 350.0 }
          ]
        })
      }
    };

    const metrics = await aggregateMetrics(mockEnv, '1h');

    expect(metrics.hitRates.edge).toBeCloseTo(78.0, 1);
    expect(metrics.hitRates.kv).toBeCloseTo(16.0, 1);
    expect(metrics.hitRates.combined).toBeCloseTo(94.0, 1);
    expect(metrics.volume.total_requests).toBe(100000);
  });
});
