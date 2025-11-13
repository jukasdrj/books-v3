# Export Setup to Swift Project

This guide shows how to export the optimal GitHub + Zen MCP + Cloudflare setup from this Flutter project to your original Swift `books` project.

---

## What Can Be Exported (95% Compatible)

### ✅ Fully Compatible (Copy Directly)
1. **GitHub Labels System** - Language-agnostic
2. **Zen MCP Configuration** - Works with any codebase
3. **Claude Code Hooks & Prompts** - Adaptable to Swift
4. **Cloudflare Workers Deployment** - Already platform-agnostic
5. **Pre-commit Hooks** - Needs Swift-specific adaptations
6. **GitHub Actions Workflows** - Needs Xcode-specific changes

### 🔄 Needs Adaptation (80% Reusable)
1. **CI/CD Workflows** - SwiftUI → Swift Package Manager / Xcode
2. **Pre-commit Hook** - flutter analyze → swiftlint
3. **Issue Templates** - Component labels (SwiftUI, SwiftData, etc.)

### ❌ Not Applicable
1. Flutter-specific build configs
2. Dart/Flutter dependencies

---

## Step-by-Step Export Guide

### Step 1: Copy GitHub Labels System

The label system is 100% reusable for your Swift project.

```bash
# Navigate to your Swift project
cd /path/to/your/swift/books

# Copy labels configuration
cp /path/to/books-flutter/.github/labels.yml .github/labels.yml

# Copy label creation script
cp /path/to/books-flutter/.github/create_labels.py .github/create_labels.py

# Create all labels
cd .github
python3 create_labels.py
```

**No changes needed!** The labels are platform-agnostic:
- Priority (P0-P3)
- Type (bug, feature, enhancement, perf, security)
- Phase (1-6)
- Platform (ios, macos, web, all)
- Component (will need updates - see Step 2)
- Status (ready, in-progress, blocked, needs-review)
- Effort (XS to XL)

### Step 2: Update Component Labels for Swift

Edit `.github/labels.yml` to replace Flutter components with Swift components:

```yaml
# Replace these Flutter component labels:
- name: "component: database"
  color: "c5def5"
  description: "SwiftData models and persistence"  # Changed from "Drift database layer"

- name: "component: ui"
  color: "c5def5"
  description: "SwiftUI views and components"  # Same concept

- name: "component: api"
  color: "c5def5"
  description: "API integration (Cloudflare Workers)"  # Same!

- name: "component: scanner"
  color: "c5def5"
  description: "VisionKit barcode & AI scanner"  # Changed from Flutter camera

- name: "component: auth"
  color: "c5def5"
  description: "Authentication & authorization"  # Same!

- name: "component: firebase"
  color: "c5def5"
  description: "Firebase services"  # Same!

- name: "component: routing"
  color: "c5def5"
  description: "NavigationStack & routing"  # Changed from go_router

- name: "component: state"
  color: "c5def5"
  description: "@Observable & state management"  # Changed from Riverpod
```

Then re-run the label script to update:

```bash
python3 .github/create_labels.py
```

### Step 3: Copy Zen MCP Configuration

Zen MCP works identically for Swift and Flutter projects.

```bash
# Copy entire Zen MCP setup
cp -r /path/to/books-flutter/.zen /path/to/swift/books/

# The configuration is already optimized:
# - Complex tasks: Gemini 2.5 Pro, GPT-5 Pro, Grok 4
# - Medium tasks: Grok Code, Gemini PC
# - Simple tasks: Haiku (local/free)
```

**No changes needed!** The model selection works for any language.

### Step 4: Copy Claude Code Configuration

```bash
# Copy Claude Code setup
cp -r /path/to/books-flutter/.claude /path/to/swift/books/
```

**Update the pre-commit hook** for Swift:

Edit `.claude/hooks/pre-commit.sh`:

