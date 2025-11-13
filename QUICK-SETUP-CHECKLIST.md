# Backend Spin-Out: Quick Setup Checklist

**Total Time:** ~20-30 minutes

---

## 📋 Quick Commands Reference

Copy and run these in order. Full instructions in `BACKEND-SPINOUT-MANUAL-TASKS.md`

### 1️⃣ Cloudflare API Token (3 min)

**Browser:** https://dash.cloudflare.com/profile/api-tokens
- Click "Create Token"
- Use "Edit Cloudflare Workers" template
- Create & copy token

**Terminal:**
```bash
gh secret set CLOUDFLARE_API_TOKEN --repo jukasdrj/bookstrack-backend
# Paste token when prompted
```

---

### 2️⃣ Cloudflare Account ID (30 sec)

**Terminal:**
```bash
gh secret set CLOUDFLARE_ACCOUNT_ID --repo jukasdrj/bookstrack-backend
# Paste: d03bed0be6d976acd8a1707b55052f79
```

---

### 3️⃣ Google Books API Key (5 min)

**Browser:** https://console.cloud.google.com/apis/credentials
- Find or create API key
- Restrict to "Google Books API"
- Copy key

**Terminal:**
```bash
gh secret set GOOGLE_BOOKS_API_KEY --repo jukasdrj/bookstrack-backend
# Paste key when prompted
```

---

### 4️⃣ Gemini API Key (3 min)

**Browser:** https://aistudio.google.com/app/apikey
- Find or create API key
- Copy key

**Terminal:**
```bash
gh secret set GEMINI_API_KEY --repo jukasdrj/bookstrack-backend
# Paste key when prompted
```

---

### 5️⃣ ISBNdb API Key (2 min)

**Browser:** https://isbndb.com/apidocs/v2
- Copy your API key from dashboard

**Terminal:**
```bash
gh secret set ISBNDB_API_KEY --repo jukasdrj/bookstrack-backend
# Paste key when prompted
```

---

## ✅ Verify Setup

```bash
# List all secrets (should show 5)
gh secret list --repo jukasdrj/bookstrack-backend

# Trigger deployment
gh workflow run deploy-production.yml --repo jukasdrj/bookstrack-backend

# Watch deployment (or check GitHub Actions page)
gh run watch --repo jukasdrj/bookstrack-backend

# Test health endpoint
curl https://api.oooefam.net/health
```

---

## 🧪 Test iOS App

```bash
cd ~/Downloads/xcode/books-tracker-v1
/sim
```

**In Simulator:**
1. Search for "The Great Gatsby" → should show results
2. Scan a barcode → should show book
3. AI bookshelf scan → should detect books

---

## 🆘 Quick Troubleshooting

**Workflow fails?**
- Check: https://github.com/jukasdrj/bookstrack-backend/actions

**API returns errors?**
- Check keys aren't expired (especially Gemini)
- Verify ISBNdb has credits remaining

**iOS app shows network error?**
- Verify: `curl https://api.oooefam.net/health`
- Rebuild iOS app: Shift+Cmd+K, then Cmd+B

---

## 📝 Progress Tracker

Mark as you complete:

- [ ] Cloudflare API Token set
- [ ] Cloudflare Account ID set
- [ ] Google Books API Key set
- [ ] Gemini API Key set
- [ ] ISBNdb API Key set
- [ ] All 5 secrets verified
- [ ] Deployment successful
- [ ] iOS app tested

**See full guide:** `BACKEND-SPINOUT-MANUAL-TASKS.md`
