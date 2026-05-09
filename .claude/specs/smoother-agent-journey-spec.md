# Smoother Agent Journey — Product Spec

## Problem

Agents discover harness gates by crashing into them one at a time. Each block costs a round-trip (read error, fix, retry). Admin prerequisites (watcher, contract) are discovered through failure just like evidence tests (MCQ, checkpoints). Agents can't distinguish "you forgot setup" from "you're being tested." No gate tells the agent what's coming next. Agents sometimes resent the process for "simple" tasks.

## Goal

Make the agent's journey through the harness smooth and predictable without weakening any enforcement. Three changes:

1. **Forward visibility** — every block message includes upcoming gates
2. **Gate type labelling** — every block tagged `[ADMIN GATE]` or `[EVIDENCE GATE]`
3. **No-shortcut messaging** — reinforce that all tasks follow the process

## Non-goals

- Removing or weakening any gate
- Auto-completing admin gates on behalf of the agent
- Changing the gate evaluation order or logic
- Adding new gates

## Gate Classification

### ADMIN GATES — "Can pre-brief"

These are setup prerequisites. No evidence value in the agent discovering them by failing. The turn packet should tell the agent to handle these proactively.

| # | Gate | Script | What it checks |
|---|------|--------|----------------|
| A1 | Watcher claim | pre-write-gate:667, pre-bash-gate:332 | Active watcher for this project |
| A2 | Cron reminder | pre-write-gate:694 | Cron job ID set in registry |
| A3 | Contract exists | pre-write-gate:163 | sprint-N-contract.md present |
| A4 | Phase gate (PLAN) | pre-write-gate:113, pre-bash-gate:126 | No source writes in PLAN |
| A5 | Phase gate (NEGOTIATE) | pre-write-gate:120, pre-bash-gate:130 | No source writes in NEGOTIATE |
| A6 | Phase gate (EVALUATE) | pre-write-gate:126, pre-bash-gate:134 | No source writes in EVALUATE |
| A7 | Phase gate (COMPLETE) | pre-write-gate:131 | No source writes in COMPLETE |
| A8 | ralph-mode protection | pre-write-gate:49, pre-bash-gate:66 | Don't touch ralph-mode.json |

### EVIDENCE GATES — "Must block for testing"

These exist to verify the agent knows its task, hasn't drifted, and has actually engaged with required material. The block IS the value. Cannot be pre-briefed or shortcut.

| # | Gate | Script | What it tests |
|---|------|--------|---------------|
| E1 | Pre-flight MCQ | pre-flight-gate:256 | Agent can answer questions about its task, current step, target file, and scope |
| E2 | Must-do summary | pre-write-gate:395-407 | Agent read required files, wrote 200+ char summary referencing them |
| E3 | Must-do stale check | pre-write-gate:398 | Summary still matches current watcher step (drift detection) |
| E4 | Evidence checkpoint (pending) | pre-write-gate:628, pre-bash-gate:310 | Sustained work triggers independent verification |
| E5 | Evidence checkpoint (FAIL) | pre-write-gate:589/598, pre-bash-gate:300/304 | Agent must produce evidence and get re-verified |
| E6 | Strategy loop | pre-write-gate:262, pre-bash-gate:231 | Agent must articulate a genuinely new approach (150+ chars) |
| E7 | Phase feedback FAIL | pre-flight-gate:36, pre-bash-gate:161 | Agent must fix validation failure before continuing |
| E8 | Verification step check-off | pre-flight-gate:132 | Independent sub-agent must verify before step completion |
| E9 | Ralph PASS required | pre-write-gate:86, pre-bash-gate:96 | Verifier must return PASS before completion |
| E10 | Ralph STUCK | pre-write-gate:71, pre-bash-gate:153 | Safety valve — too many iterations without PASS |

## Change 1: Gate Type Labels

Every BLOCKED message gets a prefix label:

- Admin gates: `[ADMIN GATE]` — "This is a setup prerequisite. Complete it and move on."
- Evidence gates: `[EVIDENCE GATE]` — "This is a verification test. The harness is checking that you know your task and haven't drifted. You must demonstrate understanding to proceed."

Format change to existing block messages:
```
BEFORE:
BLOCKED: BUILD phase requires a contract for sprint 5.

AFTER:
[ADMIN GATE] BLOCKED: BUILD phase requires a contract for sprint 5.
```

```
BEFORE:
BLOCKED: Pre-flight check required before writing.

AFTER:
[EVIDENCE GATE] BLOCKED: Pre-flight check required before writing.
The harness is verifying you know your task. This cannot be shortcut.
```

## Change 2: Forward Visibility ("Gates Ahead")

Each block message appends a "NEXT" section showing what gates the agent will encounter after clearing this one. The list is context-aware — it only shows gates that are actually pending (not already cleared).

Example for the watcher block:
```
[ADMIN GATE] BLOCKED: Write/Edit tools are LOCKED — no watcher active.
[... existing instructions ...]

GATES AHEAD (after you clear this):
 -> [ADMIN] Contract gate — need sprint-5-contract.md
 -> [ADMIN] Must-do summary — read docs/must-do/ files, write summary
 -> [EVIDENCE] Pre-flight MCQ — you will be quizzed on your task
 -> [EVIDENCE] Evidence checkpoints — periodic verification during BUILD
```

The "gates ahead" list is generated dynamically by checking which conditions are already satisfied. If the contract already exists, it's not listed. If must-do folder doesn't exist, it's not listed.

## Change 3: Turn Packet Phase Briefing

The on-prompt-submit.sh turn packet already injects phase/sprint/watcher info. Add a one-line "pipeline status" showing pending gates:

```
[HARNESS] Phase: BUILD | Sprint: 5 | Iter: 0 | Writes: 3 | Watcher: slot 2
PENDING: [ADMIN] contract -> [ADMIN] must-do-summary -> [EVIDENCE] pre-flight-MCQ
```

Once a gate is cleared, it drops from the PENDING line. When all admin gates are cleared:
```
PENDING: [EVIDENCE] pre-flight-MCQ (next write triggers quiz)
```

When all gates are cleared:
```
GATES: all clear — write freely
```

## Change 4: No-Shortcut Messaging

Add to the turn packet (once, at session start or first BUILD write):
```
PROCESS NOTE: Every task follows the full gate sequence — no exceptions for "simple" edits. The process IS the work. Gates catch drift and bugs that agents misjudge as impossible in "simple" tasks.
```

Add to every evidence gate block:
```
This gate applies to ALL tasks regardless of complexity. Simple tasks drift too.
```

## Implementation Scope

### Files to modify:
1. **pre-write-gate.sh** — add gate labels + "gates ahead" to all 19 block messages
2. **pre-bash-gate.sh** — add gate labels + "gates ahead" to all 13 block messages
3. **pre-flight-gate.sh** — add gate labels + "gates ahead" to 4 block messages
4. **on-prompt-submit.sh** — add PENDING pipeline line + no-shortcut note to turn packet
5. **lib-helpers.sh** — shared function to compute pending gates list

### Shared function (lib-helpers.sh):
```bash
# compute_pending_gates()
# Checks which gates are still pending and returns a formatted string
# Input: current phase, sprint number, project path
# Output: "-> [ADMIN] contract -> [EVIDENCE] pre-flight-MCQ" etc.
```

This prevents duplicating gate-check logic across 4 scripts.

## What does NOT change:
- Gate evaluation order
- Gate pass/fail logic
- Gate blocking behaviour (exit codes)
- Number of gates
- Evidence gate difficulty
- Any exemption lists
