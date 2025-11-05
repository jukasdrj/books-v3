/**
 * Book enrichment service
 *
 * Provides DRY enrichment services for individual and multiple book lookups:
 * - enrichSingleBook() - Individual book enrichment with multi-provider fallback
 *   (Google Books → OpenLibrary)
 * - enrichMultipleBooks() - Multiple results for search queries
 *
 * Used by:
 * - /api/enrichment/batch (via batch-enrichment.js handler)
 * - /v1/search/* endpoints (title, ISBN, advanced search)
 */

import * as externalApis from './external-apis.js';
import type { WorkDTO, EditionDTO, AuthorDTO } from '../types/canonical.js';
import type { DataProvider } from '../types/enums.js';

// ========================================================================================
// INTERFACES
// ========================================================================================

/**
 * Cloudflare Worker environment bindings
 * See wrangler.toml for complete configuration
 */
interface WorkerEnv {
	// KV Namespaces
	CACHE: KVNamespace;
	KV_CACHE: KVNamespace;

	// Secrets
	GOOGLE_BOOKS_API_KEY: string;
	ISBNDB_API_KEY: string;
	GEMINI_API_KEY: string;

	// R2 Buckets
	API_CACHE_COLD: R2Bucket;
	LIBRARY_DATA: R2Bucket;
	BOOKSHELF_IMAGES: R2Bucket;

	// Workers AI
	AI: Fetcher;

	// Durable Objects
	PROGRESS_WEBSOCKET_DO: DurableObjectNamespace;

	// Analytics Engine
	PERFORMANCE_ANALYTICS?: AnalyticsEngineDataset;
	CACHE_ANALYTICS?: AnalyticsEngineDataset;
	PROVIDER_ANALYTICS?: AnalyticsEngineDataset;
	AI_ANALYTICS?: AnalyticsEngineDataset;

	// Queue Producers
	AUTHOR_WARMING_QUEUE?: Queue;
}

/**
 * Query parameters for book searches
 */
interface BookSearchQuery {
	title?: string;
	author?: string;
	isbn?: string;
}

/**
 * Options for multi-book searches
 */
interface SearchOptions {
	maxResults?: number;
}

/**
 * Extended WorkDTO with authors property
 * external-apis.js returns works with authors array, but canonical WorkDTO doesn't include it
 */
type WorkDTOWithAuthors = WorkDTO & { authors?: AuthorDTO[] };

/**
 * Generic API response for external API calls
 */
interface ApiResponse {
	success: boolean;
	works?: WorkDTOWithAuthors[];
	editions?: EditionDTO[];
	authors?: AuthorDTO[];
	error?: string;
}

/**
 * Return type for enrichMultipleBooks
 */
interface EnrichmentResult {
	works: WorkDTO[];
	editions: EditionDTO[];
	authors: AuthorDTO[];
}

// ========================================================================================
// PUBLIC FUNCTIONS
// ========================================================================================

/**
 * Enrich multiple books with metadata from external providers
 * Used by search endpoints that need multiple results
 *
 * @param query - Search parameters
 * @param env - Worker environment bindings
 * @param options - Search options
 * @returns EnrichmentResult with works, editions, and authors
 */
export async function enrichMultipleBooks(
	query: BookSearchQuery,
	env: WorkerEnv,
	options: SearchOptions = { maxResults: 20 }
): Promise<EnrichmentResult> {
	const { title, author, isbn } = query;
	const { maxResults = 20 } = options;

	// ISBN search returns single result (ISBNs are unique)
	if (isbn) {
		const result = await enrichSingleBook({ isbn }, env);
		return result 
			? { works: [result], editions: [], authors: [] }
			: { works: [], editions: [], authors: [] };
	}

	// Build search query for Google Books
	const searchQuery = [title, author].filter(Boolean).join(' ');

	if (!searchQuery) {
		console.warn('enrichMultipleBooks: No search parameters provided');
		return { works: [], editions: [], authors: [] };
	}

  try {
    // Try Google Books first with maxResults
    console.log(`enrichMultipleBooks: Searching Google Books for "${searchQuery}" (maxResults: ${maxResults})`);
    const googleResult: ApiResponse = await externalApis.searchGoogleBooks(searchQuery, { maxResults }, env);

    if (googleResult.success && googleResult.works && googleResult.works.length > 0) {
      // Add provenance fields to all works
      return {
        works: googleResult.works.map((work: WorkDTO) => addProvenanceFields(work, 'google-books')),
        editions: googleResult.editions || [],
        authors: googleResult.authors || []
      };
    }

    // Fallback to OpenLibrary
    console.log(`enrichMultipleBooks: Google Books returned no results, trying OpenLibrary`);
    const olResult: ApiResponse = await externalApis.searchOpenLibrary(searchQuery, { maxResults }, env);

    if (olResult.success && olResult.works && olResult.works.length > 0) {
      // Add provenance fields to all works
      return {
        works: olResult.works.map((work: WorkDTO) => addProvenanceFields(work, 'openlibrary')),
        editions: olResult.editions || [],
        authors: olResult.authors || []
      };
    }

    // No results from any provider
    console.log(`enrichMultipleBooks: No results for "${searchQuery}"`);
    return { works: [], editions: [], authors: [] };

  } catch (error) {
    console.error('enrichMultipleBooks error:', error);
    // Best-effort: API errors = empty results (don't propagate errors)
    return { works: [], editions: [], authors: [] };
  }
}

