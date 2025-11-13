import { ProgressWebSocketDO } from './durable-objects/progress-socket.js';
import * as externalApis from './services/external-apis.js';
import * as enrichment from './services/enrichment.ts';
import * as aiScanner from './services/ai-scanner.js';
import * as bookSearch from './handlers/book-search.js';
import * as authorSearch from './handlers/author-search.js';
import { handleAdvancedSearch } from './handlers/search-handlers.js';
import { handleBatchScan } from './handlers/batch-scan-handler.ts';
import { handleCSVImport } from './handlers/csv-import.ts';
import { handleBatchEnrichment } from './handlers/batch-enrichment.ts';
import { processAuthorBatch } from './consumers/author-warming-consumer.js';
import { handleScheduledArchival } from './handlers/scheduled-archival.js';
import { handleScheduledAlerts } from './handlers/scheduled-alerts.js';
import { handleScheduledHarvest } from './handlers/scheduled-harvest.js';
import { handleCacheMetrics } from './handlers/cache-metrics.js';
import { handleTestMultiEdition } from './handlers/test-multi-edition.js';
import { handleHarvestDashboard } from './handlers/harvest-dashboard.js';
import { handleMetricsRequest } from './handlers/metrics-handler.js';
import { handleSearchTitle } from './handlers/v1/search-title.js';
import { handleSearchISBN } from './handlers/v1/search-isbn.js';
import { handleSearchAdvanced } from './handlers/v1/search-advanced.js';
import { adaptToUnifiedEnvelope } from './utils/envelope-helpers.ts';
import { handleImageProxy } from './handlers/image-proxy.js';
import { checkRateLimit } from './middleware/rate-limiter.js';
import { validateRequestSize, validateResourceSize } from './middleware/size-validator.js';
import { getCorsHeaders } from './middleware/cors.js';

