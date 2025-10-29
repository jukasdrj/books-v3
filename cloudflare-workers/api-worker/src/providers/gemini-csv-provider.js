// src/providers/gemini-csv-provider.js

const GEMINI_API_ENDPOINT = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:generateContent';

/**
 * Parse CSV file using Gemini 2.0 Flash API
 *
 * Features:
 * - Low temperature (0.1) for consistent, deterministic parsing
 * - Handles markdown code blocks in Gemini responses
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
      contents: [{
        parts: [{
          text: fullPrompt
        }]
      }],
      generationConfig: {
        temperature: 0.1, // Low temperature for consistent parsing
        maxOutputTokens: 8192
      }
    })
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Gemini API error: ${error}`);
  }

  const data = await response.json();
  const textResponse = data.candidates?.[0]?.content?.parts?.[0]?.text;

  if (!textResponse) {
    throw new Error('Gemini returned empty response');
  }

  // Extract JSON array from response (handle markdown code blocks)
  let jsonText = textResponse.trim();

  // Remove markdown code blocks if present
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
