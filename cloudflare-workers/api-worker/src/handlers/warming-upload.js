import { parseCSVWithGemini } from '../providers/gemini-csv-provider.js';
import { buildCSVParserPrompt } from '../prompts/csv-parser-prompt.js';

/**
 * POST /api/warming/upload - Cache warming via CSV upload
 *
 * @param {Request} request - HTTP request with { csv, maxDepth, priority }
 * @param {Object} env - Worker environment bindings
 * @param {ExecutionContext} ctx - Execution context
 * @returns {Response} Job ID and estimates
 */
export async function handleWarmingUpload(request, env, ctx) {
  try {
    const body = await request.json();

    // Validate required fields
    if (!body.csv) {
      return new Response(JSON.stringify({
        error: 'Missing required field: csv (base64-encoded CSV file)'
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Validate maxDepth
    const maxDepth = body.maxDepth || 2;
    if (maxDepth < 1 || maxDepth > 3) {
      return new Response(JSON.stringify({
        error: 'maxDepth must be 1-3'
      }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Decode CSV
    const csvText = atob(body.csv);

    // Parse with Gemini
    const prompt = buildCSVParserPrompt();
    const apiKey = env.GEMINI_API_KEY;

    if (!apiKey) {
      return new Response(JSON.stringify({
        error: 'GEMINI_API_KEY not configured'
      }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const books = await parseCSVWithGemini(csvText, prompt, apiKey);

    // Extract unique authors
    const authorsSet = new Set();
    for (const book of books) {
      if (book.author) {
        authorsSet.add(book.author.trim());
      }
    }

    const uniqueAuthors = Array.from(authorsSet);
    const jobId = crypto.randomUUID();

    // TODO: Queue authors

    return new Response(JSON.stringify({
      jobId,
      authorsQueued: uniqueAuthors.length,
      estimatedWorks: uniqueAuthors.length * 15,
      estimatedDuration: '2-4 hours'
    }), {
      status: 202,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (error) {
    return new Response(JSON.stringify({
      error: 'Failed to process upload',
      message: error.message
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}
