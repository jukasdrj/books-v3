# Planning-with-Files Automation (Auto-loaded)

Auto-loaded when user mentions: "multi-step", "phase", "migration", "implement feature", "add feature", "refactor", "redesign", "complex"

---

When you detect a **complex multi-step task**, immediately use `/planning-with-files`.

## Detection Patterns

### Trigger Planning For

**Explicit multi-step indicators:**
- "implement feature" / "add feature" / "build new"
- "migration" / "refactor entire" / "redesign"
- User mentions "phase 1" / "step 1" / "phase 2"
- Lists with 3+ implementation steps
- "first... then... finally" structure

**Complexity indicators:**
- Work requiring >5 tool calls
- Multiple files/modules affected (>3 files)
- New feature with UI + backend + tests
- Architecture changes
- Performance optimization work

**Examples:**
- ✅ "Implement Phase 3 Goals Engine with 6 goal types"
- ✅ "Add authentication to API endpoints"
- ✅ "Migrate from Core Data to SwiftData"
- ✅ "Build onboarding flow with 5 steps"
- ✅ "Refactor recommendation system"

### Don't Trigger For

**Simple tasks:**
- ❌ "Fix typo in README"
- ❌ "Add comment to function"
- ❌ "Rename variable"
- ❌ "Update version number"

**Quick questions:**
- ❌ "What does this function do?"
- ❌ "Where is the auth code?"
- ❌ "Explain this pattern"

**Single-file edits:**
- ❌ "Add log statement to LoginView.swift"
- ❌ "Fix compiler warning in Work.swift"

## Automatic Workflow

### 1. Detection (UserPromptSubmit Hook)

**Hook detects complex task:**
- Checks user input for patterns
- Verifies planning files don't exist
- Injects reminder if needed

**Hook message:**
```
🎯 Multi-step task detected. Use planning-with-files for best results:
   Run: /planning-with-files
   Creates: task_plan.md, findings.md, progress.md in project root
```

### 2. Planning Files Creation

**You see hook message, you should:**
1. Acknowledge: "I'll create planning files first"
2. Run: `/planning-with-files` skill
3. Or manually: Use init-session.sh script
4. Or manually: Create 3 files from templates

**Files created in project root:**
- `task_plan.md` - Phases, decisions, errors
- `findings.md` - Research, discoveries
- `progress.md` - Session log, test results

### 3. If Planning Files Already Exist

**Don't create new ones! Instead:**
1. Read `task_plan.md` to understand current phase
2. Check which phase is `in_progress`
3. Continue work from that phase
4. Update files as you progress

**Common scenario:**
- User resumes work on existing feature
- Planning files from previous session exist
- You pick up where previous session left off

## File Responsibilities

### task_plan.md (Roadmap)

**Update when:**
- After each phase completes
- When making decisions
- When errors occur
- When changing approach

**Structure:**
```markdown
## Goal
One-sentence clear goal

## Current Phase
Phase 2 - Implementation (In Progress)

## Phases
### Phase 1: Research & Design ✅
- [x] Read existing code
- [x] Design approach
- **Status:** complete

### Phase 2: Implementation
- [x] Build component A
- [ ] Build component B
- **Status:** in_progress

### Phase 3: Testing
- [ ] Unit tests
- [ ] UI tests
- **Status:** pending

## Decisions Made
| Decision | Rationale | Date |
|----------|-----------|------|
| Use SwiftData | Modern API, iOS 26 | 2026-01-14 |

## Errors Encountered
| Error | Attempt | Resolution | Date |
|-------|---------|------------|------|
| Build failed | 1 | Fixed import | 2026-01-14 |
```

### findings.md (Knowledge Base)

**Update when:**
- After ANY discovery (2-Action Rule!)
- After reading 2+ files
- After web searches
- After viewing images/diagrams
- After subagent returns analysis

**The 2-Action Rule:**
> "After every 2 view/browser/search operations, IMMEDIATELY save key findings to findings.md"

**Why:** Prevents visual/multimodal information from being lost when context resets.

