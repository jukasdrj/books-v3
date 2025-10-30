/**
 * Bookshelf AI Scanner Service
 * Migrated from bookshelf-ai-worker
 *
 * OPTIMIZED: Gemini 2.0 Flash only (proven working, 2M token context window)
 * CRITICAL: Uses direct function calls instead of RPC to eliminate circular dependencies!
 */

import { handleSearchAdvanced } from '../handlers/v1/search-advanced.js';
import { scanImageWithGemini } from '../providers/gemini-provider.js';
import { enrichBooksParallel } from './parallel-enrichment.js';

/**
 * Process bookshelf image scan with AI vision
 *
 * @param {string} jobId - Unique job identifier
 * @param {ArrayBuffer} imageData - Raw image data
 * @param {Request} request - Request object with X-AI-Provider header
 * @param {Object} env - Worker environment bindings
 * @param {Object} doStub - ProgressWebSocketDO stub for status updates
 */
export async function processBookshelfScan(jobId, imageData, request, env, doStub) {
  const startTime = Date.now();

  try {
    console.log(`[AI Scanner] Starting scan for job ${jobId}, image size: ${imageData.byteLength} bytes`);

    // NEW: Check if WebSocket is ready (should have been done in index.js, but double-check)
    const elapsedMs = Date.now() - startTime;
    if (elapsedMs > 6000) {
      console.warn(`[AI Scanner] Job ${jobId} started ${elapsedMs}ms after request - possible ready timeout`);
    }

    // Stage 1: Image quality analysis (10% progress)
    await doStub.pushProgress({
      progress: 0.1,
      processedItems: 0,
      totalItems: 3,
      currentStatus: 'Analyzing image quality...',
      jobId
    });
    console.log(`[AI Scanner] Progress pushed: 10% (image quality analysis)`);

    // Stage 2: AI processing with Gemini 2.0 Flash
    await doStub.pushProgress({
      progress: 0.3,
      processedItems: 1,
      totalItems: 3,
      currentStatus: 'Processing with Gemini AI...',
      jobId
    });

    console.log(`[AI Scanner] Job ${jobId} - Using Gemini 2.0 Flash`);

    let scanResult;
    let modelUsed = 'unknown'; // Default fallback
    try {
      scanResult = await scanImageWithGemini(imageData, env);
      console.log('[AI Scanner] Gemini processing complete');

      /**
       * Extract model name from AI provider metadata for completion response.
       *
       * DEFENSIVE PROGRAMMING: Fallback to 'unknown' if metadata is incomplete.
       * This prevents runtime errors in the following scenarios:
       * 1. Future AI providers may have different metadata structures
       * 2. Gemini API response structure could change in future versions
       * 3. Network issues could result in partial/corrupted responses
       *
       * Without this fallback, missing metadata would cause:
       * - "providerParam is not defined" error at completion stage
       * - Premature WebSocket closure (code 1001 instead of clean 1000)
       * - iOS client receiving "Scan failed" despite successful AI processing
       *
       * @see ai-scanner-metadata.test.js for test coverage of this fallback
       */
      modelUsed = scanResult.metadata?.model || 'unknown';
      console.log(`[AI Scanner] Model used: ${modelUsed}`);
    } catch (aiError) {
      console.error('[AI Scanner] Gemini processing failed:', aiError.message);
      throw aiError;
    }

    const detectedBooks = scanResult.books;
    const suggestions = scanResult.suggestions || [];

    console.log(`[AI Scanner] ${detectedBooks.length} books detected (${scanResult.metadata.processingTimeMs}ms)`);

    await doStub.pushProgress({
      progress: 0.5,
      processedItems: 1,
      totalItems: 3,
      currentStatus: `Detected ${detectedBooks.length} books, enriching data...`,
      jobId,
      detectedBooks
    });

    // Stage 3: Enrichment (70% → 100% progress)
    // OPTIMIZED: Parallel enrichment with 10 concurrent requests
    const enrichedBooks = await enrichBooksParallel(
      detectedBooks,
      async (book) => {
        // Direct function call - NO RPC, no circular dependency!
        // Use v1 canonical handler
        const apiResponse = await handleSearchAdvanced(
          book.title || '',
          book.author || '',
          env
        );

        // Parse canonical ApiResponse<BookSearchResponse>
        if (apiResponse.success) {
          const work = apiResponse.data.works?.[0] || null;
          const editions = apiResponse.data.works?.[0]?.editions || [];
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
        const progress = 0.7 + (0.25 * completed / total);
        await doStub.pushProgress({
          progress,
          processedItems: 2,
          totalItems: 3,
          currentStatus: hasError
            ? `Enriched ${completed}/${total} books (${title} failed)`
            : `Enriched ${completed}/${total} books`,
          jobId
        });
      },
      10 // 10 concurrent requests (matches CSV import concurrency)
    );

    // Separate high/low confidence results
    const threshold = parseFloat(env.CONFIDENCE_THRESHOLD || '0.6');
    const approved = enrichedBooks.filter(b => b.confidence >= threshold);
    const review = enrichedBooks.filter(b => b.confidence < threshold);

    const processingTime = Date.now() - startTime;

    // Stage 4: Complete (100%)
    // Extract canonical DTOs from enriched books
    const works = enrichedBooks.map(b => b.enrichment.work).filter(Boolean);
    const editions = enrichedBooks.flatMap(b => b.enrichment.editions || []);
    const authors = enrichedBooks.flatMap(b => b.enrichment.authors || []);

    await doStub.pushProgress({
      progress: 1.0,
      processedItems: 3,
      totalItems: 3,
      currentStatus: 'Scan complete',
      jobId,
      result: {
        totalDetected: detectedBooks.length,
        approved: approved.length,
        needsReview: review.length,
        works,
        editions,
        authors,
        detections: detectedBooks,  // Original AI detection data
        metadata: {
          processingTime,
          enrichedCount: enrichedBooks.filter(b => b.enrichment?.status === 'success').length,
          timestamp: new Date().toISOString(),
          modelUsed: modelUsed  // Model name from AI provider (gemini-2.0-flash-exp)
        }
      }
    });

    console.log(`[AI Scanner] Scan complete for job ${jobId}: ${detectedBooks.length} books, ${processingTime}ms`);

  } catch (error) {
    console.error(`[AI Scanner] Scan failed for job ${jobId}:`, error);

    // Push error to WebSocket
    await doStub.pushProgress({
      progress: 0,
      processedItems: 0,
      totalItems: 3,
      currentStatus: 'Scan failed',
      jobId,
      error: error.message
    });
  } finally {
    // Close WebSocket connection
    await doStub.closeConnection(1000, 'Scan complete');
  }
}
