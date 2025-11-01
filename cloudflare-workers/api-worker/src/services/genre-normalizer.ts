/**
 * Genre Normalization Service
 * Transforms provider-specific genres into canonical subjectTags
 */

/**
 * Canonical genre taxonomy
 * Maps variations → canonical names
 */
const CANONICAL_GENRES: Record<string, string[]> = {
  // Fiction categories
  'Science Fiction': ['Sci-Fi', 'Science Fiction', 'SF', 'Scifi'],
  'Fantasy': ['Fantasy', 'Fantasie'],
  'Mystery': ['Mystery', 'Detective', 'Whodunit', 'Mystrey'],
  'Thriller': ['Thriller', 'Suspense'],
  'Romance': ['Romance', 'Love Story'],
  'Horror': ['Horror', 'Scary'],
  'Literary Fiction': ['Literary', 'Literature', 'Literary Fiction'],
  'Historical Fiction': ['Historical Fiction', 'Historical Novel'],

  // Non-fiction categories
  'Biography': ['Biography', 'Memoir', 'Autobiography'],
  'History': ['History', 'Historical'],
  'Science': ['Science', 'Popular Science'],
  'Philosophy': ['Philosophy', 'Philosophical'],
  'Self-Help': ['Self-Help', 'Self Improvement', 'Personal Development'],
  'Business': ['Business', 'Economics', 'Entrepreneurship'],
  'True Crime': ['True Crime', 'Crime'],

  // Age groups
  'Young Adult': ['Young Adult', 'YA', 'Teen'],
  "Children's": ["Children's", 'Kids', 'Juvenile'],
  'Middle Grade': ['Middle Grade', 'MG'],

  // Special categories
  'Classics': ['Classic', 'Classics', 'Classical'],
  'Contemporary': ['Contemporary', 'Modern'],
  'Graphic Novels': ['Graphic Novel', 'Comics', 'Manga'],
  'Poetry': ['Poetry', 'Poems', 'Verse'],
  'Dystopian': ['Dystopian', 'Dystopia'],
  'Fiction': ['Fiction']
};

/**
 * Provider-specific genre mappings
 * Handles exact matches for known provider formats
 */
const PROVIDER_MAPPINGS: Record<string, string[]> = {
  // Google Books hierarchical format
  'Fiction / Science Fiction / General': ['Science Fiction', 'Fiction'],
  'Fiction / Science Fiction / Dystopian': ['Science Fiction', 'Dystopian', 'Fiction'],
  'Fiction / Fantasy / General': ['Fantasy', 'Fiction'],
  'Fiction / Fantasy / Epic': ['Fantasy', 'Fiction'],
  'Fiction / Mystery & Detective / General': ['Mystery', 'Fiction'],
  'Fiction / Thrillers / General': ['Thriller', 'Fiction'],
  'Fiction / Romance / General': ['Romance', 'Fiction'],
  'Fiction / Horror': ['Horror', 'Fiction'],
  'Fiction / Literary': ['Literary Fiction', 'Fiction'],
  'Fiction / Historical / General': ['Historical Fiction', 'Fiction'],

  // ISBNDB uses "&" separators
  'Science Fiction & Fantasy': ['Science Fiction', 'Fantasy'],
  'Mystery & Thriller': ['Mystery', 'Thriller'],
  'Romance & Fiction': ['Romance', 'Fiction'],

  // OpenLibrary descriptive subjects
  'Dystopian fiction': ['Dystopian', 'Science Fiction'],
  'Science fiction': ['Science Fiction'],
  'Classic Literature': ['Classics', 'Literary Fiction'],
  'Fantasy fiction': ['Fantasy'],
  'Detective and mystery stories': ['Mystery'],

  // Gemini AI free-form genres
  'Sci-fi dystopia': ['Science Fiction', 'Dystopian'],
  'Post-apocalyptic fiction': ['Science Fiction', 'Dystopian'],
  'Epic fantasy': ['Fantasy'],
};

/**
 * Calculate Levenshtein distance between two strings
 * Used for fuzzy genre matching
 */
