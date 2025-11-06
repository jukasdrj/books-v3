// test/gemini-token-usage.test.js
/**
 * Token Usage Tracking Tests
 * Validates implementation of Gemini API best practice: cost monitoring
 */
import { describe, test, expect, vi, beforeEach } from 'vitest';
import { parseCSVWithGemini } from '../src/providers/gemini-csv-provider.js';
import { scanImageWithGemini } from '../src/providers/gemini-provider.js';

describe('Token Usage Tracking - CSV Provider', () => {
  beforeEach(() => {
    // Clear console spy before each test
    vi.clearAllMocks();
  });

  test('extracts token usage from Gemini API response', async () => {
    const mockFetch = vi.fn(() => Promise.resolve({
      ok: true,
      json: () => Promise.resolve({
        candidates: [{
          content: {
            parts: [{ text: JSON.stringify([{ title: 'Book1', author: 'Author1' }]) }]
          }
        }],
        usageMetadata: {
          promptTokenCount: 150,
          candidatesTokenCount: 50,
          totalTokenCount: 200
        }
      })
    }));

    global.fetch = mockFetch;
    const consoleSpy = vi.spyOn(console, 'log');

    await parseCSVWithGemini('Title,Author\nBook1,Author1', 'Parse CSV', 'test-key');

    // Verify token usage logged
    expect(consoleSpy).toHaveBeenCalledWith(
      expect.stringContaining('[GeminiCSVProvider] Token usage - Prompt: 150, Output: 50, Total: 200')
    );
  });

  test('handles missing usageMetadata gracefully', async () => {
    const mockFetch = vi.fn(() => Promise.resolve({
      ok: true,
      json: () => Promise.resolve({
        candidates: [{
          content: {
            parts: [{ text: JSON.stringify([{ title: 'Book1' }]) }]
          }
        }]
        // No usageMetadata field
      })
    }));

    global.fetch = mockFetch;
    const consoleSpy = vi.spyOn(console, 'log');

    await parseCSVWithGemini('csv', 'prompt', 'key');

    // Should log zeros as defaults
    expect(consoleSpy).toHaveBeenCalledWith(
      expect.stringContaining('Token usage - Prompt: 0, Output: 0, Total: 0')
    );
  });

  test('includes token usage in generation config', async () => {
    const mockFetch = vi.fn(() => Promise.resolve({
      ok: true,
      json: () => Promise.resolve({
        candidates: [{
          content: {
            parts: [{ text: JSON.stringify([]) }]
          }
        }]
      })
    }));

    global.fetch = mockFetch;

    await parseCSVWithGemini('csv', 'prompt', 'key');

    const requestBody = JSON.parse(mockFetch.mock.calls[0][1].body);
    
    // Verify generation config includes best practices
    expect(requestBody.generationConfig.temperature).toBe(0.1);
    expect(requestBody.generationConfig.responseMimeType).toBe('application/json');
    expect(requestBody.generationConfig.stopSequences).toEqual(['\n\n\n']);
  });
});

describe('Token Usage Tracking - Bookshelf Scanner', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  test('includes token usage in metadata for client tracking', async () => {
    const mockFetch = vi.fn(() => Promise.resolve({
      ok: true,
      json: () => Promise.resolve({
        candidates: [{
          content: {
            parts: [{ text: JSON.stringify([{ title: 'Book1', author: 'Author1', confidence: 0.9, boundingBox: { x1: 0, y1: 0, x2: 1, y2: 1 } }]) }]
          }
        }],
        usageMetadata: {
          promptTokenCount: 4200,
          candidatesTokenCount: 500,
          totalTokenCount: 4700
        }
      })
    }));

    global.fetch = mockFetch;

    // Create mock image data (ArrayBuffer)
    const imageData = new ArrayBuffer(100);
    const env = { GEMINI_API_KEY: 'test-key' };

    const result = await scanImageWithGemini(imageData, env);

    // Verify metadata includes token usage
    expect(result.metadata.tokenUsage).toBeDefined();
    expect(result.metadata.tokenUsage.promptTokens).toBe(4200);
    expect(result.metadata.tokenUsage.outputTokens).toBe(500);
    expect(result.metadata.tokenUsage.totalTokens).toBe(4700);
  });

  test('logs token usage for monitoring', async () => {
    const mockFetch = vi.fn(() => Promise.resolve({
      ok: true,
      json: () => Promise.resolve({
        candidates: [{
          content: {
            parts: [{ text: '[]' }]
          }
        }],
        usageMetadata: {
          promptTokenCount: 4128,
          candidatesTokenCount: 258,
          totalTokenCount: 4386
        }
      })
    }));

    global.fetch = mockFetch;
    const consoleSpy = vi.spyOn(console, 'log');

    const imageData = new ArrayBuffer(100);
    const env = { GEMINI_API_KEY: 'test-key' };

    await scanImageWithGemini(imageData, env);

    // Verify logging for cost tracking
    expect(consoleSpy).toHaveBeenCalledWith(
      expect.stringContaining('[GeminiProvider] Token usage - Prompt: 4128, Output: 258, Total: 4386')
    );
  });

  test('includes token usage in empty response metadata', async () => {
    const mockFetch = vi.fn(() => Promise.resolve({
      ok: true,
      json: () => Promise.resolve({
        candidates: [{
          content: {
            parts: []  // Empty response
          }
        }],
        usageMetadata: {
          promptTokenCount: 4128,
          candidatesTokenCount: 0,
          totalTokenCount: 4128
        }
      })
    }));

    global.fetch = mockFetch;

    const imageData = new ArrayBuffer(100);
    const env = { GEMINI_API_KEY: 'test-key' };

    const result = await scanImageWithGemini(imageData, env);

    // Even empty responses should include token usage
    expect(result.metadata.tokenUsage).toBeDefined();
    expect(result.metadata.tokenUsage.totalTokens).toBe(4128);
    expect(result.books).toEqual([]);
  });

  test('includes token usage in invalid array response metadata', async () => {
    const mockFetch = vi.fn(() => Promise.resolve({
      ok: true,
      json: () => Promise.resolve({
        candidates: [{
          content: {
            parts: [{ text: '{"not": "an array"}' }]  // Invalid format
          }
        }],
        usageMetadata: {
          promptTokenCount: 4128,
          candidatesTokenCount: 50,
          totalTokenCount: 4178
        }
      })
    }));

    global.fetch = mockFetch;

    const imageData = new ArrayBuffer(100);
    const env = { GEMINI_API_KEY: 'test-key' };

    const result = await scanImageWithGemini(imageData, env);

    // Error cases should still track tokens
    expect(result.metadata.tokenUsage).toBeDefined();
    expect(result.metadata.tokenUsage.totalTokens).toBe(4178);
    expect(result.books).toEqual([]);
  });
});

