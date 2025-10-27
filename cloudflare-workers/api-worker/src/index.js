import { ProgressWebSocketDO } from './durable-objects/progress-socket.js';
import * as externalApis from './services/external-apis.js';
import * as enrichment from './services/enrichment.js';
import * as aiScanner from './services/ai-scanner.js';
import * as bookSearch from './handlers/book-search.js';
import { handleAdvancedSearch } from './handlers/search-handlers.js';
import { handleBatchScan } from './handlers/batch-scan-handler.js';

// Export the Durable Object class for Cloudflare Workers runtime
export { ProgressWebSocketDO };

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // Route WebSocket connections to the Durable Object
    if (url.pathname === '/ws/progress') {
      const jobId = url.searchParams.get('jobId');
      if (!jobId) {
        return new Response('Missing jobId parameter', { status: 400 });
      }

      // Get Durable Object instance for this specific jobId
      const doId = env.PROGRESS_WEBSOCKET_DO.idFromName(jobId);
      const doStub = env.PROGRESS_WEBSOCKET_DO.get(doId);

      // Forward the request to the Durable Object
      return doStub.fetch(request);
    }

    // ========================================================================
    // Enrichment API Endpoint
    // ========================================================================

    // POST /api/enrichment/start - Start batch enrichment with WebSocket progress
    if (url.pathname === '/api/enrichment/start' && request.method === 'POST') {
      try {
        const { jobId, workIds } = await request.json();

        // Validate request
        if (!jobId || !workIds || !Array.isArray(workIds)) {
          return new Response(JSON.stringify({
            error: 'Invalid request: jobId and workIds (array) required'
          }), {
            status: 400,
            headers: { 'Content-Type': 'application/json' }
          });
        }

        if (workIds.length === 0) {
          return new Response(JSON.stringify({
            error: 'Invalid request: workIds array cannot be empty'
          }), {
            status: 400,
            headers: { 'Content-Type': 'application/json' }
          });
        }

        // Get DO stub for this job
        const doId = env.PROGRESS_WEBSOCKET_DO.idFromName(jobId);
        const doStub = env.PROGRESS_WEBSOCKET_DO.get(doId);

        // Start enrichment in background (direct function call, NO RPC!)
        ctx.waitUntil(enrichment.enrichBatch(jobId, workIds, env, doStub));

        // Return 202 Accepted immediately
        return new Response(JSON.stringify({
          jobId,
          status: 'started',
          totalBooks: workIds.length,
          message: 'Enrichment job started. Connect to /ws/progress?jobId=' + jobId + ' for real-time updates.'
        }), {
          status: 202,
          headers: { 'Content-Type': 'application/json' }
        });

      } catch (error) {
        console.error('Failed to start enrichment:', error);
        return new Response(JSON.stringify({
          error: 'Failed to start enrichment',
          message: error.message
        }), {
          status: 500,
          headers: { 'Content-Type': 'application/json' }
        });
      }
    }

    // POST /api/enrichment/cancel - Cancel an in-flight enrichment job
    if (url.pathname === '/api/enrichment/cancel' && request.method === 'POST') {
      try {
        const { jobId } = await request.json();

        // Validate request
        if (!jobId) {
          return new Response(JSON.stringify({
            error: 'Invalid request: jobId required'
          }), {
            status: 400,
            headers: { 'Content-Type': 'application/json' }
          });
        }

        // Get DO stub for this job
        const doId = env.PROGRESS_WEBSOCKET_DO.idFromName(jobId);
        const doStub = env.PROGRESS_WEBSOCKET_DO.get(doId);

        // Call cancelJob() on the Durable Object
        const result = await doStub.cancelJob("Canceled by iOS client during library reset");

        // Return success response
        return new Response(JSON.stringify({
          jobId,
          status: 'canceled',
          message: 'Enrichment job canceled successfully'
        }), {
          status: 200,
          headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
          }
        });

      } catch (error) {
        console.error('Failed to cancel enrichment:', error);
        return new Response(JSON.stringify({
          error: 'Failed to cancel enrichment',
          message: error.message
        }), {
          status: 500,
          headers: { 'Content-Type': 'application/json' }
        });
      }
    }

    // ========================================================================
    // AI Scanner Endpoint
    // ========================================================================

    // POST /api/scan-bookshelf/batch - Batch AI bookshelf scanner with WebSocket progress
    if (url.pathname === '/api/scan-bookshelf/batch' && request.method === 'POST') {
      return handleBatchScan(request, env, ctx);
    }

    // POST /api/scan-bookshelf/cancel - Cancel batch processing
    if (url.pathname === '/api/scan-bookshelf/cancel' && request.method === 'POST') {
      try {
        const { jobId } = await request.json();

        if (!jobId) {
          return new Response(JSON.stringify({ error: 'jobId required' }), {
            status: 400,
            headers: { 'Content-Type': 'application/json' }
          });
        }

        // Call Durable Object to cancel batch
        const doId = env.PROGRESS_WEBSOCKET_DO.idFromName(jobId);
        const doStub = env.PROGRESS_WEBSOCKET_DO.get(doId);
        const result = await doStub.cancelBatch();

        return new Response(JSON.stringify(result), {
          status: 200,
          headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
          }
        });
      } catch (error) {
        console.error('Cancel batch error:', error);
        return new Response(JSON.stringify({ error: 'Failed to cancel batch' }), {
          status: 500,
          headers: { 'Content-Type': 'application/json' }
        });
      }
    }

    // POST /api/scan-bookshelf - AI bookshelf scanner with WebSocket progress
    if (url.pathname === '/api/scan-bookshelf' && request.method === 'POST') {
      try {
        // Get or generate jobId
        const jobId = url.searchParams.get('jobId') || crypto.randomUUID();

        // DIAGNOSTIC: Log all incoming headers
        console.log(`[Diagnostic Layer 1: Main Router] === Incoming Request Headers for job ${jobId} ===`);
        const aiProviderHeader = request.headers.get('X-AI-Provider');
        console.log(`[Diagnostic Layer 1: Main Router] X-AI-Provider header: ${aiProviderHeader ? aiProviderHeader : 'NOT FOUND'}`);
        console.log(`[Diagnostic Layer 1: Main Router] All headers:`, Object.fromEntries(request.headers.entries()));

        // Validate content type
        const contentType = request.headers.get('content-type') || '';
        if (!contentType.startsWith('image/')) {
          return new Response(JSON.stringify({
            error: 'Invalid content type: image/* required'
          }), {
            status: 400,
            headers: { 'Content-Type': 'application/json' }
          });
        }

        // Read image data
        const imageData = await request.arrayBuffer();

        // Validate size (default 10MB max)
        const maxSize = parseInt(env.MAX_SCAN_FILE_SIZE || '10485760');
        if (imageData.byteLength > maxSize) {
          return new Response(JSON.stringify({
            error: 'Image too large',
            maxSize: maxSize,
            receivedSize: imageData.byteLength
          }), {
            status: 413,
            headers: { 'Content-Type': 'application/json' }
          });
        }

        // Get DO stub for this job
        const doId = env.PROGRESS_WEBSOCKET_DO.idFromName(jobId);
        const doStub = env.PROGRESS_WEBSOCKET_DO.get(doId);

        // CRITICAL: Wait for WebSocket ready signal before processing
        // This prevents race condition where we send updates before client connects
        console.log(`[API] Waiting for WebSocket ready signal for job ${jobId}`);

        const readyResult = await doStub.waitForReady(5000); // 5 second timeout

        if (readyResult.timedOut || readyResult.disconnected) {
          const reason = readyResult.timedOut ? 'timeout' : 'WebSocket not connected';
          console.warn(`[API] WebSocket ready ${reason} for job ${jobId}, proceeding anyway (client may miss early updates)`);
          // Continue processing - client might be using polling fallback
        } else {
          console.log(`[API] ✅ WebSocket ready for job ${jobId}, starting processing`);
        }

        // Start AI scan in background (NOW guaranteed WebSocket is listening)
        ctx.waitUntil(aiScanner.processBookshelfScan(jobId, imageData, request, env, doStub));

        // Define stages metadata for iOS client (used for progress estimation)
        const stages = [
          { name: "Image Quality Analysis", typicalDuration: 3, progress: 0.1 },
          { name: "AI Processing", typicalDuration: 25, progress: 0.5 },
          { name: "Metadata Enrichment", typicalDuration: 12, progress: 1.0 }
        ];

        // Calculate estimated range based on total stage durations
        const totalDuration = stages.reduce((sum, stage) => sum + stage.typicalDuration, 0);
        const estimatedRange = [Math.floor(totalDuration * 0.8), Math.ceil(totalDuration * 1.2)];

        // Return 202 Accepted immediately with stages metadata
        return new Response(JSON.stringify({
          jobId,
          status: 'started',
          websocketReady: readyResult.success, // NEW: Indicates if WebSocket is ready
          message: 'AI scan started. Connect to /ws/progress?jobId=' + jobId + ' for real-time updates.',
          stages,
          estimatedRange
        }), {
          status: 202,
          headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*' // CORS for iOS app
          }
        });

      } catch (error) {
        console.error('Failed to start AI scan:', error);
        return new Response(JSON.stringify({
          error: 'Failed to start AI scan',
          message: error.message
        }), {
          status: 500,
          headers: { 'Content-Type': 'application/json' }
        });
      }
    }

    // ========================================================================
    // Book Search Endpoints
    // ========================================================================

    // GET /search/title - Search books by title with caching (6h TTL)
    if (url.pathname === '/search/title') {
      const query = url.searchParams.get('q');
      if (!query) {
        return new Response(JSON.stringify({ error: 'Missing query parameter "q"' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        });
      }

      const maxResults = parseInt(url.searchParams.get('maxResults') || '20');
      const result = await bookSearch.searchByTitle(query, { maxResults }, env, ctx);

      return new Response(JSON.stringify(result), {
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        }
      });
    }

    // GET /search/isbn - Search books by ISBN with caching (7 day TTL)
    if (url.pathname === '/search/isbn') {
      const isbn = url.searchParams.get('isbn');
      if (!isbn) {
        return new Response(JSON.stringify({ error: 'Missing ISBN parameter' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        });
      }

      const maxResults = parseInt(url.searchParams.get('maxResults') || '1');
      const result = await bookSearch.searchByISBN(isbn, { maxResults }, env, ctx);

      return new Response(JSON.stringify(result), {
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        }
      });
    }

    // POST /search/advanced - Advanced multi-field search
    if (url.pathname === '/search/advanced' && request.method === 'POST') {
      try {
        const searchParams = await request.json();
        const { bookTitle, authorName } = searchParams;

        if (!bookTitle && !authorName) {
          return new Response(JSON.stringify({
            error: 'At least one search parameter required (bookTitle or authorName)'
          }), {
            status: 400,
            headers: { 'Content-Type': 'application/json' }
          });
        }

        const maxResults = searchParams.maxResults || 20;
        const result = await handleAdvancedSearch(
          { bookTitle, authorName },
          { maxResults },
          env
        );

        return new Response(JSON.stringify(result), {
          headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
          }
        });

      } catch (error) {
        console.error('Advanced search failed:', error);
        return new Response(JSON.stringify({
          error: 'Advanced search failed',
          message: error.message
        }), {
          status: 500,
          headers: { 'Content-Type': 'application/json' }
        });
      }
    }

    // ========================================================================
    // External API Routes (backward compatibility - temporary during migration)
    // ========================================================================

    // Google Books search
    if (url.pathname === '/external/google-books') {
      const query = url.searchParams.get('q');
      if (!query) {
        return new Response(JSON.stringify({ error: 'Missing query parameter' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        });
      }

      const maxResults = parseInt(url.searchParams.get('maxResults') || '20');
      const result = await externalApis.searchGoogleBooks(query, { maxResults }, env);

      return new Response(JSON.stringify(result), {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Google Books ISBN search
    if (url.pathname === '/external/google-books-isbn') {
      const isbn = url.searchParams.get('isbn');
      if (!isbn) {
        return new Response(JSON.stringify({ error: 'Missing isbn parameter' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        });
      }

      const result = await externalApis.searchGoogleBooksByISBN(isbn, env);

      return new Response(JSON.stringify(result), {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // OpenLibrary search
    if (url.pathname === '/external/openlibrary') {
      const query = url.searchParams.get('q');
      if (!query) {
        return new Response(JSON.stringify({ error: 'Missing query parameter' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        });
      }

      const maxResults = parseInt(url.searchParams.get('maxResults') || '20');
      const result = await externalApis.searchOpenLibrary(query, { maxResults }, env);

      return new Response(JSON.stringify(result), {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // OpenLibrary author works
    if (url.pathname === '/external/openlibrary-author') {
      const author = url.searchParams.get('author');
      if (!author) {
        return new Response(JSON.stringify({ error: 'Missing author parameter' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        });
      }

      const result = await externalApis.getOpenLibraryAuthorWorks(author, env);

      return new Response(JSON.stringify(result), {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // ISBNdb search
    if (url.pathname === '/external/isbndb') {
      const title = url.searchParams.get('title');
      if (!title) {
        return new Response(JSON.stringify({ error: 'Missing title parameter' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        });
      }

      const author = url.searchParams.get('author') || '';
      const result = await externalApis.searchISBNdb(title, author, env);

      return new Response(JSON.stringify(result), {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // ISBNdb editions for work
    if (url.pathname === '/external/isbndb-editions') {
      const title = url.searchParams.get('title');
      const author = url.searchParams.get('author');

      if (!title || !author) {
        return new Response(JSON.stringify({ error: 'Missing title or author parameter' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        });
      }

      const result = await externalApis.getISBNdbEditionsForWork(title, author, env);

      return new Response(JSON.stringify(result), {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // ISBNdb book by ISBN
    if (url.pathname === '/external/isbndb-isbn') {
      const isbn = url.searchParams.get('isbn');
      if (!isbn) {
        return new Response(JSON.stringify({ error: 'Missing isbn parameter' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        });
      }

      const result = await externalApis.getISBNdbBookByISBN(isbn, env);

      return new Response(JSON.stringify(result), {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // ========================================================================
    // Test Endpoints for Durable Object Batch State Management
    // ========================================================================

    // POST /test/do/init-batch - Initialize batch job in Durable Object
    if (url.pathname === '/test/do/init-batch' && request.method === 'POST') {
      try {
        const { jobId, totalPhotos, status } = await request.json();
        const doId = env.PROGRESS_WEBSOCKET_DO.idFromName(jobId);
        const doStub = env.PROGRESS_WEBSOCKET_DO.get(doId);

        const result = await doStub.initBatch({ jobId, totalPhotos, status });

        return new Response(JSON.stringify(result), {
          status: 200,
          headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
        });
      } catch (error) {
        console.error('Test init-batch failed:', error);
        return new Response(JSON.stringify({ error: error.message }), {
          status: 500,
          headers: { 'Content-Type': 'application/json' }
        });
      }
    }

    // GET /test/do/get-state - Get batch state from Durable Object
    if (url.pathname === '/test/do/get-state' && request.method === 'GET') {
      try {
        const jobId = url.searchParams.get('jobId');
        if (!jobId) {
          return new Response(JSON.stringify({ error: 'Missing jobId parameter' }), {
            status: 400,
            headers: { 'Content-Type': 'application/json' }
          });
        }

        const doId = env.PROGRESS_WEBSOCKET_DO.idFromName(jobId);
        const doStub = env.PROGRESS_WEBSOCKET_DO.get(doId);

        const state = await doStub.getState();

        if (!state || Object.keys(state).length === 0) {
          return new Response(JSON.stringify({ error: 'Job not found' }), {
            status: 404,
            headers: { 'Content-Type': 'application/json' }
          });
        }

        return new Response(JSON.stringify(state), {
          status: 200,
          headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
        });
      } catch (error) {
        console.error('Test get-state failed:', error);
        return new Response(JSON.stringify({ error: error.message }), {
          status: 500,
          headers: { 'Content-Type': 'application/json' }
        });
      }
    }

    // POST /test/do/update-photo - Update photo status in Durable Object
    if (url.pathname === '/test/do/update-photo' && request.method === 'POST') {
      try {
        const { jobId, photoIndex, status, booksFound, error: photoError } = await request.json();
        const doId = env.PROGRESS_WEBSOCKET_DO.idFromName(jobId);
        const doStub = env.PROGRESS_WEBSOCKET_DO.get(doId);

        const result = await doStub.updatePhoto({ photoIndex, status, booksFound, error: photoError });

        return new Response(JSON.stringify(result), {
          status: result.error ? 404 : 200,
          headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
        });
      } catch (error) {
        console.error('Test update-photo failed:', error);
        return new Response(JSON.stringify({ error: error.message }), {
          status: 500,
          headers: { 'Content-Type': 'application/json' }
        });
      }
    }

    // POST /test/do/complete-batch - Complete batch in Durable Object
    if (url.pathname === '/test/do/complete-batch' && request.method === 'POST') {
      try {
        const { jobId, status, totalBooks, photoResults, books } = await request.json();
        const doId = env.PROGRESS_WEBSOCKET_DO.idFromName(jobId);
        const doStub = env.PROGRESS_WEBSOCKET_DO.get(doId);

        const result = await doStub.completeBatch({ status, totalBooks, photoResults, books });

        return new Response(JSON.stringify(result), {
          status: 200,
          headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
        });
      } catch (error) {
        console.error('Test complete-batch failed:', error);
        return new Response(JSON.stringify({ error: error.message }), {
          status: 500,
          headers: { 'Content-Type': 'application/json' }
        });
      }
    }

    // GET /test/do/is-canceled - Check if batch is canceled
    if (url.pathname === '/test/do/is-canceled' && request.method === 'GET') {
      try {
        const jobId = url.searchParams.get('jobId');
        if (!jobId) {
          return new Response(JSON.stringify({ error: 'Missing jobId parameter' }), {
            status: 400,
            headers: { 'Content-Type': 'application/json' }
          });
        }

        const doId = env.PROGRESS_WEBSOCKET_DO.idFromName(jobId);
        const doStub = env.PROGRESS_WEBSOCKET_DO.get(doId);

        const result = await doStub.isBatchCanceled();

        return new Response(JSON.stringify(result), {
          status: 200,
          headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
        });
      } catch (error) {
        console.error('Test is-canceled failed:', error);
        return new Response(JSON.stringify({ error: error.message }), {
          status: 500,
          headers: { 'Content-Type': 'application/json' }
        });
      }
    }

    // POST /test/do/cancel-batch - Cancel batch in Durable Object
    if (url.pathname === '/test/do/cancel-batch' && request.method === 'POST') {
      try {
        const { jobId } = await request.json();
        const doId = env.PROGRESS_WEBSOCKET_DO.idFromName(jobId);
        const doStub = env.PROGRESS_WEBSOCKET_DO.get(doId);

        const result = await doStub.cancelBatch();

        return new Response(JSON.stringify(result), {
          status: 200,
          headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
        });
      } catch (error) {
        console.error('Test cancel-batch failed:', error);
        return new Response(JSON.stringify({ error: error.message }), {
          status: 500,
          headers: { 'Content-Type': 'application/json' }
        });
      }
    }

    // Health check endpoint
    if (url.pathname === '/health') {
      return new Response(JSON.stringify({
        status: 'ok',
        worker: 'api-worker',
        version: '1.0.0',
        endpoints: [
          'GET /search/title?q={query}&maxResults={n} - Title search with caching (6h TTL)',
          'GET /search/isbn?isbn={isbn}&maxResults={n} - ISBN search with caching (7 day TTL)',
          'POST /search/advanced - Advanced search (body: {bookTitle, authorName, maxResults})',
          'POST /api/enrichment/start - Start batch enrichment job',
          'POST /api/enrichment/cancel - Cancel in-flight enrichment job (body: {jobId})',
          'POST /api/scan-bookshelf?jobId={id} - AI bookshelf scanner (upload image with Content-Type: image/*)',
          'POST /api/scan-bookshelf/batch - Batch AI scanner (body: {jobId, images: [{index, data}]})',
          'GET /ws/progress?jobId={id} - WebSocket progress updates',
          '/external/google-books?q={query}&maxResults={n}',
          '/external/google-books-isbn?isbn={isbn}',
          '/external/openlibrary?q={query}&maxResults={n}',
          '/external/openlibrary-author?author={name}',
          '/external/isbndb?title={title}&author={author}',
          '/external/isbndb-editions?title={title}&author={author}',
          '/external/isbndb-isbn?isbn={isbn}'
        ]
      }), {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Default 404
    return new Response(JSON.stringify({
      error: 'Not Found',
      message: 'The requested endpoint does not exist. Use /health to see available endpoints.'
    }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};
