#!/bin/bash
# Setup R2 lifecycle rules for automatic deletion

echo "Setting up R2 lifecycle for cold-cache..."

# Create lifecycle rule (deletes objects older than 1 year)
curl -X PUT "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/r2/buckets/personal-library-data/lifecycle" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "rules": [
      {
        "id": "cold-cache-expiration",
        "status": "Enabled",
        "filter": {
          "prefix": "cold-cache/"
        },
        "expiration": {
          "days": 365
        }
      }
    ]
  }'

echo "Lifecycle rule created: cold-cache entries expire after 365 days"
