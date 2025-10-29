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

  it('should parse CSV and extract unique authors', async () => {
    const csvData = btoa('title,author,isbn\nBook1,Author A,123\nBook2,Author A,456\nBook3,Author B,789');
    const request = new Request('https://api.example.com/api/warming/upload', {
      method: 'POST',
      body: JSON.stringify({ csv: csvData, maxDepth: 1 })
    });

    // Mock Gemini API KEY
    env.GEMINI_API_KEY = 'test-api-key';

    // Mock Gemini API fetch call
    global.fetch = async () => ({
      ok: true,
      json: async () => ({
        candidates: [{
          content: {
            parts: [{
              text: JSON.stringify([
                { title: 'Book1', author: 'Author A', isbn: '123' },
                { title: 'Book2', author: 'Author A', isbn: '456' },
                { title: 'Book3', author: 'Author B', isbn: '789' }
              ])
            }]
          }
        }]
      })
    });

    const response = await handleWarmingUpload(request, env, ctx);

    expect(response.status).toBe(202);
    const body = await response.json();
    expect(body.authorsQueued).toBe(2); // Author A and Author B
    expect(body.jobId).toMatch(/^[0-9a-f-]{36}$/); // UUID format
  });

  it('should queue each author with metadata', async () => {
    const messages = [];
    env.AUTHOR_WARMING_QUEUE.send = async (msg) => {
      messages.push(msg);
      return { id: `msg-${messages.length}` };
    };

    env.GEMINI_API_KEY = 'test-api-key';
    global.fetch = async () => ({
      ok: true,
      json: async () => ({
        candidates: [{
          content: {
            parts: [{
              text: JSON.stringify([
                { title: 'Book1', author: 'Author A', isbn: '123' }
              ])
            }]
          }
        }]
      })
    });

    const csvData = btoa('title,author,isbn\nBook1,Author A,123');
    const request = new Request('https://api.example.com/api/warming/upload', {
      method: 'POST',
      body: JSON.stringify({ csv: csvData, maxDepth: 2 })
    });

    await handleWarmingUpload(request, env, ctx);

    expect(messages).toHaveLength(1);
    expect(messages[0].author).toBe('Author A');
    expect(messages[0].depth).toBe(0);
    expect(messages[0].source).toBe('csv');
  });
});
