/**
 * Test Multi-Edition Discovery
 *
 * Quick test endpoint to verify edition discovery works before deploying to harvest
 * GET /api/test-multi-edition?count=5
 */

import { getTopEditions } from '../services/edition-discovery.js';

export async function handleTestMultiEdition(request, env) {
  const url = new URL(request.url);
  const count = parseInt(url.searchParams.get('count') || '5', 10);

  // Test ISBNs (first 5 from curated list)
  const testISBNs = [
    '9780008479599', // The Midnight Library
    '9780062060624', // The Light We Lost
    '9780062225559', // The Nightingale
    '9780062277022', // The Woman in Cabin 10
    '9780062300547'  // The Girl on the Train
  ].slice(0, count);

  const results = [];

  for (const isbn of testISBNs) {
    try {
      // Get metadata from Google Books
      const metadataUrl = new URL('https://www.googleapis.com/books/v1/volumes');
      metadataUrl.searchParams.set('q', `isbn:${isbn}`);

      const metadataResponse = await fetch(metadataUrl.toString());
      const metadataData = await metadataResponse.json();

      if (!metadataData.items || metadataData.items.length === 0) {
        results.push({
          seedISBN: isbn,
          title: 'Unknown',
          editions: [],
          error: 'No metadata found'
        });
        continue;
      }

      const volumeInfo = metadataData.items[0].volumeInfo;
      const title = volumeInfo.title;
      const authors = volumeInfo.authors || [];

      // Discover editions
      const editions = await getTopEditions({ title, authors }, env, 3);

      results.push({
        seedISBN: isbn,
        title,
        authors,
        editionsFound: editions.length,
        editions: editions.map(ed => ({
          isbn: ed.isbn,
          title: ed.title,
          score: ed.score,
          publisher: ed.publisher,
          publishedDate: ed.publishedDate
        }))
      });

    } catch (error) {
      results.push({
        seedISBN: isbn,
        error: error.message
      });
    }
  }

  // Summary stats
  const totalEditions = results.reduce((sum, r) => sum + (r.editionsFound || 0), 0);
  const avgEditionsPerWork = (totalEditions / results.length).toFixed(1);

  return new Response(JSON.stringify({
    success: true,
    summary: {
      worksProcessed: results.length,
      totalEditions,
      avgEditionsPerWork: parseFloat(avgEditionsPerWork)
    },
    results
  }, null, 2), {
    headers: { 'Content-Type': 'application/json' }
  });
}
