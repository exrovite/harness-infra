# Enhanced Agent Harness — Global Development Protocol

**This protocol applies to ALL projects on this machine. Follow it on every task.**

## BEFORE ANYTHING ELSE — SESSION STARTUP (read these files NOW)

When you start a session in ANY project, read these files to restore your context.
The harness hooks keep them updated automatically — you are reading CURRENT state, not stale data.

1. **Read** `.claude/state/current-phase.json` — tells you which phase you're in (PLAN/NEGOTIATE/BUILD/EVALUATE/COMPLETE)
2. **Read** `.claude/state/progress-notes.md` — tells you what was learned, decided, built so far
3. **Read** `.agent-memory/working/active-tasks.json` (if exists) — tells you what to resume from last session
4. **Read** `.agent-memory/working/session-context.md` (if exists) — last known session state with modified files
5. If `.claude/state/injected-context.md` exists: read it — these are known fixes relevant to your work
6. If `.claude/state/watcher-self-check.md` exists: **READ IT** — the harness detected sustained work without a watcher
7. If `~/AgentWiki/index.md` exists: **Read** it — scan for wiki pages relevant to your current task. Read relevant pages from `~/AgentWiki/{project-slug}/`. Check `~/AgentWiki/_dropbox/` for unprocessed session data — if any exist, process them following `~/AgentWiki/_schema/SCHEMA.md`.

If NONE of these files exist: the harness will auto-initialize on your first file write — just proceed normally.

**These files survive across sessions, across days, across weeks.** When you come back to a project after any gap, your context is in these files.

## WATCHER SYSTEM (for multi-step tasks)

The watcher keeps you on task. It fires every 3 minutes and forces you to check your progress.
**You do NOT need a watcher for quick single edits or simple questions.**
**You DO need a watcher for any task with 3+ steps that could cause you to drift.**

The harness hook will prompt you after 5+ file writes if no watcher is claimed. Answer its self-check questions honestly.

**Location**: `~/.openclaw/watchers/`
There are 5 reusable slots (`slot-1.md` through `slot-5.md`).

### When you receive a multi-step task:
1. **Read** `~/.openclaw/watchers/REGISTRY.json` — find an available slot
2. **Claim the slot** — update REGISTRY.json status to "active", write your name and timestamp
3. **Fill the slot** with:
   - What task you're doing
   - A **checklist of every step** you need to complete (your to-do list)
   - Completion criteria
   - A reminder message: "Which step am I on? Am I stuck? Have I drifted?"
4. **Start the 3-minute loop** — use `CronCreate` with `*/3 * * * *` to set a recurring reminder
5. The reminder prompt should say: "WATCHER REMINDER — Read [slot path] NOW. Check: Which step am I on? Am I following the plan? Am I stuck?"

### When the watcher fires (every 3 minutes):
1. STOP what you're doing
2. READ your watcher slot file
3. Answer honestly: Which step am I on? Am I on task? Am I stuck?
4. If you've drifted: get back on track
5. If you've completed a step: check it off in the watcher
6. If stuck: escalate per the Escalation Protocol

### When the task is complete:
1. `CronDelete` the cron job
2. Reset the slot to "available" in REGISTRY.json
3. Clear the slot file

### Watcher slot format:
```markdown
# Watcher Slot N

**Status**: active
**Claimed by**: [your identity]
**Claimed at**: [timestamp]
**Task**: [one-line description]

## TO-DO LIST
- [ ] Step 1: [description]
- [ ] Step 2: [description]
- [x] Step 3: [completed]
...

## REMINDER
When this fires, answer: Which step am I on? Am I on task? Am I stuck?

## COMPLETION CRITERIA
[What "done" looks like]
```

## STATE MACHINE (follow in order, never skip)

Every non-trivial task follows this progression:

### PHASE: PLAN
- Analyze the user's request and the codebase
- Write a HIGH-LEVEL spec to `.claude/specs/product-spec.md` (WHAT to build, not HOW)
- Write evaluation criteria to `.claude/specs/evaluation-criteria.md`
- Stay under ~100 lines — no implementation details (prevents cascading errors)
- When done: write `.claude/state/phase-complete-marker.md`

