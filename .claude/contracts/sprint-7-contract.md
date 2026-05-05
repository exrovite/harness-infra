# Sprint 7 Contract — Must-Do Gate Diagnostic Fix

## Scope

Fix the must-do summary gate in `pre-write-gate.sh`:
1. Add diagnostic error messages showing exactly which check failed
2. Add fresh summary bypass so recently-written summaries aren't blocked by stale step files

## Acceptance Criteria

| # | Criterion |
|---|-----------|
| 1 | No summary → error says "No must-do summary found" |
| 2 | Stale step → error includes both old and new step text |
| 3 | Too short → error shows character count and 200 minimum |
| 4 | Missing mentions → error says "doesn't reference any required file" |
| 5 | Fresh summary (< 5 min) with valid length + mentions → allowed despite step mismatch |
| 6 | Fresh bypass auto-updates step file to current watcher step |
| 7 | Exempt paths still pass unchanged |
| 8 | No must-do folder → allowed (no false blocks) |
| 9 | Existing phase gate tests pass (11/11) |

## Files Modified

- `C:\Users\exrov\.claude\hooks\pre-write-gate.sh` (must-do section only)

## Files Created

- `G:\harness infra\evidence\test-must-do-gate.sh`

## Verification

- Run `evidence/test-must-do-gate.sh` — all tests pass
- Run `evidence/test-phase-gate.sh` — 11/11 pass (regression check)
