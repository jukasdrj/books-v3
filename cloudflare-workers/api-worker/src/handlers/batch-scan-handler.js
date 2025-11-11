/**
 * Batch Bookshelf Scan Handler
 * Handles multiple photos in one job with sequential processing
 */

import { scanImageWithGemini } from '../providers/gemini-provider.js';
import { createSuccessResponse, createErrorResponse } from '../utils/api-responses.js';

const MAX_PHOTOS_PER_BATCH = 5;
const MAX_IMAGE_SIZE = 10_000_000; // 10MB per image

export async function handleBatchScan(request, env, ctx) {
  try {
    const { jobId, images } = await request.json();

    // Validation
    if (!jobId || !images || !Array.isArray(images)) {
      return createErrorResponse('Invalid request: jobId and images array required', 400, 'E_INVALID_REQUEST');
    }

    if (images.length === 0) {
      return createErrorResponse('At least one image required', 400, 'E_INVALID_IMAGES');
    }

    if (images.length > MAX_PHOTOS_PER_BATCH) {
      return createErrorResponse(`Batch size exceeds maximum ${MAX_PHOTOS_PER_BATCH} photos`, 400, 'E_INVALID_IMAGES');
    }

    // Validate R2 binding
    if (!env.BOOKSHELF_IMAGES) {
      console.error('R2 binding BOOKSHELF_IMAGES not configured');
      return createErrorResponse('Storage not configured', 500, 'E_INTERNAL');
    }

    // Validate image structure and size
    for (const img of images) {
      if (typeof img.index !== 'number' || !img.data) {
        return createErrorResponse('Each image must have index and data fields', 400, 'E_INVALID_IMAGES');
      }

      // Validate base64 image size (4/3 of decoded size due to base64 encoding)
      const estimatedSize = (img.data.length * 3) / 4;
      if (estimatedSize > MAX_IMAGE_SIZE) {
        return createErrorResponse(`Image ${img.index} exceeds maximum size of ${MAX_IMAGE_SIZE / 1_000_000}MB`, 413, 'E_INVALID_IMAGES');
      }
    }

    // Initialize batch job in Durable Object
    const doId = env.PROGRESS_WEBSOCKET_DO.idFromName(jobId);
    const doStub = env.PROGRESS_WEBSOCKET_DO.get(doId);

    // SECURITY: Generate authentication token for WebSocket connection
    const authToken = crypto.randomUUID();
    await doStub.setAuthToken(authToken);

    console.log(`[Batch Scan] Auth token generated for job ${jobId}`);

    await doStub.initBatch({
      jobId,
      totalPhotos: images.length,
      status: 'uploading'
    });

    // Process batch asynchronously (don't await)
    ctx.waitUntil(processBatchPhotos(jobId, images, env, doStub));

    // Return accepted response immediately with auth token
    return createSuccessResponse({
      jobId,
      token: authToken, // NEW: Token for WebSocket authentication
      totalPhotos: images.length,
      status: 'processing'
    }, {}, 202);

  } catch (error) {
    console.error('Batch scan error:', error);
    return createErrorResponse('Internal server error', 500, 'E_INTERNAL');
  }
}

async function processBatchPhotos(jobId, images, env, doStub) {
  const allBooks = [];
  const photoResults = [];

  try {
    // Phase 1: Upload all images to R2 in parallel
    const uploadPromises = images.map(async (img, idx) => {
      try {
        const imageBuffer = Buffer.from(img.data, 'base64');
        const r2Key = `bookshelf-scans/${jobId}/photo-${idx}.jpg`;

        await env.BOOKSHELF_IMAGES.put(r2Key, imageBuffer, {
          httpMetadata: { contentType: 'image/jpeg' }
        });

        return { index: idx, r2Key, success: true };
      } catch (error) {
        console.error(`Upload failed for photo ${idx}:`, error);
        return { index: idx, success: false, error: error.message };
      }
    });

    const uploadResults = await Promise.all(uploadPromises);

    // Update progress after uploads - send initial processing status
    await doStub.updateProgress(0.1, 'Photos uploaded, starting AI processing...');

    // Phase 2: Process images sequentially with Gemini
    for (let i = 0; i < uploadResults.length; i++) {
      const upload = uploadResults[i];

      if (!upload.success) {
        photoResults.push({
          index: i,
          status: 'error',
          error: upload.error
        });
        continue;
      }

      // Check if job canceled
      const isCanceled = await doStub.isBatchCanceled();
      if (isCanceled.canceled) {
        console.log(`Job ${jobId} canceled at photo ${i}, returning partial results`);

        // Return partial results from completed photos
        const partialBooks = deduplicateBooks(allBooks);

        await doStub.completeBatch({
          status: 'canceled',
          totalBooks: partialBooks.length,
          photoResults: photoResults.concat(
            // Mark remaining photos as skipped
            uploadResults.slice(i).map((upload, idx) => ({
              index: i + idx,
              status: 'skipped',
              booksFound: 0
            }))
          ),
          books: partialBooks
        });

        return; // Exit early with partial results
      }

      // Update progress: processing this photo
      await doStub.updatePhoto({
        photoIndex: i,
        status: 'processing'
      });

      try {
        // Call Gemini provider directly (already imported at top)
        const r2Object = await env.BOOKSHELF_IMAGES.get(upload.r2Key);
        const imageBuffer = await r2Object.arrayBuffer();

        const result = await scanImageWithGemini(imageBuffer, env);

        photoResults.push({
          index: i,
          status: 'complete',
          booksFound: result.books.length
        });

        allBooks.push(...result.books);

        // Update progress: photo complete
        await doStub.updatePhoto({
          photoIndex: i,
          status: 'complete',
          booksFound: result.books.length
        });

      } catch (error) {
        console.error(`Processing failed for photo ${i}:`, error);
        photoResults.push({
          index: i,
          status: 'error',
          error: error.message
        });

        // Update progress: photo error
        await doStub.updatePhoto({
          photoIndex: i,
          status: 'error',
          error: error.message
        });
      }
    }

    // Phase 3: Deduplicate books by ISBN
    const uniqueBooks = deduplicateBooks(allBooks);

    // Send final completion
    await doStub.completeBatch({
      status: 'complete',
      totalBooks: uniqueBooks.length,
      photoResults,
      books: uniqueBooks
    });

  } catch (error) {
    console.error('Batch processing error:', error);
    await doStub.fail({
      error: error.message,
      fallbackAvailable: false
    });
  }
}

function deduplicateBooks(books) {
  const seen = new Map();

  for (const book of books) {
    // Use ISBN as primary key, fallback to title+author
    const key = book.isbn || `${book.title}::${book.author}`;

    if (!seen.has(key)) {
      seen.set(key, book);
    } else {
      // Keep book with higher confidence
      const existing = seen.get(key);
      if ((book.confidence || 0) > (existing.confidence || 0)) {
        seen.set(key, book);
      }
    }
  }

  return Array.from(seen.values());
}
