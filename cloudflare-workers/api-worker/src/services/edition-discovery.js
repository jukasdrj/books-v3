/**
 * Edition Discovery Service
 *
 * Discovers all available editions of a Work using Google Books API.
 * Scores editions based on quality indicators and returns top candidates
 * for cover image harvesting.
 */

/**
 * Score an edition based on quality indicators
 * @param {Object} volumeInfo - Google Books volume metadata
 * @returns {number} Score from 0-100
 */
function scoreEdition(volumeInfo) {
  let score = 0;

  // Image quality (40 points max)
  if (volumeInfo.imageLinks?.extraLarge) {
    score += 40;
  } else if (volumeInfo.imageLinks?.large) {
    score += 30;
  } else if (volumeInfo.imageLinks?.medium) {
    score += 20;
  } else if (volumeInfo.imageLinks?.thumbnail) {
    score += 10;
  }

  // Edition type (30 points max)
  const description = (volumeInfo.description || '').toLowerCase();
  const title = (volumeInfo.title || '').toLowerCase();

  if (description.includes('illustrated') || title.includes('illustrated')) {
    score += 30;
  } else if (description.includes('first edition') || title.includes('first edition')) {
    score += 25;
  } else if (description.includes('collector') || title.includes('collector')) {
    score += 25;
  } else if (description.includes('anniversary') || title.includes('anniversary')) {
    score += 20;
  }

  // Binding type (15 points max)
  if (volumeInfo.printType === 'BOOK') {
    if (title.includes('hardcover') || description.includes('hardcover')) {
      score += 15;
    } else if (title.includes('paperback') || description.includes('paperback')) {
      score += 10;
    }
  }

  // Publication date recency (10 points max)
  if (volumeInfo.publishedDate) {
    const year = parseInt(volumeInfo.publishedDate.substring(0, 4));
    const currentYear = new Date().getFullYear();
    const age = currentYear - year;

    if (age <= 5) {
      score += 10; // Recent editions often have better covers
    } else if (age <= 15) {
      score += 5;
    }
  }

  // Page count (5 points max)
  if (volumeInfo.pageCount && volumeInfo.pageCount > 0) {
    score += 5;
  }

  return score;
}

/**
 * Discover all editions of a Work using Google Books API
 * @param {Object} workMetadata - Basic work metadata
 * @param {string} workMetadata.title - Work title
 * @param {string[]} workMetadata.authors - List of author names
 * @param {Object} env - Worker environment bindings
 * @returns {Promise<Array>} Array of edition objects with scores
 */
export async function discoverEditions(workMetadata, env) {
  const { title, authors } = workMetadata;

  if (!title || !authors || authors.length === 0) {
    console.warn('Missing title or authors for edition discovery');
    return [];
  }

  try {
    // Build Google Books search query
    // Format: intitle:"Exact Title" inauthor:"Author Name"
    const titleQuery = `intitle:"${title.replace(/"/g, '')}"`;
    const authorQuery = authors.map(a => `inauthor:"${a.replace(/"/g, '')}"`).join(' ');
    const query = `${titleQuery} ${authorQuery}`;

    // Query Google Books API
    const url = new URL('https://www.googleapis.com/books/v1/volumes');
    url.searchParams.set('q', query);
    url.searchParams.set('maxResults', '40'); // Max allowed by Google Books
    url.searchParams.set('printType', 'books'); // Exclude magazines
    url.searchParams.set('orderBy', 'relevance');

    const response = await fetch(url.toString());

    if (!response.ok) {
      console.error(`Google Books API error: ${response.status}`);
      return [];
    }

    const data = await response.json();

    if (!data.items || data.items.length === 0) {
      console.log(`No editions found for: ${title}`);
      return [];
    }

    // Score each edition
    const editions = data.items
      .map(item => {
        const volumeInfo = item.volumeInfo;
        const score = scoreEdition(volumeInfo);

        // Extract ISBN-13 (prefer over ISBN-10)
        const identifiers = volumeInfo.industryIdentifiers || [];
        const isbn13 = identifiers.find(id => id.type === 'ISBN_13');
        const isbn10 = identifiers.find(id => id.type === 'ISBN_10');
        const isbn = isbn13?.identifier || isbn10?.identifier;

        return {
          isbn,
          title: volumeInfo.title,
          subtitle: volumeInfo.subtitle,
          authors: volumeInfo.authors || [],
          publisher: volumeInfo.publisher,
          publishedDate: volumeInfo.publishedDate,
          pageCount: volumeInfo.pageCount,
          imageLinks: volumeInfo.imageLinks,
          description: volumeInfo.description,
          score,
          // Debug info
          _scoreBreakdown: {
            hasExtraLargeImage: !!volumeInfo.imageLinks?.extraLarge,
            hasLargeImage: !!volumeInfo.imageLinks?.large,
            hasMediumImage: !!volumeInfo.imageLinks?.medium,
            isIllustrated: (volumeInfo.description || volumeInfo.title || '').toLowerCase().includes('illustrated'),
            isFirstEdition: (volumeInfo.description || volumeInfo.title || '').toLowerCase().includes('first edition'),
            binding: volumeInfo.printType,
            publicationYear: volumeInfo.publishedDate?.substring(0, 4)
          }
        };
      })
      .filter(edition => edition.isbn) // Only keep editions with ISBNs
      .sort((a, b) => b.score - a.score); // Sort by score descending

    console.log(`Discovered ${editions.length} editions for "${title}" (top score: ${editions[0]?.score || 0})`);

    return editions;
  } catch (error) {
    console.error('Edition discovery error:', error);
    return [];
  }
}

/**
 * Get top N editions for a Work
 * @param {Object} workMetadata - Basic work metadata
 * @param {Object} env - Worker environment bindings
 * @param {number} limit - Max editions to return (default: 3)
 * @returns {Promise<Array>} Top N edition ISBNs with metadata
 */
export async function getTopEditions(workMetadata, env, limit = 3) {
  const allEditions = await discoverEditions(workMetadata, env);

  if (allEditions.length === 0) {
    return [];
  }

  const topEditions = allEditions.slice(0, limit);

  // Log edition selection for debugging
  console.log(`Selected top ${topEditions.length} editions for "${workMetadata.title}":`);
  topEditions.forEach((ed, idx) => {
    console.log(`  ${idx + 1}. ISBN: ${ed.isbn}, Score: ${ed.score}, Publisher: ${ed.publisher || 'Unknown'}`);
  });

  return topEditions.map(ed => ({
    isbn: ed.isbn,
    title: ed.title,
    score: ed.score,
    imageUrl: ed.imageLinks?.large || ed.imageLinks?.medium || ed.imageLinks?.thumbnail,
    publisher: ed.publisher,
    publishedDate: ed.publishedDate
  }));
}