```bash
#!/bin/bash
set -e

echo "🔍 Pre-commit Hook: Running code quality checks..."

# 1. SwiftLint (install: brew install swiftlint)
if command -v swiftlint &> /dev/null; then
    if ! swiftlint lint --strict; then
        echo "❌ SwiftLint found issues. Please fix before committing."
        exit 1
    fi
    echo "✅ SwiftLint passed"
else
    echo "⚠️  SwiftLint not installed. Run: brew install swiftlint"
fi

# 2. Swift Format (install: brew install swift-format)
if command -v swift-format &> /dev/null; then
    swift-format lint --recursive Sources/ Tests/
    echo "✅ Swift format check passed"
else
    echo "⚠️  swift-format not installed. Run: brew install swift-format"
fi

# 3. Run tests (optional - can be slow)
# swift test

# 4. Check for sensitive files
if git diff --cached --name-only | grep -E "google-services\.json|GoogleService-Info\.plist|\.env$|credentials\.json"; then
    echo "❌ ERROR: Attempting to commit sensitive files!"
    echo "Files detected:"
    git diff --cached --name-only | grep -E "google-services\.json|GoogleService-Info\.plist|\.env$|credentials\.json"
    exit 1
fi

# 5. Check for debug statements
if git diff --cached | grep -E "^\+.*print\(|^\+.*debugPrint\(|^\+.*NSLog\("; then
    echo "⚠️  WARNING: Found debug print statements in staged changes."
    echo "Consider removing before committing to main branch."
    # Uncomment to make this fail the commit:
    # exit 1
fi

echo "✅ Pre-commit checks passed!"
```

**Update Claude Code prompts** for Swift:

Edit `.claude/prompts/code-review.md`:

```markdown
# Code Review with Zen MCP

Review the following Swift files with focus on:
{{files}}

**Review Type:** {{review_type}}

**Focus Areas:**
- Code quality and maintainability
- Performance optimization opportunities
- Security vulnerabilities (OWASP Top 10)
- Swift best practices (Swift 6 concurrency, @MainActor, etc.)
- SwiftUI best practices (view composition, state management)
- SwiftData best practices (relationships, migrations)
- iOS Human Interface Guidelines compliance

**Swift-Specific Checks:**
- Proper @MainActor usage for UI updates
- Sendable conformance for concurrency
- Memory management (weak/unowned references, retain cycles)
- Force unwraps (!) vs optional chaining (?.)
- Proper error handling (throws, Result, async/await)

Use Gemini 2.5 Pro or GPT-5 Pro for expert validation.
```

### Step 5: Copy GitHub Issue Templates

```bash
# Copy issue templates
cp -r /path/to/books-flutter/.github/ISSUE_TEMPLATE /path/to/swift/books/.github/
```

**Update platform options** in templates:

Edit `.github/ISSUE_TEMPLATE/feature.yml`:

```yaml
- type: dropdown
  id: platform
  attributes:
    label: Platform
    options:
      - iOS
      - macOS
      - watchOS  # Add if applicable
      - All platforms
    required: true
```

### Step 6: Adapt GitHub Actions CI/CD

Create `.github/workflows/ci.yml` for Swift:

