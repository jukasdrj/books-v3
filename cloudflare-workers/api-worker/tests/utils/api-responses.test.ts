import { describe, test, expect } from 'vitest';
import { createSuccessResponse, createErrorResponse } from '../../src/utils/api-responses';
import type { ResponseEnvelope } from '../../src/types/responses';

describe('API Response Utilities', () => {
  test('createSuccessResponse wraps data with metadata', async () => {
    const payload = { id: 123, name: 'Test Book' };
    const response = createSuccessResponse(payload, { traceId: 'abc-123' }, 201);

    expect(response.status).toBe(201);
    expect(response.headers.get('Content-Type')).toBe('application/json');

    const body: ResponseEnvelope<typeof payload> = await response.json();

    expect(body.data).toEqual(payload);
    expect(body.error).toBeUndefined();
    expect(body.metadata.traceId).toBe('abc-123');
    expect(body.metadata.timestamp).toBeDefined();
    expect(new Date(body.metadata.timestamp).getTime()).toBeGreaterThan(0);
  });

  test('createSuccessResponse uses defaults for status and metadata', async () => {
    const payload = { message: 'OK' };
    const response = createSuccessResponse(payload);

    expect(response.status).toBe(200);

    const body: ResponseEnvelope<typeof payload> = await response.json();
    expect(body.data).toEqual(payload);
    expect(body.metadata.timestamp).toBeDefined();
  });

  test('createErrorResponse formats error with code', async () => {
    const response = createErrorResponse('Resource not found', 404, 'E_NOT_FOUND');

    expect(response.status).toBe(404);
    expect(response.headers.get('Content-Type')).toBe('application/json');

    const body: ResponseEnvelope<null> = await response.json();

    expect(body.data).toBeNull();
    expect(body.error).toBeDefined();
    expect(body.error?.message).toBe('Resource not found');
    expect(body.error?.code).toBe('E_NOT_FOUND');
    expect(body.metadata.timestamp).toBeDefined();
  });

  test('createErrorResponse uses default status 500', async () => {
    const response = createErrorResponse('Internal error');

    expect(response.status).toBe(500);

    const body: ResponseEnvelope<null> = await response.json();
    expect(body.error?.message).toBe('Internal error');
    expect(body.error?.code).toBeUndefined();
  });
});
