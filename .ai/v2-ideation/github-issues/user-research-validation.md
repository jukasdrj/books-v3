# User Research: Validate v2 Priorities & UI/UX Choices

**Issue Type:** Research Spike
**Phase:** Pre-Phase 1 (Planning)
**Priority:** CRITICAL
**Time-box:** 1 week (Nov 25 - Dec 1, 2025)
**Blockers:** Sprint 1 implementation depends on this research

---

## Research Goals

Validate v2 feature priorities and UI/UX design decisions with beta users before committing to implementation roadmap.

### Primary Questions

1. **Feature Priorities:** Do users agree with Top 5 feature ranking?
2. **UI Design:** Is "Bento Box" layout more intuitive than current vertical list?
3. **Diversity Visualization:** Does Representation Radar chart effectively communicate diversity data?
4. **Progressive Profiling:** Are contextual prompts less friction than upfront forms?
5. **Gamification:** Do progress rings and curator badges motivate contribution?

---

## Research Methods

### 1. User Survey (Quantitative)

**Target:** 50+ current BooksTracker users
**Distribution:** In-app prompt, email to beta list, TestFlight notes
**Duration:** 7 days open
**Tool:** Google Forms or Typeform

**Questions:**
- [See Survey Questions section below]

---

### 2. Moderated User Interviews (Qualitative)

**Target:** 10-15 users (diverse user profiles)
**Duration:** 30-45 minutes per interview
**Format:** Video call with screen sharing (Figma prototype)
**Incentive:** $25 Amazon gift card or 1-year Pro subscription (when available)

**Interview Script:**
- [See Interview Guide section below]

---

### 3. Prototype Testing (Usability)

**Target:** 8-12 users
**Duration:** 20-30 minutes per session
**Format:** Moderated remote testing with thinking-aloud protocol
**Tool:** Figma prototype + screen recording

**Tasks:**
- [See Usability Test Tasks section below]

---

## Survey Questions

### Section 1: Feature Priorities (Ranking)

**Q1:** Rank these 5 proposed features by how valuable they would be to you (1 = most valuable, 5 = least valuable):

- [ ] **Reading Session Tracking** - Timer to track reading time, calculate reading pace, and build reading streaks
- [ ] **Annotation System** - Add notes, highlights, bookmarks, and collect quotes from books
- [ ] **Enhanced Diversity Stats** - Visual charts showing representation across your reading (cultural origin, gender, translation, etc.)
- [ ] **Reading Circles** - Create private groups to share books and reading progress with friends
- [ ] **AI Recommendations** - Get personalized book suggestions based on your reading habits (privacy-first, processed locally on your device)

**Q2:** Which of these features would make you MORE likely to use BooksTracker daily?
- [ ] Reading session timer
- [ ] Annotation system
- [ ] Diversity visualization
- [ ] Reading circles
- [ ] AI recommendations
- [ ] None of these
- [ ] Other: _________

---

### Section 2: Reading Session Tracking

**Q3:** How important is tracking your reading time to you?
- [ ] Very important - I'd use this daily
- [ ] Somewhat important - I'd use it occasionally
- [ ] Not very important - I might try it once
- [ ] Not important at all - I wouldn't use this

**Q4:** What would you want to track during reading sessions? (Select all that apply)
- [ ] Time spent reading
- [ ] Pages read
- [ ] Reading pace (pages per hour)
- [ ] Reading streaks (consecutive days)
- [ ] Mood before/after reading
- [ ] Location where I'm reading
- [ ] Other: _________

**Q5:** Would a visible timer button encourage you to track your reading more?
- [ ] Yes, definitely
- [ ] Maybe, I'd try it
- [ ] No, I prefer not to track
- [ ] I'm not sure

---

### Section 3: UI/UX Design (Bento Box Layout)

**[Show mockup images of current vs. Bento Box layout]**

**Q6:** Which layout do you find easier to scan for information?
- [ ] Current layout (vertical list)
- [ ] New layout (Bento Box grid)
- [ ] No preference

**Q7:** What do you like about the new Bento Box layout? (Open-ended)

**Q8:** What concerns do you have about the new layout? (Open-ended)

---

### Section 4: Diversity Visualization (Radar Chart)

**[Show mockup of Representation Radar chart]**

**Q9:** How well does this radar chart help you understand diversity in your reading?
- [ ] Very clear - I immediately understand it
- [ ] Somewhat clear - I'd need a brief explanation
- [ ] Unclear - I'm confused by this chart
- [ ] Not interested in this data

**Q10:** The chart shows missing data as dashed lines with a "+" icon to add information. How do you feel about this approach?
- [ ] Love it - Clear call-to-action
- [ ] Like it - Seems helpful
- [ ] Neutral - Don't care either way
- [ ] Dislike it - Feels like extra work
- [ ] Hate it - Don't want to be prompted

