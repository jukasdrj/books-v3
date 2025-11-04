import { normalizeImageURL } from '../utils/normalization.js';

/**
 * Environment bindings for image proxy handler
 */
interface Env {
  BOOK_COVERS: R2Bucket;
}

/**
 * Proxies and caches book cover images via R2 + Cloudflare Image Resizing
 *
 * Flow:
 * 1. Normalize image URL for cache key
 * 2. Check R2 bucket for cached original
 * 3. If miss: Fetch from origin, store in R2
 * 4. Return image with Cloudflare Image Resizing (on-the-fly thumbnail)
 */
export async function handleImageProxy(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const imageUrl = url.searchParams.get('url');
  const size = url.searchParams.get('size') || 'medium'; // small, medium, large

  // Validation
  if (!imageUrl) {
    return new Response('Missing url parameter', { status: 400 });
  }

  // Security: Only allow known book cover domains
  // Using Set for O(1) lookup performance vs O(n) for array.includes()
  const allowedDomains = new Set([
    'books.google.com',
    'covers.openlibrary.org',
    'images-na.ssl-images-amazon.com'
  ]);

  try {
    const parsedUrl = new URL(imageUrl);
    if (!allowedDomains.has(parsedUrl.hostname)) {
      return new Response('Domain not allowed', { status: 403 });
    }
  } catch {
    return new Response('Invalid URL', { status: 400 });
  }

  // Normalize URL for consistent caching
  const normalizedUrl = normalizeImageURL(imageUrl);
  const cacheKey = `covers/${await hashURL(normalizedUrl)}`;

  // Check R2 for cached image
  const cached = await env.BOOK_COVERS.get(cacheKey);

  if (cached) {
    try {
      console.log(`Image cache HIT: ${cacheKey}`);
      const imageData = await cached.arrayBuffer();
      const contentType = cached.httpMetadata?.contentType || 'image/jpeg';
      return resizeImage(imageData, size, contentType);
    } catch (err) {
      console.error(`Error reading cached image from R2 for key ${cacheKey}:`, err);
      // Fall through to fetch from origin
    }
  }

  console.log(`Image cache MISS: ${cacheKey}`);

  // Cache miss - fetch from origin
  const origin = await fetch(normalizedUrl, {
    headers: { 'User-Agent': 'BooksTrack/3.0 (book-cover-proxy)' }
  });

  if (!origin.ok) {
    console.error(`Failed to fetch image from origin: ${origin.status}`);
    return new Response('Failed to fetch image', { status: 502 });
  }

  // Store in R2 for future requests
  const imageData = await origin.arrayBuffer();
  const contentType = origin.headers.get('content-type') || 'image/jpeg';

  await env.BOOK_COVERS.put(cacheKey, imageData, {
    httpMetadata: { contentType }
  });

  console.log(`Stored in R2: ${cacheKey} (${imageData.byteLength} bytes)`);

  // Return resized image
  return resizeImage(imageData, size, contentType);
}

/**
 * Hash URL for R2 key generation (consistent, collision-resistant)
 * Uses Web Crypto API (Cloudflare Workers compatible)
 */
async function hashURL(url: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(url);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
}

/**
 * Resize image using Cloudflare Image Resizing
 */
function resizeImage(imageData: ArrayBuffer, size: string, contentType: string): Response {
  const SIZE_MAP: Record<string, { width: number; height: number }> = {
    small: { width: 128, height: 192 },
    medium: { width: 256, height: 384 },
    large: { width: 512, height: 768 }
  };

  const dimensions = SIZE_MAP[size] || SIZE_MAP.medium;

  return new Response(imageData, {
    headers: {
      'Content-Type': contentType,
      'Cache-Control': 'public, max-age=2592000, immutable', // 30 days
      'CF-Image-Width': dimensions.width.toString(),
      'CF-Image-Height': dimensions.height.toString(),
      'CF-Image-Fit': 'scale-down'
    }
  });
}
