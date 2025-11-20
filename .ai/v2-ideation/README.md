# BooksTracker v2 Ideation & Planning

**Version:** 2.0.0 (Planning Phase)
**Branch:** `ideation/exploration`
**Created:** November 20, 2025
**Status:** Ideation Phase

---

## Overview

This directory contains all planning, design, and ideation documents for BooksTracker v2. The goal of v2 is to transform BooksTracker from a library manager into a comprehensive reading companion with advanced analytics, habit tracking, and privacy-first social features.

---

## Document Structure

```
.ai/v2-ideation/
├── README.md                           # This file
├── DATA_STRUCTURE_ANALYSIS.md          # Comprehensive analysis of v1 → v2 data model
├── ISSUE_TEMPLATE.md                   # GitHub issue templates for v2 development
│
├── sprints/
│   ├── SPRINT_OVERVIEW.md              # All sprints overview & timeline
│   ├── sprint-01-reading-session.md    # Sprint 1 detailed plan
│   ├── sprint-02-session-analytics.md  # Sprint 2 (TBD)
│   └── ... (sprints 3-16)
│
├── features/
│   ├── book-details-redesign.md        # Feature spec: Bento Box UI redesign
│   ├── reading-sessions.md             # Feature spec: Reading sessions
│   ├── annotations.md                  # Feature spec: User annotations
│   ├── diversity-stats.md              # Feature spec: Enhanced diversity
│   ├── reading-circles.md              # Feature spec: Privacy-first social
│   └── ai-recommendations.md           # Feature spec: Local AI recs
│
├── technical-design/
│   ├── reading-sessions.md             # Technical design: Sessions
│   ├── annotations.md                  # Technical design: Annotations
│   ├── ai-recommendations.md           # Technical design: Local AI
│   └── social-features.md              # Technical design: Social
│
└── decisions/
    ├── 001-local-first-ai.md           # ADR: Why local AI vs cloud
    ├── 002-swiftdata-migration.md      # ADR: Schema migration strategy
    └── 003-federated-learning.md       # ADR: Federated learning approach
```

---

## Quick Start

### For Developers

1. **Understand the vision:** Start with [`DATA_STRUCTURE_ANALYSIS.md`](DATA_STRUCTURE_ANALYSIS.md)
2. **Review the roadmap:** Read [`sprints/SPRINT_OVERVIEW.md`](sprints/SPRINT_OVERVIEW.md)
3. **Deep dive on features:** Check [`technical-design/`](technical-design/) for implementation details
4. **Pick up a task:** Create an issue using [`ISSUE_TEMPLATE.md`](ISSUE_TEMPLATE.md)

### For Product Planning

1. **Feature priorities:** See Top 5 priorities in [`DATA_STRUCTURE_ANALYSIS.md`](DATA_STRUCTURE_ANALYSIS.md)
2. **Sprint timeline:** Review [`sprints/SPRINT_OVERVIEW.md`](sprints/SPRINT_OVERVIEW.md)
3. **User stories:** Check individual sprint docs in [`sprints/`](sprints/)

### For AI Agents

1. **Context gathering:** Read [`DATA_STRUCTURE_ANALYSIS.md`](DATA_STRUCTURE_ANALYSIS.md) for v2 goals
2. **Implementation guidance:** Use [`technical-design/`](technical-design/) docs
3. **Decision context:** Review [`decisions/`](decisions/) for architectural choices

---

## Key Documents

### 1. [DATA_STRUCTURE_ANALYSIS.md](DATA_STRUCTURE_ANALYSIS.md)
**Purpose:** Comprehensive analysis of v1 architecture with v2 enhancement recommendations

**Contents:**
- Current architecture strengths
- Enhancement opportunities by category
- Top 5 priority additions (ReadingSession, UserAnnotation, EnhancedDiversityStats, ReadingCircle, UserPreferenceProfile)
- Implementation strategy (4 phases, 16 sprints)
- Privacy & security considerations
- Competitive analysis context

**When to use:**
- Understanding v2 vision
- Feature prioritization decisions
- Architectural context for new features

---

### 2. [sprints/SPRINT_OVERVIEW.md](sprints/SPRINT_OVERVIEW.md)
**Purpose:** High-level sprint planning and timeline

**Contents:**
- 16 sprints across 4 phases
- Phase 1: Engagement Foundation (Q1 2026)
- Phase 2: Intelligence Layer (Q2 2026)
- Phase 3: Social Features (Q3 2026)
- Phase 4: Discovery & Polish (Q4 2026)
- Success metrics per phase

