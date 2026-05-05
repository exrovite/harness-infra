# Persistent Execution Loop ($ralph) — Sprint 22 Plan

## The Problem

Our harness has all the pieces for iterative work — phase gates, evidence checkpoints, verifier injection, fix ceiling — but the agent must manually drive the BUILD > EVALUATE > BUILD cycle. This creates three failure modes:

1. **Agents skip verification** — they finish BUILD, declare success, move to COMPLETE without spawning a verifier
2. **Agents self-certify** — even when they "verify," they read their own notes instead of testing independently
3. **Fix loops are shallow** — agents fix one thing, then declare done instead of re-running full verification
4. **Users can't force the loop** — there's no way to say "keep going until this passes" that the agent can't sidestep

OMX solved this with `$ralph` — a persistent execution loop that autonomously cycles implement > verify > fix until verified-done or hard-failed.

## The Solution

A user-activated persistent execution loop enforced through Layer 2 gates. The agent cannot skip verification, cannot self-certify, and cannot deactivate the loop.

### How It Works

```
User types: $ralph implement the payment system

     IMPLEMENT ──> VERIFY ──> PASS? ──> COMPLETE
          ^                     |
          |                     | FAIL
          |                     v
          └──────── FIX <──────┘

     Hard ceiling: 5 iterations (configurable via $ralph:N)
     Terminal: STUCK after ceiling
```

### Three Unbypassable Enforcement Points

**Gate 1 — Completion block** (pre-write-gate.sh):
When ralph-mode.json is active, BLOCK writes to phase-complete-marker.md unless evidence-verdict.json shows PASS with a fresh timestamp. The agent literally cannot complete until a verifier approves.

**Gate 2 — State protection** (pre-write-gate.sh + pre-bash-gate.sh):
BLOCK any agent attempt to write or delete ralph-mode.json. Only the user can deactivate ralph mode. The agent cannot turn it off.

**Gate 3 — Iteration ceiling** (on-prompt-submit.sh):
Track iteration count. After N failed cycles (default 5), inject terminal STUCK block. Agent must write stuck-report.md and WAIT for user. Same pattern as sprint 21 fix ceiling.

### Activation

- User types `$ralph` anywhere in their prompt during BUILD phase
- on-prompt-submit.sh detects the keyword via stdin JSON, creates ralph-mode.json
- Phase guard: `$ralph` during PLAN/NEGOTIATE/EVALUATE/COMPLETE injects a warning but does NOT activate
- `$ralph:3` sets max_iterations to 3

### Auto-Deactivation

Ralph can only end three ways:
1. **Verifier PASS** — harness sets active:false, allows COMPLETE transition
2. **Iteration ceiling** — terminal STUCK, user must intervene
3. **User manual delete** — user removes ralph-mode.json

### Turn Packet Injection

When ralph is active, the turn packet gains a RALPH LOOP section:

- First iteration: `RALPH LOOP: Iteration 1/5 | Implement, then spawn verifier. You CANNOT complete until PASS.`
- After FAIL: `RALPH LOOP: Iteration 2/5 | FAIL — fix failures, then spawn verifier. Cannot complete until PASS.`
- After PASS: `RALPH LOOP: PASSED at iteration 2. Write phase-complete-marker.md to finish.`
- After ceiling: `RALPH LOOP: STUCK — 5 iterations exhausted. STOP. Write stuck-report.md. WAIT for user.`

## Why This Matters

This is the missing piece between our gate system and true autonomous completion. Currently:

| Without $ralph | With $ralph |
|---------------|-------------|
| Agent chooses whether to verify | Harness forces verification |
| Agent can skip to COMPLETE | Completion blocked until PASS |
| Agent can self-certify | Must spawn independent verifier |
| User hopes agent will iterate | Harness guarantees iteration |
| No iteration ceiling | Hard failure after N attempts |

The key insight from OMX: **the loop driver should be the harness, not the agent**. Agents don't choose whether to verify — the infrastructure forces it.

## Contract Status

- Spec: `.claude/specs/ralph-loop-spec.md`
- Contract: `.claude/contracts/sprint-22-contract.md` (42 acceptance criteria)
- First verification: REJECTED — 5 blocking issues found
- Issues fixed: stdin variable reference, PASS auto-deactivation, phase guard on activation, packet truncation safety, missing verdict deletion criterion
- Re-verification: pending (contract revised, ready for BUILD when chosen)

## Files That Will Change (When Built)

| File | Change |
|------|--------|
| `on-prompt-submit.sh` | Add stdin reading, keyword detection, ralph state management, turn packet section, iteration accounting |
| `pre-write-gate.sh` | Add completion gate (phase-complete-marker requires PASS), ralph-mode.json protection |
| `pre-bash-gate.sh` | Add ralph-mode.json protection |
| `ralph-mode.json` | New state file (created by harness, protected from agent) |

## Integration With Existing Systems

- **Evidence checkpoints**: Ralph reuses the existing evidence-checkpoint.json infrastructure
- **Strategy loop breaker**: Independent — ralph tracks iterations separately from fix cycles
- **Fix ceiling (sprint 21)**: Both can be active; more restrictive gate wins
- **Verifier injection (sprint 21)**: EVALUATE-phase verifier rules apply when verifier sub-agent runs
- **Watcher system**: No conflict — ralph operates at verification level, watchers at task-tracking level

## What OMX Has That We Still Won't Have (After This Sprint)

- Auto-spawning the verifier (our agent still spawns it manually; harness just blocks until it does)
- Team/multi-agent parallel execution
- Visual verdict integration
- PRD/test-spec as hard gates (advisory only via sprint 21 PROTOCOL line)
- Worker scope boundaries for sub-agents
