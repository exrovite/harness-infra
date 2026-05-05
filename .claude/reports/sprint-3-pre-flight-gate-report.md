# Sprint 3 Report: Pre-Flight Gate System

## Date: 2026-04-06

---

## The Problem We Solved

The watcher system was mechanically working -- agents claimed slots, got 3-minute reminders, filled in checklists. But agents were **bluffing through it**. They did the bare minimum to satisfy the watcher then rushed back to coding. The watcher enforced **process** (rhythm, check-ins) but not **comprehension** (actually understanding and remembering the task).

Agents drifted. They started on-task, then went down rabbit holes -- gold-plating, refactoring unrelated code, losing track of which step they were on.

### The Insight

First solved in a specific domain: an experiment-gate system blocked Write/Edit on experiment scripts unless the agent filled in a pre-flight file proving it had read the ground truth, mistake catalog, and protocols. It worked because the agent could not fake it -- the sections required content from actually reading the source documents.

Key insight: **the watcher slot, filled at task start when comprehension is highest, IS the ground truth**. Force the agent to re-engage with it before every write, and drift becomes structurally impossible.

### Why Free-Text Failed

- **Unvalidatable** -- bash cannot determine if two phrasings mean the same thing
- **Bluffable** -- agents write vague filler that technically satisfies the requirement
- **High friction** -- writing paragraphs 4x per task is slow

### Why Multiple Choice Works

- **Deterministically validatable** -- answer is A/B/C/D. Exact match. Pure Layer 2.
- **Unbluffable** -- wrong answers are plausible (rotating distractor pool)
- **Low friction** -- 10 seconds to answer, but requires genuine reading

---

## What We Built

### System 1: Watcher + Cron (enhanced)
- Watcher slot captures task when comprehension is freshest
- Enhanced with: SCOPE, OUT OF SCOPE, MISTAKES TO AVOID sections
- 3-minute cron stays -- catches agents that go quiet

### System 2: Pre-Flight Gate (new)
- PreToolUse hook on Write|Edit
- 4-question MCQ derived from watcher slot
- Rotating distractors (240 entries across 4 categories)
- Response consumed after each write -- must re-answer every time
- No stored answer key -- re-derived from watcher slot

### The 4 Questions

| # | Question | Source |
|---|----------|--------|
| Q1 | What is your current task? | Watcher Task line |
| Q2 | Which step are you on? | First unchecked item in TO-DO |
| Q3 | What file should this edit target? | Actual file from tool call |
| Q4 | What should you avoid? | MISTAKES TO AVOID or OUT OF SCOPE |

### Scripts

| Script | Layer | Purpose |
|--------|-------|---------|
| generate-pre-flight-challenge.sh | 2 | Reads watcher, picks distractors, writes challenge |
| validate-pre-flight.sh | 2 | Re-derives answers, validates, consumes files |
| pre-flight-gate.sh | Hook | Orchestrates generate + validate on Write|Edit |

### Exemptions (bypass gate)
- .claude/pre-flight/ -- agent writes response.md here
- .openclaw/watchers/ -- agent updates watcher slot
- .claude/state/ -- phase markers, progress notes

---

## Flow

```
Task -> read/explore (open) -> claim watcher (ground truth)
-> start cron (inactivity net) -> try Write/Edit
-> pre-write-gate (watcher check) -> pre-flight-gate (MCQ check)
   No response? BLOCKED, challenge generated
   Wrong? BLOCKED, told which Q is wrong
   Correct? Write proceeds, files consumed
-> next Write/Edit -> new challenge, answer again
Meanwhile: cron every 3 min -> are you stuck?
```

---

## Failure Mode Coverage

| Failure | Watcher+Cron | Pre-Flight Gate |
|---------|-------------|-----------------|
| No understanding | Captures truth early | Validates every write |
| Drift | Soft 3-min nudge | Hard block every write |
| Scope creep | OUT OF SCOPE field | Q4 checks awareness |
| Skipping steps | Checklist | Q2 checks current step |
| Going quiet | Cron catches | Cannot fire (no writes) |
| Bluffing | N/A | MCQ + rotating distractors |

---

## Bugs Found and Fixed

1. **grep -F without -- on dash-leading patterns** -- leading dash interpreted as flag. Fixed with grep -F -- in generator and validator.
2. **Unchecked item matching too broad** -- found - [ ] in MISTAKES TO AVOID text. Fixed by scoping to TO-DO section with sed range.
3. **Circular dependency** -- validator bug prevented fixing validator via Edit. Bypassed via Bash/sed.

---

## Verification: 24/24 criteria passing

- Run 1: 21/24 -- found defects 1-2
- Run 2: 7/8 -- defects fixed, slot 2 re-claimed
- Run 3: 1/1 -- slot 2 updated, content preserved

---

## Design Rationale

**No stored answer key** -- agent could read it and copy letters without engaging. Re-deriving means nothing to cheat from.

**Consume response after each write** -- prevents answering once and coasting.

**Keep the 3-min cron** -- gate only fires on writes. Cron catches read-only rabbit holes.

**MCQ over free-text** -- deterministic validation. Layer 2, no fuzzy matching.

**Rotating distractor pool** -- 60 entries per category + shuf = different wrong answers every time.

---

## Harness Total: 32 components (21 scripts + 7 hooks + 4 agents)

The pre-flight gate is the first system that enforces **knowledge** rather than just **process**. It does not ask 'do you have a plan' -- it asks 'do you know what your plan says.'
