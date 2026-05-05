# Sprint 7 Proposal — Must-Do Gate Diagnostic Fix

## Scope

Fix the must-do summary gate in `pre-write-gate.sh` so agents can diagnose why they're blocked and fresh summaries aren't rejected due to stale step files.

## Deliverables

1. **Diagnostic error messages** — track which check failed (no file, stale step, too short, missing mentions) and include it in the block message
2. **Fresh summary bypass** — if summary was modified within 5 minutes and passes length + mentions, accept it and auto-update the step file
3. **Test script** — `evidence/test-must-do-gate.sh` covering all failure modes

## Acceptance Criteria

| # | Criterion | Verification |
|---|-----------|-------------|
| 1 | No summary → error says "No must-do summary found" | Test script |
| 2 | Stale step → error includes old step text and new step text | Test script |
| 3 | Too short → error shows char count and 200 minimum | Test script |
| 4 | Missing mentions → error says "doesn't reference any required file" | Test script |
| 5 | Fresh summary (< 5 min) with valid length + mentions → allowed despite step mismatch | Test script |
| 6 | Fresh bypass auto-updates step file to current watcher step | Test script |
| 7 | Exempt paths still pass (`.claude/state/`, `.agent-memory/`, etc.) | Test script |
| 8 | No summary + no must-do folder → allowed (no false blocks) | Test script |
| 9 | Existing phase gate tests still pass (11/11) | Run `evidence/test-phase-gate.sh` |

## Files Modified

- `C:\Users\exrov\.claude\hooks\pre-write-gate.sh` (lines ~98-201, must-do section only)

## Files Created

- `G:\harness infra\evidence\test-must-do-gate.sh`

## Risk

Low — changes are scoped to the must-do section only. Phase gate, contract gate, and watcher gate are untouched.
