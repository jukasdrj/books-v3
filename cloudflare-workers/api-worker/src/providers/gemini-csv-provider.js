// src/providers/gemini-csv-provider.js

const GEMINI_API_ENDPOINT = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:generateContent';

/**
 * Parse CSV file using Gemini 2.0 Flash API
 *
 * Features:
 * - System instructions for role definition (Gemini best practice)
 * - Low temperature (0.2) for consistent, deterministic parsing
 * - responseMimeType for guaranteed JSON output (no markdown stripping needed)
 * - Validates JSON array output
 * - Supports large CSVs (up to 8K tokens output)
 *
 * @param {string} csvText - Raw CSV content
 * @param {string} prompt - Gemini prompt with few-shot examples
 * @param {string} apiKey - Gemini API key from env.GEMINI_API_KEY
 * @returns {Promise<Array<Object>>} Parsed book data
 * @throws {Error} If API call fails or response is invalid
 */
export async function parseCSVWithGemini(csvText, prompt, apiKey) {
  const fullPrompt = `${prompt}\n\nCSV Data:\n${csvText}`;

  const response = await fetch(GEMINI_API_ENDPOINT, {
    method: 'POST',
    headers: {
      'x-goog-api-key': apiKey,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      // System instruction: Define the CSV parser's role
      system_instruction: {
        parts: [{
          text: `You are an expert book data parser specialized in extracting structured book information from CSV exports.

Your primary task is to intelligently map CSV columns to a standardized book data schema, handling various CSV formats from Goodreads, LibraryThing, StoryGraph, and custom exports.

Core capabilities:
- Auto-detect column headers regardless of format variations
- Infer missing metadata (author gender, cultural region, genre) when possible
- Normalize data types and formats (dates, ratings, ISBN formats)
- Handle malformed or incomplete rows gracefully

Always return ONLY a valid JSON array. Do not include explanatory text.`
        }]
      },
      contents: [{
        parts: [{
          text: fullPrompt
        }]
      }],
      generationConfig: {
        temperature: 0.2, // Low temperature for consistent, deterministic parsing (slightly higher than 0.1 for better inference)
        topP: 0.95,       // Nucleus sampling for quality
        maxOutputTokens: 8192,
        responseMimeType: 'application/json',  // Force JSON output (eliminates markdown code blocks)
        stopSequences: ['\n\n\n']  // Stop on triple newline (prevents unnecessary continuation)
      }
    })
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Gemini API error: ${error}`);
  }

  const data = await response.json();
  const textResponse = data.candidates?.[0]?.content?.parts?.[0]?.text;

  // Extract token usage metrics (Gemini API best practice: cost tracking)
  const tokenUsage = data.usageMetadata || {};
  const promptTokens = tokenUsage.promptTokenCount || 0;
  const outputTokens = tokenUsage.candidatesTokenCount || 0;
  const totalTokens = tokenUsage.totalTokenCount || 0;

  console.log(`[GeminiCSVProvider] Token usage - Prompt: ${promptTokens}, Output: ${outputTokens}, Total: ${totalTokens}`);

  if (!textResponse) {
    throw new Error('Gemini returned empty response');
  }

  // With responseMimeType='application/json', text should be clean JSON
  // Keep markdown stripping as defensive fallback for API version compatibility
  let jsonText = textResponse.trim();

  // Remove markdown code blocks if present (defensive fallback)
  if (jsonText.startsWith('```json')) {
    jsonText = jsonText.replace(/```json\n?/g, '').replace(/```\n?/g, '');
  } else if (jsonText.startsWith('```')) {
    jsonText = jsonText.replace(/```\n?/g, '');
  }

  // Parse JSON
  try {
    const parsed = JSON.parse(jsonText);
    if (!Array.isArray(parsed)) {
      throw new Error('Gemini response is not an array');
    }
    return parsed;
  } catch (error) {
    throw new Error(`Invalid JSON from Gemini: ${error.message}`);
  }
}
