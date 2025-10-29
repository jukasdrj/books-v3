import { describe, it, expect, beforeEach } from 'vitest';
import { handleWarmingUpload } from '../src/handlers/warming-upload.js';

describe('handleWarmingUpload', () => {
  let env, ctx;

  beforeEach(() => {
    env = {
      AUTHOR_WARMING_QUEUE: {
        send: async (msg) => ({ id: 'msg-123' })
      },
      CACHE: {
        put: async () => {},
        get: async () => null
      }
    };
    ctx = {
      waitUntil: (promise) => promise
    };
  });

  it('should reject request without csv field', async () => {
    const request = new Request('https://api.example.com/api/warming/upload', {
      method: 'POST',
      body: JSON.stringify({ maxDepth: 2 })
    });

    const response = await handleWarmingUpload(request, env, ctx);

    expect(response.status).toBe(400);
    const body = await response.json();
    expect(body.error).toContain('csv');
  });

  it('should reject invalid maxDepth', async () => {
    const request = new Request('https://api.example.com/api/warming/upload', {
      method: 'POST',
      body: JSON.stringify({ csv: 'base64data', maxDepth: 5 })
    });

    const response = await handleWarmingUpload(request, env, ctx);

    expect(response.status).toBe(400);
    const body = await response.json();
    expect(body.error).toContain('maxDepth must be 1-3');
  });
});