function levenshteinDistance(a: string, b: string): number {
  const matrix: number[][] = [];

  for (let i = 0; i <= b.length; i++) {
    matrix[i] = [i];
  }

  for (let j = 0; j <= a.length; j++) {
    matrix[0][j] = j;
  }

  for (let i = 1; i <= b.length; i++) {
    for (let j = 1; j <= a.length; j++) {
      if (b.charAt(i - 1) === a.charAt(j - 1)) {
        matrix[i][j] = matrix[i - 1][j - 1];
      } else {
        matrix[i][j] = Math.min(
          matrix[i - 1][j - 1] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j] + 1
        );
      }
    }
  }

  return matrix[b.length][a.length];
}

/**
 * Genre Normalizer Service
 * Transforms provider-specific genres into canonical subjectTags
 */
export class GenreNormalizer {
  private readonly fuzzyThreshold = 0.85;

  /**
   * Normalize raw genres from any provider to canonical subjectTags
   * @param rawGenres - Raw genre strings from provider
   * @param provider - Provider name ('google-books', 'openlibrary', etc.)
   * @returns Array of canonical genre tags (sorted, deduplicated)
   */
  normalize(rawGenres: string[], provider: string): string[] {
    const normalized: Set<string> = new Set();

    for (const raw of rawGenres) {
      // 1. Provider-specific preprocessing
      const cleaned = this.preprocess(raw, provider);

      // 2. Exact mapping lookup
      const exactMatch = PROVIDER_MAPPINGS[cleaned];
      if (exactMatch) {
        exactMatch.forEach(tag => normalized.add(tag));
        continue;
      }

      // 3. Check canonical genre variations
      const canonicalMatch = this.findCanonicalMatch(cleaned);
      if (canonicalMatch) {
        normalized.add(canonicalMatch);
        continue;
      }

      // 4. Fuzzy matching for unmapped genres
      const fuzzyMatch = this.findFuzzyMatch(cleaned);
      if (fuzzyMatch) {
        normalized.add(fuzzyMatch);
      } else {
        // Pass through if no match found (user might have custom tags)
        normalized.add(cleaned);
      }
    }

    // Sort alphabetically for consistency
    return Array.from(normalized).sort();
  }

  /**
   * Provider-specific preprocessing
   * - Google Books: Attempts exact match for hierarchical genres (e.g., "Fiction / Science Fiction / General") via PROVIDER_MAPPINGS, falls back to fuzzy matching
   * - OpenLibrary: Lowercase normalization, trim
   * - ISBNDB: Split "&" separators
   */
  private preprocess(raw: string, provider: string): string {
    // Trim whitespace
    let cleaned = raw.trim();

    // Provider-specific transformations
    if (provider === 'google-books') {
      // Google Books uses hierarchical format "Fiction / Science Fiction / General"
      // We check the full string first in PROVIDER_MAPPINGS
      // If not found, we'll fuzzy match
      return cleaned;
    }

    if (provider === 'isbndb') {
      // ISBNDB uses "&" separators - but we check full string first
      return cleaned;
    }

    if (provider === 'openlibrary') {
      // OpenLibrary uses lowercase descriptive subjects
      // Capitalize first letter for consistency
      return cleaned.charAt(0).toUpperCase() + cleaned.slice(1).toLowerCase();
    }

    return cleaned;
  }

  /**
   * Find canonical genre by checking all variations
   */
  private findCanonicalMatch(genre: string): string | null {
    const lowerGenre = genre.toLowerCase();

    for (const [canonical, variations] of Object.entries(CANONICAL_GENRES)) {
      if (variations.some(v => v.toLowerCase() === lowerGenre)) {
        return canonical;
      }
    }

    return null;
  }

  /**
   * Find fuzzy match using Levenshtein distance
   * Returns canonical genre if similarity > threshold (85%)
   */
  private findFuzzyMatch(genre: string): string | null {
    const lowerGenre = genre.toLowerCase();
    let bestMatch: string | null = null;
    let bestSimilarity = 0;

    for (const canonical of Object.keys(CANONICAL_GENRES)) {
      const distance = levenshteinDistance(lowerGenre, canonical.toLowerCase());
      const maxLen = Math.max(lowerGenre.length, canonical.length);
      const similarity = 1 - distance / maxLen;

      if (similarity > bestSimilarity && similarity >= this.fuzzyThreshold) {
        bestMatch = canonical;
        bestSimilarity = similarity;
      }
    }

    return bestMatch;
  }
}
