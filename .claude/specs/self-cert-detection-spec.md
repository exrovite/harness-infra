# Sprint 5 Product Spec: Verification Enforcement (Revised)

## Problem Statement

AI agents self-certify their own work — declaring things "verified", "complete", or "working" without spawning independent subagents to check. This happens mid-task (not just at phase boundaries), so existing gates don't catch it.

Audit of 37 projects found 194 unique self-certification phrases. The most dangerous pattern: the builder agent writes "All 24 criteria verified and passed" in its own progress notes, then it gets auto-duplicated across 12+ session files.

## Design Constraint

Hooks CANNOT read the agent's conversational text output. They only see tool names and tool inputs. Scanning 194 phrases in file content is noisy and misses prose entirely.

**Better approach:** Don't try to detect bad behavior. Instead, enforce good behavior at the three structural moments where verification matters.

## Solution: Three-Point Verification Enforcement

### Point 1: MCQ Piggyback (Soft — Graduated)

The pre-flight MCQ already fires every 4th write. Add a **5th question** to the challenge:

```
## Q5: Have you done work since the last gate that should be independently verified?
A) Yes — I completed work that an independent subagent should check
B) No — all work since the last gate was trivial / already verified by a subagent
```

This is a self-report question. The agent answers honestly (or not). But the system tracks the answer:

- If the agent answers **"No"** (claiming no verification needed): increment a `no_verify_count` counter
- If the agent answers **"Yes"** (admitting verification needed): inject a nudge — "You acknowledged unverified work. Spawn an independent subagent before continuing."
- If `no_verify_count` reaches **5 consecutive "No" answers** without any Agent verification call in between: **harden to a block** on next MCQ. The agent cannot proceed until it spawns a verification subagent.

**Why this works:** It uses the existing MCQ infrastructure. No new hooks. The question forces the agent to confront whether it has self-certified. Even if it lies (answers "No" when it should say "Yes"), the counter eventually catches sustained avoidance.

### Point 2: Step Completion Gate (Hard — Binary)

When the agent edits a watcher slot to change `- [ ]` to `- [x]` (marking a step complete), the PreToolUse hook checks:

- Read the verification ledger (`verification-ledger.jsonl`)
- Is there an entry for this step from an Agent verification call?
- **No entry → BLOCKED.** "You cannot mark this step complete without independent verification. Spawn a subagent to verify this step first."
- **Entry exists → ALLOWED.**

Exceptions:
- Steps that are inherently non-verifiable (e.g., "Read the codebase") — detected by keyword: "read", "search", "explore", "set up", "claim"
- Steps where the watcher SCOPE says verification is not needed

### Point 3: Phase Completion Gate (Hard — Binary)

When the agent writes `phase-complete-marker.md`, the existing `validate-phase.sh` adds a check:

- Read the verification ledger
- For the current phase (especially BUILD and EVALUATE), was at least one Agent verification call made?
- **No → BLOCKED.** "Phase completion requires at least one independent verification. Spawn a subagent."
- **Yes → Continue normal phase validation.**

## Shared Infrastructure

All three points share two tracking files:

### 1. Verification Ledger (append-only)

**File:** `.claude/state/verification-ledger.jsonl`

Written by a PostToolUse hook on Agent tool calls. Each entry:

```json
{"ts":"2026-04-06T23:15:00","step":"Fix issue 6","prompt_snippet":"verify...","phase":"BUILD","sprint":5}
```

**What qualifies as a verification call:** The Agent tool prompt contains any of: `verify`, `review`, `evaluate`, `check`, `validate`, `test`, `audit`, `assess`. This is checked by `grep -iE` on the prompt field.

**What does NOT qualify:** Agent calls for research, exploration, search — these don't reset the counter or add ledger entries.

### 2. MCQ Verification Counter

**File:** `.claude/pre-flight/verify-counter.json`

```json
{"no_verify_count": 3, "last_reset": "2026-04-06T23:00:00", "hardened": false}
```

- Increments when agent answers Q5 with "No"
- Resets to 0 when a qualifying Agent verification call happens
- Sets `hardened: true` at count 5 — next MCQ blocks until verification subagent runs

## Changes to Existing Scripts

### generate-pre-flight-challenge.sh

**Add Q5** after Q4. Q5 is not derived from the watcher slot — it's a fixed self-report question. Two options only (Yes/No mapped to A/B, shuffled).

