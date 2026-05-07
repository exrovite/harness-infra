# Sprint 21 Contract: Segfault Detection + Stale Timeout Fix

## Goal
Prevent environment crashes (segfaults) from permanently blocking agents, and reduce stale feedback auto-clear timeout.

## Deliverables

### D1: Segfault Detection in validate-phase.sh
- Distinguish signal-killed processes (exit >= 128) from real test failures (exit 1-127)
- Segfaults produce WARNING, not FAIL
- Real test failures still produce FAIL as before

### D2: Reduced Stale Timeout in startup-recovery.sh
- Change phase-feedback.md auto-clear threshold from 7200s (2h) to 1800s (30min)

## Acceptance Criteria
| # | Criterion |
|---|-----------|
| AC1 | validate-phase.sh captures test exit code before checking |
| AC2 | Exit >= 128 prints WARNING to stderr, does NOT exit 1 |
| AC3 | Exit 1-127 still prints FAIL and exits 1 |
| AC4 | Exit 0 passes silently as before |
| AC5 | startup-recovery.sh threshold is 1800 not 7200 |
