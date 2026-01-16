# Planning Systems Setup Guide

**Repo:** books-v3 (iOS Swift app for BooksTrack)

**Status:** Dual planning system configured (native + plugin)

---

## Architecture Overview

This repository uses TWO planning systems that complement each other:

```
User Request
     |
     v
┌─────────────────────────────────────┐
│   Claude Code Request Router        │
│   (Keyword Analysis)                │
└─────────────────────────────────────┘
     |                    |
     v                    v
┌──────────────┐    ┌──────────────────────┐
│ Simple Task  │    │  Complex Task        │
│ (1-2 steps)  │    │  (3+ steps/phases)   │
└──────────────┘    └──────────────────────┘
     |                    |
     v                    v
┌──────────────┐    ┌──────────────────────┐
│ Native Plans │    │  planning-with-files │
│   (.md)      │    │  (task_plan.md +     │
│              │    │   findings.md +      │
│              │    │   progress.md)       │
└──────────────┘    └──────────────────────┘
     |                    |
     +────────┬───────────+
              v
    .claude/plans/ (unified storage)
```

---

## System 1: Native Claude Code Plans

### What It Is
Built-in planning mode shipped with Claude Code (v2.0.0+).

### When It's Used
Automatically triggered for simple, linear tasks:
- Bug fixes in a single file
- Adding a computed property
- UI tweaks (color, spacing, font)
- Straightforward refactoring

### What It Creates
Single markdown file in `.claude/plans/`:
```
.claude/plans/fix-book-cover-layout.md
```

### File Format
```markdown
# Task: Fix Book Cover Layout

## Goal
Adjust BookCoverView aspect ratio from 2:3 to 3:4

## Steps
1. Update aspectRatio modifier in BookCoverView.swift
2. Test in SwiftUI preview
3. Verify on device

## Files Modified
- BooksTracker/Views/BookCoverView.swift

## Status
Completed 2026-01-16
```

### Configuration
Configured via `.claude/settings.json`:
```json
{
  "plansDirectory": ".claude/plans"
}
```

No additional setup required (built-in feature).

---

## System 2: planning-with-files Plugin

### What It Is
Third-party plugin implementing Manus-style planning (Anthropic research project).

### When It's Used
Explicitly triggered for complex, multi-phase tasks:
- Feature implementations across multiple files
- Architectural migrations (Core Data → SwiftData)
- Performance optimization requiring analysis
- CloudKit integration with sync logic

### Trigger Keywords (Auto-Detection)
See `.claude/rules/planning-automation.md`:
- "implement feature"
- "multi-step"
- "phase"
- "migration"
- "refactor"
- "redesign"

### What It Creates
Structured directory with 3 files:
```
.claude/plans/cloudkit-sync/
  ├── task_plan.md    # Phase breakdown, dependencies
  ├── findings.md     # Research notes, decisions
  └── progress.md     # Completion tracking
```

### File Formats

**task_plan.md:**
```markdown
# Task: Implement CloudKit Sync

## Overview
Add CloudKit sync for book collection with conflict resolution

## Dependencies
- CloudKit entitlement enabled in Xcode
- iCloud container configured
- CKContainer.default() accessible

## Phase 1: Schema Design
- [ ] Define Book record type
- [ ] Define Author record type
- [ ] Set up relationships

## Phase 2: Sync Engine
- [ ] Implement CKSyncEngine wrapper
- [ ] Handle create/update/delete operations
- [ ] Add conflict resolution (last-write-wins)

## Phase 3: UI Integration
- [ ] Add sync status indicator
- [ ] Handle network errors gracefully
- [ ] Show sync conflicts to user

## Testing Strategy
- Unit tests: CKRecord conversion (quick-validate)
- Integration tests: Mock CKDatabase (sim-safe)
- E2E tests: Real CloudKit backend (device-deploy)
```

