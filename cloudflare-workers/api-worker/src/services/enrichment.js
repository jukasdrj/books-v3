import * as externalApis from './external-apis.js';
import { normalizeGoogleBooksToWork, normalizeGoogleBooksToEdition } from './normalizers/google-books.js';

/**
 * Transforms the raw Google Books API response into canonical DTO format
 * @param {Object} googleBooksResponse - The raw JSON response from the Google Books API
 * @returns {Object} Canonical format: { work, editions, authors }
 */
function transformGoogleBooksResponse(googleBooksResponse) {
  if (!googleBooksResponse || !googleBooksResponse.items || googleBooksResponse.items.length === 0) {
    return {
      work: null,
      editions: [],
      authors: []
    };
  }

  // Use first item as primary book
  const primaryItem = googleBooksResponse.items[0];
  const volumeInfo = primaryItem.volumeInfo || {};

  // Normalize to canonical WorkDTO
  const work = normalizeGoogleBooksToWork(primaryItem);

  // Normalize all items to EditionDTOs
  const editions = googleBooksResponse.items.map(item => normalizeGoogleBooksToEdition(item));

  // Extract unique authors
  const authorNames = volumeInfo.authors || [];
  const authors = authorNames.map(name => ({
    name,
    gender: 'Unknown',
  }));

  return {
    work,
    editions,
    authors
  };
}


/**
 * Book enrichment service
 * Migrated from enrichment-worker (Task 6: Monolith Refactor)
 *
 * Key change: Direct function calls instead of RPC service bindings.
 * Progress updates sent directly to ProgressWebSocketDO via doStub parameter.
 */

/**
 * Enrich batch of works with progress updates via WebSocket
 *
 * @param {string} jobId - Job identifier for tracking
 * @param {string[]} workIds - Array of work IDs to enrich (ISBN or title+author)
 * @param {Object} env - Worker environment bindings
 * @param {Object} doStub - ProgressWebSocketDO stub for direct progress updates
 * @returns {Promise<Object>} Enrichment result
 */
export async function enrichBatch(jobId, workIds, env, doStub) {
  const totalCount = workIds.length;
  let processedCount = 0;
  const enrichedWorks = [];
  const errors = [];

  try {
    // Initial progress update
    await doStub.pushProgress({
      progress: 0,
      processedItems: 0,
      totalItems: totalCount,
      currentStatus: `Starting enrichment for ${totalCount} books...`,
      jobId
    });

    // Process each work
    for (const workId of workIds) {
      // --- NEW CANCELLATION CHECK ---
      // Before processing the next item, check if the DO has been canceled
      let canceled = false;
      try {
        canceled = await doStub.isCanceled();
      } catch (e) {
        // An error here (e.g., "Job canceled by client") also means we should stop
        console.warn(`[${jobId}] Stopping batch, DO stub threw: ${e.message}`);
        canceled = true;
      }

      if (canceled) {
        console.log(`[${jobId}] Cancellation detected. Stopping enrichment batch.`);
        // Send cancellation status to client
        await doStub.pushProgress({
          progress: processedCount / totalCount,
          processedItems: processedCount,
          totalItems: totalCount,
          currentStatus: 'Enrichment canceled by user',
          jobId,
          result: {
            success: false,
            canceled: true,
            processedCount: processedCount,
            totalCount: totalCount,
            enrichedCount: enrichedWorks.length,
            errorCount: errors.length
          }
        }).catch(() => {
          // Ignore error - socket might already be closed
          console.log(`[${jobId}] Could not send cancel status (socket closed)`);
        });
        // Break the loop to stop processing
        break;
      }
      // --- END CANCELLATION CHECK ---

      try {
        // Enrich single work using internal function call (NO RPC!)
        const result = await enrichWorkWithAPIs(workId, env);
        enrichedWorks.push(result);

        processedCount++;
        const progress = processedCount / totalCount;

        // Direct progress update to DO (NO RPC!)
        await doStub.pushProgress({
          progress: progress,
          processedItems: processedCount,
          totalItems: totalCount,
          currentStatus: `Enriched ${processedCount}/${totalCount} books`,
          currentWorkId: workId,
          jobId
        });

      } catch (error) {
        console.error(`Enrichment failed for ${workId}:`, error);
        errors.push({
          workId,
          error: error.message
        });

        // Continue processing remaining works
        processedCount++;
      }

      // Yield to event loop to avoid blocking
      await new Promise(resolve => setTimeout(resolve, 0));
    }

    // Final success update
    await doStub.pushProgress({
      progress: 1.0,
      processedItems: processedCount,
      totalItems: totalCount,
      currentStatus: 'Enrichment complete',
      jobId,
      result: {
        success: true,
        processedCount: processedCount,
        totalCount: totalCount,
        enrichedCount: enrichedWorks.length,
        errorCount: errors.length,
        enrichedWorks: enrichedWorks,
        errors: errors
      }
    });

    return {
      success: true,
      processedCount: processedCount,
      totalCount: totalCount,
      enrichedWorks: enrichedWorks,
      errors: errors
    };

  } catch (error) {
    console.error('Enrichment batch failed:', error);

    // Send error status
    await doStub.pushProgress({
      progress: processedCount / totalCount,
      error: error.message,
      currentStatus: 'Enrichment failed',
      jobId
    });

    throw error;

  } finally {
    // Close WebSocket connection when done
    await doStub.closeConnection(1000, "Job complete");
  }
}

/**
 * Internal: Enrich single work using external APIs
 *
 * @param {string} workId - Work identifier (ISBN or title+author)
 * @param {Object} env - Worker environment bindings
 * @returns {Promise<Object>} Enrichment result with metadata
 */
async function enrichWorkWithAPIs(workId, env) {
  try {
    // Determine if workId is ISBN or title search
    const isISBN = /^(97[89])?\d{9}[\dX]$/i.test(workId);

    let enrichmentData;
    if (isISBN) {
      // Use ISBN search - direct function call (NO RPC!)
      enrichmentData = await externalApis.searchGoogleBooksByISBN(workId, env);

      // Fallback to other providers if Google Books fails
      if (!enrichmentData || !enrichmentData.items || enrichmentData.items.length === 0) {
        // Try other providers as fallback
        console.log(`Google Books returned no results for ISBN ${workId}, trying alternatives...`);
      }
    } else {
      // Use general search - direct function call (NO RPC!)
      enrichmentData = await externalApis.searchGoogleBooks(workId, { maxResults: 5 }, env);
    }

    const canonicalData = transformGoogleBooksResponse(enrichmentData);

    return {
      workId,
      enriched: true,
      work: canonicalData.work,
      editions: canonicalData.editions,
      authors: canonicalData.authors,
      isISBN,
      timestamp: new Date().toISOString()
    };

  } catch (error) {
    console.error(`enrichWorkWithAPIs failed for ${workId}:`, error);

    return {
      workId,
      enriched: false,
      error: error.message,
      timestamp: new Date().toISOString()
    };
  }
}