/**
 * Enrich a single book with metadata from external providers
 * Used by enrichment pipeline that needs best match for a specific book
 *
 * @param query - Search parameters
 * @param env - Worker environment bindings
 * @returns WorkDTO with editions and authors, or null if not found
 */
export async function enrichSingleBook(query: BookSearchQuery, env: WorkerEnv): Promise<WorkDTO | null> {
	const { title, author, isbn } = query;

	// Require at least one search parameter
	if (!title && !isbn && !author) {
    console.warn('enrichSingleBook: No search parameters provided');
    return null;
  }

  try {
    // Strategy 1: If ISBN provided, use ISBN search (most accurate)
    if (isbn) {
      const result: WorkDTO | null = await searchByISBN(isbn, env);
      if (result) return result;

      // If ISBN search failed but we have title/author, fall back to text search
      // Don't continue to Strategy 2/3 if we only have ISBN (nothing else to search)
      if (!title && !author) {
        console.log(`enrichSingleBook: No results for ISBN "${isbn}"`);
        return null;
      }
    }

    // Strategy 2: Try Google Books with title+author (not ISBN - already tried above)
    const googleResult: WorkDTO | null = await searchGoogleBooks({ title, author }, env);
    if (googleResult) {
      return googleResult;
    }

    // Strategy 3: Fallback to OpenLibrary
    const openLibResult: WorkDTO | null = await searchOpenLibrary({ title, author }, env);
    if (openLibResult) {
      return openLibResult;
    }

    // Book not found in any provider
    console.log(`enrichSingleBook: No results for "${title}" by "${author || 'unknown'}"`);
    return null;

  } catch (error) {
    console.error('enrichSingleBook error:', error);
    // Best-effort: API errors = not found (don't propagate errors)
    return null;
  }
}

/**
 * Search Google Books API with query
 * Thin wrapper around external-apis.js - just adds provenance fields
 *
 * @param query - Search parameters
 * @param env - Worker environment bindings
 * @returns First work result or null
 */
async function searchGoogleBooks(query: BookSearchQuery, env: WorkerEnv): Promise<WorkDTO | null> {
	const { title, author, isbn } = query;

	// Build search query (title + author for better precision)
	const searchQuery: string = isbn ? isbn : [title, author].filter(Boolean).join(' ');

	const result: ApiResponse = isbn
		? await externalApis.searchGoogleBooksByISBN(searchQuery, env)
		: await externalApis.searchGoogleBooks(searchQuery, { maxResults: 1 }, env);

	if (!result.success || !result.works || result.works.length === 0) {
		return null;
	}

	// Return first work with provenance fields added
	const work: WorkDTO = result.works[0];
	return addProvenanceFields(work, 'google-books');
}

/**
 * Search OpenLibrary API with query
 * Thin wrapper around external-apis.js - just adds provenance fields
 *
 * @param query - Search parameters
 * @param env - Worker environment bindings
 * @returns First work result or null
 */
async function searchOpenLibrary(query: BookSearchQuery, env: WorkerEnv): Promise<WorkDTO | null> {
	const { title, author } = query;

	const searchQuery: string = [title, author].filter(Boolean).join(' ');
	const result: ApiResponse = await externalApis.searchOpenLibrary(searchQuery, { maxResults: 1 }, env);

	if (!result.success || !result.works || result.works.length === 0) {
		return null;
	}

	// Return first work with provenance fields added
	const work: WorkDTO = result.works[0];
	return addProvenanceFields(work, 'openlibrary');
}

/**
 * ISBN-specific search (tries Google Books, then OpenLibrary)
 * Thin wrapper around external-apis.js - just adds provenance fields
 *
 * @param isbn - ISBN-10 or ISBN-13
 * @param env - Worker environment bindings
 * @returns Work result or null
 */
async function searchByISBN(isbn: string, env: WorkerEnv): Promise<WorkDTO | null> {
	// Try Google Books ISBN search first
	const googleResult: ApiResponse = await externalApis.searchGoogleBooksByISBN(isbn, env);

	if (googleResult.success && googleResult.works && googleResult.works.length > 0) {
		const work: WorkDTO = googleResult.works[0];
		return addProvenanceFields(work, 'google-books');
	}

	// Fallback to OpenLibrary ISBN search
	const olResult: ApiResponse = await externalApis.searchOpenLibrary(isbn, { maxResults: 1, isbn }, env);

	if (olResult.success && olResult.works && olResult.works.length > 0) {
		const work: WorkDTO = olResult.works[0];
		return addProvenanceFields(work, 'openlibrary');
	}

	return null;
}

/**
 * Add provenance fields to work already normalized by external-apis.js
 *
 * The external-apis.js already returns fully normalized works.
 * We just add provenance tracking fields:
 * - primaryProvider - Which API contributed the data
 * - contributors - Array of all providers (single provider for direct calls)
 * - synthetic - Flag for inferred works (false for direct API results)
 *
 * @param work - Normalized work from external-apis.js
 * @param provider - Provider name
 * @returns WorkDTO with provenance fields
 */
function addProvenanceFields(work: WorkDTO, provider: DataProvider): WorkDTO {
	return {
		...work, // Preserve all existing normalized fields
		primaryProvider: provider,
    contributors: [provider],
    synthetic: false // Direct API result, not inferred
  };
}
