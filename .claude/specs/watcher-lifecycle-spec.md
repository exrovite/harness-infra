# Sprint 28 Product Spec — Watcher Lifecycle Completion Protocol

## Problem

Three related lifecycle gaps in the watcher/cron system:

1. **Cron interrupts discussions**: The 3-minute watcher cron fires during PLAN/NEGOTIATE phases when the user and agent are just talking. No code is being written, so drift prevention is pointless — but the cron butts in every 3 minutes.

2. **Premature watcher/cron cleanup**: Agents release watchers and delete crons after verifier PASS but BEFORE the COMPLETE phase finishes. Write/Edit tools lock (no watcher), agent can't write phase-complete-marker, next sprint inherits stale phase state.

3. **No forewarning on release protocol**: When the verifier returns PASS, the agent has no reminder about the required completion sequence. It tries to release immediately and hits a block it didn't expect.

## Solution — Three Features

### F1: Cron Pause/Resume

A state file `.claude/state/cron-paused.json` controls whether the cron prompt is active or suppressed.

**Pause trigger**: User says "pause cron" or agent enters discussion. Agent writes `cron-paused.json` with `paused: true`, `resume_at` (now + 30min), `resume_on_write: true`.

**Resume triggers** (whichever comes first):
- 30 minutes elapsed (time-based auto-resume)
- Agent performs a Write or Edit (activity-based auto-resume via post-write-check.sh)

**How it works**: The cron still fires every 3 minutes (can't change CronCreate interval dynamically). But the cron prompt tells the agent to check `cron-paused.json` first. If paused and not expired, agent acknowledges silently and continues. The post-write-check.sh hook clears the pause on Write/Edit.

### F2: Watcher Release Guard

A check in pre-bash-gate.sh that detects watcher release attempts (jq writes to REGISTRY.json setting status to "available") and blocks them if `current-phase.json` phase is not COMPLETE.

**What it blocks**: Bash commands that modify REGISTRY.json to set a slot to "available" while the current phase is BUILD/EVALUATE/PLAN/NEGOTIATE.

**What it allows**: Release when phase is COMPLETE, or when no phase file exists (fresh project).

### F3: Verifier PASS Completion Reminder

When post-write-check.sh detects a PASS verdict in evidence-verdict.json, the injected context message includes the completion protocol reminder:

> "Verifier PASS — DO NOT release watcher or delete cron yet. Sequence: write phase-complete-marker.md, confirm COMPLETE transition, THEN release watcher and cron."

Soft enforcement (reminder) backed by F2's hard enforcement (block).

## Files Modified

| File | Feature | Change |
|------|---------|--------|
| `post-write-check.sh` | F1, F3 | Clear cron-paused.json on Write/Edit; add PASS reminder to verdict injection |
| `pre-bash-gate.sh` | F2 | Detect REGISTRY.json release attempts, block if phase != COMPLETE |
| `lib-helpers.sh` | F1 | Add `cron_pause()` and `cron_resume()` helper functions |
| `on-prompt-submit.sh` | F1 | Inject pause status into turn packet so agent knows cron is paused |

## Files NOT Modified

- validate-phase.sh, pre-write-gate.sh, pre-flight-gate.sh, on-session-end.sh
- CronCreate/CronDelete internals (can't modify)

## Non-Goals

- Changing the 3-minute cron interval dynamically
- Blocking CronDelete directly (it's a Claude Code internal tool)
- Auto-writing phase-complete-marker (agent should still do this consciously)
