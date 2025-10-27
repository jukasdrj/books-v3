// src/handlers/csv-import.js
import { validateCSV } from '../utils/csv-validator.js';
import { buildCSVParserPrompt, PROMPT_VERSION } from '../prompts/csv-parser-prompt.js';
import { generateCSVCacheKey, generateISBNCacheKey } from '../utils/cache-keys.js';
import { enrichBooksParallel } from '../services/parallel-enrichment.js';

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
      return Response.json({ error: 'No file provided' }, { status: 400 });
    }

    // Check file size
    if (csvFile.size > MAX_FILE_SIZE) {
      return Response.json({
        error: 'CSV file too large (max 10MB)',
        suggestion: 'Split into smaller files or use batch import'
      }, { status: 413 });
    }

    // Generate jobId
    const jobId = crypto.randomUUID();

    // Get WebSocket DO stub
    const doId = env.PROGRESS_WEBSOCKET_DO.idFromName(jobId);
    const doStub = env.PROGRESS_WEBSOCKET_DO.get(doId);

    // Start background processing
    env.ctx.waitUntil(processCSVImport(csvFile, jobId, doStub, env));

    return Response.json({ jobId });

  } catch (error) {
    return Response.json({ error: error.message }, { status: 500 });
  }
}

/**
 * Background processor for CSV import (two-stage: parse → enrich)
 *
 * Stage 1 (5-50%): Gemini parses CSV into structured book data
 * Stage 2 (50-100%): Parallel enrichment with external APIs
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

    await doStub.updateProgress(0.5, `Parsed ${parsedBooks.length} books. Starting enrichment...`);

    // Stage 2: Parallel Enrichment (50-100%)
    const enrichedBooks = await enrichBooksParallel(
      parsedBooks,
      async (book) => {
        // Check ISBN cache first
        if (book.isbn) {
          const cacheKey = generateISBNCacheKey(book.isbn);
          const cachedData = await env.CACHE_KV.get(cacheKey, 'json');
          if (cachedData?.coverUrl) {
            return { ...book, ...cachedData };
          }
        }

        // Enrich via external APIs (placeholder - actual implementation varies)
        return await enrichBook(book, env);
      },
      async (completed, total, title, hasError) => {
        const progress = 0.5 + (completed / total) * 0.5;
        const status = hasError
          ? `Enriching (${completed}/${total}): ${title} [failed]`
          : `Enriching (${completed}/${total}): ${title}`;
        await doStub.updateProgress(progress, status);
      },
      10 // Concurrency limit
    );

    // Complete
    const errors = enrichedBooks.filter(b => b.enrichmentError);
    await doStub.complete({
      books: enrichedBooks,
      errors: errors.map(e => ({ title: e.title, error: e.enrichmentError })),
      successRate: `${enrichedBooks.length - errors.length}/${enrichedBooks.length}`
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
 * Call Gemini API to parse CSV (placeholder - implemented in Task 6)
 *
 * @param {string} csvText - Raw CSV content
 * @param {string} prompt - Gemini prompt with few-shot examples
 * @param {Object} env - Worker environment bindings
 * @returns {Promise<Array<Object>>} Parsed book data
 */
async function callGemini(csvText, prompt, env) {
  // Placeholder - will implement in Task 6 (Gemini Provider Module)
  throw new Error('Gemini integration not implemented');
}

/**
 * Enrich single book with external APIs (placeholder)
 *
 * @param {Object} book - Book data from Gemini (title, author, isbn)
 * @param {Object} env - Worker environment bindings
 * @returns {Promise<Object>} Enriched book with coverUrl, publisher, etc.
 */
async function enrichBook(book, env) {
  // Placeholder - actual implementation would call external-apis service
  // For now, return book as-is (enrichment will be added later)
  return book;
}