**Q11:** Would seeing this diversity data change how you choose books?
- [ ] Yes, significantly
- [ ] Yes, somewhat
- [ ] Maybe occasionally
- [ ] No, not really
- [ ] No, this isn't relevant to me

---

### Section 5: Progressive Profiling (Data Entry)

**[Show mockup of post-session prompt with multiple choice pills]**

**Q12:** After a reading session, how would you feel about a quick prompt asking about the book's cultural context?
- [ ] Happy to help - I'd answer every time
- [ ] Willing - I'd answer most times
- [ ] Neutral - I might skip it
- [ ] Annoyed - Please don't interrupt my flow
- [ ] Very annoyed - This would make me stop using the app

**Q13:** Which approach to gathering book metadata do you prefer?
- [ ] Quick prompts that appear contextually (after reading, when viewing book)
- [ ] A comprehensive form I fill out once per book
- [ ] No prompts at all - I'll add data manually if I want to
- [ ] I don't want to contribute data

---

### Section 6: Gamification

**[Show mockup of progress ring on book cover]**

**Q14:** Would a "metadata completion" ring on book covers motivate you to add more information?
- [ ] Yes, very motivating
- [ ] Somewhat motivating
- [ ] Neutral - I'd ignore it
- [ ] No, this wouldn't affect my behavior
- [ ] No, this would annoy me

**Q15:** Would earning a "Curator" badge for contributing 5+ data points interest you?
- [ ] Yes, I'd enjoy earning badges
- [ ] Maybe, depends on the reward
- [ ] No, badges don't motivate me
- [ ] No, I dislike gamification

**Q16:** What would make contributing book metadata more rewarding for you? (Open-ended)

---

### Section 7: Annotation System

**Q17:** How often do you currently take notes while reading?
- [ ] Always - For every book
- [ ] Often - For most books
- [ ] Sometimes - For certain books
- [ ] Rarely - Only occasionally
- [ ] Never

**Q18:** What types of annotations would you use? (Select all that apply)
- [ ] Highlights (mark favorite passages)
- [ ] Notes (add my thoughts)
- [ ] Bookmarks (save my place)
- [ ] Quotes (collect memorable lines)
- [ ] Tags (categorize themes)
- [ ] None - I don't annotate books

**Q19:** Where do you currently keep your book notes?
- [ ] Physical notebook
- [ ] Notes app (Apple Notes, Notion, etc.)
- [ ] Goodreads reviews
- [ ] Don't take notes
- [ ] Other: _________

---

### Section 8: Privacy & Data

**Q20:** How important is it that BooksTracker keeps your data private and local-first?
- [ ] Extremely important - This is a key reason I use the app
- [ ] Very important - I prefer privacy-focused apps
- [ ] Somewhat important - I consider this
- [ ] Not very important - I don't worry about this
- [ ] Not important at all

**Q21:** Would you be willing to participate in "federated learning" where AI models are trained locally on your device and only anonymized model weights are shared (never your personal data)?
- [ ] Yes, definitely
- [ ] Yes, if I can opt-out anytime
- [ ] Maybe, I'd need more information
- [ ] No, I prefer zero data sharing
- [ ] I don't understand this question

---

### Section 9: Demographics

**Q22:** How long have you been using BooksTracker?
- [ ] Less than 1 month
- [ ] 1-3 months
- [ ] 3-6 months
- [ ] 6-12 months
- [ ] Over 1 year

**Q23:** How many books do you typically read per year?
- [ ] 1-10 books
- [ ] 11-25 books
- [ ] 26-50 books
- [ ] 51-100 books
- [ ] 100+ books

**Q24:** What is your primary reason for using BooksTracker? (Select top 2)
- [ ] Track my reading progress
- [ ] Discover diverse books
- [ ] Maintain a reading log
- [ ] Set reading goals
- [ ] Organize my library
- [ ] Track reading habits
- [ ] Other: _________

**Q25:** Any other feedback on v2 plans? (Open-ended)

---

## Interview Guide (Moderated Sessions)

### Introduction (5 minutes)

**Script:**
> "Thank you for joining today! I'm [Name] and I work on BooksTracker. We're planning a major update (v2) and want to make sure we're building features you'll actually use.
>
> This is not a test of you - there are no right or wrong answers. We're testing our designs, not you. Please think aloud as much as possible and be completely honest.
>
> I'll be recording this session so I can review your feedback later. Is that okay?"

**Warm-up Questions:**
- How long have you been using BooksTracker?
- What's your favorite feature currently?
- What frustrates you about the app?

---

### Section 1: Feature Priorities (10 minutes)

**Task:** Show list of 5 features and ask user to rank them.