```yaml
name: CI - Swift Build & Test

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]
  workflow_dispatch:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  swiftlint:
    name: SwiftLint
    runs-on: macos-latest
    timeout-minutes: 10

    steps:
      - name: 📥 Checkout repository
        uses: actions/checkout@v4

      - name: 🔍 Run SwiftLint
        run: |
          brew install swiftlint
          swiftlint lint --strict

  test:
    name: Unit & UI Tests
    runs-on: macos-latest
    timeout-minutes: 20

    steps:
      - name: 📥 Checkout repository
        uses: actions/checkout@v4

      - name: 🍎 Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_15.1.app

      - name: 📦 Install dependencies
        run: |
          # If using Swift Package Manager
          swift package resolve

      - name: 🧪 Run tests
        run: |
          xcodebuild test \
            -scheme YourAppScheme \
            -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
            -enableCodeCoverage YES \
            -derivedDataPath DerivedData

      - name: 📊 Generate coverage report
        run: |
          xcrun llvm-cov export \
            -format="lcov" \
            -instr-profile DerivedData/Build/ProfileData/*/Coverage.profdata \
            DerivedData/Build/Products/Debug-iphonesimulator/YourApp.app/YourApp \
            > coverage.lcov

      - name: 📈 Upload coverage to Codecov
        uses: codecov/codecov-action@v3
        with:
          files: ./coverage.lcov
          flags: unittests
          name: codecov-umbrella

  build-ios:
    name: Build iOS
    runs-on: macos-latest
    timeout-minutes: 30
    needs: [swiftlint, test]

    steps:
      - name: 📥 Checkout repository
        uses: actions/checkout@v4

      - name: 🍎 Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_15.1.app

      - name: 🔧 Build for iOS
        run: |
          xcodebuild build \
            -scheme YourAppScheme \
            -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
            -configuration Debug

  build-macos:
    name: Build macOS
    runs-on: macos-latest
    timeout-minutes: 30
    needs: [swiftlint, test]

    steps:
      - name: 📥 Checkout repository
        uses: actions/checkout@v4

      - name: 🍎 Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_15.1.app

      - name: 🔧 Build for macOS
        run: |
          xcodebuild build \
            -scheme YourAppScheme \
            -destination 'platform=macOS' \
            -configuration Debug

  security-scan:
    name: Security Scan
    runs-on: ubuntu-latest
    timeout-minutes: 10

    steps:
      - name: 📥 Checkout repository
        uses: actions/checkout@v4

      - name: 🔐 Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'fs'
          scan-ref: '.'
          format: 'sarif'
          output: 'trivy-results.sarif'

      - name: 📊 Upload Trivy results to GitHub Security
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: 'trivy-results.sarif'
```

### Step 7: Copy Copilot Review Workflow

The Copilot review workflow is 100% reusable:

```bash
cp /path/to/books-flutter/.github/workflows/copilot-review.yml \
   /path/to/swift/books/.github/workflows/copilot-review.yml
```

**Update the Super Linter validation** (line 29-32):

```yaml
env:
  GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  VALIDATE_ALL_CODEBASE: false
  DEFAULT_BRANCH: main
  VALIDATE_SWIFT: true  # Changed from VALIDATE_DART
  VALIDATE_YAML: true
  VALIDATE_JSON: true
  VALIDATE_MARKDOWN: true
```

### Step 8: Copy Cloudflare Deployment

**Good news:** Your Cloudflare Workers API is already platform-agnostic! It works with both Swift and Flutter frontends.

```bash
# Copy Cloudflare workflow (if not already in Swift repo)
cp /path/to/books-flutter/.github/workflows/deploy-cloudflare.yml \
   /path/to/swift/books/.github/workflows/
```

**Update the web deployment section** for Swift (if you have a web version):

```yaml
deploy-web:
  name: Deploy Swift Web to Cloudflare Pages
  runs-on: macos-latest
  # ... (if you're using Swift for WebAssembly or have a web version)
```

Or **remove the deploy-web job** if Swift is iOS/macOS only and just keep the Workers deployment.

### Step 9: Copy Environment Templates

```bash
# Copy .env.example
cp /path/to/books-flutter/.env.example /path/to/swift/books/.env.example

# Update .gitignore (add if not present)
cat >> /path/to/swift/books/.gitignore <<EOF

# Environment variables (API keys)
.env

# Zen MCP (AI provider keys)
.zen/cache/
.zen/logs/
.zen/.session

# Claude Code
.claude/.session
.claude/cache/

# Firebase configuration files (contain API keys)
**/GoogleService-Info.plist
**/google-services.json
EOF
```

### Step 10: Copy Documentation

