/**
 * ISBNdb API Service
 *
 * Fetches book metadata and cover URLs from ISBNdb API.
 * Used by scheduled harvest cron to pre-populate cover cache.
 *
 * API Documentation: https://isbndb.com/apidocs
 * Rate Limit: 1000 req/day (paid tier)
 */

export class ISBNdbAPI {
  constructor(apiKey) {
    this.apiKey = apiKey;
    this.baseUrl = 'https://api2.isbndb.com';
  }

  /**
   * Fetch book data by ISBN
   * @param {string} isbn - ISBN-10 or ISBN-13
   * @returns {Promise<{image: string, title: string, authors: string[]}|null>}
   */
  async fetchBook(isbn) {
    try {
      const response = await fetch(`${this.baseUrl}/book/${isbn}`, {
        method: 'GET',
        headers: {
          'Authorization': this.apiKey,
          'Accept': 'application/json'
        }
      });

      if (response.status === 404) {
        console.log(`ISBNdb: Book not found - ${isbn}`);
        return null;
      }

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`ISBNdb API error: ${response.status} - ${errorText}`);
      }

      const data = await response.json();

      // Validate response structure
      if (!data.book) {
        console.warn(`ISBNdb: Unexpected response format for ${isbn}`, data);
        return null;
      }

      // Extract cover URL (required)
      if (!data.book.image) {
        console.log(`ISBNdb: No cover image for ${isbn}`);
        return null;
      }

      return {
        image: data.book.image,
        title: data.book.title || 'Unknown',
        authors: data.book.authors || [],
        publisher: data.book.publisher || null,
        publishedDate: data.book.date_published || null
      };

    } catch (error) {
      console.error(`ISBNdb API error for ${isbn}:`, error.message);
      throw error;
    }
  }

  /**
   * Health check - verify API key is valid
   * @returns {Promise<boolean>}
   */
  async healthCheck() {
    try {
      // Use a known good ISBN for testing (verified working: 1984 by George Orwell)
      const testISBN = '9780451524935'; // 1984 by George Orwell
      const response = await fetch(`${this.baseUrl}/book/${testISBN}`, {
        method: 'GET',
        headers: {
          'Authorization': this.apiKey,
          'Accept': 'application/json'
        }
      });

      return response.ok || response.status === 404; // 404 is OK (means auth passed)
    } catch (error) {
      console.error('ISBNdb health check failed:', error);
      return false;
    }
  }
}