describe('Stop Sequences Configuration', () => {
  test('bookshelf scanner includes stop sequences', async () => {
    const mockFetch = vi.fn(() => Promise.resolve({
      ok: true,
      json: () => Promise.resolve({
        candidates: [{
          content: {
            parts: [{ text: '[]' }]
          }
        }]
      })
    }));

    global.fetch = mockFetch;

    const imageData = new ArrayBuffer(100);
    const env = { GEMINI_API_KEY: 'test-key' };

    await scanImageWithGemini(imageData, env);

    const requestBody = JSON.parse(mockFetch.mock.calls[0][1].body);
    
    expect(requestBody.generationConfig.stopSequences).toEqual(['\n\n\n']);
    expect(requestBody.generationConfig.temperature).toBe(0.4);
    expect(requestBody.generationConfig.responseMimeType).toBe('application/json');
  });

  test('CSV parser includes stop sequences', async () => {
    const mockFetch = vi.fn(() => Promise.resolve({
      ok: true,
      json: () => Promise.resolve({
        candidates: [{
          content: {
            parts: [{ text: '[]' }]
          }
        }]
      })
    }));

    global.fetch = mockFetch;

    await parseCSVWithGemini('csv', 'prompt', 'key');

    const requestBody = JSON.parse(mockFetch.mock.calls[0][1].body);
    
    expect(requestBody.generationConfig.stopSequences).toEqual(['\n\n\n']);
  });
});

describe('Token Usage Calculation Documentation', () => {
  test('documents expected token usage for typical bookshelf scan', () => {
    // This test documents the expected token calculation for validation
    const imageWidth = 3072;
    const imageHeight = 3072;
    
    // Gemini 2.0 Flash token calculation
    const cropUnit = Math.floor(Math.min(imageWidth, imageHeight) / 1.5);
    const tiles = (imageWidth / cropUnit) * (imageHeight / cropUnit);
    const expectedImageTokens = tiles * 258;
    
    // Expected: 3072 / 2048 = 1.5, so 1.5 * 1.5 = 2.25 tiles ≈ 2-3 tiles
    // Actual: 3072 / floor(3072/1.5) = 3072 / 2048 = 1.5, tiles = 1.5 * 1.5 = 2.25
    expect(cropUnit).toBe(2048);
    expect(tiles).toBeCloseTo(2.25, 1);
    expect(expectedImageTokens).toBeCloseTo(580.5, 1); // ~258 * 2.25 = 580.5
    
    // Total estimate: prompt (~150) + image (~580) + output (~500) = ~1230 tokens
    // Note: Actual may vary based on Gemini's internal tiling algorithm
  });

  test('validates small image token calculation', () => {
    // Images ≤384px should use 258 tokens
    const imageWidth = 384;
    const imageHeight = 384;
    
    // For small images, Gemini uses base 258 tokens (no tiling)
    const expectedTokens = 258;
    
    expect(imageWidth).toBeLessThanOrEqual(384);
    expect(imageHeight).toBeLessThanOrEqual(384);
    // This is a documentation test - actual token count from API may differ
  });
});