**When to use:**
- Sprint planning
- Timeline estimates
- Understanding phase dependencies

---

### 3. [sprints/sprint-01-reading-session.md](sprints/sprint-01-reading-session.md)
**Purpose:** Detailed plan for first sprint (ReadingSession feature)

**Contents:**
- User stories with acceptance criteria
- Technical task breakdown (9 tasks)
- Design specifications (UI mockups, component diagrams)
- Testing strategy (unit, integration, manual)
- Definition of done
- Risk mitigation

**When to use:**
- Implementing Sprint 1
- Creating GitHub issues for Sprint 1 tasks
- Understanding ReadingSession feature scope

---

### 4. [technical-design/reading-sessions.md](technical-design/reading-sessions.md)
**Purpose:** Detailed technical design for reading sessions feature

**Contents:**
- Data model (SwiftData schema)
- Architecture (component diagram, service layer)
- State persistence (UserDefaults + SwiftData)
- UI/UX design (button states, sheets)
- Query optimization strategies
- Error handling patterns
- Testing strategy
- Performance considerations

**When to use:**
- Implementing ReadingSession feature
- Making architectural decisions
- Writing tests
- Debugging session-related issues

---

### 5. [ISSUE_TEMPLATE.md](ISSUE_TEMPLATE.md)
**Purpose:** GitHub issue templates for consistent issue tracking

**Contents:**
- Feature issue template
- Bug issue template
- Technical debt template
- Documentation template
- Research spike template
- Label conventions
- Example issues

**When to use:**
- Creating new GitHub issues
- Tracking sprint progress
- Organizing work in GitHub Projects

---

## Development Workflow

### 1. Sprint Planning

1. Review [`sprints/SPRINT_OVERVIEW.md`](sprints/SPRINT_OVERVIEW.md)
2. Read detailed sprint plan (e.g., [`sprint-01-reading-session.md`](sprints/sprint-01-reading-session.md))
3. Create GitHub issues using [`ISSUE_TEMPLATE.md`](ISSUE_TEMPLATE.md)
4. Add issues to Sprint Project board
5. Assign issues to developers

### 2. Implementation

1. Create feature branch: `feature/v2-<feature-name>`
2. Review technical design docs in [`technical-design/`](technical-design/)
3. Follow TDD approach (write tests first)
4. Implement feature per acceptance criteria
5. Ensure zero warnings policy maintained

### 3. Testing

1. Run unit tests: `swift test`
2. Run integration tests: `@xcode run tests`
3. Manual testing on simulator
4. Manual testing on real device (iPhone 16 Pro)
5. Performance profiling (Instruments)

### 4. Review & Merge

1. Create PR with detailed description
2. Link related issues
3. Request review from team
4. Address feedback
5. Merge to `main` when approved

---

## Phases & Milestones

### Phase 1: Engagement Foundation (Q1 2026)
**Milestone:** Users can track reading sessions, view streaks, and annotate books

**Sprints:** 1-4
**Key Features:**
- ReadingSession tracking
- Streak analytics
- Annotation system
- Enhanced diversity stats

**Success Criteria:**
- [ ] 80%+ user engagement with timer feature
- [ ] Average 3+ sessions per user per week
- [ ] 50%+ users create at least 1 annotation
- [ ] Zero crashes related to new features

---

### Phase 2: Intelligence Layer (Q2 2026)
**Milestone:** AI-powered recommendations and insights working locally

**Sprints:** 5-8
**Key Features:**
- UserPreferenceProfile
- Pattern recognition
- Local AI recommendations
- Advanced insights

**Success Criteria:**
- [ ] 70%+ user satisfaction with recommendations
- [ ] Zero personal data sent to cloud
- [ ] <1s recommendation generation time
- [ ] Pattern recognition identifies 5+ habit patterns per user

---

### Phase 3: Social Features (Q3 2026)
**Milestone:** Privacy-first social reading features live

**Sprints:** 9-12
**Key Features:**
- ReadingCircle
- Private sharing
- Group challenges
- Community recommendations

**Success Criteria:**
- [ ] 30%+ users create or join a reading circle
- [ ] E2E encryption verified for all shared data
- [ ] 50%+ circle participation in group challenges
- [ ] Zero data leaks or privacy violations

---

### Phase 4: Discovery & Polish (Q4 2026)
**Milestone:** Feature-complete v2.0 ready for release