**Structure:**
```markdown
## Research Findings
- Work model has personalRating field (UserLibraryEntry.swift:42)
- StarRatingView already exists (Components/StarRatingView.swift)
- API client uses x-user-id header pattern

## Technical Decisions
| Decision | Rationale |
|----------|-----------|
| Separate RecommendationsClient | Different error schema than V3APIClient |
| @MainActor for ViewModels | Swift 6 concurrency requirement |

## Patterns Identified
- Observable classes need @MainActor
- SwiftData: Insert before relate pattern
- API errors: Typed enum with Equatable

## File Locations
- Models: BooksTrackerPackage/Sources/Types/Models/
- Views: BooksTrack/Features/[Feature]/
- API: BooksTrackerPackage/Sources/Client/
```

### progress.md (Session Log)

**Update when:**
- Throughout session (continuous)
- After completing actions
- After running tests
- After errors occur
- After each phase completes

**Structure:**
```markdown
## Phase 1: Research & Design
- **Status:** complete
- **Started:** 2026-01-14 10:00
- **Completed:** 2026-01-14 10:30
- Actions taken:
  - Read Work.swift model
  - Read User.swift model
  - Analyzed StarRatingView component
  - Updated findings.md with discoveries
- Files read:
  - BooksTrackerPackage/Sources/Types/Models/Work.swift
  - BooksTrackerPackage/Sources/Types/Models/User.swift
  - BooksTrack/Components/StarRatingView.swift
- Files modified:
  - findings.md (research)
  - task_plan.md (phase 1 → complete)

## Phase 2: Implementation
- **Status:** in_progress
- **Started:** 2026-01-14 10:30
- Actions taken:
  - Delegated to Haiku (Explore agent)
  - Created RecommendationsClient.swift
  - Built RecommendationCard component
- Files created:
  - BooksTrackerPackage/Sources/BooksTrackerFeature/Services/RecommendationsClient.swift
  - BooksTrack/Features/Recommendations/RecommendationCard.swift

## Test Results
| Test | Command | Expected | Actual | Status |
|------|---------|----------|--------|--------|
| Build | /quick-validate | Zero warnings | Zero warnings | ✅ |
| UI | /sim-safe | Card displays | Card displays | ✅ |

## Session Notes
- Using Manus pattern for complex feature
- PM orchestration mode active
- Delegating implementation to Haiku
- PAL review with Grok before integration
```

## Integration with PM Orchestration

Planning-with-files provides the **persistent memory** for PM orchestration:

### PM Workflow with Planning Files

**You (PM):**
- Create the plan (task_plan.md)
- Break into phases
- Track decisions
- Log errors

**Subagents (Workers):**
- Haiku implements phases
- Gemini debugs issues
- Grok reviews quality

**PAL MCP (QA):**
- Validates implementation
- Provides expert review
- Ensures quality

**Planning Files (Audit Trail):**
- task_plan.md = roadmap
- findings.md = discoveries
- progress.md = history

### Phase Completion Workflow

**After each phase:**
1. Mark status: `in_progress` → `complete` in task_plan.md
2. Update findings.md with discoveries
3. Update progress.md with actions taken
4. Trigger PAL review (if implementation phase)
5. Integrate validated output
6. Move to next phase

## The 5-Question Reboot Test

If you can answer these, your planning files are working:

| Question | Answer Source |
|----------|---------------|
| Where am I? | Current phase in task_plan.md |
| Where am I going? | Remaining phases in task_plan.md |
| What's the goal? | Goal statement in task_plan.md |
| What have I learned? | findings.md |
| What have I done? | progress.md |

**If you can't answer these → planning files need updating!**

## When Planning Files Get Stale

### Resuming After Context Reset

**Scenario:** New session, continuing existing work

**You should:**
1. Read task_plan.md first (understand current phase)
2. Read findings.md second (understand discoveries)
3. Optionally read progress.md (understand history)
4. Continue from current phase
5. Update files as you progress

**Don't:**
- Create new planning files (use existing ones!)
- Start from scratch (continue from current phase)
- Ignore existing decisions (respect previous work)

### Completing Multi-Day Projects

**End of session:**
1. Update task_plan.md with current phase status
2. Save all discoveries to findings.md
3. Log session in progress.md
4. Commit planning files to git (if user wants)

**Next session:**
1. Read task_plan.md to resume context
2. Continue from `in_progress` phase
3. Respect previous decisions
4. Update files throughout

## Safe Testing Integration

When working with planning files on BooksTrack iOS:

### Testing Commands (in order of preference)

