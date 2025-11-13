# Backend Spin-Out: Manual Tasks Guide

**Date:** November 13, 2025
**Goal:** Configure GitHub secrets for automated CI/CD deployment

---

## Prerequisites ✅

- ✅ Backend repo created: `jukasdrj/bookstrack-backend`
- ✅ Cloudflare logged in (account ID: `d03bed0be6d976acd8a1707b55052f79`)
- ✅ GitHub CLI installed (`gh`)

---

## Task 1: Create Cloudflare API Token

**Time:** 3 minutes

### Steps:

1. **Open Cloudflare Dashboard**
   - Go to: https://dash.cloudflare.com/profile/api-tokens
   - Login if needed

2. **Create New Token**
   - Click **"Create Token"** button (blue button, top right)

3. **Select Template**
   - Find **"Edit Cloudflare Workers"** template
   - Click **"Use template"** button

4. **Configure Token (keep defaults, just verify)**
   - Account Resources: Should show `Jukasdrj@gmail.com's Account - All accounts`
   - Zone Resources: `All zones`
   - Permissions should include:
     - `Account > Workers Scripts > Edit`
     - `Account > Workers KV Storage > Edit`
     - `Zone > Workers Routes > Edit`

5. **Create Token**
   - Scroll to bottom
   - Click **"Continue to summary"**
   - Click **"Create Token"**

6. **IMPORTANT: Copy Token**
   - You'll see a screen with your API token
   - Click **"Copy"** button (looks like two overlapping squares)
   - **⚠️ THIS TOKEN ONLY SHOWS ONCE! Keep it somewhere temporarily**

7. **Save Token to GitHub**
   - Open your terminal
   - Run:
   ```bash
   gh secret set CLOUDFLARE_API_TOKEN --repo jukasdrj/bookstrack-backend
   ```
   - When prompted, **paste the token** you just copied
   - Press Enter

8. **Verify (Optional)**
   - Go to: https://github.com/jukasdrj/bookstrack-backend/settings/secrets/actions
   - You should see `CLOUDFLARE_API_TOKEN` listed

---

## Task 2: Set Cloudflare Account ID

**Time:** 30 seconds

### Steps:

1. **Copy Account ID**
   - Your account ID is: `d03bed0be6d976acd8a1707b55052f79`
   - Copy this value (Command+C)

2. **Set GitHub Secret**
   ```bash
   gh secret set CLOUDFLARE_ACCOUNT_ID --repo jukasdrj/bookstrack-backend
   ```
   - When prompted, paste: `d03bed0be6d976acd8a1707b55052f79`
   - Press Enter

---

## Task 3: Get Google Books API Key

**Time:** 5 minutes (if key exists) OR 10 minutes (if creating new)

### Option A: Use Existing Key from iOS Repo

1. **Check iOS repo for existing key**
   ```bash
   cd ~/Downloads/xcode/books-tracker-v1/cloudflare-workers/api-worker
   grep -r "GOOGLE_BOOKS" wrangler.toml || echo "Not in wrangler.toml"
   ```

2. **If key found, skip to Step 3**

### Option B: Get from Google Cloud Console

1. **Open Google Cloud Console**
   - Go to: https://console.cloud.google.com/
   - Select project: **BooksTrack** (or your project)

2. **Navigate to API Keys**
   - Click hamburger menu (☰) → "APIs & Services" → "Credentials"

3. **Find Existing Key OR Create New**

   **If key exists:**
   - Find "API key" in the list
   - Click "SHOW KEY" or the key name
   - Click "Copy" button

   **If creating new:**
   - Click **"+ CREATE CREDENTIALS"** → "API key"
   - Copy the key that appears
   - Click **"RESTRICT KEY"**
   - Under "API restrictions" → "Restrict key"
   - Select **"Google Books API"** from dropdown
   - Click **"Save"**

4. **Set GitHub Secret**
   ```bash
   gh secret set GOOGLE_BOOKS_API_KEY --repo jukasdrj/bookstrack-backend
   ```
   - Paste the API key
   - Press Enter

---

## Task 4: Get Gemini API Key

**Time:** 3 minutes

### Steps:

1. **Open Google AI Studio**
   - Go to: https://aistudio.google.com/app/apikey
   - Login with your Google account if needed

2. **Find or Create API Key**

   **If you see existing keys:**
   - Look for a key (might be named "Default" or similar)
   - Click the **"Copy"** icon (📋) next to the key

   **If no keys exist:**
   - Click **"Create API Key"**
   - Select "Create API key in existing project"
   - Choose your project
   - Click **"Create API key in [project name]"**
   - Copy the key that appears

3. **Set GitHub Secret**
   ```bash
   gh secret set GEMINI_API_KEY --repo jukasdrj/bookstrack-backend
   ```
   - Paste the API key
   - Press Enter

---

## Task 5: Get ISBNdb API Key

**Time:** 2 minutes

### Steps:

1. **Open ISBNdb Dashboard**
   - Go to: https://isbndb.com/apidocs/v2
   - Login if needed

2. **Copy API Key**
   - Look for your API key on the dashboard
   - It should be displayed prominently
   - Click copy or select and copy (Command+C)

3. **Set GitHub Secret**
   ```bash
   gh secret set ISBNDB_API_KEY --repo jukasdrj/bookstrack-backend
   ```
   - Paste the API key
   - Press Enter

