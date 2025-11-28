# SDK Publishing Instructions

**Quick reference for publishing `@jukasdrj/bookstrack-api-client` to npm and GitHub Packages**

---

## 🚀 Quick Publish (Manual)

### To npm (Recommended for Frontend Teams)

```bash
# 1. Log in to npm (one-time setup)
npm login

# 2. Navigate to SDK directory
cd packages/api-client

# 3. Build and publish
npm run prepublishOnly
npm publish
```

**Result:** `npm install @jukasdrj/bookstrack-api-client` works globally

---

### To GitHub Packages (Backup)

```bash
# 1. Set GitHub token
export GITHUB_TOKEN=ghp_your_token_here

# 2. Navigate to SDK directory
cd packages/api-client

# 3. Use GitHub-specific config
cp .npmrc-github .npmrc

# 4. Temporarily update package.json
node -e "
  const pkg = require('./package.json');
  pkg.publishConfig = { registry: 'https://npm.pkg.github.com' };
  require('fs').writeFileSync('package.json', JSON.stringify(pkg, null, 2));
"

# 5. Build and publish
npm run prepublishOnly
npm publish

# 6. Restore original config
git checkout package.json .npmrc
```

**Result:** Package available at GitHub Packages (requires `.npmrc` for installation)

---

## 🤖 Automated Publishing (GitHub Actions)

### Setup (One-Time)

1. **Add npm token to GitHub Secrets:**
   - Go to https://github.com/jukasdrj/bendv3/settings/secrets/actions
   - Click "New repository secret"
   - Name: `NPM_TOKEN`
   - Value: Your npm access token (create at https://www.npmjs.com/settings/tokens)

2. **Workflow is ready:** `.github/workflows/publish-sdk.yml` is already configured

### Publishing via GitHub Actions

**Option 1: Automatic (on code changes)**
```bash
# Any push to main that changes these files triggers auto-publish:
# - packages/api-client/**
# - docs/openapi.yaml

git add packages/api-client
git commit -m "feat: Update SDK types"
git push origin main
# → SDK auto-publishes to npm
```

**Option 2: Manual trigger**
1. Go to https://github.com/jukasdrj/bendv3/actions/workflows/publish-sdk.yml
2. Click "Run workflow"
3. Select registry:
   - `npm` - Publish to npm only
   - `github` - Publish to GitHub Packages only
   - `both` - Publish to both registries

---

## 📦 Version Management

### Bump Version Before Publishing

```bash
cd packages/api-client

# Patch release (1.0.0 → 1.0.1) - Bug fixes
npm version patch

# Minor release (1.0.0 → 1.1.0) - New features
npm version minor

# Major release (1.0.0 → 2.0.0) - Breaking changes
npm version major

# Then publish
npm publish
```

**GitHub Actions workflow will respect the version in `package.json`**

---

## ✅ Pre-Publish Checklist

Before publishing, ensure:

- [ ] OpenAPI spec is up-to-date (`docs/openapi.yaml`)
- [ ] SDK types are regenerated (`npm run generate`)
- [ ] Build succeeds (`npm run build`)
- [ ] Version is bumped (`npm version patch/minor/major`)
- [ ] README is updated with examples
- [ ] `FRONTEND_HANDOFF.md` reflects current version

**The `prepublishOnly` script runs these automatically:**
```json
"prepublishOnly": "npm run generate && npm run build"
```

---

## 🧪 Testing Before Publishing

```bash
cd packages/api-client

# 1. Create a tarball (doesn't publish)
npm pack

# 2. Test installation in a separate project
cd /tmp/test-project
npm install /path/to/bendv3/packages/api-client/jukasdrj-bookstrack-api-client-1.0.0.tgz

# 3. Test imports
node -e "const client = require('@jukasdrj/bookstrack-api-client'); console.log(client)"
```

---

## 📊 Publishing Status

**Check npm:**
```bash
npm view @jukasdrj/bookstrack-api-client
```

**Check GitHub Packages:**
```bash
npm view @jukasdrj/bookstrack-api-client --registry=https://npm.pkg.github.com
```

---

## 🐛 Troubleshooting

### Error: `need auth`

**Solution:**
```bash
npm login
# Or for GitHub Packages:
export GITHUB_TOKEN=ghp_your_token_here
```

### Error: `Cannot publish over existing version`

**Solution:** Bump version first:
```bash
npm version patch
npm publish
```

### Error: `403 Forbidden`

**Solutions:**
- **npm:** Verify you own the `@jukasdrj` scope or use a different scope
- **GitHub:** Ensure `GITHUB_TOKEN` has `write:packages` permission

### Error: `EPUBLISHCONFLICT`

**Solution:** Package name collision. Change `name` in `package.json` to something unique.

---

## 🔐 Security Notes

**npm token:**
- Create at https://www.npmjs.com/settings/tokens
- Use "Automation" token type for CI/CD
- Store in GitHub Secrets, never commit to code

**GitHub token:**
- Personal Access Token with `write:packages` scope
- Or use automatic `GITHUB_TOKEN` in Actions (already configured)

---

## 📞 Support

**Issues:** https://github.com/jukasdrj/bendv3/issues

**npm registry:** https://www.npmjs.com/package/@jukasdrj/bookstrack-api-client

**GitHub Packages:** https://github.com/jukasdrj/bendv3/packages

---

**Last Updated:** November 28, 2025
