# GPU Test Coordination Protocol

## Problem
The harness auto-runs `python -m pytest` in validate-phase.sh as Phantom TDD defense (Failure Mode #11). This creates four problems: GPU contention (two test processes load models simultaneously), agent unawareness (agent doesn't know harness tests are running), duplicate runs (harness + agent both run full suite), and no timeout/cleanup (orphaned Chromium/model processes).

## Goal
One test runner at a time. Agent knows when harness is testing. No orphaned processes. No duplicate runs. Phantom TDD defense preserved.

## Solution: Five Components

### C1: Test Lock (GPU Mutex)
- `lib-helpers.sh` gains `test_lock_acquire()`, `test_lock_release()`, `test_lock_check()`
- Lock: `.claude/state/test-lock.json` with PID, timestamp, command, source (harness|agent)
- Uses `mkdir` atomic lock (same pattern as registry locking)
- Stale detection: PID dead or lock older than timeout → auto-release

### C2: Agent Blocking During Harness Tests
- `pre-bash-gate.sh` detects test commands (pytest, npm test, python -m pytest)
- If test-lock.json exists and locked by harness → exit 2 with "HARNESS TESTS RUNNING — wait"
- If locked by agent (same session) → allow (agent's own test)

### C3: Agent Awareness (Result Injection)
- validate-phase.sh writes `.claude/state/harness-test-result.json` after test run
- post-write-check.sh and on-prompt-submit.sh inject result into turn packet
- Agent sees `[HARNESS TESTS: PASSED]` or `[HARNESS TESTS: FAILED]`

### C4: Deduplication
- validate-phase.sh checks harness-test-result.json before running: if fresh PASS exists (within N minutes), skip re-run
- on-prompt-submit.sh turn packet tells agent "tests verified by harness — skip re-run" when fresh result exists
- Freshness configurable, default 5 minutes

### C5: Timeout and Process Tree Cleanup
- validate-phase.sh reads `.claude/state/test-config.json` (optional): `{"command":"...","timeout":60}`
- Default: 60s timeout, project's default test command
- Runs tests in process group; on timeout, kills entire group
- Respects pyproject.toml ignore patterns if present

## Files Modified
- `validate-phase.sh` — lock, timeout, process group, config, result file
- `pre-bash-gate.sh` — test command detection + lock check
- `post-write-check.sh` — inject harness test result into output
- `on-prompt-submit.sh` — inject harness test result into turn packet
- `lib-helpers.sh` — test lock helper functions

## Files Created (runtime, not committed)
- `.claude/state/test-lock.json` — runtime lock
- `.claude/state/test-config.json` — optional per-project config
- `.claude/state/harness-test-result.json` — last harness test result

## Constraints
- Harness auto-test-run MUST be kept (Phantom TDD defense)
- Must work on Windows/MSYS/Git Bash
- Zero-config projects get sensible defaults
- No permanent deadlocks from crashed processes
