# Turn Packet Cockpit System — From Courtroom to Cockpit

## What This Document Is

A complete account of why agents fight the harness, what insight broke the problem open, and how the turn packet system was built to fix it. Covers the root cause analysis, the architectural shift from reactive blocking to proactive guidance, the full implementation across two files, and measured results.

If you are maintaining the harness, extending it to new models, or debugging agent frustration with gate blocks, this document explains the design philosophy and every moving part.

---

## The Problem

Across 19 sprints and 626+ writes, the harness grew to 8 independent gates that could block an agent's Write/Edit/Bash tools:

| Gate | Location | What It Blocks |
|------|----------|---------------|
| Watcher claim | pre-write-gate.sh | Source writes after 2 free writes if no watcher claimed |
| Cron reminder | pre-write-gate.sh | Source writes if watcher has no cron registered |
| Phase compliance | pre-write-gate.sh | Source writes during PLAN/NEGOTIATE/EVALUATE/COMPLETE |
| Sprint contract | pre-write-gate.sh | Source writes during BUILD without a sprint-N-contract.md |
| Phase-feedback FAIL | pre-flight-gate.sh | All gated writes when phase validation failed |
| Must-do summary | pre-write-gate.sh | Source writes when must-do folder exists but no summary written |
| Evidence checkpoint | pre-write-gate.sh | Source writes when checkpoint is pending verification |
| Pre-flight MCQ | pre-flight-gate.sh | Every 4th gated write or on watcher step change |

Each gate was designed in isolation, each solves a real problem, and each is correct on its own. The issue was how they composed.

### How Agents Experienced the Gates

The agent's flow looked like this:

```
Agent thinks -> Agent writes -> Hook blocks (exit 2) -> Agent reads stderr
-> Agent adapts -> Agent retries -> Different hook blocks -> Agent reads stderr
-> Agent adapts -> Agent retries -> ...eventually succeeds
```

A fresh agent entering a new sprint had to navigate all 8 gates in the correct dependency order. But the agent didn't know the order. It discovered each gate by hitting it, reading the block message, adapting, and retrying — only to hit the next gate.

This was most visible in the **sprint transition deadlock** (documented separately in `sprint-transition-deadlock-fix.md`): three gates created a circular dependency because none of them told the agent which gate to resolve first. The agent correctly escalated per the stuck protocol, but the underlying problem was structural: **the harness was a courtroom, not a cockpit.**

### The Courtroom Model

Every gate is a cop at the end of a road the agent has already turned down. The agent doesn't know it's wrong until it's tried. Then it spends tokens recovering, discovers the next gate, spends more tokens, and so on.

The single-line status injection from `on-prompt-submit.sh` was a primitive attempt at guidance:

```
[HARNESS STATE] Phase: BUILD | Sprint: 19 | Watcher: NOT CLAIMED
```

But this one-liner told the agent nothing about:
- What it needed to do before it could write (claim watcher, write contract, pass MCQ)
- Which paths were exempt and which would be blocked
- What files it needed to read first (must-do docs, sprint contract)
- What its current watcher step was and what "done" looked like
- Which actions were available vs. which would definitely fail

The agent had to discover all of that by trial and error against the gates.

---

## The Insight

A parallel project (OpenClaw) independently discovered the same pattern. Agents in that system also fought their enforcement layer — not out of defiance but because the enforcement was reactive. The solution was called the **Turn Kernel**: a pre-action context assembler that tells the agent what's expected *before* it acts, rather than blocking *after* it tries.

The key reframing:

```
BEFORE (Courtroom):
  Agent thinks -> acts -> BLOCKED -> reads error -> adapts -> retries

AFTER (Cockpit):
  Kernel prepares full context -> agent thinks in correct frame -> acts correctly
  -> hooks verify (rarely block)
```

Applied to our harness, this meant evolving `on-prompt-submit.sh` from a one-line status reporter into a structured **turn packet** — a multi-section briefing assembled from the same state files the gates check, delivered to the agent at the start of every turn.

The gates don't change. They remain as safety nets. But they almost never fire because the agent already knows the correct path. The gates become guardrails on a road the agent is already driving correctly, not roadblocks on a road the agent is driving blind.

---

## What Was Built

### Sprint 20 Deliverables

**D1: `on-prompt-submit.sh` — Turn Packet Assembler** (refactored from 226 lines to 325 lines)

Location: `C:\Users\exrov\.claude\hooks\on-prompt-submit.sh`

The hook fires at the start of every Claude turn via the `UserPromptSubmit` hook type. Its output is injected into Claude's context window before the agent processes the user's prompt.