**Default:** `/quick-validate`
- Build validation without Simulator
- Safest for low-memory systems
- Use for continuous validation

**UI Testing:** Ask user first
- `/device-deploy` - Real device (most efficient)
- `/sim-safe` - Simulator with resource limits (safer)
- `/sim` - Standard Simulator (avoid unless requested)

**Emergency:** `/kill-xcode`
- System becomes unresponsive
- Xcode processes frozen

### Document Test Results in progress.md

```markdown
## Test Results
| Test | Command | Expected | Actual | Status |
|------|---------|----------|--------|--------|
| Build validation | /quick-validate | Zero warnings | Zero warnings | ✅ |
| Goal progress UI | /sim-safe | Displays 60% | Displays 60% | ✅ |
| CloudKit sync | /device-deploy | Background sync | Background sync | ✅ |
```

## Examples

### Example 1: Feature Implementation (Recommendations)

**User:** "Implement recommendations feature with API client and UI"

**You:**
1. Hook detects: "implement" + "feature"
2. Hook message: "🎯 Multi-step task detected..."
3. You respond: "I'll create planning files first. Running /planning-with-files..."
4. Create task_plan.md:
   ```markdown
   ## Goal
   Implement personalized book recommendations

   ## Phases
   ### Phase 1: Research (in_progress)
   - [ ] Check existing models
   - [ ] Understand API contract

   ### Phase 2: API Client
   - [ ] Create RecommendationsClient
   - [ ] Add types

   ### Phase 3: UI
   - [ ] Build RecommendationCard
   - [ ] Build list view
   ```
5. Start Phase 1 (research)
6. Update findings.md with discoveries
7. Mark Phase 1 complete
8. Delegate Phase 2 to Haiku
9. PAL review with Grok
10. Continue...

### Example 2: Migration (Core Data → SwiftData)

**User:** "Migrate from Core Data to SwiftData"

**You:**
1. Hook detects: "migration"
2. Hook message: "🎯 Multi-step task detected..."
3. Create planning files
4. task_plan.md phases:
   - Phase 1: Audit existing Core Data models
   - Phase 2: Create SwiftData equivalents
   - Phase 3: Migrate data
   - Phase 4: Update views
   - Phase 5: Remove Core Data
5. Work through phases systematically
6. Update files throughout

### Example 3: Simple Fix (No Planning)

**User:** "Fix typo in README line 42"

**You:**
1. Hook checks: No multi-step indicators
2. Hook doesn't trigger
3. You handle directly (no planning files)
4. Quick edit, done

## Anti-Patterns to Avoid

**❌ Don't:**
- Skip planning for complex tasks
- Forget 2-Action Rule (update findings.md!)
- Create new planning files when they exist
- Ignore existing task_plan.md decisions
- Let planning files get stale
- Over-plan trivial tasks

**✅ Do:**
- Use /planning-with-files for complex work
- Update findings.md after discoveries (2-Action Rule!)
- Read existing task_plan.md before continuing
- Respect previous decisions
- Keep files updated throughout
- Skip planning for simple tasks

## Troubleshooting

### "I forgot to update findings.md"

**Problem:** Made discoveries but didn't save to findings.md

**Solution:**
1. Immediately write current discoveries to findings.md
2. Don't wait until "later" (information will be lost)
3. Follow 2-Action Rule going forward

### "Planning files in wrong location"

**Problem:** Files created in .claude/plugins/ instead of project root

**Solution:**
- Planning files belong in: `/Users/juju/dev_repos/books-v3/`
- NOT in: `.claude/plugins/planning-with-files/`
- Use init-session.sh from project root

### "Hook isn't triggering"

**Problem:** Complex task but no hook reminder

**Solution:**
1. Check UserPromptSubmit hook is configured in settings.json
2. Check hook script is executable (`chmod +x`)
3. Manually create planning files if needed

### "Can't answer 5-Question Reboot Test"

**Problem:** Lost context, can't remember what you're doing

**Solution:**
1. Read task_plan.md (where am I? where going?)
2. Read findings.md (what have I learned?)
3. Read progress.md (what have I done?)
4. Continue from current phase
5. Update files more frequently going forward

---

**Last Updated:** 2026-01-14
**Context:** BooksTrack iOS (solo-dev family app)
**Related Rules:** pm-orchestration.md, safe-testing.md