### PHASE: NEGOTIATE
- Propose a sprint contract: what you will build and how success will be verified
- Write to `.claude/contracts/sprint-N-proposal.md`
- Review your own proposal as a sceptical evaluator
- If solid: write `.claude/contracts/sprint-N-contract.md`
- Max 3 revision attempts before escalating to user

### PHASE: BUILD
- Read the sprint contract
- **Write tests FIRST** (TDD) — tests MUST FAIL before implementation
- Implement ONE feature at a time
- Run ALL tests after each feature
- Update `.claude/state/progress-notes.md` as you work
- When done: write `.claude/state/phase-complete-marker.md`

### PHASE: EVALUATE
- Spawn an **independent sub-agent** to verify your work (use the Agent tool)
- The verifier does NOT read your progress notes — it tests the live output
- The verifier checks every criterion in the sprint contract
- If ANY criterion fails: return to BUILD with feedback
- If ALL pass: advance to next sprint or COMPLETE

### PHASE: COMPLETE
- All sprints passed. Write handoff. Commit. Report to user.

## ESCALATION PROTOCOL (when STUCK)

**DO NOT spin in circles. STOP and escalate.**

Triggers (any ONE sufficient):
- Same error 3 times in a row
- No progress for 5+ minutes
- Environment error you can't fix
- Don't know what to do next

How to escalate:
1. State the FACTS: last 3 actions, raw errors (NO theories, NO diagnosis)
2. STOP working and tell the user

## TDD PROTOCOL (mandatory)
- Write tests FIRST — before implementation
- Tests MUST FAIL first — if they pass, the test is wrong
- ONE feature at a time
- Run ALL tests after each feature
- NEVER remove tests

## BUILDER/VERIFIER SEPARATION
- You CANNOT declare your own work as verified or complete
- At EVALUATE, spawn an independent sub-agent verifier
- The verifier tests from scratch — does NOT read your notes
- The verifier's default: FAIL if in doubt

## RULES (never violate)
- NEVER skip a phase
- ALWAYS update `.claude/state/progress-notes.md` as you work
- ALWAYS run tests after code changes
- If you lose track: read `.claude/state/current-phase.json`
- If a known fix exists in `.claude/state/injected-context.md`: apply it EXACTLY
- NEVER self-certify — the evaluator decides

## AUTOMATED MEMORY (do NOT manually update these — hooks manage them)

The following files are **automatically written by harness hooks**. Do NOT waste tokens updating them manually — the hooks handle it deterministically on every Write/Edit and session Stop.

**Auto-updated on every Write/Edit** (by post-write-check.sh hook):
- `.agent-memory/working/session-context.md` — current phase, sprint, iteration, modified files (hash-gated, only writes if changed)
- `.agent-memory/working/recent-activity.jsonl` — append-only activity log (trimmed to 50 entries on session end)
- `.agent-memory/episodic/decisions/transitions.jsonl` — phase transition log (appended when phase validation passes)

**Auto-updated on session Stop** (by on-session-end.sh hook):
- `.agent-memory/episodic/sessions/YYYY-MM-DD_HH-MM-SS.md` — full session summary
- `.agent-memory/MEMORY_MANIFEST.json` — session count, last_accessed timestamp
- `.agent-memory/working/active-tasks.json` — what to resume next session

**Your responsibility (these require judgment):**
- `.claude/state/progress-notes.md` — update as you work (what you learned, decided, built)
- `features.json` / `tests.json` — update feature and test status
- `claude-progress.txt` — human-readable log

## PROTOCOL LEVELS
- **Full**: Multi-feature work, new systems → follow all phases above
- **Lightweight**: Single-file edits, config changes → implement, test, verify inline
- **Emergency**: Production down → fix first, verify immediately after, document

## CONTEXT MANAGEMENT (mandatory)
- Run `/compact` when your context exceeds 200k tokens
- Check context regularly — if a conversation is getting long, compact proactively
- After compaction, re-read `.claude/state/current-phase.json` and your watcher slot to restore context
- The 3-minute watcher cron reminder should also prompt you to check context size
