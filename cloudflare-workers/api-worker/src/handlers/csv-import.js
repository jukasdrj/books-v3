// src/handlers/csv-import.js
import { validateCSV } from '../utils/csv-validator.js';
import { buildCSVParserPrompt, PROMPT_VERSION } from '../prompts/csv-parser-prompt.js';
import { generateCSVCacheKey } from '../utils/cache-keys.js';
import { parseCSVWithGemini } from '../providers/gemini-csv-provider.js';
import { createSuccessResponseObject, createErrorResponseObject } from '../types/responses.js';

const MAX_FILE_SIZE = 10 * 1024 * 1024; // 10MB

/**
 * Handle CSV import request (POST /api/import/csv-gemini)
 *
 * Uses Durable Object alarm to avoid ctx.waitUntil() timeout (Issue #249)
 * Long-running Gemini API calls (20-60s) exceed Workers inactivity limits
 *
 * @param {Request} request - Incoming request with FormData containing CSV file
 * @param {Object} env - Worker environment bindings
 * @param {ExecutionContext} ctx - Execution context (not used for processing)
 * @returns {Promise<Response>} Response with jobId
 */
export async function handleCSVImport(request, env, ctx) {
  try {
    const formData = await request.formData();
    const csvFile = formData.get('file');

    if (!csvFile) {
      return Response.json(
        createErrorResponseObject('No file provided', 'E_MISSING_FILE'),
        { status: 400 }
      );
    }

    // Check file size
    if (csvFile.size > MAX_FILE_SIZE) {
      return Response.json(
        createErrorResponseObject('CSV file too large (max 10MB)', 'E_FILE_TOO_LARGE', {
          suggestion: 'Try splitting your CSV into smaller files or removing unnecessary columns'
        }),
        { status: 413 }
      );
    }

    // Generate jobId
    const jobId = crypto.randomUUID();

    // Get WebSocket DO stub
    const doId = env.PROGRESS_WEBSOCKET_DO.idFromName(jobId);
    const doStub = env.PROGRESS_WEBSOCKET_DO.get(doId);

    // Read CSV content and schedule processing via Durable Object alarm
    // This avoids ctx.waitUntil() timeout for long-running Gemini API calls
    const csvText = await csvFile.text();
    await doStub.scheduleCSVProcessing(csvText, jobId);

    return Response.json(
      createSuccessResponseObject({ jobId }, {}),
      { status: 202 }
    );

  } catch (error) {
    return Response.json(
      createErrorResponseObject(error.message, 'E_INTERNAL'),
      { status: 500 }
    );
  }
}

/**
 * Core CSV import processor (called by Durable Object alarm)
 *
 * Stage 1 (5-50%): Gemini parses CSV into structured book data
 * Stage 2 (50-100%): Validate parsed books (title and author required)
 *
 * Note: Enrichment now happens on iOS via EnrichmentQueue
 *
 * @param {string} csvText - Raw CSV file content
 * @param {string} jobId - Unique job identifier
 * @param {Object} doStub - ProgressWebSocketDO stub (or 'this' from alarm context)
 * @param {Object} env - Worker environment bindings
 */
