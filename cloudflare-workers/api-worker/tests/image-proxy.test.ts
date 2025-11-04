import { describe, test, expect, vi, beforeEach } from 'vitest';
import { handleImageProxy } from '../src/handlers/image-proxy';

describe('handleImageProxy', () => {
  let mockEnv: any;

  beforeEach(() => {
    mockEnv = {
      BOOK_COVERS: {
        get: vi.fn().mockResolvedValue(null),
        put: vi.fn().mockResolvedValue(undefined)
      }
    };
  });

  test('returns 400 if url parameter missing', async () => {
    const request = new Request('https://worker.dev/images/proxy');
    const response = await handleImageProxy(request, mockEnv);

    expect(response.status).toBe(400);
    const text = await response.text();
    expect(text).toContain('Missing url parameter');
  });

  test('returns 403 if domain not allowed', async () => {
    const request = new Request('https://worker.dev/images/proxy?url=https://evil.com/image.jpg');
    const response = await handleImageProxy(request, mockEnv);

    expect(response.status).toBe(403);
    const text = await response.text();
    expect(text).toContain('Domain not allowed');
  });

  test('returns 400 if URL invalid', async () => {
    const request = new Request('https://worker.dev/images/proxy?url=not-a-url');
    const response = await handleImageProxy(request, mockEnv);

    expect(response.status).toBe(400);
    const text = await response.text();
    expect(text).toContain('Invalid URL');
  });

  test('returns cached image from R2 if available', async () => {
    const imageUrl = 'https://books.google.com/covers/abc.jpg';
    const request = new Request(`https://worker.dev/images/proxy?url=${encodeURIComponent(imageUrl)}`);

    const mockImageData = new Uint8Array([0xFF, 0xD8, 0xFF]); // Fake JPEG header
    const mockR2Object = {
      arrayBuffer: () => Promise.resolve(mockImageData.buffer),
      httpMetadata: { contentType: 'image/jpeg' }
    };

    mockEnv.BOOK_COVERS.get.mockResolvedValue(mockR2Object);

    const response = await handleImageProxy(request, mockEnv);

    expect(response.status).toBe(200);
    expect(mockEnv.BOOK_COVERS.get).toHaveBeenCalledWith(expect.stringContaining('covers/'));
    const contentType = response.headers.get('Content-Type');
    expect(contentType).toBe('image/jpeg');
  });

  test('fetches and caches image on cache miss', async () => {
    const imageUrl = 'https://books.google.com/covers/abc.jpg';
    const request = new Request(`https://worker.dev/images/proxy?url=${encodeURIComponent(imageUrl)}`);

    // Mock fetch to return image
    const mockImageData = new Uint8Array([0xFF, 0xD8, 0xFF, 0xE0]);
    global.fetch = vi.fn().mockResolvedValue({
      ok: true,
      arrayBuffer: () => Promise.resolve(mockImageData.buffer),
      headers: new Headers({ 'content-type': 'image/jpeg' })
    });

    const response = await handleImageProxy(request, mockEnv);

    expect(response.status).toBe(200);
    expect(mockEnv.BOOK_COVERS.put).toHaveBeenCalled();
  });
});
