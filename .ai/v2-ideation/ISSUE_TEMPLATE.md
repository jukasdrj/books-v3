# GitHub Issue Template for BooksTracker v2

---

## Feature Issue Template

```markdown
### Feature: [Feature Name]

**Phase:** [1/2/3/4]
**Sprint:** [Sprint Number]
**Priority:** [Critical/High/Medium/Low]
**Estimated:** [Hours]

---

### User Story

**As a** [user role]
**I want to** [action]
**So that** [benefit]

---

### Acceptance Criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

---

### Technical Details

**Files to Modify:**
- `path/to/file1.swift` - [What changes]
- `path/to/file2.swift` - [What changes]

**New Files:**
- `path/to/new/file.swift` - [Purpose]

**Dependencies:**
- Issue #XXX (must be completed first)
- External library: [name]

---

### Design Notes

[Link to Figma/design docs, or inline ASCII mockups]

---

### Testing Requirements

**Unit Tests:**
- [ ] Test case 1
- [ ] Test case 2

**Integration Tests:**
- [ ] Test scenario 1

**Manual Testing:**
- [ ] Manual test 1 (simulator)
- [ ] Manual test 2 (real device)

---

### Definition of Done

- [ ] Code written and reviewed
- [ ] All tests passing
- [ ] Zero compiler warnings
- [ ] Documentation updated
- [ ] Tested on real device

---

### Labels

`v2:phase-1` `feature` `priority:critical` `sprint-1`
```

---

## Bug Issue Template

```markdown
### Bug: [Short Description]

**Severity:** [Critical/High/Medium/Low]
**Affected Version:** [v2.0.0-sprint-X]
**Environment:** [Simulator/Device, iOS version]

---

### Description

[Clear description of the bug]

---

### Steps to Reproduce

1. Step 1
2. Step 2
3. Step 3

**Expected:** [What should happen]
**Actual:** [What actually happens]

---

### Error Logs

```
[Paste relevant error logs or crash reports]
```

---

### Screenshots

[Attach screenshots if applicable]

---

### Possible Cause

[Your hypothesis about what's causing the bug]

---

### Suggested Fix

[If you have ideas for how to fix it]

---

### Labels

`bug` `v2:phase-1` `severity:high` `sprint-1`
```

---

## Technical Debt Issue Template

```markdown
### Tech Debt: [Short Description]

**Category:** [Architecture/Performance/Code Quality/Testing]
**Priority:** [High/Medium/Low]
**Effort:** [Small/Medium/Large]

---

### Problem

[What is the technical debt? Why does it exist?]

---

### Impact

**Current Impact:**
- Impact 1
- Impact 2

**Future Risk:**
- Risk 1 if not addressed

---

### Proposed Solution

[How should we address this?]

---

### Alternatives Considered

1. **Alternative 1:** [Pros/Cons]
2. **Alternative 2:** [Pros/Cons]

---

### Estimated Work

- [ ] Task 1 (X hours)
- [ ] Task 2 (X hours)

**Total:** [Y hours]

---

### Labels

`tech-debt` `v2:phase-1` `priority:medium`
```

---

## Documentation Issue Template

```markdown
### Documentation: [What needs documenting]

**Type:** [API/Architecture/User Guide/Developer Guide]
**Priority:** [High/Medium/Low]

---

### What Needs Documentation

[Clear description of what documentation is missing or needs updating]

---

### Target Audience

- [ ] End users
- [ ] Developers (internal)
- [ ] Contributors (external)
- [ ] AI agents (AGENTS.md/CLAUDE.md)

---

### Outline

1. Section 1
   - Subsection A
   - Subsection B
2. Section 2
   - Subsection A

---

### Related Files/Features

- Feature: [Link to issue]
- Existing docs: [Path to file]

---

### Labels

`documentation` `v2:phase-1` `priority:medium`
```

---

## Research Spike Issue Template