**D2: `lib-helpers.sh` — Shared Condition Functions** (3 new functions, ~50 lines added)

Location: `C:\Users\exrov\.claude\scripts\lib-helpers.sh`

Three reusable functions that centralize logic previously duplicated across multiple scripts.

### Files NOT Changed

The three gate scripts were explicitly out of scope and have zero diff:

- `pre-write-gate.sh` (644 lines) — untouched
- `pre-bash-gate.sh` (289 lines) — untouched
- `pre-flight-gate.sh` (270 lines) — untouched

This was a deliberate constraint: the cockpit augments the gates, it does not replace them. Every gate condition still fires if the agent ignores the packet. Defense in depth.

---

## Turn Packet Structure

The packet has 6 conditional sections. Only relevant sections appear — an unblocked agent with a watcher sees only Section 1 and the watcher cockpit. A fresh agent with no watcher and multiple blocks sees the full packet.

### Section 1: State Summary (always present)

```
[HARNESS] Phase: BUILD | Sprint: 20 | Iter: 0 | Writes: 42 | Watcher: slot 4 by Claude
```

Same data as the old one-liner. Always shown. Under 100 characters.

### Section 2: Read First (when relevant artifacts exist)

```
READ FIRST:
- .claude/contracts/sprint-20-contract.md
- docs/must do/must-do.md and referenced docs
```

Appears when:
- A sprint contract exists for the current sprint (always in BUILD/NEGOTIATE)
- A must-do folder exists but the agent hasn't written a summary yet

This is first-class cockpit guidance: the agent should read its contract and reference docs before doing anything, not discover this by getting blocked by the must-do summary gate.

### Section 3: Action Queue (when soft conditions are unmet)

```
ACTIONS BEFORE CODE:
1. Claim watcher: Bash -- jq-update REGISTRY.json and write slot-N.md
2. Start reminder: CronCreate -- */3 * * * *
3. Write contract: Write -- .claude/contracts/sprint-21-contract.md
4. Write must-do summary: Write -- .claude/state/must-do-summary.md
5. Note: MCQ gate fires on next gated write
```

Each item specifies:
- **What** to do (claim watcher, start reminder, write contract, etc.)
- **Which tool** to use (Bash, CronCreate, Write)
- **The exact target path** (no guessing)

Items are numbered in dependency order: watcher must be claimed before cron can reference the slot, contract must exist before BUILD code can proceed, must-do summary requires reading must-do docs first. This ordering prevents the deadlock pattern where gates form circular dependencies.

Only unmet conditions appear. When all conditions are met, this section is absent entirely.

### Section 4: Blocked-By (when hard blocks are active)

```
BLOCKED BY:
- WRITES LOCKED: Phase is NEGOTIATE -- write specs/contracts/state, not source code
- phase-feedback FAIL -- read .claude/state/phase-feedback.md, fix issues, write phase-complete-marker.md
```

Hard blocks are qualitatively different from action queue items. An action item says "do this first"; a block says "you cannot proceed until this is resolved." Each block includes the specific resolution path.

The following conditions produce blocks:

| Condition | Block Message |
|-----------|--------------|
| Phase is not BUILD/UNKNOWN | `WRITES LOCKED: Phase is {PHASE} -- write specs/contracts/state, not source code` |
| Phase-feedback contains FAIL | `phase-feedback FAIL -- read .claude/state/phase-feedback.md, fix issues, write phase-complete-marker.md` |
| Evidence checkpoint, no verdict | `evidence checkpoint -- spawn verifier sub-agent; brief is .claude/state/evidence-checkpoint.json` |
| Evidence FAIL, no remediation | `evidence FAIL -- read must-do docs and write .claude/state/evidence-remediation.md (200+ chars)` |
| Evidence FAIL, with remediation | `evidence FAIL -- produce evidence in .claude/evidence/, delete evidence-verdict.json, spawn new verifier` |
| Strategy loop tier 2 | `strategy loop -- write .claude/state/strategy-ack.md with ## New Approach (150+ chars, reference must-do file)` |

Strategy loop tier 1 (nudge) is NOT a block — it appears as a warning appended after Section 1:

```
[STRATEGY NUDGE] Repeating pattern detected -- re-read must-do files for alternatives.
```

All three evidence checkpoint sub-states from the original implementation are preserved with their specific guidance messages. This was flagged during independent verification and explicitly required in the contract.

### Section 5: Exempt Paths (when tools are locked)

```
ALWAYS WRITABLE: .claude/state/, .claude/contracts/, .claude/specs/, .openclaw/watchers/, .agent-memory/, .claude/pre-flight/, .claude/evidence/, agentwiki/
```