**Sprints:** 13-16
**Key Features:**
- Price tracking
- Enhanced metadata (series, awards)
- Content warnings
- Performance optimization

**Success Criteria:**
- [ ] <200ms app launch time
- [ ] 95%+ WCAG AA accessibility compliance
- [ ] Price tracking covers 5+ retailers
- [ ] Zero known critical bugs

---

## Contributing

### Creating New Documents

**Sprint Docs:**
- Use [`sprint-01-reading-session.md`](sprints/sprint-01-reading-session.md) as template
- Follow same structure: Goals, User Stories, Technical Tasks, Design, Testing, DoD

**Technical Design Docs:**
- Use [`technical-design/reading-sessions.md`](technical-design/reading-sessions.md) as template
- Include: Overview, Goals, Data Model, Architecture, Design, Testing, Performance

**Feature Specs:**
- Create in [`features/`](features/) directory
- Focus on user-facing behavior and value proposition
- Include: Problem, Solution, User Stories, UX mockups

**Decision Records:**
- Use ADR (Architecture Decision Record) format
- Include: Context, Decision, Consequences, Alternatives
- Number sequentially (001, 002, etc.)

---

## Tools & Resources

### Development Tools
- **Xcode 16+** - IDE
- **Swift 6.2+** - Language
- **SwiftData** - Persistence
- **Swift Testing** - Test framework

### MCP Servers
- **XcodeBuildMCP** - Build, test, deploy
- **Zen MCP** - AI-powered analysis and debugging

### Slash Commands
- `/build` - Quick build validation
- `/test` - Run Swift tests
- `/sim` - Launch in simulator
- `/device-deploy` - Deploy to connected device

### Custom Agents
- `@pm` - Product manager & orchestrator
- `@zen` - Deep analysis specialist
- `@xcode` - Build, test & deploy specialist

---

## Privacy & Security Philosophy

BooksTracker v2 maintains our **privacy-first philosophy**:

1. **Local-First Processing** - All personal data stays on device
2. **No User Tracking** - No analytics, telemetry, or behavioral tracking
3. **User-Controlled Sharing** - Explicit opt-in for all social features
4. **Federated Learning** - AI models trained locally, only model weights shared (opt-in)
5. **Anonymized Benchmarks** - Statistical comparisons without personal data

**Every feature MUST adhere to these principles.**

---

## Getting Help

### Documentation Issues
- Create issue with `documentation` label
- Tag with appropriate sprint/phase label
- Provide details on what's unclear or missing

### Technical Questions
- Review [`technical-design/`](technical-design/) docs first
- Check [`decisions/`](decisions/) for architectural context
- Create `spike` issue if research needed

### Feature Clarifications
- Review feature spec in [`features/`](features/)
- Check sprint plan in [`sprints/`](sprints/)
- Create issue with `question` label

---

## Status & Next Steps

### Current Status: Ideation Phase
**As of November 20, 2025:**

- [x] Comprehensive data structure analysis completed
- [x] 16-sprint roadmap defined
- [x] Sprint 1 detailed planning completed
- [x] Technical design for ReadingSession feature completed
- [x] Issue templates created
- [ ] User research validation (scheduled for week of Nov 25)
- [ ] Sprint 1 implementation (TBD - post user research)

### Next Milestones

**Week of Nov 25, 2025: User Research**
- Validate ReadingSession feature priority
- Test timer UI mockups with beta users
- Gather feedback on annotation system concepts
- Validate enhanced diversity stats value proposition

**Week of Dec 2, 2025: Sprint 1 Kickoff**
- Finalize technical specs
- Create GitHub issues for all Sprint 1 tasks
- Set up feature branch: `feature/v2-reading-sessions`
- Begin implementation (TDD approach)

**Week of Dec 16, 2025: Sprint 1 Complete**
- ReadingSession model and timer UI shipped
- Unit & integration tests passing
- Documentation updated
- Ready for Sprint 2 (Session Analytics)

---

## Questions & Feedback

**For maintainers:**
- oooe (jukasdrj) - Primary maintainer

**For contributors:**
- Review contribution guidelines in `AGENTS.md` and `CLAUDE.md`
- Create issues using templates in `ISSUE_TEMPLATE.md`
- Follow zero-warnings policy and Swift 6 concurrency patterns

---

**Last Updated:** November 20, 2025
**Branch:** `ideation/exploration`
**Next Review:** December 1, 2025 (Post user research)
