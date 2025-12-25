# Cross-Repository Reference

This project is part of the BooksTrack ecosystem.

## System Architecture

See **`~/dev_repos/bendv3/docs/SYSTEM_ARCHITECTURE.md`** for:
- System topology diagram
- Service communication patterns
- Cloudflare bindings reference
- Deployment order

## Related Repositories

| Repo | Purpose | Docs |
|------|---------|------|
| **bendv3** | API gateway, user data, caching | `~/dev_repos/bendv3/CLAUDE.md` |
| **alex** | Book metadata, covers, PostgreSQL | `~/dev_repos/alex/CLAUDE.md` |
| **books-v3** (this repo) | iOS frontend | `CLAUDE.md` (this repo) |

## Quick Navigation

```bash
# Jump to system architecture
cat ~/dev_repos/bendv3/docs/SYSTEM_ARCHITECTURE.md

# Read other repo contexts
cat ~/dev_repos/alex/CLAUDE.md
cat ~/dev_repos/bendv3/CLAUDE.md
```

## API Contract

The iOS app communicates with bendv3 via:
- **Endpoint:** `https://api.oooefam.net/v3/*`
- **Spec:** `https://api.oooefam.net/v3/openapi.json`
- **Local copy:** `docs/openapi-v3.json` (for offline reference)
