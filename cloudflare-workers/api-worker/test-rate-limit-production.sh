#!/bin/bash
# Test rate limiting in production

echo "Testing rate limiting on production endpoint..."
echo "Sending 12 requests to /api/enrichment/start"
echo ""

for i in $(seq 1 12); do
  response=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "{\"jobId\":\"test-$i\",\"workIds\":[\"test\"]}" \
    https://api-worker.jukasdrj.workers.dev/api/enrichment/start \
    -w "\n%{http_code}")

  status_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  echo "Request $i: HTTP $status_code"

  if [ "$status_code" = "429" ]; then
    echo "  ✅ Rate limit triggered at request $i!"
    echo "  Error message: $(echo "$body" | jq -r '.error')"
    echo "  Retry after: $(echo "$body" | jq -r '.details.retryAfter') seconds"
    exit 0
  fi

  sleep 0.3
done

echo ""
echo "⚠️  Rate limit was NOT triggered after 12 requests"
echo "This may indicate the rate limiter is not working correctly."
exit 1
