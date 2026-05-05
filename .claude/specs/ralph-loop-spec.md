# Persistent Execution Loop ($ralph) — Product Spec

## Problem

Our harness has all the pieces for iterative work — phase gates, evidence checkpoints, verifier injection, fix ceiling — but the agent must manually drive the BUILD → EVALUATE → BUILD cycle. This means:

1. **Agents skip verification** — they finish BUILD, declare success, and move to COMPLETE without spawning a verifier
2. **Agents self-certify** — even when they do "verify," they read their own progress notes instead of testing independently
3. **Fix loops are shallow** — agents fix one thing the verifier caught, then declare done instead of re-running the full verification
4. **Users can't force the loop** — there's no way to say "keep going until this actually passes" in a way the agent can't sidestep

OMX solved this with `$ralph` — a persistent execution loop that autonomously cycles through implement → verify → fix until verified-done or hard-failed. The agent doesn't choose whether to verify; the loop forces it.

## Solution

Build a **persistent execution loop** activated by user keyword (`$ralph`) that the harness enforces through Layer 2 gates. The agent cannot skip verification, cannot self-certify, and cannot declare completion until an independent verifier approves.

### Activation

User types `$ralph` anywhere in their prompt. The `on-prompt-submit.sh` hook detects it, creates `.claude/state/ralph-mode.json`, and from that point forward the harness enforces the loop.

### The Loop

```
┌─────────────────────────────────────────────────┐
│                   RALPH LOOP                     │
│                                                  │
│  IMPLEMENT ──► VERIFY ──► PASS? ──► COMPLETE     │
│       ▲                     │                    │
│       │                     │ FAIL               │
│       │                     ▼                    │
│       └──────── FIX ◄──────┘                     │
│                                                  │
│  Hard ceiling: max_iterations (default 5)        │
│  Terminal: STUCK after ceiling                   │
└─────────────────────────────────────────────────┘
```

Each iteration:
1. **IMPLEMENT**: Agent works on the task (normal BUILD phase)
2. **VERIFY**: Harness FORCES verification — agent MUST spawn a verifier sub-agent before it can write any completion marker. The gate blocks phase-complete-marker.md until evidence-verdict.json exists with a fresh timestamp.
3. **PASS → COMPLETE**: If verifier says PASS, harness allows transition to COMPLETE
4. **FAIL → FIX**: If verifier says FAIL, harness injects the failure details and forces the agent back to implementing. The agent cannot skip to COMPLETE.

### What Makes It Unbypassable

Three Layer 2 enforcement points:

**Gate 1 — Completion block** (`pre-write-gate.sh`):
When ralph-mode.json is active, block writes to `phase-complete-marker.md` UNLESS `evidence-verdict.json` exists with verdict "PASS" and a timestamp within the current iteration.

**Gate 2 — Ralph state protection** (`pre-write-gate.sh`):
Block any agent attempt to write/delete `ralph-mode.json`. Only the user can deactivate ralph mode (by manually deleting the file or setting active:false).

**Gate 3 — Iteration accounting** (`on-prompt-submit.sh`):
Track iteration count. When max_iterations is reached without PASS, inject terminal STUCK block — same pattern as the fix ceiling from sprint 21.

### Turn Packet Injection

When ralph-mode is active, the turn packet gains a `RALPH LOOP:` section:

```
RALPH LOOP: Iteration 2/5 | Last verdict: FAIL (3 criteria failed)
NEXT: Fix the failures listed in evidence-verdict.json, then spawn a verifier sub-agent.
DO NOT write phase-complete-marker.md until verifier returns PASS.
```

### State File

`.claude/state/ralph-mode.json`:
```json
{
  "active": true,
  "activated_by": "user_prompt",
  "activated_at": "2026-05-04T14:30:00+00:00",
  "iteration": 2,
  "max_iterations": 5,
  "last_verdict": "FAIL",
  "last_verdict_at": "2026-05-04T14:45:00+00:00",
  "failed_criteria": ["C3", "C7", "C12"],
  "sprint": 22
}
```

### Deactivation

Ralph mode can only end in three ways:
1. **Verifier PASS** — harness auto-deactivates, allows COMPLETE
2. **Iteration ceiling** — terminal STUCK, user must intervene
3. **User manual delete** — user deletes ralph-mode.json

The agent cannot deactivate it. The gate blocks agent writes to ralph-mode.json.

## What Success Looks Like

- User types `$ralph implement the payment system` → harness activates loop
- Agent implements → harness forces verification → verifier finds failures → harness injects failures → agent fixes → re-verifies → repeat
- Agent CANNOT write phase-complete-marker.md until verifier returns PASS
- Agent CANNOT delete ralph-mode.json
- Agent CANNOT skip verification
- After 5 failed iterations, terminal STUCK fires automatically
- Turn packet shows current iteration, last verdict, and explicit next action

## Design Constraints

1. Keyword detection in `on-prompt-submit.sh` via stdin (user prompt JSON)
2. State protection in `pre-write-gate.sh` (ralph-mode.json is user-only)
3. Completion gate in `pre-write-gate.sh` (phase-complete-marker requires PASS verdict)
4. Iteration tracking in `on-prompt-submit.sh` (reads ralph-mode.json, updates iteration count)
5. Compatible with existing evidence checkpoint system
6. Compatible with fix ceiling (sprint 21) — ralph's iteration ceiling is separate from strategy loop fix ceiling
7. `pre-bash-gate.sh` also blocks ralph-mode.json writes via Bash