```bash
# Copy setup guides
cp /path/to/books-flutter/GITHUB_ZEN_SETUP.md /path/to/swift/books/
cp /path/to/books-flutter/WORKFLOW_SUMMARY.md /path/to/swift/books/
cp /path/to/books-flutter/.github/CLOUDFLARE_SETUP.md /path/to/swift/books/.github/
```

**Update technology references** in the docs:
- Change "Flutter" → "Swift/SwiftUI"
- Change "Riverpod" → "@Observable"
- Change "Drift" → "SwiftData"
- Change "go_router" → "NavigationStack"

---

## Quick Export Script

**The export script is already created!** Just run:

```bash
cd /Users/justingardner/Downloads/vscode/books-flutter
./export-to-swift.sh
```

**For other projects** (not just Swift), use the same script:

```bash
# Export to any project
cd /Users/justingardner/Downloads/vscode/books-flutter
./export-to-swift.sh

# When prompted, enter target project path:
# - Swift project: /path/to/books-swift
# - React project: /path/to/other-react-app
# - Python project: /path/to/python-api
# - Any project: /path/to/any-repo
```

**The script will copy:**

1. GitHub Labels (100% compatible with any language)
2. Zen MCP config (works for any codebase)
3. Claude Code setup (needs language-specific pre-commit hook)
4. Issue templates
5. Copilot workflows
6. Documentation

**Script contents (already created at `export-to-swift.sh`):**

```bash
#!/bin/bash
# Already exists! Just run: ./export-to-swift.sh
echo "📋 Copying GitHub labels..."
mkdir -p "$SWIFT_PROJECT/.github"
cp "$FLUTTER_PROJECT/.github/labels.yml" "$SWIFT_PROJECT/.github/"
cp "$FLUTTER_PROJECT/.github/create_labels.py" "$SWIFT_PROJECT/.github/"

# 2. Copy Zen MCP
echo "🤖 Copying Zen MCP configuration..."
cp -r "$FLUTTER_PROJECT/.zen" "$SWIFT_PROJECT/"

# 3. Copy Claude Code
echo "🔧 Copying Claude Code configuration..."
cp -r "$FLUTTER_PROJECT/.claude" "$SWIFT_PROJECT/"

# 4. Copy Issue Templates
echo "📝 Copying issue templates..."
mkdir -p "$SWIFT_PROJECT/.github/ISSUE_TEMPLATE"
cp -r "$FLUTTER_PROJECT/.github/ISSUE_TEMPLATE/"* "$SWIFT_PROJECT/.github/ISSUE_TEMPLATE/"

# 5. Copy Workflows (you'll need to adapt these)
echo "⚙️  Copying workflows (needs manual adaptation)..."
cp "$FLUTTER_PROJECT/.github/workflows/copilot-review.yml" "$SWIFT_PROJECT/.github/workflows/"
cp "$FLUTTER_PROJECT/.github/workflows/deploy-cloudflare.yml" "$SWIFT_PROJECT/.github/workflows/"

# 6. Copy environment template
echo "🔐 Copying .env.example..."
cp "$FLUTTER_PROJECT/.env.example" "$SWIFT_PROJECT/"

# 7. Copy documentation
echo "📚 Copying documentation..."
cp "$FLUTTER_PROJECT/GITHUB_ZEN_SETUP.md" "$SWIFT_PROJECT/"
cp "$FLUTTER_PROJECT/WORKFLOW_SUMMARY.md" "$SWIFT_PROJECT/"
cp "$FLUTTER_PROJECT/.github/CLOUDFLARE_SETUP.md" "$SWIFT_PROJECT/.github/"

echo "✅ Export complete!"
echo ""
echo "Next steps:"
echo "1. Update component labels in .github/labels.yml for Swift"
echo "2. Run: cd $SWIFT_PROJECT/.github && python3 create_labels.py"
echo "3. Update pre-commit hook in .claude/hooks/pre-commit.sh for Swift"
echo "4. Adapt CI workflow in .github/workflows/ci.yml for Xcode"
echo "5. Update documentation to reference Swift instead of Flutter"
echo "6. Copy .env.example to .env and add your API keys"
```