export async function processCSVImportCore(csvText, jobId, doStub, env) {
  try {

    // Give the client a predictable window to establish the WebSocket connection.
    // This is a temporary workaround for the race condition where ctx.waitUntil()
    // starts background processing immediately, before iOS can receive HTTP 202
    // response and connect WebSocket. 200ms provides reliable buffer for connection.
    await new Promise(resolve => setTimeout(resolve, 200));

    console.log(`[CSV Import] Waiting for WebSocket ready signal for job ${jobId}`);
    const readyResult = await doStub.waitForReady(10000); // 10 second timeout

    if (readyResult.timedOut || readyResult.disconnected) {
      const reason = readyResult.timedOut ? 'timeout' : 'WebSocket not connected';
      console.warn(`[CSV Import] WebSocket ready ${reason} for job ${jobId}, proceeding anyway (client may miss early updates)`);
    } else {
      console.log(`[CSV Import] ✅ WebSocket ready for job ${jobId}, starting processing`);
    }

    // Stage 0: Validation (0-5%)
    await doStub.updateProgress(0.02, 'Validating CSV file...');

    const validation = validateCSV(csvText);
    if (!validation.valid) {
      throw new Error(`Invalid CSV: ${validation.error}`);
    }

    // Stage 1: Gemini Parsing (5-50%)
    await doStub.updateProgress(0.05, 'Uploading CSV to Gemini...');

    const cacheKey = await generateCSVCacheKey(csvText, PROMPT_VERSION);
    let parsedBooks = await env.KV_CACHE.get(cacheKey, 'json');

    if (!parsedBooks) {
      // NOTE: setInterval keep-alive removed - it doesn't prevent waitUntil() timeout
      // because async callbacks don't register as I/O activity in Workers runtime.
      // Gemini 2.0 Flash typically responds in <20 seconds for CSV parsing.
      const prompt = buildCSVParserPrompt();
      parsedBooks = await callGemini(csvText, prompt, env);

      // Validate Gemini response
      if (!Array.isArray(parsedBooks) || parsedBooks.length === 0) {
        throw new Error('Gemini returned invalid format');
      }

      const validBooks = parsedBooks.filter(b => b.title && b.author);
      if (validBooks.length === 0) {
        throw new Error('No valid books found in CSV');
      }

      parsedBooks = validBooks;

      // Cache for 7 days
      await env.KV_CACHE.put(cacheKey, JSON.stringify(parsedBooks), {
        expirationTtl: 604800
      });
    }

    // Stage 2: Validation (50-100%)
    await doStub.updateProgress(0.5, `Parsed ${parsedBooks.length} books. Validating...`);

    // Validate parsed books (title and author required)
    const validBooks = parsedBooks.filter(book => {
      if (!book.title || !book.author) {
        return false;
      }
      return true;
    });

    await doStub.updateProgress(0.75, `Validated ${validBooks.length}/${parsedBooks.length} books`);

    // Complete immediately (no enrichment)
    const invalidCount = parsedBooks.length - validBooks.length;
    const errors = invalidCount > 0
      ? [{ title: 'Validation', error: `${invalidCount} books missing title or author` }]
      : [];

    await doStub.complete({
      books: validBooks,
      errors: errors,
      successRate: `${validBooks.length}/${parsedBooks.length}`
    });

  } catch (error) {
    await doStub.fail({
      error: error.message,
      fallbackAvailable: true,
      suggestion: 'Try manual CSV import instead'
    });
  }
  // NOTE: No finally block! complete() and fail() handle WebSocket cleanup with
  // delayed closeConnection() to ensure final messages are delivered to client.
}

/**
 * Call Gemini API to parse CSV
 *
 * @param {string} csvText - Raw CSV content
 * @param {string} prompt - Gemini prompt with few-shot examples
 * @param {Object} env - Worker environment bindings
 * @returns {Promise<Array<Object>>} Parsed book data
 */
async function callGemini(csvText, prompt, env) {
  /**
   * GEMINI_API_KEY binding supports two patterns:
   *   1. Secrets Store binding (recommended for production): env.GEMINI_API_KEY is a SecretsStore binding and requires .get() to retrieve the value.
   *   2. Plain string binding (for local development/testing): env.GEMINI_API_KEY is a string.
   *
   * This dynamic resolution allows local development with a plaintext key (e.g., via wrangler.toml)
   * while ensuring production uses the more secure Secrets Store.
   *
   * - Use Secrets Store in production for security: `[[secrets]]` in wrangler.toml, or dashboard binding.
   * - Use plain string only for local/dev/testing: `GEMINI_API_KEY = "sk-..."` in wrangler.toml `[vars]`.
   *
   * If neither is configured, an error will be thrown.
   */
  const apiKey = env.GEMINI_API_KEY?.get
    ? await env.GEMINI_API_KEY.get()
    : env.GEMINI_API_KEY;

  if (!apiKey) {
    throw new Error('GEMINI_API_KEY not configured');
  }

  return await parseCSVWithGemini(csvText, prompt, apiKey);
}

