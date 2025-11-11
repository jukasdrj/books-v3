/**
 * Batch Bookshelf Scan Handler
 * Handles multiple photos in one job with sequential processing
 */

import { scanImageWithGemini } from '../providers/gemini-provider.js';
import { createSuccessResponse, createErrorResponse } from '../utils/api-responses.js';
import { enrichBooksParallel } from '../services/parallel-enrichment.js';
import { handleSearchAdvanced } from './v1/search-advanced.js';

const MAX_PHOTOS_PER_BATCH = 5;
const MAX_IMAGE_SIZE = 10_000_000; // 10MB per image

/**
 * Helper function to map book objects to DetectedBook format
 * Centralizes transformation logic to ensure consistency across all code paths
 */
function mapToDetectedBook(book) {
  return {
    title: book?.title,
    author: book?.author,
    isbn: book?.isbn,
    confidence: book?.confidence,
    boundingBox: book?.boundingBox,
    enrichmentStatus: book?.enrichment?.status || book?.enrichmentStatus || 'pending',
    coverUrl: book?.enrichment?.work?.coverImageURL || book?.coverUrl || null,
    publisher: book?.enrichment?.editions?.[0]?.publisher || book?.publisher || null,
    publicationYear: book?.enrichment?.editions?.[0]?.publicationYear || book?.publicationYear || null
  };
}

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

    // Initialize job state for batch scan
    await doStub.initializeJobState('ai_scan', images.length);

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
    await doStub.updateProgressV2('ai_scan', {
      progress: 0.1,
      status: 'Photos uploaded, starting AI processing...',
      processedCount: 0,
      currentItem: `Uploaded ${uploadResults.length} photos`
    });

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

      // Check if job canceled (batch-specific cancellation check)
      const { canceled: isCanceled } = await doStub.isBatchCanceled();
      if (isCanceled) {
        console.log(`Job ${jobId} canceled at photo ${i}, returning partial results`);

        // Return partial results from completed photos
        const partialBooks = deduplicateBooks(allBooks);

        // Enrich partial results before returning
        await doStub.updateProgressV2('ai_scan', {
          progress: 0.8,
          status: `Job canceled, enriching ${partialBooks.length} partial results...`,
          processedCount: i,
          currentItem: 'Enrichment phase'
        });

        const enrichedPartialBooks = await enrichBooksParallel(
          partialBooks,
          async (book) => {
            // Enrichment function: fetch metadata for this book
            const apiResponse = await handleSearchAdvanced(
              book.title || '',
              book.author || '',
              env
            );

            // Parse canonical ApiResponse<BookSearchResponse>
            if (apiResponse.success) {
              const work = apiResponse.data.works?.[0] || null;
              const editions = apiResponse.data.editions || [];
              const authors = apiResponse.data.authors || [];

              return {
                ...book,
                enrichment: {
                  status: work ? 'success' : 'not_found',
                  work,
                  editions,
                  authors,
                  provider: apiResponse.meta.provider,
                  cachedResult: apiResponse.meta.cached || false
                }
              };
            } else {
              return {
                ...book,
                enrichment: {
                  status: 'error',
                  error: apiResponse.error.message,
                  work: null,
                  editions: [],
                  authors: []
                }
              };
            }
          },
          async (completed, total, title, hasError) => {
            // Progress callback: update progress after each book
            const enrichProgress = 0.8 + (0.2 * (completed / total));
            await doStub.updateProgressV2('ai_scan', {
              progress: enrichProgress,
              status: hasError
                ? `Enriching canceled job results... (${completed}/${total}, ${title} failed)`
                : `Enriching canceled job results... (${completed}/${total})`,
              processedCount: completed,
              currentItem: title || 'Unknown title'
            });
          },
          10 // maxConcurrent
        );

        const approvedCount = enrichedPartialBooks.filter(b => b.confidence >= 0.6).length;
        const reviewCount = enrichedPartialBooks.filter(b => b.confidence < 0.6).length;

        // Final progress update before completion
        await doStub.updateProgressV2('ai_scan', {
          progress: 1.0,
          status: 'Job canceled, returning partial results...',
          processedCount: enrichedPartialBooks.length,
          currentItem: 'Finalizing'
        });

        // FIX: Removed non-standard 'canceled: true' field (not in AIScanCompletePayload schema)
        // Client will know about cancellation from progress messages showing partial results
        await doStub.completeV2('ai_scan', {
          totalDetected: enrichedPartialBooks.length,
          approved: approvedCount,
          needsReview: reviewCount,
          books: enrichedPartialBooks.map(mapToDetectedBook)
        });

        return; // Exit early with partial results
      }

      // Update progress: processing this photo
      const progress = (i + 0.5) / uploadResults.length;
      await doStub.updateProgressV2('ai_scan', {
        progress,
        status: `Processing photo ${i + 1} of ${uploadResults.length}...`,
        processedCount: i,
        currentItem: `Photo ${i + 1}`
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
        const completionProgress = (i + 1) / uploadResults.length;
        await doStub.updateProgressV2('ai_scan', {
          progress: completionProgress,
          status: `Completed photo ${i + 1} of ${uploadResults.length} - Found ${result.books.length} books`,
          processedCount: i + 1,
          currentItem: `Photo ${i + 1}: ${result.books.length} books`
        });

      } catch (error) {
        console.error(`Processing failed for photo ${i}:`, error);
        photoResults.push({
          index: i,
          status: 'error',
          error: error.message
        });

        // Update progress: photo error
        const errorProgress = (i + 1) / uploadResults.length;
        await doStub.updateProgressV2('ai_scan', {
          progress: errorProgress,
          status: `Error processing photo ${i + 1}: ${error.message}`,
          processedCount: i + 1,
          currentItem: `Photo ${i + 1}: Error`
        });
      }
    }

    // Phase 3: Deduplicate books by ISBN
    const uniqueBooks = deduplicateBooks(allBooks);

    // Phase 4: Enrich books with metadata (parallel)
    // Update progress to show enrichment phase starting
    await doStub.updateProgressV2('ai_scan', {
      progress: 0.8,
      status: `Enriching ${uniqueBooks.length} books with metadata...`,
      processedCount: uploadResults.length,
      currentItem: 'Enrichment phase'
    });

    const enrichedBooks = await enrichBooksParallel(
      uniqueBooks,
      async (book) => {
        // Enrichment function: fetch metadata for this book
        const apiResponse = await handleSearchAdvanced(
          book.title || '',
          book.author || '',
          env
        );

        // Parse canonical ApiResponse<BookSearchResponse>
        if (apiResponse.success) {
          const work = apiResponse.data.works?.[0] || null;
          const editions = apiResponse.data.editions || [];
          const authors = apiResponse.data.authors || [];

          return {
            ...book,
            enrichment: {
              status: work ? 'success' : 'not_found',
              work,
              editions,
              authors,
              provider: apiResponse.meta.provider,
              cachedResult: apiResponse.meta.cached || false
            }
          };
        } else {
          return {
            ...book,
            enrichment: {
              status: 'error',
              error: apiResponse.error.message,
              work: null,
              editions: [],
              authors: []
            }
          };
        }
      },
      async (completed, total, title, hasError) => {
        // Progress callback: update progress after each book
        const enrichProgress = 0.8 + (0.2 * (completed / total));
        await doStub.updateProgressV2('ai_scan', {
          progress: enrichProgress,
          status: hasError
            ? `Enriching books... (${completed}/${total}, ${title} failed)`
            : `Enriching books... (${completed}/${total})`,
          processedCount: completed,
          currentItem: title || 'Unknown title'
        });
      },
      10 // maxConcurrent
    );

    // Calculate approved vs review queue counts (threshold: 0.6 confidence)
    const approvedCount = enrichedBooks.filter(b => b.confidence >= 0.6).length;
    const reviewCount = enrichedBooks.filter(b => b.confidence < 0.6).length;

    // Final progress update before completion (100%)
    await doStub.updateProgressV2('ai_scan', {
      progress: 1.0,
      status: 'Batch scan complete, finalizing results...',
      processedCount: uniqueBooks.length,
      currentItem: 'Finalizing'
    });

    // Send final completion using V2 schema with enriched data
    await doStub.completeV2('ai_scan', {
      totalDetected: enrichedBooks.length,
      approved: approvedCount,
      needsReview: reviewCount,
      books: enrichedBooks.map(mapToDetectedBook)
    });

  } catch (error) {
    console.error('Batch processing error:', error);
    await doStub.sendError('ai_scan', {
      code: 'E_BATCH_SCAN_FAILED',
      message: error.message,
      retryable: true,
      details: {
        fallbackAvailable: false
      }
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