**Questions:**
- Walk me through your ranking. Why is [top choice] most important to you?
- Tell me about a time you wished BooksTracker had [feature]?
- Which feature would you use daily vs. occasionally?

**Follow-up:**
- Are there any features NOT on this list that you wish were prioritized?
- If you could only have ONE of these features, which would it be?

---

### Section 2: Bento Box Layout (10 minutes)

**Task:** Show Figma prototype with Bento Box layout side-by-side with current layout.

**Questions:**
- What's your first impression of the new layout?
- What do you like about it? What concerns you?
- Which layout helps you find information faster?
- Can you point to the most important information on each screen?

**Task:** Ask user to find specific information:
- "Find the book's publication year"
- "Find the diversity stats"
- "Start a reading session"

**Observe:**
- Do they scan horizontally or vertically?
- Do they miss any modules?
- Do they understand the visual hierarchy?

---

### Section 3: Representation Radar (10 minutes)

**Task:** Show radar chart in complete and "ghost" state.

**Questions:**
- What does this chart tell you about this book?
- What do you think the dashed lines mean?
- Would you tap the "+" icon? Why or why not?
- How would you explain this chart to a friend?

**Task:** Show a book with 90% diversity score vs. 30% score.
- What's the difference between these two books?
- Would this influence which book you read next?

**Follow-up:**
- Is this chart overwhelming or helpful?
- Would you prefer a simple percentage or this detailed breakdown?

---

### Section 4: Progressive Profiling (5 minutes)

**Task:** Walk through a reading session scenario.

> "You just finished a 30-minute reading session. The app shows you this prompt..."