Make it executable and run:

```bash
chmod +x export-to-swift.sh
./export-to-swift.sh
```

---

## Post-Export Checklist

After running the export, complete these manual steps:

### GitHub Setup
- [ ] Update component labels in `.github/labels.yml` for Swift
- [ ] Run label creation script: `python3 .github/create_labels.py`
- [ ] Update issue templates for Swift-specific platforms
- [ ] Test issue creation with new templates

### Zen MCP Setup
- [ ] Verify `.zen/conf/providers.yml` (no changes needed)
- [ ] Copy `.env.example` to `.env`
- [ ] Add API keys to `.env`
- [ ] Test Zen MCP: `claude` in terminal (if installed)

### Claude Code Setup
- [ ] Update `.claude/hooks/pre-commit.sh` for SwiftLint
- [ ] Install SwiftLint: `brew install swiftlint`
- [ ] Install swift-format: `brew install swift-format`
- [ ] Link pre-commit hook: `ln -sf ../../.claude/hooks/pre-commit.sh .git/hooks/pre-commit`
- [ ] Update `.claude/prompts/*.md` for Swift-specific checks
- [ ] Test pre-commit hook

### GitHub Actions Setup
- [ ] Create Swift-specific CI workflow (`.github/workflows/ci.yml`)
- [ ] Update Copilot review workflow for Swift validation
- [ ] Add GitHub secrets (same as Flutter project)
- [ ] Update Cloudflare deployment (Workers only, no iOS web build)
- [ ] Test workflows on a test branch

### Documentation
- [ ] Update `GITHUB_ZEN_SETUP.md` references (Flutter → Swift)
- [ ] Update `WORKFLOW_SUMMARY.md` tech stack
- [ ] Update `CLOUDFLARE_SETUP.md` if needed
- [ ] Add Swift-specific notes to `CLAUDE.md`

### Security
- [ ] Verify `.gitignore` includes `.env`, Firebase configs, Zen cache
- [ ] Rotate API keys if exposed during export
- [ ] Test pre-commit hook blocks sensitive files

---

## Differences: Swift vs Flutter

### Build Tools
- **Flutter:** `flutter build`, `dart run build_runner`
- **Swift:** `xcodebuild`, `swift build`, Xcode Cloud

### Linting
- **Flutter:** `flutter analyze`, `dart format`
- **Swift:** `swiftlint`, `swift-format`

### Testing
- **Flutter:** `flutter test --coverage`
- **Swift:** `xcodebuild test`, `swift test`

### Package Management
- **Flutter:** `pubspec.yaml`, `flutter pub get`
- **Swift:** `Package.swift`, `swift package resolve` or CocoaPods/Carthage

### CI/CD
- **Flutter:** Works on ubuntu-latest
- **Swift:** Requires macos-latest (for Xcode)

---

## Cost Comparison

### Flutter Project (Current)
- **GitHub Actions:** ~100 min/month (free tier: 2000 min)
- **Cloudflare Pages:** Free
- **Cloudflare Workers:** $5/month
- **Zen MCP API costs:** ~$2-5/month (with Haiku optimization)
- **Total:** ~$7-10/month

### Swift Project (After Export)
- **GitHub Actions:** ~150 min/month (macOS runners: 10x multiplier)
- **Cloudflare Workers:** $5/month (same backend)
- **Zen MCP API costs:** ~$2-5/month (same models)
- **TestFlight/App Store:** $99/year (Apple Developer)
- **Total:** ~$7-10/month + $99/year

**Note:** macOS runners consume minutes 10x faster, but still within free tier.

---

## Recommended Adaptations

### 1. SwiftLint Configuration

