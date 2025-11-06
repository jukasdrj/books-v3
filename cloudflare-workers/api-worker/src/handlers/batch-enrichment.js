// src/handlers/batch-enrichment.js
import { enrichBooksParallel } from '../services/parallel-enrichment.js';
import { enrichSingleBook } from '../services/enrichment.ts';
import { createSuccessResponse, createErrorResponse } from '../utils/api-responses.js';

/**
 * Handle batch enrichment request (POST /api/enrichment/batch)
 *
 * Accepts a batch of books for background enrichment and returns immediately with 202 Accepted.
 * Actual enrichment happens asynchronously via ctx.waitUntil() with progress updates pushed via WebSocket.
 *
 * Used by:
 * - iOS CSV import enrichment
 * - iOS background enrichment queue
 * - Batch enrichment for large libraries
 *
 * @param {Request} request - Incoming request with JSON body { books: [{ title, author, isbn }], jobId }
 * @param {Object} env - Worker environment bindings
 * @param {ExecutionContext} ctx - Execution context for waitUntil
 * @returns {Promise<Response>} ResponseEnvelope<{ success, processedCount, totalCount }> with 202 status
 */
export async function handleBatchEnrichment(request, env, ctx) {
  try {
    const { books, jobId } = await request.json();

    if (!books || !Array.isArray(books)) {
      return createErrorResponse('Invalid books array', 400, 'E_INVALID_REQUEST');
    }

    if (!jobId) {
      return createErrorResponse('Missing jobId', 400, 'E_INVALID_REQUEST');
    }

    if (books.length === 0) {
      return createErrorResponse('Empty books array', 400, 'E_EMPTY_BATCH');
    }

    // Get WebSocket DO stub
    const doId = env.PROGRESS_WEBSOCKET_DO.idFromName(jobId);
    const doStub = env.PROGRESS_WEBSOCKET_DO.get(doId);

    // Start background enrichment
    ctx.waitUntil(processBatchEnrichment(books, doStub, env));

    // Return structure expected by iOS EnrichmentAPIClient
    // iOS expects: { success: Bool, processedCount: Int, totalCount: Int }
    // Since enrichment happens async, we return:
    // - success: true (job accepted and started)
    // - processedCount: 0 (no books processed yet)
    // - totalCount: books.length (total books queued)
    // Actual enrichment results come via WebSocket
    return createSuccessResponse({ 
      success: true,
      processedCount: 0,
      totalCount: books.length
    }, {}, 202);

  } catch (error) {
    return createErrorResponse(error.message, 500, 'E_INTERNAL');
  }
}

/**
 * Background processor for batch enrichment
 *
 * @param {Array<Object>} books - Books to enrich (title, author, isbn)
 * @param {Object} doStub - ProgressWebSocketDO stub
 * @param {Object} env - Worker environment bindings
 */
async function processBatchEnrichment(books, doStub, env) {
  try {
    // Reuse existing enrichBooksParallel() logic
    const enrichedBooks = await enrichBooksParallel(
      books,
      async (book) => {
        // Call enrichment service (multi-provider fallback: Google Books → OpenLibrary)
        // Returns SingleEnrichmentResult { work, edition, authors } or null
        const enriched = await enrichSingleBook(
          {
            title: book.title,
            author: book.author,
            isbn: book.isbn
          },
          env
        );

        if (enriched) {
          // enriched is now SingleEnrichmentResult with work, edition (includes coverImageURL!), and authors
          return { ...book, enriched, success: true };
        } else {
          return {
            ...book,
            enriched: null,
            success: false,
            error: 'Book not found in any provider'
          };
        }
      },
      async (completed, total, title, hasError) => {
        const progress = completed / total;
        const status = hasError
          ? `Enriching (${completed}/${total}): ${title} [failed]`
          : `Enriching (${completed}/${total}): ${title}`;
        await doStub.updateProgress(progress, status);
      },
      10 // Concurrency limit
    );

    await doStub.complete({ books: enrichedBooks });

  } catch (error) {
    await doStub.fail({
      error: error.message,
      suggestion: 'Retry batch enrichment request'
    });
  }
}