**[Show post-session prompt asking about author's cultural heritage]**

**Questions:**
- How do you feel about this prompt appearing now?
- Would you answer it? Why or why not?
- Is this the right time to ask, or would you prefer a different time?
- How do you feel about the multiple choice format?

**Scenario variation:**
- What if this prompt appeared BEFORE you started reading?
- What if it appeared when you first added the book?

---

### Section 5: Gamification (5 minutes)

**Task:** Show book cover with completion ring.

**Questions:**
- What do you think this ring represents?
- Would you tap it? What do you expect to happen?
- Would this motivate you to complete the book's metadata?
- What about earning badges like "Curator" for contributing data?

**Follow-up:**
- What types of rewards would actually motivate you?
- Is there a risk this becomes annoying instead of motivating?

---

### Wrap-up (5 minutes)

**Questions:**
- If you could have ONE feature from v2 tomorrow, which would it be?
- Is there anything we didn't discuss that you think is important?
- On a scale of 1-10, how excited are you about v2 based on what you've seen?
- Would you recommend BooksTracker v2 to a friend? Why or why not?

**Thank participant and send incentive.**

---

## Usability Test Tasks

### Setup
- Provide Figma prototype link
- Ask user to share screen
- Remind them to think aloud

### Task 1: Start a Reading Session
**Scenario:** You're about to read "The Name of the Wind" for 30 minutes. Start a reading session.

**Success Criteria:**
- User finds timer button within 10 seconds
- User successfully starts session
- User understands what's being tracked

**Observe:**
- Do they look for the button?
- Is the button placement intuitive?
- Do they understand the timer interface?

---

### Task 2: Find Diversity Information
**Scenario:** You want to know if this book has diverse representation. Find the diversity information.

**Success Criteria:**
- User locates diversity block within 15 seconds
- User understands the radar chart
- User can explain what the chart shows

**Observe:**
- Do they scroll to find it?
- Do they understand the visual at a glance?
- Do they try to interact with the chart?

---

### Task 3: Add Missing Metadata
**Scenario:** You notice some diversity data is missing. Add information about the author's cultural background.

**Success Criteria:**
- User identifies "ghost" state indicators
- User taps "+" icon
- User completes the prompt
- User sees chart update

**Observe:**
- Do they understand what the dashed lines mean?
- Is the "+" icon discoverable?
- Is the prompt clear and easy to complete?
- Do they notice the chart updating?

---

### Task 4: Browse Your Reading Stats
**Scenario:** You want to see how much you've read this week. Find your reading statistics.

**Success Criteria:**
- User navigates to stats view
- User understands the metrics shown
- User can find specific data (reading time, pages read, streak)

**Observe:**
- Is the navigation clear?
- Do they understand the Bento Box layout?
- Can they find specific metrics quickly?

---

### Task 5: Add an Annotation
**Scenario:** You just read a powerful quote on page 42. Save it to your annotations.

**Success Criteria:**
- User finds annotation feature
- User creates a new annotation
- User sees it saved successfully

**Observe:**
- Is the annotation feature discoverable?
- Is the interface intuitive?
- Do they understand annotation types?

---

## Success Metrics

### Quantitative (Survey)

**Feature Priorities:**
- [ ] 60%+ users rank ReadingSession in top 2
- [ ] 50%+ users rank Annotations in top 3
- [ ] 70%+ users interested in diversity visualization

**UI/UX:**
- [ ] 70%+ users prefer Bento Box layout over current
- [ ] 60%+ users rate radar chart as "very clear" or "somewhat clear"
- [ ] 50%+ users "willing" or "happy to help" with progressive prompts

**Gamification:**
- [ ] 40%+ users find progress ring "very" or "somewhat" motivating
- [ ] 30%+ users interested in earning curator badges

---

### Qualitative (Interviews)

**Must Have:**
- [ ] No major usability blockers identified
- [ ] Users can complete all 5 tasks in usability test
- [ ] Users express excitement about at least 2 features

**Red Flags (Stop and Pivot):**
- [ ] Users confused by radar chart despite explanation
- [ ] Users express strong negative reaction to progressive prompts
- [ ] Users prefer current layout over Bento Box
- [ ] Users find gamification annoying rather than motivating

---

## Deliverables

### Week of Nov 25-Dec 1, 2025

**Day 1-2 (Mon-Tue):**
- [ ] Launch survey (in-app, email, TestFlight)
- [ ] Schedule 10+ user interviews

**Day 3-5 (Wed-Fri):**
- [ ] Conduct interviews
- [ ] Run usability tests
- [ ] Collect survey responses

**Day 6-7 (Sat-Sun):**
- [ ] Analyze quantitative data (survey results)
- [ ] Synthesize qualitative insights (interviews)
- [ ] Create findings report

### Final Report (Due: Dec 1, 2025)

**Document:** `.ai/v2-ideation/user-research-findings.md`

**Sections:**
1. Executive Summary
2. Feature Priority Validation
3. UI/UX Findings (Bento Box, Radar Chart)
4. Progressive Profiling Feedback
5. Gamification Insights
6. Recommended Changes to v2 Plan
7. Go/No-Go Decision for Sprint 1

---

## Decision Criteria

### Go (Proceed with Sprint 1 as planned)
- 60%+ users rank ReadingSession in top 2
- 70%+ users prefer or neutral on Bento Box layout
- No critical usability blockers
- Positive overall sentiment

### Pivot (Adjust v2 plan)
- <50% users interested in ReadingSession
- 50%+ users prefer current layout
- Major usability issues with radar chart
- Strong negative reaction to progressive profiling

### No-Go (Delay Sprint 1)
- Widespread confusion about v2 features
- Users don't see value in any proposed features
- Critical privacy concerns raised
- Major technical feasibility issues discovered

---

## Budget & Resources

**Participant Incentives:**
- Survey: None (5-minute commitment)
- Interviews: $25 gift card × 12 participants = $300
- Usability tests: $25 gift card × 10 participants = $250
- **Total incentives:** $550

**Tools:**
- Survey: Google Forms (free) or Typeform ($25/month)
- Interviews: Zoom (existing)
- Prototype: Figma (existing)
- **Total tools:** ~$25

**Total Budget:** ~$575

---

## Risk Mitigation

### Risk 1: Low survey response rate
**Mitigation:**
- Incentivize with entry to win $100 gift card
- Keep survey under 10 minutes
- Send reminder emails after 3 days

### Risk 2: Biased sample (only power users respond)
**Mitigation:**
- Target users with varying usage levels
- Include new users (< 3 months) in interview pool
- Weight responses by user segment

### Risk 3: Users say they want features but won't use them
**Mitigation:**
- Focus on past behavior, not hypothetical preference
- Ask "When was the last time you wanted this?" not "Would you use this?"
- Usability test actual prototypes, not concepts

### Risk 4: Timeline delays
**Mitigation:**
- Start survey immediately (Nov 25)
- Schedule backup interview slots
- Have async option (recorded task completion)

---

## Next Steps After Research

**If GO:**
1. Finalize Sprint 1 technical specs
2. Update priority ranking if needed
3. Begin Sprint 1 implementation (Week of Dec 2)

**If PIVOT:**
1. Adjust v2 roadmap based on findings
2. Re-prioritize features
3. Update sprint allocations
4. Plan revised Sprint 1 (if different feature)

**If NO-GO:**
1. Conduct deeper user research
2. Consider smaller, incremental v1.x updates
3. Validate core assumptions about user needs

---

## Labels

`research` `spike` `user-testing` `v2:planning` `priority:critical` `time-boxed`

---

**Created:** November 20, 2025
**Owner:** Product/UX Team
**Participants:** Beta users, power users, new users
**Status:** Ready to launch
**Timeline:** Nov 25 - Dec 1, 2025