---

## Task 6: Verify All Secrets

**Time:** 1 minute

### Steps:

1. **List GitHub Secrets**
   ```bash
   gh secret list --repo jukasdrj/bookstrack-backend
   ```

2. **Expected Output (should show 5 secrets):**
   ```
   CLOUDFLARE_ACCOUNT_ID      Updated 2025-11-13
   CLOUDFLARE_API_TOKEN       Updated 2025-11-13
   GEMINI_API_KEY             Updated 2025-11-13
   GOOGLE_BOOKS_API_KEY       Updated 2025-11-13
   ISBNDB_API_KEY             Updated 2025-11-13
   ```

3. **Alternative: Check in Browser**
   - Go to: https://github.com/jukasdrj/bookstrack-backend/settings/secrets/actions
   - Verify all 5 secrets are listed

---

## Task 7: Test Deployment

**Time:** 3 minutes

### Steps:

1. **Trigger Manual Deployment**
   ```bash
   gh workflow run deploy-production.yml --repo jukasdrj/bookstrack-backend
   ```

2. **Watch Deployment Progress**
   ```bash
   gh run watch --repo jukasdrj/bookstrack-backend
   ```
   - OR go to: https://github.com/jukasdrj/bookstrack-backend/actions

3. **Wait for Completion**
   - Deployment takes ~1-2 minutes
   - Look for green checkmark ✅

4. **Test Health Endpoint**
   ```bash
   curl https://api.oooefam.net/health
   ```
   - Should return: `{"status":"healthy",...}`

---

## Task 8: Test iOS App Integration

**Time:** 5 minutes

### Steps:

1. **Launch iOS App in Simulator**
   ```bash
   cd ~/Downloads/xcode/books-tracker-v1
   /sim
   ```

2. **Test Book Search**
   - Open app
   - Navigate to "Search" tab
   - Search for: `"The Great Gatsby"`
   - Verify results appear (should show book covers)

3. **Test ISBN Scanner**
   - Navigate to "Search" tab
   - Tap barcode scanner icon
   - Grant camera permission if prompted
   - Scan any book barcode
   - Verify book details appear

4. **Test Bookshelf AI Scanner**
   - Navigate to "Shelf" tab
   - Tap "Scan Bookshelf"
   - Select a test image (or take photo)
   - Verify WebSocket progress appears
   - Verify books are detected

5. **Check for Errors**
   - Look for any error messages
   - Check console logs for 404s or API errors

---

## Troubleshooting

### ❌ Workflow Fails: "Invalid API Token"

**Solution:**
1. Regenerate Cloudflare API token (Task 1)
2. Make sure you select "Edit Cloudflare Workers" template
3. Re-run: `gh secret set CLOUDFLARE_API_TOKEN --repo jukasdrj/bookstrack-backend`

---

### ❌ Workflow Fails: "Account ID not found"

**Solution:**
1. Double-check account ID:
   ```bash
   npx wrangler whoami
   ```
2. Copy the exact Account ID
3. Re-run: `gh secret set CLOUDFLARE_ACCOUNT_ID --repo jukasdrj/bookstrack-backend`

---

### ❌ Deployment Succeeds but API Returns 500 Errors

**Solution:**
1. Check that API keys are correct (not expired)
2. Test each API key manually:
   - Google Books: https://www.googleapis.com/books/v1/volumes?q=gatsby&key=YOUR_KEY
   - Gemini: Check in AI Studio for quota/limits
   - ISBNdb: Check dashboard for remaining credits

---

### ❌ iOS App Shows "Network Error"

**Solution:**
1. Verify backend is deployed:
   ```bash
   curl https://api.oooefam.net/health
   ```
2. Check iOS app is using correct URL:
   ```bash
   grep -r "api.oooefam.net" ~/Downloads/xcode/books-tracker-v1/BooksTrackerPackage/
   ```
3. Rebuild iOS app (Clean Build Folder: Shift+Cmd+K)

---

## Success Checklist

Mark each item when complete:

- [ ] Task 1: Cloudflare API Token created and set
- [ ] Task 2: Cloudflare Account ID set
- [ ] Task 3: Google Books API Key set
- [ ] Task 4: Gemini API Key set
- [ ] Task 5: ISBNdb API Key set
- [ ] Task 6: All 5 secrets verified in GitHub
- [ ] Task 7: Production deployment successful
- [ ] Task 8: iOS app works with backend

---

## Next Steps (After Manual Tasks)

Once all secrets are configured and deployment works:

1. **Monitor for 48 hours**
   - Check error rates in Cloudflare dashboard
   - Monitor API quota usage (Google, ISBNdb)

2. **Clean up iOS repo (Optional)**
   - Archive `cloudflare-workers/` directory
   - Update README to reference backend repo

3. **Document API contract versioning**
   - Ensure iOS DTOs stay in sync with backend

---

**Questions or Issues?**

If you run into problems, check:
1. GitHub Actions logs: https://github.com/jukasdrj/bookstrack-backend/actions
2. Cloudflare Workers logs: `npx wrangler tail api-worker`
3. This guide's troubleshooting section above

---

**Estimated Total Time:** 20-30 minutes
**Last Updated:** November 13, 2025
