/**
 * GET /api/cache/metrics - Cache performance and cost metrics
 *
 * @param {Request} request
 * @param {Object} env
 * @returns {Response} Metrics summary
 */
export async function handleCacheMetrics(request, env) {
  try {
    const url = new URL(request.url);
    const period = url.searchParams.get('period') || '24h';

    // NOTE: Analytics Engine queries must be done via Cloudflare API/GraphQL
    // Workers only have writeDataPoint() available
    // For now, return instructions on how to query via API

    const metrics = {
      period: period,
      message: 'Analytics Engine queries must be performed via Cloudflare API or GraphQL',
      queryInstructions: {
        method: 'GraphQL',
        endpoint: 'https://api.cloudflare.com/client/v4/graphql',
        sampleQuery: `
query {
  viewer {
    accounts(filter: { accountTag: $accountId }) {
      analyticsEngineDatasets(filter: { name: "books_api_cache_metrics" }) {
        query(
          filter: { timestamp_geq: $startTime }
          orderBy: [timestamp_DESC]
        ) {
          index1
          count
        }
      }
    }
  }
}
        `,
        alternativeSQL: `
SELECT
  index1 as cache_tier,
  COUNT(*) as hits
FROM CACHE_ANALYTICS
WHERE timestamp > NOW() - INTERVAL '${period}'
GROUP BY index1
        `
      },
      realTimeMetrics: {
        note: 'Real-time metrics are written but require external query',
        dataset: 'books_api_cache_metrics',
        indices: ['edge_hit', 'kv_hit', 'cold_check', 'r2_rehydrated', 'api_miss']
      }
    };

    return new Response(JSON.stringify(metrics, null, 2), {
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (error) {
    return new Response(JSON.stringify({
      error: 'Failed to fetch metrics',
      message: error.message
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}
