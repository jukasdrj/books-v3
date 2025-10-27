// test/gemini-csv-provider.test.js
import { describe, test, expect, vi } from 'vitest';
import { parseCSVWithGemini } from '../src/providers/gemini-csv-provider.js';

describe('Gemini CSV Provider', () => {
  test('calls Gemini API with prompt and CSV content', async () => {
    const mockFetch = vi.fn(() => Promise.resolve({
      ok: true,
      json: () => Promise.resolve({
        candidates: [{
          content: {
            parts: [{
              text: JSON.stringify([{ title: 'Book1', author: 'Author1' }])
            }]
          }
        }]
      })
    }));

    global.fetch = mockFetch;

    const prompt = 'Parse this CSV';
    const csvText = 'Title,Author\nBook1,Author1';
    const apiKey = 'test-key';

    const result = await parseCSVWithGemini(csvText, prompt, apiKey);

    expect(result).toEqual([{ title: 'Book1', author: 'Author1' }]);
    expect(mockFetch).toHaveBeenCalledWith(
      expect.stringContaining('generativelanguage.googleapis.com'),
      expect.objectContaining({ method: 'POST' })
    );
  });

  test('throws error on invalid JSON response', async () => {
    const mockFetch = vi.fn(() => Promise.resolve({
      ok: true,
      json: () => Promise.resolve({
        candidates: [{
          content: {
            parts: [{ text: 'Not valid JSON' }]
          }
        }]
      })
    }));

    global.fetch = mockFetch;

    await expect(parseCSVWithGemini('csv', 'prompt', 'key')).rejects.toThrow('Invalid JSON');
  });
});