// Export the Durable Object class for Cloudflare Workers runtime
export { ProgressWebSocketDO };

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // Feature flag for unified response envelope (Issue #399)
    // Computed once per request at fetch scope for reuse across all v1 handlers
    const useUnifiedEnvelope = env.ENABLE_UNIFIED_ENVELOPE === 'true';

    // Custom domain routing: harvest.oooefam.net root → Dashboard
    if (url.hostname === 'harvest.oooefam.net' && url.pathname === '/') {
      return await handleHarvestDashboard(request, env);
    }

    // Handle OPTIONS preflight requests (CORS)
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: getCorsHeaders(request)
      });
    }

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

    // POST /api/token/refresh - Refresh authentication token for long-running jobs
    if (url.pathname === '/api/token/refresh' && request.method === 'POST') {
      // Rate limiting: Prevent abuse of token refresh endpoint
      const rateLimitResponse = await checkRateLimit(request, env);
      if (rateLimitResponse) return rateLimitResponse;

      try {
        const { jobId, oldToken } = await request.json();

        if (!jobId || !oldToken) {
          return new Response(JSON.stringify({
            error: 'Invalid request: jobId and oldToken required'
          }), {
            status: 400,
            headers: {
              ...getCorsHeaders(request),
              'Content-Type': 'application/json'
            }
          });
        }

        // Get DO stub for this job
        const doId = env.PROGRESS_WEBSOCKET_DO.idFromName(jobId);
        const doStub = env.PROGRESS_WEBSOCKET_DO.get(doId);

        // Refresh token via Durable Object
        const result = await doStub.refreshAuthToken(oldToken);

        if (result.error) {
          return new Response(JSON.stringify({
            error: result.error
          }), {
            status: 401,
            headers: {
              ...getCorsHeaders(request),
              'Content-Type': 'application/json'
            }
          });
        }

        // Return new token
        return new Response(JSON.stringify({
          jobId,
          token: result.token,
          expiresIn: result.expiresIn
        }), {
          status: 200,
          headers: {
            ...getCorsHeaders(request),
            'Content-Type': 'application/json'
          }
        });

      } catch (error) {
        console.error('Failed to refresh token:', error);
        return new Response(JSON.stringify({
          error: 'Failed to refresh token',
          message: error.message
        }), {
          status: 500,
          headers: {
            ...getCorsHeaders(request),
            'Content-Type': 'application/json'
          }
        });
      }
    }

    // GET /api/job-state/:jobId - Get current job state for reconnection sync
    if (url.pathname.startsWith('/api/job-state/') && request.method === 'GET') {
      try {
        const jobId = url.pathname.split('/').pop();

        if (!jobId) {
          return new Response(JSON.stringify({
            error: 'Invalid request: jobId required'
          }), {
            status: 400,
            headers: {
              ...getCorsHeaders(request),
              'Content-Type': 'application/json'
            }
          });
        }

        // Validate Bearer token (REQUIRED for auth)
        const authHeader = request.headers.get('Authorization');
        const providedToken = authHeader?.replace('Bearer ', '');
        if (!providedToken) {
          return new Response(JSON.stringify({ error: 'Missing authorization token' }), {
            status: 401,
            headers: { ...getCorsHeaders(request), 'Content-Type': 'application/json' }
          });
        }

        // Get DO stub for this job
        const doId = env.PROGRESS_WEBSOCKET_DO.idFromName(jobId);
        const doStub = env.PROGRESS_WEBSOCKET_DO.get(doId);

        // Fetch job state and auth details (includes validation)
        const result = await doStub.getJobStateAndAuth();

        if (!result) {
          return new Response(JSON.stringify({
            error: 'Job not found or state not initialized'
          }), {
            status: 404,
            headers: {
              ...getCorsHeaders(request),
              'Content-Type': 'application/json'
            }
          });
        }

        const { jobState, authToken, authTokenExpiration } = result;

        // Validate token
        if (!authToken || providedToken !== authToken || Date.now() > authTokenExpiration) {
          return new Response(JSON.stringify({ error: 'Invalid or expired token' }), {
            status: 401,
            headers: { ...getCorsHeaders(request), 'Content-Type': 'application/json' }
          });
        }

        // Return job state
        return new Response(JSON.stringify(jobState), {
          status: 200,
          headers: {
            ...getCorsHeaders(request),
            'Content-Type': 'application/json'
          }
        });

      } catch (error) {
        console.error('Failed to get job state:', error);
        return new Response(JSON.stringify({
          error: 'Failed to get job state',
          message: error.message
        }), {
          status: 500,
          headers: {
            ...getCorsHeaders(request),
            'Content-Type': 'application/json'
          }
        });
      }
    }

    // ========================================================================
    // Enrichment API Endpoint
    // ========================================================================

    // POST /api/enrichment/start - DEPRECATED: Redirect to /api/enrichment/batch
    // This endpoint used old workIds format. iOS should migrate to /api/enrichment/batch with books array.
    // For backward compatibility, we convert workIds to books format (assuming workId = title for now)
    if (url.pathname === '/api/enrichment/start' && request.method === 'POST') {
      console.warn('[DEPRECATED] /api/enrichment/start called. iOS should migrate to /api/enrichment/batch');

      // Rate limiting: Prevent denial-of-wallet attacks
      const rateLimitResponse = await checkRateLimit(request, env);
      if (rateLimitResponse) return rateLimitResponse;

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

        // Convert workIds to books format (workId is treated as title for backward compat)
        // TODO: iOS should send actual book data via /api/enrichment/batch instead
        const books = workIds.map(id => ({ title: String(id) }));

        // Redirect to new batch enrichment handler
        const modifiedRequest = new Request(request, {
          body: JSON.stringify({ books, jobId })
        });

        return handleBatchEnrichment(modifiedRequest, env, ctx);

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
            ...getCorsHeaders(request),
            'Content-Type': 'application/json'
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
      // Rate limiting: Prevent denial-of-wallet attacks on AI batch endpoint
      const rateLimitResponse = await checkRateLimit(request, env);
      if (rateLimitResponse) return rateLimitResponse;

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
            ...getCorsHeaders(request),
            'Content-Type': 'application/json'
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

    // ========================================================================
    // CSV Import Endpoint
    // ========================================================================

    // POST /api/import/csv-gemini - Gemini-powered CSV import with WebSocket progress
    if (url.pathname === '/api/import/csv-gemini' && request.method === 'POST') {
      // Rate limiting: Prevent denial-of-wallet attacks on AI CSV import
      const rateLimitResponse = await checkRateLimit(request, env);
      if (rateLimitResponse) return rateLimitResponse;

      // Size validation: Prevent memory crashes (10MB limit)
      const sizeCheck = validateResourceSize(request, 10, 'CSV file');
      if (sizeCheck) return sizeCheck;

      return handleCSVImport(request, env, ctx);
    }

    // POST /api/warming/upload - Cache warming via CSV upload
    if (url.pathname === '/api/warming/upload' && request.method === 'POST') {
      const { handleWarmingUpload } = await import('./handlers/warming-upload.js');
      return handleWarmingUpload(request, env, ctx);
    }

    // GET /api/warming/dlq - Monitor dead letter queue
    if (url.pathname === '/api/warming/dlq' && request.method === 'GET') {
      const { handleDLQMonitor } = await import('./handlers/dlq-monitor.js');
      return handleDLQMonitor(request, env);
    }

    // Batch enrichment endpoint (POST /api/enrichment/batch)
    if (url.pathname === '/api/enrichment/batch' && request.method === 'POST') {
      // Rate limiting: Prevent denial-of-wallet attacks
      const rateLimitResponse = await checkRateLimit(request, env);
      if (rateLimitResponse) return rateLimitResponse;

      return handleBatchEnrichment(request, env, ctx);
    }

    // POST /api/scan-bookshelf - AI bookshelf scanner with WebSocket progress
    if (url.pathname === '/api/scan-bookshelf' && request.method === 'POST') {
      // Rate limiting: Prevent denial-of-wallet attacks on AI endpoint
      const rateLimitResponse = await checkRateLimit(request, env);
      if (rateLimitResponse) return rateLimitResponse;

      // Size validation: Prevent memory crashes (5MB limit per photo)
      const sizeCheck = validateResourceSize(request, 5, 'image');
      if (sizeCheck) return sizeCheck;

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

        // Get DO stub for this job
        const doId = env.PROGRESS_WEBSOCKET_DO.idFromName(jobId);
        const doStub = env.PROGRESS_WEBSOCKET_DO.get(doId);

        // SECURITY: Generate authentication token for WebSocket connection
        const authToken = crypto.randomUUID();
        await doStub.setAuthToken(authToken);

        console.log(`[API] Auth token generated for scan job ${jobId}`);

        // CRITICAL: Wait for WebSocket ready signal before processing
        // This prevents race condition where we send updates before client connects
        console.log(`[API] Waiting for WebSocket ready signal for job ${jobId}`);

        const readyResult = await doStub.waitForReady(5000); // 5 second timeout

        if (readyResult.timedOut || readyResult.disconnected) {
          const reason = readyResult.timedOut ? 'timeout' : 'WebSocket not connected';
          console.warn(`[API] WebSocket ready ${reason} for job ${jobId}, proceeding anyway (client may miss early updates)`);

          // NEW: Log analytics event
          console.log(`[Analytics] websocket_ready_timeout - job_id: ${jobId}, reason: ${reason}, client_ip: ${request.headers.get('CF-Connecting-IP')}`);

          // Continue processing - client might be using polling fallback
        } else {
          console.log(`[API] ✅ WebSocket ready for job ${jobId}, starting processing`);
        }

        // Start AI scan in background (NOW guaranteed WebSocket is listening)
        ctx.waitUntil(aiScanner.processBookshelfScan(jobId, imageData, request, env, doStub, ctx));

        // Define stages metadata for iOS client (used for progress estimation)
        const stages = [
          { name: "Image Quality Analysis", typicalDuration: 3, progress: 0.1 },
          { name: "AI Processing", typicalDuration: 25, progress: 0.5 },
          { name: "Metadata Enrichment", typicalDuration: 12, progress: 1.0 }
        ];

        // Calculate estimated range based on total stage durations
        const totalDuration = stages.reduce((sum, stage) => sum + stage.typicalDuration, 0);
        const estimatedRange = [Math.floor(totalDuration * 0.8), Math.ceil(totalDuration * 1.2)];

        // Return 202 Accepted immediately with stages metadata and auth token
        return new Response(JSON.stringify({
          jobId,
          token: authToken, // NEW: Token for WebSocket authentication
          status: 'started',
          websocketReady: readyResult.success, // NEW: Indicates if WebSocket is ready
          message: 'AI scan started. Connect to /ws/progress?jobId=' + jobId + ' for real-time updates.',
          stages,
          estimatedRange
        }), {
          status: 202,
          headers: {
            ...getCorsHeaders(request),
            'Content-Type': 'application/json'
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
    // Cache Metrics Endpoint (Phase 3)
    // ========================================================================

    // GET /api/cache/metrics - Cache performance metrics
    if (url.pathname === '/api/cache/metrics' && request.method === 'GET') {
      return handleCacheMetrics(request, env);
    }

    // GET /metrics - Aggregated metrics with Analytics Engine (Phase 4)
    if (url.pathname === '/metrics' && request.method === 'GET') {
      return handleMetricsRequest(request, env, ctx);
    }

    // ========================================================================
    // Book Search Endpoints - V1 (Canonical Contracts)
    // ========================================================================

    // GET /v1/search/title - Search books by title (canonical response)
    if (url.pathname === '/v1/search/title' && request.method === 'GET') {
      const query = url.searchParams.get('q');
      const response = await handleSearchTitle(query, env);
      return adaptToUnifiedEnvelope(response, useUnifiedEnvelope);
    }

    // GET /v1/search/isbn - Search books by ISBN (canonical response)
    if (url.pathname === '/v1/search/isbn' && request.method === 'GET') {
      const isbn = url.searchParams.get('isbn');
      const response = await handleSearchISBN(isbn, env);
      return adaptToUnifiedEnvelope(response, useUnifiedEnvelope);
    }

    // GET /v1/search/advanced - Advanced search by title and/or author (canonical response)
    if (url.pathname === '/v1/search/advanced' && request.method === 'GET') {
      const title = url.searchParams.get('title') || '';
      const author = url.searchParams.get('author') || '';
      const response = await handleSearchAdvanced(title, author, env, ctx);
      return adaptToUnifiedEnvelope(response, useUnifiedEnvelope);
    }

    // ========================================================================
    // Image Proxy Endpoint
    // ========================================================================

    // GET /images/proxy - Proxy and cache book cover images via R2
    if (url.pathname === '/images/proxy' && request.method === 'GET') {
      return handleImageProxy(request, env);
    }

    // ========================================================================
    // Book Search Endpoints - Legacy
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

      // Extract cache headers from result
      const cacheHeaders = result._cacheHeaders || {};
      delete result._cacheHeaders; // Don't expose internal field to client

      return new Response(JSON.stringify(result), {
        headers: {
          ...getCorsHeaders(request),
          'Content-Type': 'application/json',
          ...cacheHeaders
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

      // Extract cache headers from result
      const cacheHeaders = result._cacheHeaders || {};
      delete result._cacheHeaders; // Don't expose internal field to client

      return new Response(JSON.stringify(result), {
        headers: {
          ...getCorsHeaders(request),
          'Content-Type': 'application/json',
          ...cacheHeaders
        }
      });
    }

    // GET /search/author - Search books by author with pagination (6h cache)
    if (url.pathname === '/search/author') {
      const authorName = url.searchParams.get('q');
      if (!authorName) {
        return new Response(JSON.stringify({ error: 'Missing query parameter "q"' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        });
      }

      // Support both 'limit' (new) and 'maxResults' (iOS compatibility)
      const limitParam = url.searchParams.get('limit') || url.searchParams.get('maxResults') || '50';
      const limit = parseInt(limitParam);
      const offset = parseInt(url.searchParams.get('offset') || '0');
      const sortBy = url.searchParams.get('sortBy') || 'publicationYear';

      // Validate parameters
      if (limit < 1 || limit > 100) {
        return new Response(JSON.stringify({
          error: 'Invalid limit parameter',
          message: 'Limit must be between 1 and 100'
        }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        });
      }

      if (offset < 0) {
        return new Response(JSON.stringify({
          error: 'Invalid offset parameter',
          message: 'Offset must be >= 0'
        }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        });
      }

      const validSortOptions = ['publicationYear', 'publicationYearAsc', 'title', 'popularity'];
      if (!validSortOptions.includes(sortBy)) {
        return new Response(JSON.stringify({
          error: 'Invalid sortBy parameter',
          message: `sortBy must be one of: ${validSortOptions.join(', ')}`
        }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        });
      }

      const result = await authorSearch.searchByAuthor(
        authorName,
        { limit, offset, sortBy },
        env,
        ctx
      );

      // Extract cache status for headers
      const cacheStatus = result.cached ? 'HIT' : 'MISS';
      const cacheSource = result.cacheSource || 'NONE';

      return new Response(JSON.stringify(result), {
        headers: {
          ...getCorsHeaders(request),
          'Content-Type': 'application/json',
          'Cache-Control': 'public, max-age=21600', // 6h cache
          'X-Cache': cacheStatus,
          'X-Cache-Source': cacheSource,
          'X-Provider': result.provider || 'openlibrary'
        }
      });
    }

    // GET/POST /search/advanced - Advanced multi-field search
    // GET is primary (aligns with /search/title, /search/isbn, enables HTTP caching)
    // POST supported for backward compatibility
    if (url.pathname === '/search/advanced') {
      try {
        let bookTitle, authorName, maxResults;

        if (request.method === 'GET') {
          // Query parameters (iOS enrichment, documentation examples, REST standard)
          // Support both "title" and "bookTitle" for flexibility
          bookTitle = url.searchParams.get('title') || url.searchParams.get('bookTitle');
          authorName = url.searchParams.get('author') || url.searchParams.get('authorName');
          maxResults = parseInt(url.searchParams.get('maxResults') || '20', 10);

        } else if (request.method === 'POST') {
          // JSON body (legacy support for existing clients)
          const searchParams = await request.json();
          // Support both naming conventions: "title"/"bookTitle", "author"/"authorName"
          bookTitle = searchParams.title || searchParams.bookTitle;
          authorName = searchParams.author || searchParams.authorName;
          maxResults = searchParams.maxResults || 20;

        } else {
          // Only GET and POST allowed
          return new Response(JSON.stringify({
            error: 'Method not allowed',
            message: 'Use GET with query parameters or POST with JSON body'
          }), {
            status: 405,
            headers: {
              'Content-Type': 'application/json',
              'Allow': 'GET, POST'
            }
          });
        }

        // Validate that at least one search parameter is provided
        if (!bookTitle && !authorName) {
          return new Response(JSON.stringify({
            error: 'At least one search parameter required (title or author)'
          }), {
            status: 400,
            headers: { 'Content-Type': 'application/json' }
          });
        }

        // Call handler (works with both GET and POST)
        const result = await handleAdvancedSearch(
          { bookTitle, authorName },
          { maxResults },
          env
        );

        return new Response(JSON.stringify(result), {
          headers: {
            ...getCorsHeaders(request),
            'Content-Type': 'application/json',
            // Add cache header for GET requests (like /search/title)
            ...(request.method === 'GET' && { 'Cache-Control': 'public, max-age=21600' }) // 6h cache
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
          headers: { ...getCorsHeaders(request), 'Content-Type': 'application/json' }
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
          headers: { ...getCorsHeaders(request), 'Content-Type': 'application/json' }
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
          headers: { ...getCorsHeaders(request), 'Content-Type': 'application/json' }
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
          headers: { ...getCorsHeaders(request), 'Content-Type': 'application/json' }
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
          headers: { ...getCorsHeaders(request), 'Content-Type': 'application/json' }
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
          headers: { ...getCorsHeaders(request), 'Content-Type': 'application/json' }
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
          'GET /search/author?q={author}&limit={n}&offset={n}&sortBy={sort} - Author bibliography (6h TTL)',
          'GET /search/advanced?title={title}&author={author} - Advanced search (primary method, 6h cache)',
          'POST /search/advanced - Advanced search (legacy support, JSON body)',
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

    // Harvest Dashboard (public, no auth required)
    if (url.pathname === '/admin/harvest-dashboard' && request.method === 'GET') {
      return await handleHarvestDashboard(request, env);
    }

    // Test multi-edition discovery (no auth required)
    if (url.pathname === '/api/test-multi-edition' && request.method === 'GET') {
      return await handleTestMultiEdition(request, env);
    }

    // Manual ISBNdb harvest trigger (for testing, requires secret header)
    if (url.pathname === '/api/harvest-covers' && request.method === 'POST') {
      // Security: Require secret header to prevent unauthorized harvests
      const authHeader = request.headers.get('X-Harvest-Secret');
      if (authHeader !== env.HARVEST_SECRET && authHeader !== 'test-local-dev') {
        return new Response(JSON.stringify({
          error: 'Unauthorized',
          message: 'Invalid or missing X-Harvest-Secret header'
        }), {
          status: 401,
          headers: { 'Content-Type': 'application/json' }
        });
      }

      console.log('🌾 Manual ISBNdb harvest triggered');
      const result = await handleScheduledHarvest(env);

      return new Response(JSON.stringify({
        success: result.success,
        stats: result.stats,
        message: result.success ? 'Harvest completed successfully' : 'Harvest failed',
        error: result.error
      }), {
        status: result.success ? 200 : 500,
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
  },

  async queue(batch, env, ctx) {
    // Route queue messages to appropriate consumer
    if (batch.queue === 'author-warming-queue') {
      await processAuthorBatch(batch, env, ctx);
    } else {
      console.error(`Unknown queue: ${batch.queue}`);
    }
  },

  async scheduled(event, env, ctx) {
    // Route by cron pattern
    if (event.cron === '0 2 * * *') {
      // Daily archival at 2:00 AM UTC
      await handleScheduledArchival(env, ctx);
    } else if (event.cron === '*/15 * * * *') {
      // Alert checks every 15 minutes
      await handleScheduledAlerts(env, ctx);
    } else if (event.cron === '0 3 * * *') {
      // Daily ISBNdb cover harvest at 3:00 AM UTC
      await handleScheduledHarvest(env);
    }
  }
};