```markdown
### Spike: [Research Question]

**Time-box:** [2 hours/1 day/2 days]
**Priority:** [High/Medium/Low]
**Blocker for:** [Issue #XXX]

---

### Research Question

[Clear question that needs answering]

---

### Context

[Why do we need to research this?]

---

### Success Criteria

- [ ] Question answered with confidence level documented
- [ ] Proof-of-concept code written (if applicable)
- [ ] Recommendation documented
- [ ] Trade-offs clearly outlined

---

### Research Areas

- [ ] Research area 1
- [ ] Research area 2
- [ ] Research area 3

---

### Deliverable

[What document/code/decision will result from this spike?]

---

### Labels

`spike` `research` `v2:phase-1` `time-boxed`
```

---

## How to Use These Templates

### Creating a New Issue

1. **Choose the right template** based on issue type
2. **Fill in all sections** - don't skip sections, use "N/A" if not applicable
3. **Add appropriate labels** - Use v2 phase labels, priority, type
4. **Link related issues** - Reference dependencies and related work
5. **Assign to sprint** - Add to sprint project board if known

### Label Conventions

**Phase Labels:**
- `v2:phase-1` - Engagement Foundation
- `v2:phase-2` - Intelligence Layer
- `v2:phase-3` - Social Features
- `v2:phase-4` - Discovery & Polish

**Type Labels:**
- `feature` - New functionality
- `bug` - Something broken
- `tech-debt` - Code quality improvement
- `documentation` - Docs needed
- `spike` - Research needed

**Priority Labels:**
- `priority:critical` - Blocking sprint progress
- `priority:high` - Important for sprint completion
- `priority:medium` - Nice to have in sprint
- `priority:low` - Future consideration

**Sprint Labels:**
- `sprint-1` through `sprint-16`

---

## Example Issues for Sprint 1

### Example 1: Feature Issue

```markdown
### Feature: Create ReadingSession SwiftData Model

**Phase:** 1
**Sprint:** 1
**Priority:** Critical
**Estimated:** 2 hours

---

### User Story

**As a** developer
**I want to** create a SwiftData model for reading sessions
**So that** we can persist user reading session data

---

### Acceptance Criteria

- [ ] ReadingSession model created with all required properties
- [ ] Inverse relationship to UserLibraryEntry defined
- [ ] Computed properties for pagesRead and readingPace implemented
- [ ] Unit tests written and passing

---

### Technical Details

**Files to Modify:**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/UserLibraryEntry.swift` - Add readingSessions relationship

**New Files:**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Models/ReadingSession.swift` - New model
- `BooksTrackerPackageTests/ReadingSessionTests.swift` - Unit tests

**Dependencies:**
- None (foundational feature)

---

### Testing Requirements

**Unit Tests:**
- [ ] Test pagesRead computation
- [ ] Test readingPace computation
- [ ] Test relationship behavior

---

### Labels

`v2:phase-1` `feature` `priority:critical` `sprint-1`
```

---

### Example 2: Bug Issue

```markdown
### Bug: Timer continues running after app force quit

**Severity:** High
**Affected Version:** v2.0.0-sprint-1-dev
**Environment:** iPhone 16 Pro, iOS 26.0

---

### Description

When user starts a reading session and force quits the app, the timer does not persist state. Upon reopening, the session is lost.

---

### Steps to Reproduce

1. Open app and start reading session for any book
2. Wait 5 minutes
3. Force quit app (swipe up from app switcher)
4. Reopen app
5. Navigate to book detail view

**Expected:** Session should show "Resume Session" with elapsed time
**Actual:** No active session, all progress lost

---

### Possible Cause

`ReadingSessionService` state is not persisting to UserDefaults or SwiftData when app enters background.

---

### Suggested Fix

1. Save session start time to UserDefaults in `startSession()`
2. Check UserDefaults on app launch for active session
3. Restore session state if found

---

### Labels

`bug` `v2:phase-1` `severity:high` `sprint-1`
```

---

**Created:** November 20, 2025
**Maintained by:** oooe (jukasdrj)