Create `.swiftlint.yml`:

```yaml
disabled_rules:
  - trailing_whitespace
opt_in_rules:
  - empty_count
  - explicit_init
  - first_where
  - closure_spacing
  - force_unwrapping
  - implicitly_unwrapped_optional
included:
  - Sources
excluded:
  - Pods
  - DerivedData
  - .build
line_length: 120
```

### 2. Swift-Specific Claude Prompts

Add `.claude/prompts/swift-review.md`:

```markdown
# Swift Code Review

Review Swift code with focus on:

**Swift 6 Concurrency:**
- [ ] Proper @MainActor usage for UI updates
- [ ] Sendable conformance for shared mutable state
- [ ] Task priority and cancellation
- [ ] AsyncSequence for streams

**SwiftUI Best Practices:**
- [ ] View composition over massive views
- [ ] @State, @Binding, @Observable usage
- [ ] PreferenceKey for child-to-parent communication
- [ ] Avoid GeometryReader when possible

**SwiftData Best Practices:**
- [ ] Relationships (cascade deletes)
- [ ] Migration strategies
- [ ] Predicate and FetchDescriptor usage
- [ ] @Query performance

**Memory Management:**
- [ ] Weak/unowned references to avoid retain cycles
- [ ] Capture lists in closures
- [ ] Deinit checks for cleanup

Use Gemini 2.5 Pro for expert validation.
```

### 3. Update Copilot Suggestions

In `.github/workflows/copilot-review.yml`, update the comment body:

```javascript
const body = `## 🤖 Copilot Code Review

**Files Changed:** ${files.length}
**Swift Files:** ${swiftFiles.length}

### ✅ Automated Checks Passed
- SwiftLint validation
- Code formatting
- Security scan

### 💡 Copilot Suggestions for Swift
- Use Copilot Chat to review complex SwiftUI views
- Ask Copilot for Swift 6 concurrency patterns
- Check Copilot security suggestions for vulnerabilities

**Tip:** Use \`@github-copilot\` in Xcode to get real-time SwiftUI suggestions.
`;
```

---

## Benefits of This Setup for Swift

1. **Consistent Workflow Across Projects**
   - Same labels, same processes
   - Same AI tools (Zen MCP)
   - Same Cloudflare backend

2. **Team Collaboration**
   - Friends can review both projects with familiar labels
   - Same issue tracking structure
   - Shared knowledge base

3. **Cost Optimization**
   - Single Cloudflare Workers deployment serves both apps
   - Single Zen MCP config with optimized model selection
   - Shared API keys

4. **Quality Assurance**
   - Pre-commit hooks prevent bad commits
   - Automated testing on every PR
   - AI-powered code reviews

5. **Deployment Automation**
   - TestFlight deployment via GitHub Actions (can add)
   - App Store submission automation (can add)
   - Same Cloudflare Workers deployment

---

## Next Steps After Export

1. **Test the Setup**
   ```bash
   # Create a test branch
   git checkout -b test-new-workflow

   # Make a small change
   echo "// Test" >> Sources/YourApp/ContentView.swift

   # Try to commit (pre-commit hook should run)
   git add .
   git commit -m "test: workflow setup"

   # Push and create PR (CI should run)
   git push -u origin test-new-workflow
   gh pr create
   ```

2. **Configure Xcode Cloud (Optional)**
   - Alternative to GitHub Actions
   - Integrated with App Store Connect
   - Can run alongside GitHub Actions

3. **Set Up TestFlight Automation**
   - Add Fastlane configuration
   - Automate beta deployments
   - Integrate with GitHub releases

4. **Migrate Existing Issues**
   - Apply new labels to existing issues
   - Close duplicates
   - Organize backlog by phase

---

**Last Updated:** November 12, 2025
**Export Compatibility:** 95% (5% needs Swift-specific adaptation)
**Estimated Export Time:** 2-3 hours (including testing)
