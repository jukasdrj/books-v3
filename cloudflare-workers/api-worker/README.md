# API Worker

Cloudflare Worker monolith for BooksTrack backend services.

## Architecture

Single monolith worker combining:
- Book search (ISBNdb, Google Books, OpenLibrary)
- AI bookshelf scanning (Gemini 2.0 Flash)
- CSV import with AI parsing
- Batch enrichment
- WebSocket progress tracking

See `MONOLITH_ARCHITECTURE.md` for architecture details.

## Tasks

### Cover Harvest Task

One-time harvest of ISBNdb cover images before subscription expires.

See [docs/HARVEST_COVERS.md](docs/HARVEST_COVERS.md) for details.

```bash
npx wrangler dev --remote --task harvest-covers
```

## Development

```bash
# Install dependencies
npm install

# Run locally
npx wrangler dev

# Deploy
npx wrangler deploy

# View logs
npx wrangler tail
```

## Related Documentation

- `/cloudflare-workers/MONOLITH_ARCHITECTURE.md` - Architecture overview
- `/docs/features/` - Feature-specific documentation
- `/CLAUDE.md` - Project standards and guidelines
