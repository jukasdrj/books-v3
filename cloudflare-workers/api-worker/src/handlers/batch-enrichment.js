// src/handlers/batch-enrichment.js
import { enrichBooksParallel } from '../services/parallel-enrichment.js';

/**
 * Handle batch enrichment request (POST /api/enrichment/batch)
 *
 * This endpoint is preserved for future use but NOT called by CSV import.
 * Potential future uses:
 * - iOS batch enrichment for large libraries
 * - Background enrichment jobs
 * - Admin tools for data quality improvements
 *
 * @param {Request} request - Incoming request with JSON body { books, jobId }
 * @param {Object} env - Worker environment bindings
 * @returns {Promise<Response>} Response with jobId
 */
export async function handleBatchEnrichment(request, env) {
  try {
    const { books, jobId } = await request.json();

    if (!books || !Array.isArray(books)) {
      return Response.json({ error: 'Invalid books array' }, { status: 400 });
    }

    if (!jobId) {
      return Response.json({ error: 'Missing jobId' }, { status: 400 });
    }

    // Get WebSocket DO stub
    const doId = env.PROGRESS_WEBSOCKET_DO.idFromName(jobId);
    const doStub = env.PROGRESS_WEBSOCKET_DO.get(doId);

    // Start background enrichment
    env.ctx.waitUntil(processBatchEnrichment(books, doStub, env));

    return Response.json({ jobId });

  } catch (error) {
    return Response.json({ error: error.message }, { status: 500 });
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
        // Enrichment logic here (placeholder for now)
        // Future: Call external APIs (Google Books, OpenLibrary)
        return book;
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
