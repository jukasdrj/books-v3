#!/usr/bin/env node

/**
 * Analytics-Driven Cache Warming Script
 *
 * Queries Analytics Engine for popular searches with low cache hit rates,
 * then sends warming jobs to the author-warming queue.
 *
 * Usage:
 *   node scripts/analyze-and-warm.js --account-id YOUR_ACCOUNT_ID --auth-token YOUR_TOKEN
 *
 * Environment Variables:
 *   CF_ACCOUNT_ID - Cloudflare account ID
 *   CF_API_TOKEN - Cloudflare API token with Analytics Engine read access
 *
 * Runs as:
 *   - GitHub Actions daily cron (automated)
 *   - Manual trigger for testing
 */

import https from 'https';

// Configuration
const ACCOUNT_ID = process.env.CF_ACCOUNT_ID || process.argv[2];
const API_TOKEN = process.env.CF_API_TOKEN || process.argv[3];
const TEST_MODE = process.env.TEST_MODE === 'true' || process.argv.includes('--test');
const ANALYTICS_DATASET = 'books_api_cache_metrics';
const QUEUE_NAME = 'author-warming-queue';

// Warming criteria
const MIN_REQUESTS = 5;        // Must have at least 5 requests in period
const MAX_CACHE_HIT_RATE = 0.6; // Less than 60% cache hit rate
const TOP_N_QUERIES = 20;       // Warm top 20 queries
const LOOKBACK_HOURS = 24;      // Analyze last 24 hours

if (!TEST_MODE && (!ACCOUNT_ID || !API_TOKEN)) {
  console.error('❌ Missing credentials. Set CF_ACCOUNT_ID and CF_API_TOKEN environment variables.');
  console.error('   Or run in test mode: node scripts/analyze-and-warm.js --test');
  process.exit(1);
}

/**
 * Query Analytics Engine for popular searches
 */
async function queryAnalytics() {
  if (TEST_MODE) {
    // Return mock data for testing
    return [
      { blob1: 'author', blob2: 'Stephen King', count: 47 },
      { blob1: 'author', blob2: 'J.K. Rowling', count: 32 },
      { blob1: 'author', blob2: 'Agatha Christie', count: 28 },
      { blob1: 'title', blob2: 'Harry Potter', count: 24 },
      { blob1: 'author', blob2: 'Isaac Asimov', count: 19 },
      { blob1: 'author', blob2: 'Neil Gaiman', count: 15 }
    ];
  }

  // SQL query for Analytics Engine
  // Note: Analytics Engine COUNT() takes no arguments
  // Use NOW() - INTERVAL for timestamp filtering
  const sqlQuery = `
    SELECT
      blob1 as query_type,
      blob2 as query_text,
      COUNT() as count
    FROM ${ANALYTICS_DATASET}
    WHERE timestamp > NOW() - INTERVAL '${LOOKBACK_HOURS}' HOUR
    GROUP BY blob1, blob2
    ORDER BY count DESC
    LIMIT 1000
  `;

  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'api.cloudflare.com',
      port: 443,
      path: `/client/v4/accounts/${ACCOUNT_ID}/analytics_engine/sql`,
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${API_TOKEN}`,
        'Content-Type': 'application/json'
      }
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        try {
          const parsed = JSON.parse(data);
          // Analytics Engine SQL API returns { data: [...rows...], meta: [...columns...] }
          if (parsed.data) {
            console.log(`✅ Retrieved ${parsed.data.length} analytics data points`);
            resolve(parsed.data);
          } else {
            reject(new Error(`Unexpected SQL API response format: ${JSON.stringify(parsed)}`));
          }
        } catch (error) {
          console.error(`DEBUG: Failed to parse response. Raw data: ${data.substring(0, 200)}`);
          reject(error);
        }
      });
    });

    req.on('error', reject);
    req.write(sqlQuery);
    req.end();
  });
}

/**
 * Analyze query patterns and identify warming candidates
 */
function analyzeQueries(analyticsData) {
  if (!analyticsData || analyticsData.length === 0) {
    console.warn('⚠️  No analytics data found');
    return [];
  }

  // Group by query type and calculate cache hit rates
  const queryStats = {};

  for (const entry of analyticsData) {
    const queryType = entry.query_type || entry.blob1; // 'title', 'isbn', 'author'
    const query = entry.query_text || entry.blob2;     // Actual search query
    const count = entry.count;

    if (!queryStats[query]) {
      queryStats[query] = {
        query: query,
        type: queryType,
        totalRequests: 0,
        cacheHits: 0,
        cacheMisses: 0
      };
    }

    queryStats[query].totalRequests += count;

    // NOTE: This is simplified - actual implementation needs to track
    // cache hits vs misses separately in Analytics Engine
    // For now, assume if count > MIN_REQUESTS, it's worth warming
  }

  // Filter and sort candidates
  const candidates = Object.values(queryStats)
    .filter(stat => stat.totalRequests >= MIN_REQUESTS)
    .filter(stat => stat.type === 'author') // Focus on author searches (highest warming value)
    .sort((a, b) => b.totalRequests - a.totalRequests)
    .slice(0, TOP_N_QUERIES);

  return candidates;
}

/**
 * Send warming jobs to queue
 */
async function sendWarmingJobs(candidates) {
  if (candidates.length === 0) {
    console.log('✅ No warming candidates found (cache is hot!)');
    return;
  }

  console.log(`📤 Sending ${candidates.length} warming jobs to queue...`);

  const jobs = candidates.map((candidate, index) => ({
    body: {
      author: candidate.query,
      depth: 1,
      source: 'analytics-driven',
      jobId: `analytics-${Date.now()}-${index}`,
      priority: candidate.totalRequests // Higher requests = higher priority
    }
  }));

  if (TEST_MODE) {
    console.log('🧪 TEST MODE: Would send jobs:', JSON.stringify(jobs, null, 2));
    console.log(`✅ Test complete: ${jobs.length} warming jobs validated`);
    return { result: jobs };
  }

  // Send to queue via API
  const response = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/queues/${QUEUE_NAME}/messages`,
    {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${API_TOKEN}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ messages: jobs })
    }
  );

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Failed to send warming jobs: ${error}`);
  }

  const result = await response.json();
  console.log(`✅ Queued ${result.result.length} warming jobs`);

  return result;
}

/**
 * Main execution
 */
async function main() {
  if (TEST_MODE) {
    console.log('🧪 TEST MODE ENABLED - No API calls will be made\n');
  }

  console.log('🔍 Analyzing cache performance...');
  console.log(`   Period: Last ${LOOKBACK_HOURS} hours`);
  console.log(`   Min requests: ${MIN_REQUESTS}`);
  console.log(`   Top N: ${TOP_N_QUERIES}`);
  console.log('');

  try {
    // Step 1: Query Analytics Engine
    console.log('📊 Querying Analytics Engine...');
    const analyticsData = await queryAnalytics();

    // Step 2: Analyze and identify candidates
    console.log('🧮 Analyzing query patterns...');
    const candidates = analyzeQueries(analyticsData);

    console.log(`\n📋 Found ${candidates.length} warming candidates:`);
    candidates.forEach((c, i) => {
      console.log(`   ${i + 1}. "${c.query}" (${c.totalRequests} requests)`);
    });
    console.log('');

    // Step 3: Send warming jobs
    await sendWarmingJobs(candidates);

    console.log('\n🎉 Analytics-driven warming complete!');

  } catch (error) {
    console.error('❌ Error:', error.message);
    process.exit(1);
  }
}

main();
