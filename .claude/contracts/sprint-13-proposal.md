# Sprint 13 Proposal: Evidence Checkpoint System

## What We're Building

A periodic verification checkpoint that fires during execution (not just at entry/exit), forces the agent to spawn a verifier sub-agent, and injects the must-do source files into the verifier's environment so the builder can't control what the verifier sees.

## Deliverables

### D1: create-evidence-checkpoint.sh (NEW script)
Deterministic script that builds the checkpoint brief:
- Reads must-do source files listed in `docs/must do/must-do.md` (or `docs/must-do/` or `.claude/must-do/`)
- Reads `.claude/state/must-do-summary.md`
- Lists files modified since last checkpoint (from session-context.md or git diff)
- Writes `.claude/state/evidence-checkpoint.json` with all context
- Truncates each source file to 3000 chars to keep brief manageable
- Exit 0 on success, exit 1 if no must-do folder exists

### D2: pre-write-gate.sh modification (checkpoint block)
- New gate section after must-do summary gate, before watcher/cron gate
- Blocks source code writes when `evidence-checkpoint.json` exists with `status: pending`
- Clears on valid verdict (`evidence-verdict.json` with `verdict: PASS`)
- On FAIL verdict: stays blocked, tells agent to fix issues
- Exempt: `.claude/state/`, `.claude/evidence/`, plus all existing exemptions
- Agent tool exempt (sub-agents need to spawn)

### D3: pre-bash-gate.sh modification (mirror block)
- Same checkpoint block logic as D2 for file-writing Bash commands
- Same exemptions

### D4: on-prompt-submit.sh modification (injection)
- When `evidence-checkpoint.json` exists with `status: pending`: inject alert
- Short injection (~200 chars): "EVIDENCE CHECKPOINT ACTIVE — read .claude/state/evidence-checkpoint.json"
- Does NOT inject the full brief (too large) — sub-agent reads the file

### D5: post-write-check.sh modification (counter + trigger)
- After each write, increment counter in `.claude/state/checkpoint-counter.json`
- If counter >= threshold (default 15) AND must-do summary exists AND no active checkpoint: call create-evidence-checkpoint.sh
- On watcher step change (compare current step to last seen): reset counter, trigger immediately
- Threshold configurable via `.claude/state/checkpoint-config.json`

## Acceptance Criteria (24 items)

### Trigger Logic (6)
1. Checkpoint triggers after 15 writes when must-do summary exists
2. Checkpoint triggers immediately on watcher step change
3. Checkpoint does NOT trigger when no must-do summary exists
4. Checkpoint does NOT trigger when a checkpoint is already active
5. Counter resets to 0 after successful checkpoint (PASS verdict)
6. Counter does NOT reset after failed checkpoint (FAIL verdict)

### Block Gate (6)
7. Source code writes blocked when checkpoint is pending
8. `.claude/state/` writes allowed during checkpoint (verdict writable)
9. `.claude/evidence/` writes allowed during checkpoint (evidence writable)
10. Agent tool calls allowed during checkpoint (must spawn verifier)
11. Block clears when `evidence-verdict.json` has `verdict: PASS`
12. Block persists when `evidence-verdict.json` has `verdict: FAIL`

### Checkpoint Brief (4)
13. Brief contains full text of must-do summary
14. Brief contains content of must-do source files (truncated to 3000 chars each)
15. Brief contains list of files modified since last checkpoint
16. Brief contains verifier instruction telling sub-agent what to do

### Injection (3)
17. on-prompt-submit injects alert when checkpoint is pending
18. Injection is short (under 300 chars) — not the full brief
19. No injection when no checkpoint is active

### Non-Interference (5)
20. Projects without must-do folders: zero effect on write flow
21. Projects without must-do folders: zero injection on prompt submit
22. Existing must-do summary gate still works unchanged
23. Existing pre-flight MCQ still fires after checkpoint clears
24. Existing strategy loop breaker still works unchanged

## Verification Method

Independent sub-agent tests each criterion against the actual scripts. Tests include:
- Simulated write counts with/without must-do folders
- Checkpoint file creation and content validation
- Block/allow behavior with pending/passed/failed verdicts
- Injection presence/absence in prompt output
- Regression: existing gates unchanged

## Risk Assessment

**High risk**: Hooks fire on every Write/Edit across ALL projects. A bug here blocks every agent on the machine.
**Mitigation**: All new logic gated behind must-do folder existence check. Projects without must-do are untouched.
**Mitigation**: Checkpoint block uses same exemption pattern as existing gates (proven stable).
**Mitigation**: New script (create-evidence-checkpoint.sh) is standalone — if it fails, no checkpoint is created and writes continue normally.