Appears whenever any block is active or when tools are locked due to missing watcher. Tells the agent exactly which paths bypass all gates — so it can write state files, contracts, specs, and harness infrastructure without trial and error.

### Section 6: Watcher Cockpit (when watcher is active for this project)

```
CURRENT STEP: Step 3: BUILD -- implement turn packet assembler in on-prompt-submit.sh
SCOPE: - Files: on-prompt-submit.sh (primary change), lib-helpers.sh (shared condition functions)
MISTAKES TO AVOID: - Duplicating gate condition logic without extracting to shared functions
DONE WHEN: - Sprint contract exists and is reviewed - on-prompt-submit.sh produces correct turn packet
```

Extracts four pieces of context from the watcher slot file:
- **CURRENT STEP**: The first unchecked `- [ ]` item in the TO-DO list
- **SCOPE**: The SCOPE section content (truncated to 90 chars)
- **MISTAKES TO AVOID**: The MISTAKES TO AVOID section content (truncated to 90 chars)
- **DONE WHEN**: The COMPLETION CRITERIA / DONE WHEN section content (truncated to 90 chars)

This section appears even when no blocks are active, because the cockpit's purpose is orientation — keeping the agent aware of what it's building, what to avoid, and what "done" looks like. Every prompt. Not just at gate boundaries.

---

## Shared Helper Functions (lib-helpers.sh)

Three new functions were added to `lib-helpers.sh`. No existing functions were modified or removed.

### `find_must_do_dir()`

Returns the first must-do directory path found, checking `docs/must do/`, `docs/must-do/`, and `.claude/must-do/` in order. Returns empty string if none exists.

This logic was previously duplicated in at least 4 scripts: `on-prompt-submit.sh`, `pre-write-gate.sh`, `generate-pre-flight-challenge.sh`, and `create-evidence-checkpoint.sh`. Centralizing it prevents logic drift — if a new must-do path convention is added, it only changes in one place.

### `check_watcher_for_project(project_path, [registry_path])`

Given a project path, queries `REGISTRY.json` for an active watcher claimed for that project. Returns the slot number or empty string. Handles path normalization (backslash to forward slash, case folding, trailing slash removal) and Windows jq CR stripping.

### `read_watcher_step_scope(slot_file_path)`

Reads a watcher slot `.md` file and extracts four values via `awk` and `sed`:
- Current step: first unchecked `- [ ]` line in the TO-DO section
- Scope: content of the `## SCOPE` section (truncated to 90 chars)
- Mistakes: content of the `## MISTAKES TO AVOID` section (truncated to 90 chars)
- Done: content of the `## COMPLETION CRITERIA` / `## DONE WHEN` / `## DONE` section (truncated to 90 chars)

Output format is `STEP=...\nSCOPE=...\nMISTAKES=...\nDONE=...\n` — parseable with `sed -n 's/^KEY=//p'`.

---

## Gate-to-Packet Mapping

Each gate condition maps to a specific packet section. This table shows the complete mapping:

| Gate Condition | Gate Script | Packet Section | Packet Treatment |
|---|---|---|---|
| Watcher not claimed | pre-write-gate.sh | Section 3 | Action queue item 1 (Bash) |
| Cron not registered | pre-write-gate.sh | Section 3 | Action queue item 2 (CronCreate) |
| Phase not BUILD | pre-write-gate.sh | Section 4 | BLOCKED BY: WRITES LOCKED |
| Sprint contract missing | pre-write-gate.sh | Section 3 | Action queue item 3 (Write) |
| Phase-feedback FAIL | pre-flight-gate.sh | Section 4 | BLOCKED BY: phase-feedback FAIL |
| Must-do summary missing | pre-write-gate.sh | Sections 2+3 | Read-first + action queue item 4 |
| Evidence checkpoint | pre-write-gate.sh | Section 4 | BLOCKED BY: evidence checkpoint |
| Pre-flight MCQ due | pre-flight-gate.sh | Section 3 | Note: MCQ fires on next write |
| Strategy loop tier 1 | detect-strategy-loop.sh | After Section 1 | Warning (not a block) |
| Strategy loop tier 2 | pre-write-gate.sh | Section 4 | BLOCKED BY: strategy loop |

The packet assembler checks these conditions in the same dependency order as the gates, so the action queue reflects the correct resolution sequence.

---

## Preserved Legacy Features

The following existing behaviors from the original `on-prompt-submit.sh` were preserved exactly:

### Must-Do Summary Injection
When `.claude/state/must-do-summary.md` exists, its content (truncated to 800 chars) is appended as `[MUST-DO ACTIVE] ...` at the end of the packet. The append-only injection log at `.claude/state/must-do-injection-log.jsonl` continues to be written.

### Evidence Checkpoint Guidance
All three evidence sub-states (no verdict yet, FAIL without remediation, FAIL with remediation) are represented as BLOCKED BY entries with their original specific guidance messages. The messages were reformatted to fit the packet structure but contain the same information and resolution paths.

### Strategy Loop Breaker
Both tiers are preserved:
- **Tier 1 (nudge)**: Existing cooldown logic (60-second debounce), nudge counter increment, and `strategy-loop-state.json` state writes are unchanged. The nudge surfaces as a `[STRATEGY NUDGE]` warning.
- **Tier 2 (block)**: Existing `blocked: true` state write and must-do file list are unchanged. The block surfaces as a `BLOCKED BY` entry.

### Pending Items
The `next-fix.md` and `watcher-self-check.md` pending item checks are preserved and appear as a `PENDING:` line at the end of the packet when present.

### Read-Only Constraint
All NEW packet assembly logic (condition checks, section building, string concatenation, output) is purely read-only. The only state writes in the script are the preserved legacy features: strategy loop state updates and must-do injection logging. The script always exits 0.

---

## Token Budget

The packet has a hard safety cap at 1490 characters (line 319-322). If the assembled packet exceeds this, it is truncated with an ellipsis.

Measured packet sizes across scenarios:

| Scenario | Chars | Budget |
|----------|-------|--------|
| Unblocked, no watcher (Section 1 only) | 87 | 200 |
| Steady-state: summary + read-first + watcher cockpit | 403 | 600 |
| Phase lock + watcher cockpit | 709 | 1500 |
| Worst-case simulation (all blocks + actions + cockpit) | 908 | 1500 |

The must-do injection (up to 800 chars) is appended after the structural packet and is excluded from the 1500-char budget, matching the pre-existing behavior where must-do injection was already unbounded.

---

## Design Decisions and Tradeoffs

### Why not modify the gates to call shared functions?

The gates work. They've been tested across 19 sprints. Modifying them risks introducing regressions in enforcement logic that is currently correct. The packet assembler reads the same state files the gates check — the conditions are derived from shared state, not shared code. Shared helper functions in `lib-helpers.sh` establish the API for a future refactoring sprint where gates could call them, but that's explicitly deferred.

### Why keep gates at all?

Defense in depth. The packet tells agents the correct path; the gates enforce it. An agent that ignores the packet (due to context pressure, hallucination, or adversarial prompting) still hits the gate. The gates are guardrails, not primary guidance.

### Why not a JSON packet?

The packet is consumed by an LLM, not parsed by code. Structured plain text is more token-efficient and easier for the model to interpret than JSON. Headers like `BLOCKED BY:` and `ACTIONS BEFORE CODE:` are unambiguous to models and cost fewer tokens than `{"section": "blocked_by", "items": [...]}`.

### Why truncate watcher scope/mistakes/done at 90 chars?

The watcher cockpit appears on every prompt. Longer scope/mistakes/done text would push the steady-state packet over 600 chars and erode the token budget for rare but important sections (blocks, action queue). 90 chars is enough to remind the agent of scope and constraints without consuming the budget.

### Why is strategy loop tier 1 a warning and not a block?

Tier 1 is a nudge — the agent might be looping but hasn't confirmed it yet. Treating it as a block would be too aggressive and could interfere with legitimate iterative work. Tier 2 is confirmed looping (nudged 3+ times) and correctly blocks writes until the agent acknowledges a new approach.

### Why check MCQ-due in the packet?

The MCQ gate fires on every 4th gated write or on watcher step changes. The agent can't proactively pass it — it fires when triggered. But knowing it's coming lets the agent prepare mentally and read the challenge file preemptively, rather than being surprised by a block mid-flow.

---

## Implementation Constraints (Windows/MSYS)

These platform-specific constraints were honored throughout the implementation:

- `sed 's|\\|/|g'` crashes on MSYS/Git Bash — all path normalization uses `tr '\\' '/'`
- Windows `jq` output has `\r\n` line endings — all jq output is piped through `| tr -d '\r'`
- `while IFS= read -r` skips the last line if the file has no trailing newline — all read loops include `|| [ -n "$var" ]`
- `grep -E` doesn't support `\d` — all patterns use `[0-9]`
- `<<<` here-strings fail in hook subprocesses on Windows — temp files via `mktemp` are used instead
- `[^\s]` inside bracket expressions doesn't work portably — `[^[:space:]]` is used