**findings.md:**
```markdown
# CloudKit Sync - Research & Decisions

## CKSyncEngine vs Manual Sync (2024-01-16)

### Research
- WWDC 2023: Introducing CKSyncEngine
- Replaces manual change tracking
- Handles zone fetching, conflict resolution

### Decision
Use CKSyncEngine (iOS 17+) instead of manual CKFetchRecordZoneChangesOperation.

**Rationale:**
- Less boilerplate (Apple handles change tracking)
- Built-in conflict resolution
- Automatic retry logic

**Trade-off:**
Requires iOS 17 minimum (acceptable - app targets iOS 17+)

## Record Type Design (2024-01-16)

### Option A: Flat Structure
- Single "Book" record with all fields
- Pros: Simple, fewer relationships
- Cons: Duplicate author data

### Option B: Normalized Structure
- Separate "Book" and "Author" records
- Pros: No data duplication, easier author queries
- Cons: More complex sync logic

### Decision: Option B (Normalized)
- Author data is stable (rarely changes)
- Enables author-based queries (find all books by author)
- CloudKit relationships are efficient
```

**progress.md:**
```markdown
# CloudKit Sync - Progress Tracking

## Overall Status: 2/3 Phases Complete (66%)

### ✅ Phase 1: Schema Design (Completed 2024-01-16)
- Book record type defined (title, isbn, coverURL)
- Author record type defined (name, authorID)
- Relationship set up: Book.author → Author

**Files Modified:**
- CloudKit Dashboard: Record types configured
- BooksTracker/Models/CloudKitSchema.swift (added)

### ✅ Phase 2: Sync Engine (Completed 2024-01-17)
- CKSyncEngineWrapper actor implemented
- CRUD operations working
- Conflict resolution: last-write-wins strategy

**Files Modified:**
- BooksTracker/CloudKit/CKSyncEngineWrapper.swift (added)
- BooksTracker/CloudKit/CKRecordConversion.swift (added)
- BooksTrackerTests/CloudKitTests.swift (added)

**Test Results:**
- 34/34 unit tests passing (quick-validate)
- 12/12 integration tests passing (sim-safe)

### 🚧 Phase 3: UI Integration (In Progress)
**Started:** 2024-01-18

**Completed:**
- [x] Sync status indicator added to SettingsView
- [x] Network error alerts implemented

**In Progress:**
- [ ] Conflict resolution UI (show conflicts to user)
  - **Blocker:** Need design decision on conflict UI pattern
  - **Options:** Sheet modal vs inline banner
  - **Recommendation:** Sheet modal (matches Apple Notes)

**Pending:**
- [ ] Background sync on app launch
- [ ] Manual sync button in toolbar

**Files Modified:**
- BooksTracker/Views/SettingsView.swift (in progress)
- BooksTracker/Views/SyncConflictSheet.swift (to be added)

### ⏸️ Phase 4: E2E Testing (Not Started)
- Waiting for Phase 3 completion
- Requires real CloudKit backend (device-deploy)
```

### Configuration
Plugin installed via:
```bash
code --install-extension planning-with-files
```

Trigger keywords configured in `.claude/rules/planning-automation.md`.

---

## How They Work Together

### Automatic Routing
Claude Code analyzes your request and chooses the appropriate system:

**Example: Simple Request**
```
You: "Fix the broken navigation bar tint color"

Claude:
1. Detects simple task (single file, 1-2 steps)
2. Uses native plans
3. Creates .claude/plans/fix-nav-bar-tint.md
```

**Example: Complex Request**
```
You: "Implement CloudKit sync for the book collection"

Claude:
1. Detects keywords: "implement", "sync" (complex task)
2. Uses planning-with-files plugin
3. Creates .claude/plans/cloudkit-sync/task_plan.md + findings.md + progress.md
```

### Manual Override
Force plugin mode with explicit trigger:
```
You: "/planning-with-files Add bookmark support"
```

### Unified Storage
Both systems write to `.claude/plans/` for consistency:
```
.claude/plans/
  ├── fix-nav-bar-tint.md          # Native plan
  ├── add-genre-filter.md          # Native plan
  ├── cloudkit-sync/               # Plugin plan
  │   ├── task_plan.md
  │   ├── findings.md
  │   └── progress.md
  └── swiftdata-migration/         # Plugin plan
      ├── task_plan.md
      ├── findings.md
      └── progress.md
```

---