The challenge header changes from "Answer all 4 questions" to "Answer all 5 questions" and the format example adds `Q5: A`.

### validate-pre-flight.sh

**Add Q5 validation.** Unlike Q1-Q4, Q5 has no "correct" answer — both are valid. But the validator:
- Records which answer was given
- If "No" (no verification needed): increments `no_verify_count` in `verify-counter.json`
- If "Yes" (verification needed): injects nudge text into stderr output
- If `hardened` is true AND no new verification ledger entry exists: exit 1 (block)

### pre-flight-gate.sh

**Add hardened check.** Before generating the MCQ, check `verify-counter.json`. If `hardened: true` AND no Agent verification call in ledger since last MCQ: block with message "You must spawn an independent subagent to verify your recent work before continuing."

### New hook: agent-call-tracker.sh (PostToolUse on Agent)

When an Agent tool call completes:
- Read the prompt from stdin
- Check if it contains verification language (`grep -iE 'verify|review|evaluate|check|validate|test|audit|assess'`)
- If yes: append entry to `verification-ledger.jsonl` and reset `verify-counter.json` (set `no_verify_count: 0`, `hardened: false`)
- Output: no additionalContext needed (silent tracking)

### New: step-completion-gate logic in pre-flight-gate.sh

When PreToolUse detects the target file is a watcher slot AND the edit content contains `[x]`:
- Extract the step text being checked off
- Check verification ledger for a matching entry
- No match → exit 2 with block message
- Match → exit 0

## Integration Flow

```
Agent attempts Write/Edit
        |
        v
pre-write-gate.sh: watcher + cron check         [Layer 1]
        |
        v
pre-flight-gate.sh: hardened check               [Layer 2 — NEW]
        |  (if verify-counter hardened + no ledger entry → block)
        |
        v
pre-flight-gate.sh: step completion check        [Layer 2 — NEW]
        |  (if editing watcher slot [x] → check ledger)
        |
        v
pre-flight-gate.sh: counter + MCQ check          [Layer 2 — existing]
        |  (MCQ now has Q5 verification question)
        |
        v
Write/Edit executes
        |
        v
post-write-check.sh: counter, memory             [Layer 1 — existing]

Agent spawns subagent (Agent tool)
        |
        v
agent-call-tracker.sh: verification language?     [Layer 2 — NEW]
        |  (if yes → ledger entry + counter reset)
```

## What This Does NOT Do

- Does not scan file content for self-certification phrases (too noisy)
- Does not scan conversational text (hooks can't see it)
- Does not block non-verification Agent calls
- Does not replace the existing MCQ Q1-Q4 (those check task knowledge; Q5 checks verification honesty)
- Does not require the agent to verify trivial steps (read/search/setup steps are exempt)

## New Files

| File | Purpose |
|------|---------|
| `~/.claude/hooks/agent-call-tracker.sh` | PostToolUse on Agent — writes verification ledger, resets counter |
| `.claude/state/verification-ledger.jsonl` | Append-only log of verification Agent calls |
| `.claude/pre-flight/verify-counter.json` | MCQ Q5 "No" counter + hardened flag |

## Modified Files

| File | Change |
|------|--------|
| `~/.claude/scripts/generate-pre-flight-challenge.sh` | Add Q5 generation |
| `~/.claude/scripts/validate-pre-flight.sh` | Add Q5 validation + counter logic |
| `~/.claude/hooks/pre-flight-gate.sh` | Add hardened check + step completion gate |
| `~/.claude/settings.json` | Add PostToolUse Agent hook entry |

## Success Criteria

1. MCQ challenges contain Q5 asking about unverified work
2. Q5 "No" answer increments verify-counter
3. Q5 "Yes" answer injects nudge telling agent to spawn subagent
4. After 5 consecutive "No" answers, gate hardens and blocks until verification
5. Agent verification call resets counter and adds ledger entry
6. Non-verification Agent calls do NOT reset counter
7. Checking off a watcher step is blocked without a matching ledger entry
8. Phase-complete-marker write is blocked without any ledger entry for the phase
9. Trivial steps (read/search/setup) are exempt from step-completion gate
10. Existing Q1-Q4 continue to work identically
11. All existing hooks remain functional
12. All scripts pass bash -n syntax check
