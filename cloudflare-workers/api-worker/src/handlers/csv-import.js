// src/handlers/csv-import.js
import { validateCSV } from '../utils/csv-validator.js';
import { buildCSVParserPrompt, PROMPT_VERSION } from '../prompts/csv-parser-prompt.js';
import { generateCSVCacheKey } from '../utils/cache-keys.js';
import { parseCSVWithGemini } from '../providers/gemini-csv-provider.js';
import { createSuccessResponse, createErrorResponse } from '../utils/api-responses.js';

const MAX_FILE_SIZE = 10 * 1024 * 1024; // 10MB

/**
 * Handle CSV import request (POST /api/import/csv-gemini)
 *
 * @param {Request} request - Incoming request with FormData containing CSV file
 * @param {Object} env - Worker environment bindings
 * @returns {Promise<Response>} Response with jobId
 */
export async function handleCSVImport(request, env) {
  try {
    const formData = await request.formData();
    const csvFile = formData.get('file');

    if (!csvFile) {
      return createErrorResponse('No file provided', 400, 'E_MISSING_FILE');
    }

    // Check file size
    if (csvFile.size > MAX_FILE_SIZE) {
      return createErrorResponse(
        'CSV file too large (max 10MB)',
        413,
        'E_FILE_TOO_LARGE',
        { suggestion: 'Try splitting your CSV into smaller files or removing unnecessary columns' }
      );
    }

    // Generate jobId
    const jobId = crypto.randomUUID();

    // Get WebSocket DO stub
    const doId = env.PROGRESS_WEBSOCKET_DO.idFromName(jobId);
    const doStub = env.PROGRESS_WEBSOCKET_DO.get(doId);

    // Start background processing
    env.ctx.waitUntil(processCSVImport(csvFile, jobId, doStub, env));

    return createSuccessResponse({ jobId }, {}, 202);

  } catch (error) {
    return createErrorResponse(error.message, 500, 'E_INTERNAL');
  }
}

/**
 * Background processor for CSV import (two-stage: parse → validate)
 *
 * Stage 1 (5-50%): Gemini parses CSV into structured book data
 * Stage 2 (50-100%): Validate parsed books (title and author required)
 *
 * Note: Enrichment now happens on iOS via EnrichmentQueue
 *
 * @param {File} csvFile - CSV file from FormData
 * @param {string} jobId - Unique job identifier
 * @param {Object} doStub - ProgressWebSocketDO stub
 * @param {Object} env - Worker environment bindings
 */
export async function processCSVImport(csvFile, jobId, doStub, env) {
  try {
    // Read CSV content
    const csvText = await csvFile.text();

    // CRITICAL: Wait for WebSocket ready signal before processing
    // This prevents race condition where we send updates before client connects
    console.log(`[CSV Import] Waiting for WebSocket ready signal for job ${jobId}`);

    const readyResult = await doStub.waitForReady(5000); // 5 second timeout

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
    let parsedBooks = await env.CACHE_KV.get(cacheKey, 'json');

    if (!parsedBooks) {
      // Keep-alive interval
      const keepAliveInterval = setInterval(async () => {
        await doStub.updateProgress(0.25, 'Gemini is parsing your file...', true);
      }, 5000);

      try {
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
        await env.CACHE_KV.put(cacheKey, JSON.stringify(parsedBooks), {
          expirationTtl: 604800
        });

      } finally {
        clearInterval(keepAliveInterval);
      }
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
  const apiKey = env.GEMINI_API_KEY;
  if (!apiKey) {
    throw new Error('GEMINI_API_KEY not configured');
  }

  return await parseCSVWithGemini(csvText, prompt, apiKey);
}

