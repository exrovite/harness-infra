# Sprint 28 Proposal — Watcher Lifecycle Completion Protocol

## What We Build

Three features fixing watcher/cron lifecycle gaps:

| Feature | What | Where |
|---------|------|-------|
| F1: Cron Pause/Resume | State file pauses cron reminders; auto-resumes on Write/Edit or 30min timeout | lib-helpers.sh, post-write-check.sh, on-prompt-submit.sh |
| F2: Watcher Release Guard | Blocks watcher release if phase != COMPLETE | pre-bash-gate.sh |
| F3: PASS Completion Reminder | Injects release protocol reminder on verifier PASS | post-write-check.sh |

## Build Order

1. F1 first (lib-helpers.sh helpers) — foundation
2. F1 in post-write-check.sh — auto-resume on write
3. F1 in on-prompt-submit.sh — pause status injection
4. F2 in pre-bash-gate.sh — release guard
5. F3 in post-write-check.sh — PASS reminder (additive to existing verdict injection)

## How Success Is Verified

32 evaluation criteria (EC1-EC32) including 8 functional TDD tests (EC25-EC32) executed live by an independent sub-agent.

## Risks and Mitigations

### R1: Cron prompt is agent-interpreted, not harness-enforced
The cron fires a text prompt. The agent must read cron-paused.json and decide to stay quiet. If the agent ignores the instruction, the cron still interrupts.
**Mitigation**: This is acceptable — the cron prompt is already soft enforcement. The pause just adds a "check before acting" step. The key enforcement (F2: release guard) is hard.

### R2: REGISTRY.json release detection could false-positive
If an agent runs a jq command on REGISTRY.json for something other than release (e.g. reading it), the detection might trigger.
**Mitigation**: Detection checks for BOTH "REGISTRY.json" in the command AND "available" as a value being set. Reading commands (jq -r '.watchers') don't set values.

### R3: Phase stuck at non-COMPLETE forever
If the agent never reaches COMPLETE (session ends, crash), the watcher is locked forever.
**Mitigation**: startup-recovery.sh already cleans stale watchers (>4h old). This existing mechanism handles abandoned sessions.

### R4: post-write-check.sh getting too large
We keep adding sections. Each Write/Edit triggers this hook.
**Mitigation**: The new code is ~15 lines for F1 (pause clear) and ~5 lines for F3 (reminder addition to existing verdict block). Minimal additions.

### R5: Cron pause file left behind across sessions
If a session ends while paused, the file persists. Next session's cron would see it.
**Mitigation**: startup-recovery.sh can clear stale cron-paused.json (>2h old), same as phase-feedback.md. Add this check.

### R6: CronDelete not directly blockable
CronDelete is a Claude Code internal tool, not a Bash command. We can't intercept it in pre-bash-gate.sh.
**Mitigation**: The watcher release guard (F2) is the real enforcement. If the agent deletes the cron but can't release the watcher, the watcher gate still blocks writes until a new cron is created. The agent learns it needs to follow the sequence.

## Revision from Self-Review

Added R5 mitigation: startup-recovery.sh should clear stale cron-paused.json. This adds one more file touch (startup-recovery.sh) and one more EC.