## Session Management

### Session Start Hook
`.claude/hooks/session-start.sh` checks for active plans:

```bash
#!/bin/bash
echo "🔍 Checking for active planning files..."

# Check native plans
native_plans=$(find .claude/plans -maxdepth 1 -name "*.md" -type f 2>/dev/null)
if [ -n "$native_plans" ]; then
  echo "📋 Active native plans:"
  echo "$native_plans"
fi

# Check plugin plans
plugin_plans=$(find .claude/plans -maxdepth 2 -name "task_plan.md" 2>/dev/null)
if [ -n "$plugin_plans" ]; then
  echo "📁 Active plugin plans:"
  for plan in $plugin_plans; do
    dir=$(dirname "$plan")
    status=$(grep "Overall Status:" "$dir/progress.md" 2>/dev/null || echo "Not started")
    echo "  - $dir: $status"
  done
fi
```

Output:
```
🔍 Checking for active planning files...
📋 Active native plans:
  .claude/plans/fix-nav-bar-tint.md
📁 Active plugin plans:
  - .claude/plans/cloudkit-sync: 2/3 Phases Complete (66%)
```

### Session End Hook
`.claude/hooks/session-end.sh` archives completed plans:
```bash
#!/bin/bash
# Move completed native plans to archive
for plan in .claude/plans/*.md; do
  if grep -q "Status: Completed" "$plan"; then
    mkdir -p .claude/plans/archive
    mv "$plan" .claude/plans/archive/
  fi
done
```

---

## iOS-Specific Workflows

### Safe Testing Integration
Plans MUST document which test mode to use:

**In task_plan.md:**
```markdown
## Testing Strategy
- **Unit Tests (quick-validate):** ViewModels, business logic
  - Run: /quick-validate
  - Duration: ~30 seconds
  - No simulator required

- **UI Tests (sim-safe):** SwiftUI views, navigation flows
  - Run: /sim-safe
  - Duration: ~2 minutes
  - Uses iOS Simulator

- **Integration Tests (device-deploy):** CloudKit, background tasks
  - Run: /device-deploy
  - Duration: ~5 minutes
  - Requires physical device (real CloudKit backend)
```

### Swift Concurrency Planning
Document actor isolation in findings.md:

```markdown
## Actor Isolation Strategy (2024-01-16)

### Problem
BookViewModel needs to update UI (@MainActor) but fetch from network (background).

### Solution
Use `@MainActor` on ViewModel class, call async network code with `Task { }`.

### Code Pattern
```swift
@MainActor
class BookViewModel: ObservableObject {
  @Published var books: [Book] = []

  func loadBooks() {
    Task {
      let fetchedBooks = await networkService.fetchBooks() // Background
      self.books = fetchedBooks // Back on MainActor
    }
  }
}
```

### Testing
- Unit test: Mock NetworkService, verify books updated
- UI test: Verify loading indicator appears/disappears
```

### Core Data Migration Planning
Always plan migration path in task_plan.md:

```markdown
## Phase 1: Schema Migration

### Current Schema (Version 1)
- Book entity: title, author, isbn

### New Schema (Version 2)
- Book entity: title, isbn, publishDate (new)
- Author entity: name, authorID (new)
- Relationship: Book.author → Author

### Migration Strategy
**Lightweight Migration:** YES
- Only adding fields (publishDate)
- Adding new entity (Author)
- No field deletions or type changes

**Migration Steps:**
1. Update .xcdatamodeld with Version 2
2. Set lightweight migration options in Core Data stack
3. Test migration with sample data (v1 → v2)
4. Rollback plan: Keep v1 schema in version control

**Rollback:**
If migration fails:
1. Revert .xcdatamodeld to Version 1
2. Delete app from device (removes migrated store)
3. Reinstall app (uses Version 1 schema)
```

---

## Troubleshooting

### Problem: Native plans still creating files in root directory
**Cause:** Settings change requires Claude Code restart

