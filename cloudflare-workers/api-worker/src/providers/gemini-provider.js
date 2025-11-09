/**
 * Google Gemini AI vision provider
 * Extracted from ai-scanner service for compartmentalization
 *
 * Uses Gemini 2.5 Flash (production-stable) for high-accuracy bookshelf scanning
 */

import { BOOKSHELF_RESPONSE_SCHEMA } from '../types/gemini-schemas.js';

/**
 * Scan bookshelf image using Gemini AI
 * @param {ArrayBuffer} imageData - Raw JPEG image data
 * @param {Object} env - Worker environment with GEMINI_API_KEY
 * @returns {Promise<Object>} Scan result with books array
 */
export async function scanImageWithGemini(imageData, env) {
    const startTime = Date.now();

    // DIAGNOSTIC: Log secret binding status
    console.log('[GeminiProvider] DIAGNOSTIC: Checking GEMINI_API_KEY binding...');
    console.log('[GeminiProvider] env.GEMINI_API_KEY exists:', !!env.GEMINI_API_KEY);
    console.log('[GeminiProvider] env.GEMINI_API_KEY.get exists:', !!env.GEMINI_API_KEY?.get);

    // Get API key
    const apiKey = env.GEMINI_API_KEY?.get
        ? await env.GEMINI_API_KEY.get()
        : env.GEMINI_API_KEY;

    console.log('[GeminiProvider] DIAGNOSTIC: API key retrieved:', !!apiKey);
    console.log('[GeminiProvider] DIAGNOSTIC: API key length:', apiKey?.length || 0);

    if (!apiKey) {
        console.error('[GeminiProvider] ERROR: GEMINI_API_KEY not configured or empty');
        throw new Error('GEMINI_API_KEY not configured');
    }

    // Convert ArrayBuffer to base64
    const bytes = new Uint8Array(imageData);
    let binary = '';
    for (let i = 0; i < bytes.byteLength; i++) {
        binary += String.fromCharCode(bytes[i]);
    }
    const base64Image = btoa(binary);

    // Call Gemini API with optimized prompting strategy
    const response = await fetch(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent',
        {
            method: 'POST',
            headers: {
                'x-goog-api-key': apiKey,
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                // System instruction: Define role and output format (static, won't change)
                system_instruction: {
                    parts: [{
                        text: `You are an expert bookshelf analyzer specialized in extracting book metadata from shelf photos.

Your output must be a valid JSON array with this exact schema:
[
  {
    "title": "Book Title",
    "author": "Author Name",
    "format": "hardcover" | "paperback" | "mass-market" | "unknown",
    "confidence": 0.0-1.0,
    "boundingBox": {
      "x1": 0.0-1.0,
      "y1": 0.0-1.0,
      "x2": 0.0-1.0,
      "y2": 0.0-1.0
    }
  }
]

Format Detection Rules:
- "hardcover": Rigid spine, larger size, cloth/embossed texture, square corners
- "paperback": Flexible spine, glossy cover, rounded spine edge
- "mass-market": Small paperback (~4x7 inches), pocket-sized
- "unknown": Cannot determine from visual cues

Quality Standards:
- Only include books where you can read at least the title
- Skip decorative items, bookends, or non-book objects
- confidence: Your certainty level (0.0-1.0) about the extracted text
- boundingBox: Normalized coordinates (0.0-1.0) for the book spine location`
                    }]
                },
                contents: [{
                    parts: [
                        {
                            inline_data: {
                                mime_type: 'image/jpeg',
                                data: base64Image
                            }
                        },
                        {
                            text: `Analyze this bookshelf image step by step:

1. **Identify individual book spines**: Look for vertical or horizontal book orientations
2. **Handle common challenges**:
   - Vertical spines with sideways text
   - Horizontal stacks with upward-facing covers
   - Partial visibility (books cut off at frame edges)
   - Glare or reflections on glossy covers
   - Low contrast text on dark spines
   - Books tilted or at angles
3. **Extract text carefully**: For each readable book spine:
   - Title (required)
   - Author name (if visible)
   - Assign confidence based on text clarity
4. **Detect physical format**: Based on visual cues (size, spine flexibility, texture)
5. **Return structured JSON**: Only include books with readable titles

Extract all visible book information now.`
                        }
                    ]
                }],
                generationConfig: {
                    temperature: 0.4,  // Balanced: deterministic enough for accuracy, flexible enough for inference
                    topK: 40,          // Allow some variation for better book spine recognition
                    topP: 0.95,        // Nucleus sampling for quality
                    maxOutputTokens: 2048,  // Prevent truncation
                    responseMimeType: 'application/json',  // Force JSON output
                    responseSchema: BOOKSHELF_RESPONSE_SCHEMA,  // Schema-enforced validation (guarantees structure)
                    stopSequences: ['\n\n\n']  // Stop on triple newline (prevents unnecessary continuation)
                }
            })
        }
    );

    if (!response.ok) {
        const errorText = await response.text();
        console.error(`[GeminiProvider] Gemini API error: ${response.status}`);
        console.error(`[GeminiProvider] Error details:`, errorText);
        throw new Error(`Gemini API error: ${response.status} - ${errorText}`);
    }

    console.log('[GeminiProvider] Gemini API response OK, parsing JSON...');
    const geminiData = await response.json();
    console.log('[GeminiProvider] Response parsed, checking for candidates...');

    // Extract token usage metrics (Gemini API best practice: cost tracking)
    const tokenUsage = geminiData.usageMetadata || {};
    const promptTokens = tokenUsage.promptTokenCount || 0;
    const outputTokens = tokenUsage.candidatesTokenCount || 0;
    const totalTokens = tokenUsage.totalTokenCount || 0;

    console.log(`[GeminiProvider] Token usage - Prompt: ${promptTokens}, Output: ${outputTokens}, Total: ${totalTokens}`);

    // Parse response
    const text = geminiData.candidates?.[0]?.content?.parts?.[0]?.text;
    if (!text) {
        console.error('[GeminiProvider] Empty response');
        return {
            books: [],
            suggestions: [],
            metadata: {
                provider: 'gemini',
                model: 'gemini-2.0-flash-exp',
                timestamp: new Date().toISOString(),
                processingTimeMs: Date.now() - startTime,
                tokenUsage: {
                    promptTokens,
                    outputTokens,
                    totalTokens
                }
            }
        };
    }

    // With structured output, response is guaranteed to be valid JSON matching schema
    const books = JSON.parse(text);

    // Lightweight defensive check: Catches API bugs, not schema violations
    // (Schema guarantees array structure, but we verify to catch unexpected API changes)
    if (!Array.isArray(books)) {
        console.error('[GeminiProvider] Schema violation: Expected array, got', typeof books);
        return {
            books: [],
            suggestions: [],
            metadata: {
                provider: 'gemini',
                model: 'gemini-2.5-flash',
                timestamp: new Date().toISOString(),
                processingTimeMs: Date.now() - startTime,
                tokenUsage: {
                    promptTokens,
                    outputTokens,
                    totalTokens
                }
            }
        };
    }

    // Trust schema for normalization - no validation needed
    // Schema enforces: confidence (0-1), boundingBox coords (0-1), format enum
    const normalizedBooks = books.map(book => ({
        title: book.title,
        author: book.author || '',
        isbn: book.isbn || null,
        format: book.format,         // Enum enforced by schema
        confidence: book.confidence,  // Range enforced by schema (0.0-1.0)
        boundingBox: book.boundingBox // Coordinates enforced by schema (0.0-1.0)
    })).filter(book => book.title.length > 0);

    return {
        books: normalizedBooks,
        suggestions: [],  // Gemini doesn't provide suggestions in current implementation
        metadata: {
            provider: 'gemini',
            model: 'gemini-2.5-flash',
            timestamp: new Date().toISOString(),
            processingTimeMs: Date.now() - startTime,
            tokenUsage: {
                promptTokens,
                outputTokens,
                totalTokens
            }
        }
    };
}
