import { describe, it, expect } from 'vitest';
import { checkAlertThresholds } from '../src/services/alert-monitor.js';

describe('checkAlertThresholds', () => {
  it('should generate critical alert for high miss rate', () => {
    const metrics = {
      hitRates: { combined: 80 }, // < 85% threshold
      latency: { p99: 300 },
      volume: { total_requests: 10000 }
    };

    const alerts = checkAlertThresholds(metrics);

    expect(alerts).toHaveLength(1);
    expect(alerts[0].severity).toBe('critical');
    expect(alerts[0].type).toBe('miss_rate');
  });

  it('should generate warning for low edge hit rate', () => {
    const metrics = {
      hitRates: { combined: 95, edge: 70 }, // < 75% threshold
      latency: { p99: 50 },
      volume: { total_requests: 10000 }
    };

    const alerts = checkAlertThresholds(metrics);

    expect(alerts).toHaveLength(1);
    expect(alerts[0].severity).toBe('warning');
    expect(alerts[0].type).toBe('edge_hit_rate');
  });

  it('should return no alerts for healthy metrics', () => {
    const metrics = {
      hitRates: { combined: 96, edge: 82 },
      latency: { p99: 100 },
      volume: { total_requests: 10000 }
    };

    const alerts = checkAlertThresholds(metrics);

    expect(alerts).toHaveLength(0);
  });
});
