// test/csv-import.test.js
import { describe, test, expect, vi } from 'vitest';
import { handleCSVImport, processCSVImport } from '../src/handlers/csv-import.js';

describe('CSV Import Handler', () => {
  test('POST /api/import/csv-gemini returns jobId', async () => {
    const formData = new FormData();
    formData.append('file', new File(['Title,Author\nBook1,Author1'], 'test.csv'));

    const request = new Request('http://localhost/api/import/csv-gemini', {
      method: 'POST',
      body: formData
    });

    const mockEnv = {
      PROGRESS_WEBSOCKET_DO: {
        idFromName: vi.fn(() => 'do-id'),
        get: vi.fn(() => ({}))
      },
      ctx: { waitUntil: vi.fn() }
    };

    const response = await handleCSVImport(request, mockEnv);
    const data = await response.json();

    expect(response.status).toBe(200);
    expect(data.jobId).toBeDefined();
    expect(mockEnv.ctx.waitUntil).toHaveBeenCalled();
  });

  test('rejects files larger than 10MB', async () => {
    const largeContent = 'x'.repeat(11 * 1024 * 1024);
    const formData = new FormData();
    formData.append('file', new File([largeContent], 'large.csv'));

    const request = new Request('http://localhost/api/import/csv-gemini', {
      method: 'POST',
      body: formData
    });

    const response = await handleCSVImport(request, {});
    expect(response.status).toBe(413);
  });
});
