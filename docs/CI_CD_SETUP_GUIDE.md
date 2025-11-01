# CI/CD Setup Guide for BooksTrack

**Last Updated:** October 31, 2025
**Status:** Not Configured (Manual verification only)

## What is CI/CD?

**CI/CD = Continuous Integration / Continuous Deployment**

Think of it as an **automated quality gate** that checks every code change before it can be merged.

### 🤖 Continuous Integration (CI)

**Simple Definition:** Automatically build and test code when someone creates a Pull Request

**Real-World Analogy:**
- **Without CI:** You're a pilot who only checks the plane's instruments after takeoff (too late!)
- **With CI:** Automated pre-flight checklist runs before every flight (catches problems early)

**What CI Does:**
1. Developer creates Pull Request
2. **GitHub automatically runs:** Build + Tests + Linting
3. **If anything fails:** ❌ PR blocked, can't merge
4. **If everything passes:** ✅ PR approved for merge

### 🚀 Continuous Deployment (CD)

**Simple Definition:** Automatically deploy/release your app when tests pass

**For BooksTrack:**
- Auto-upload to TestFlight after merging to `main`
- Auto-deploy Cloudflare Workers backend
- Auto-generate release notes

---

## Why BooksTrack Needs CI

### Recent Incident (October 31, 2025)

**What happened WITHOUT CI:**
```
1. Commit 14f55b9: Change API signatures
2. PR #165 (jules bot): Merges code using OLD signatures
3. Result: Main branch broken (3 build errors)
4. Impact: All developers blocked
```

**What WOULD happen WITH CI:**
```
1. Commit 14f55b9: Change API signatures
2. PR #165 (jules bot): Attempts merge
3. CI Build: ❌ FAILS (API mismatch detected)
4. GitHub: Blocks merge until fixed
5. Result: Main branch NEVER broken
```

### Benefits for Your Project

✅ **Catch Swift 6 concurrency violations** (MainActor, Sendable)
✅ **Enforce zero-warnings policy** (project standard)
✅ **Prevent API signature mismatches** (today's issue)
✅ **Validate CloudKit schema changes**
✅ **Test against iOS 26 APIs**
✅ **Verify SwiftData relationships** (insert-before-relate pattern)

---

## Quick Setup (5 Minutes)

### Step 1: Create GitHub Actions Workflow

Create file: `.github/workflows/build.yml`

```yaml
name: Build & Test

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    name: Build BooksTrack
    runs-on: macos-14  # macOS with Xcode 16.1

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.1.app

      - name: Build for iOS Simulator
        run: |
          xcodebuild build \
            -scheme BooksTracker \
            -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.0' \
            -quiet

      - name: Run Swift Tests
        run: |
          xcodebuild test \
            -scheme BooksTracker \
            -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.0' \
            -quiet
```

### Step 2: Enable Branch Protection

1. Go to: `Settings → Branches → Branch protection rules`
2. Add rule for `main` branch:
   - ✅ Require status checks to pass
   - ✅ Require branches to be up to date
   - ✅ Select check: `Build BooksTrack`
3. Save changes

### Step 3: Test It!

1. Create a test PR (change a comment)
2. Watch GitHub Actions run automatically
3. Verify green checkmark appears
4. Merge only if checks pass

---

## Advanced Configuration (Optional)

### Add Cloudflare Worker Deployment

```yaml
jobs:
  deploy-backend:
    name: Deploy Cloudflare Workers
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'

    steps:
      - uses: actions/checkout@v4

      - name: Deploy to Cloudflare
        uses: cloudflare/wrangler-action@v3
        with:
          apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          workingDirectory: 'cloudflare-workers/api-worker'
```

### Add TestFlight Upload

```yaml
jobs:
  testflight:
    name: Upload to TestFlight
    runs-on: macos-14
    if: github.ref == 'refs/heads/main'

    steps:
      - uses: actions/checkout@v4

      - name: Build for App Store
        run: xcodebuild archive -scheme BooksTracker ...

      - name: Upload to TestFlight
        uses: apple-actions/upload-testflight-build@v1
        with:
          app-path: BooksTracker.ipa
          issuer-id: ${{ secrets.APPSTORE_ISSUER_ID }}
          api-key-id: ${{ secrets.APPSTORE_API_KEY_ID }}
          api-private-key: ${{ secrets.APPSTORE_API_PRIVATE_KEY }}
```

---

## Cost

**GitHub Actions Free Tier:**
- 2,000 minutes/month for macOS runners (free for public repos)
- Your project: ~5 min/build × 20 PRs/month = **100 minutes** (well within free tier)

**Cloudflare Workers:**
- 100,000 requests/day free
- Deployment bandwidth: Free

**Total Cost:** $0/month for your current usage

---

## Common Questions

### Q: Will CI slow down development?

**A:** No! CI runs in parallel while you work. Typical build time: 3-5 minutes.

```
You create PR → Go get coffee → Come back → CI passed ✅
```

### Q: What if CI fails?

**A:** GitHub blocks the merge and shows you the error:

```
Build Failed ❌
Line 42: Missing argument for parameter 'context'
Click to see full logs →
```

You fix it, push again, CI re-runs automatically.

### Q: Can I skip CI for urgent fixes?

**A:** You can bypass (not recommended), but better approach:

```bash
# Quick fix + CI in parallel
git commit -m "hotfix: critical bug"
git push  # CI starts building
# If CI passes (5 min), merge immediately
# If CI fails, fix before merge (prevents breaking main)
```

---

## Success Metrics

Track these after enabling CI:

- **Main branch build failures:** Should drop to 0
- **Time to detect breaking changes:** 5 min (instead of hours/days)
- **Developer productivity:** Increases (less time debugging merge conflicts)
- **Code quality:** Improves (automated enforcement of standards)

---

## Next Steps

1. **Week 1:** Enable basic build checks (build.yml above)
2. **Week 2:** Add Swift Testing (`xcodebuild test`)
3. **Week 3:** Add SwiftLint for code style
4. **Week 4:** Add Cloudflare Worker deployment
5. **Month 2:** Add TestFlight automation

**Start simple, add more over time!**

---

## Related Documentation

- [GitHub Actions for iOS](https://docs.github.com/en/actions/automating-builds-and-tests/building-and-testing-swift)
- [Xcode Cloud vs GitHub Actions](https://developer.apple.com/xcode-cloud/)
- [Cloudflare Wrangler GitHub Action](https://github.com/cloudflare/wrangler-action)

---

**Questions?** Create a GitHub issue with label `ci-cd-setup`

🤖 This guide was generated by Claude Code based on BooksTrack's actual needs.
