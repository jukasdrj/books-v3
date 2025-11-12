// src/handlers/batch-enrichment.js
import { enrichBooksParallel } from '../services/parallel-enrichment.js';
import { enrichSingleBook } from '../services/enrichment.ts';
import { createSuccessResponse, createErrorResponse } from '../utils/api-responses.js';

/**
 * Sanitize user input to prevent XSS attacks
 * Escapes HTML entities: <, >, &, ", '
 *
 * @param {string} str - Input string to sanitize
 * @returns {string} Sanitized string
 */
function sanitizeString(str) {
  if (typeof str !== 'string') return str;
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#x27;')
    .trim();
}

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

    // Validate request structure
    if (!books || !Array.isArray(books)) {
      return createErrorResponse('Invalid books array', 400, 'E_INVALID_REQUEST');
    }

    if (!jobId) {
      return createErrorResponse('Missing jobId', 400, 'E_INVALID_REQUEST');
    }

    // DoS Protection: Limit batch size to prevent cost explosion
    if (books.length === 0) {
      return createErrorResponse('Empty books array', 400, 'E_EMPTY_BATCH');
    }

    if (books.length > 100) {
      return createErrorResponse(
        'Batch size exceeds maximum of 100 books',
        400,
        'E_BATCH_TOO_LARGE'
      );
    }

    // Validate and sanitize each book
    for (let i = 0; i < books.length; i++) {
      const book = books[i];

      // Title validation
      if (!book.title || typeof book.title !== 'string') {
        return createErrorResponse(
          `Invalid title for book at index ${i}`,
          400,
          'E_INVALID_BOOK'
        );
      }

      // XSS Protection: Limit title length
      if (book.title.length > 500) {
        return createErrorResponse(
          `Title exceeds maximum length of 500 characters at index ${i}`,
          400,
          'E_TITLE_TOO_LONG'
        );
      }

      // Optional fields validation
      if (book.author && typeof book.author !== 'string') {
        return createErrorResponse(
          `Invalid author for book at index ${i}`,
          400,
          'E_INVALID_BOOK'
        );
      }

      if (book.author && book.author.length > 300) {
        return createErrorResponse(
          `Author exceeds maximum length of 300 characters at index ${i}`,
          400,
          'E_AUTHOR_TOO_LONG'
        );
      }

      if (book.isbn && typeof book.isbn !== 'string') {
        return createErrorResponse(
          `Invalid ISBN for book at index ${i}`,
          400,
          'E_INVALID_BOOK'
        );
      }

      if (book.isbn && book.isbn.length > 17) {
        return createErrorResponse(
          `ISBN exceeds maximum length of 17 characters at index ${i}`,
          400,
          'E_ISBN_TOO_LONG'
        );
      }

      // XSS Protection: Sanitize HTML entities in title and author
      book.title = sanitizeString(book.title);
      if (book.author) book.author = sanitizeString(book.author);
      if (book.isbn) book.isbn = sanitizeString(book.isbn);
    }

    // Get WebSocket DO stub
    const doId = env.PROGRESS_WEBSOCKET_DO.idFromName(jobId);
    const doStub = env.PROGRESS_WEBSOCKET_DO.get(doId);

    // Generate and store auth token for WebSocket authentication
    const authToken = crypto.randomUUID();
    await doStub.setAuthToken(authToken);

    console.log(`[Batch Enrichment] Auth token generated for job ${jobId}`);

    // Start background enrichment
    ctx.waitUntil(processBatchEnrichment(books, doStub, env, jobId));

    // Return structure expected by iOS EnrichmentAPIClient
    // iOS expects: { success: Bool, processedCount: Int, totalCount: Int, token: String }
    // Since enrichment happens async, we return:
    // - success: true (job accepted and started)
    // - processedCount: 0 (no books processed yet)
    // - totalCount: books.length (total books queued)
    // - token: authToken (for WebSocket authentication)
    // Actual enrichment results come via WebSocket
    return createSuccessResponse({
      success: true,
      processedCount: 0,
      totalCount: books.length,
      token: authToken  // Required for WebSocket connection
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
 * @param {string} jobId - The client-provided job identifier
 */
async function processBatchEnrichment(books, doStub, env, jobId) {
  const startTime = Date.now();
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

        // Call DO with pipeline and payload (DO constructs the message envelope)
        await doStub.updateProgressV2('batch_enrichment', {
          progress,
          status,
          processedCount: completed,
          currentItem: title,
        });
      },
      10 // Concurrency limit
    );

    const totalProcessed = enrichedBooks.length;
    const successCount = enrichedBooks.filter(b => b.success).length;
    const failureCount = totalProcessed - successCount;
    const duration = Date.now() - startTime;

    // Call DO with pipeline and payload (DO constructs the message envelope)
    await doStub.completeV2('batch_enrichment', {
      totalProcessed,
      successCount,
      failureCount,
      duration,
      enrichedBooks,
    });

  } catch (error) {
    // Call sendError on DO (DO constructs the error message)
    await doStub.sendError('batch_enrichment', {
      code: 'E_BATCH_PROCESSING_FAILED',
      message: error.message,
      retryable: true,
    });
  }
}