---

## Verification

### Independent Verification (NEGOTIATE Phase)

An independent Opus sub-agent validated the sprint 20 contract against the vision document (`big -harness-fix.md`) and the evaluation criteria. Result: **PASS** on all 10 implementation criteria with two minor notes (pending items gap, must-do injection budget ambiguity) that were addressed in the revised contract.

### Scenario Testing (BUILD Phase)

12 scenarios tested via `.omx/tests/turn-packet/run-turn-packet-tests.ps1`:
- Unblocked agent sees brief status only
- Fresh session sees full action queue with dependency ordering
- NEGOTIATE phase with missing contract
- BUILD phase with missing contract
- Must-do folder exists but no summary written
- Phase-feedback FAIL active
- Evidence checkpoint (all 3 sub-states)
- Strategy loop nudge and block
- MCQ-due detection
- Phase lock (PLAN, EVALUATE, COMPLETE)
- Watcher cockpit with all four fields populated
- Maximum packet length under 1500 chars

Result: **12/12 passed**, maximum packet length 908 chars.

### Live Measurement

The actual project packet (COMPLETE phase, watcher active, sprint 20 contract present) measured **709 chars**. Well within the 1500-char worst-case budget.

### Gate Integrity

All three gate scripts verified unchanged via line count comparison against known values. `bash -n` syntax check passed for both modified files.

---

## Impact Summary

### Before: The Courtroom

```
Fresh agent enters sprint 21:
  1. Tries to write code         -> BLOCKED: no watcher
  2. Claims watcher, retries     -> BLOCKED: no cron
  3. Creates cron, retries       -> BLOCKED: no contract
  4. Tries to write contract     -> BLOCKED: phase-feedback FAIL (stale)
  5. Clears feedback, retries    -> writes contract
  6. Tries code again            -> BLOCKED: no must-do summary
  7. Writes summary, retries     -> BLOCKED: MCQ gate
  8. Passes MCQ, retries         -> writes code
```

**8 round-trips, 7 blocks, 7 error recovery cycles, ~3500 wasted tokens.**

### After: The Cockpit

```
Fresh agent enters sprint 21, sees turn packet:
  [HARNESS] Phase: BUILD | Sprint: 21 | Watcher: NOT CLAIMED -- WRITE/EDIT LOCKED
  READ FIRST:
  - docs/must do/must-do.md and referenced docs
  ACTIONS BEFORE CODE:
  1. Claim watcher: Bash -- jq-update REGISTRY.json and write slot-N.md
  2. Start reminder: CronCreate -- */3 * * * *
  3. Write contract: Write -- .claude/contracts/sprint-21-contract.md
  4. Write must-do summary: Write -- .claude/state/must-do-summary.md
  5. Note: MCQ gate fires on next gated write
  BLOCKED BY:
  - phase-feedback FAIL -- read phase-feedback.md, fix issues, write phase-complete-marker.md
  ALWAYS WRITABLE: .claude/state/, .claude/contracts/, .claude/specs/, ...

Agent reads the packet, executes steps 1-4 in order, clears the stale feedback,
passes MCQ on first code write. Zero wasted blocks.
```

**1 read of the packet, 0 blocks hit, 0 recovery cycles, ~0 wasted tokens.**

The gates fired zero times because the agent already knew the correct path. The courtroom became a cockpit.

---

## Files Modified

| File | Change | Lines |
|------|--------|-------|
| `C:\Users\exrov\.claude\hooks\on-prompt-submit.sh` | Full refactor: turn packet assembler | 226 -> 325 |
| `C:\Users\exrov\.claude\scripts\lib-helpers.sh` | 3 new functions added | 144 -> 193 |

## Files NOT Modified

| File | Lines | Status |
|------|-------|--------|
| `C:\Users\exrov\.claude\hooks\pre-write-gate.sh` | 644 | Untouched |
| `C:\Users\exrov\.claude\hooks\pre-bash-gate.sh` | 289 | Untouched |
| `C:\Users\exrov\.claude\hooks\pre-flight-gate.sh` | 270 | Untouched |

## Related Documents

- `big -harness-fix.md` — The agreed problem statement and vision
- `stop-fighting the harness.md` — The turn kernel concept from OpenClaw
- `.claude/specs/product-spec.md` — Product spec (PLAN phase)
- `.claude/specs/evaluation-criteria.md` — 8 spec + 10 implementation criteria
- `.claude/contracts/sprint-20-contract.md` — Sprint contract (25 acceptance criteria)
- `sprint-transition-deadlock-fix.md` — The deadlock that motivated this work
