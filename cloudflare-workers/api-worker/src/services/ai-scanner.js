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

    // Initialize job state
    await doStub.initializeJobState('ai_scan', 3); // 3 stages total

    // Stage 1: Image quality analysis (10% progress)
    await doStub.updateProgressV2('ai_scan', {
      progress: 0.1,
      status: 'Analyzing image quality...',
      processedCount: 0,
      currentItem: 'Image quality check'
    });
    console.log(`[AI Scanner] Progress pushed: 10% (image quality analysis)`);

    // Stage 2: AI processing with Gemini 2.0 Flash
    await doStub.updateProgressV2('ai_scan', {
      progress: 0.3,
      status: 'Processing with Gemini AI...',
      processedCount: 1,
      currentItem: 'Gemini AI processing'
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

    await doStub.updateProgressV2('ai_scan', {
      progress: 0.5,
      status: `Detected ${detectedBooks.length} books, enriching data...`,
      processedCount: 1,
      currentItem: `${detectedBooks.length} books detected`
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
          const editions = apiResponse.data.editions || [];  // FIX: Editions are at top level, not nested in works
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
        await doStub.updateProgressV2('ai_scan', {
          progress,
          status: hasError
            ? `Enriched ${completed}/${total} books (${title} failed)`
            : `Enriched ${completed}/${total} books`,
          processedCount: 2,
          currentItem: `Enriching: ${title}`
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
    // Build unified books array using AIScanCompletePayload structure
    const books = enrichedBooks.map(b => ({
      title: b.title,
      author: b.author,
      isbn: b.isbn || null,
      confidence: b.confidence,
      boundingBox: b.boundingBox,
      enrichmentStatus: b.enrichment?.status || 'pending',
      coverUrl: b.enrichment?.work?.coverImageURL || null,
      publisher: b.enrichment?.editions?.[0]?.publisher || null,
      publicationYear: b.enrichment?.editions?.[0]?.publicationYear || null
    }));

    // Final progress update before completion (100%)
    await doStub.updateProgressV2('ai_scan', {
      progress: 1.0,
      status: 'Scan complete, finalizing results...',
      processedCount: 3,
      currentItem: 'Finalizing'
    });

    // Send completion using V2 schema
    await doStub.completeV2('ai_scan', {
      totalDetected: detectedBooks.length,
      approved: approved.length,
      needsReview: review.length,
      books
    });

    console.log(`[AI Scanner] Scan complete for job ${jobId}: ${detectedBooks.length} books, ${processingTime}ms`);

  } catch (error) {
    console.error(`[AI Scanner] Scan failed for job ${jobId}:`, error);

    // Send error using V2 schema
    await doStub.sendError('ai_scan', {
      code: 'E_AI_SCAN_FAILED',
      message: error.message,
      retryable: true,
      details: {
        jobId,
        stage: 'AI processing'
      }
    });
  }
  // NOTE: No finally block needed! completeV2() and sendError() handle WebSocket cleanup
}