**Solution:**
```bash
# 1. Verify settings.json has plansDirectory
jq '.plansDirectory' /Users/juju/dev_repos/books-v3/.claude/settings.json
# Output: ".claude/plans"

# 2. Restart Claude Code
# (Close and reopen the app)

# 3. Test with simple request
"Fix the book cover aspect ratio"
# Should create .claude/plans/fix-book-cover-aspect.md
```

### Problem: Plugin not triggering for complex tasks
**Cause:** Missing trigger keywords

**Solution:**
Use explicit keywords from `.claude/rules/planning-automation.md`:
```
❌ "Add CloudKit sync"
✅ "Implement feature: CloudKit sync"  (trigger: "implement feature")

❌ "Update Core Data model"
✅ "Multi-step migration: Core Data to SwiftData"  (trigger: "multi-step")
```

Or use manual override:
```
/planning-with-files Add CloudKit sync
```

### Problem: progress.md not updating during implementation
**Cause:** Plugin requires explicit progress updates

**Solution:**
After completing a phase, tell Claude:
```
"Update progress: Phase 2 is complete, all tests passing"
```

Claude will update progress.md automatically.

---

## File Organization Best Practices

### Native Plans (Simple Tasks)
Keep filenames descriptive but concise:
```
✅ .claude/plans/fix-book-cover-aspect.md
✅ .claude/plans/add-genre-filter-ui.md
❌ .claude/plans/fix.md  (too vague)
❌ .claude/plans/fix-the-broken-book-cover-aspect-ratio-in-detail-view.md  (too long)
```

### Plugin Plans (Complex Tasks)
Use project-style directory names:
```
✅ .claude/plans/cloudkit-sync/
✅ .claude/plans/swiftdata-migration/
✅ .claude/plans/ios18-api-updates/
❌ .claude/plans/project-1/  (not descriptive)
```

### Archive Completed Work
Move finished plans to archive:
```bash
mkdir -p .claude/plans/archive/2026-01
mv .claude/plans/fix-*.md .claude/plans/archive/2026-01/
```

Keep active plans in root `.claude/plans/` for visibility.

---

## Version Control

### Git Tracking
Both plan types are committed to git:
```bash
git add .claude/plans/
git commit -m "docs: Add CloudKit sync planning artifacts"
```

**Why commit plans?**
- Provides design rationale for future changes
- Preserves architectural decisions
- Enables AI context across sessions

### .gitignore Exclusions
See `.gitignore` for planning file exclusions:
```gitignore
# Planning - Root directory cleanup (all planning in .claude/plans/)
/task_plan.md
/findings.md
/progress.md
/*.plan.md

# Planning - Temporary working files
.claude/plans/**/*.tmp
.claude/plans/**/*.scratch
.claude/plans/**/*.wip
```

**Committed:** Final planning artifacts
**Ignored:** Temporary working files, agent logs

---

## References

### Native Plans
- **Documentation:** https://code.claude.com/docs/en/settings
- **Settings Schema:** https://json.schemastore.org/claude-code-settings.json

### planning-with-files Plugin
- **Plugin Repo:** https://github.com/ckreiling/planning-with-files
- **Manus System:** https://github.com/anthropics/manus (original research)

### iOS Development Context
- **Safe Testing Policy:** `.claude/rules/safe-testing.md`
- **Swift Concurrency:** `.claude/rules/swift-concurrency.md`
- **PM Orchestration:** `.claude/rules/pm-orchestration.md`

---

## Quick Command Reference

```bash
# Check current settings
jq '.plansDirectory' .claude/settings.json

# List active plans
find .claude/plans -name "task_plan.md" -o -name "*.md" -maxdepth 2

# Archive completed native plans
mkdir -p .claude/plans/archive/$(date +%Y-%m)
mv .claude/plans/*.md .claude/plans/archive/$(date +%Y-%m)/

# Validate JSON settings
jq empty .claude/settings.json && echo "✅ Valid JSON" || echo "❌ Invalid JSON"

# Search planning content
grep -r "CloudKit" .claude/plans/

# Show planning plugin status
code --list-extensions | grep planning
```

---

**Configuration Date:** 2026-01-16
**Last Verified:** 2026-01-16
**Status:** ✅ Dual planning system operational
**Maintained By:** Claude Code AI + @jukasdrj
