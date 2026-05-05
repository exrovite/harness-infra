# Must-Do Gate Diagnostic Fix — Product Spec

## Problem

The must-do summary gate in `pre-write-gate.sh` blocks agents with a generic error message regardless of which validation check failed. This causes agents to loop: they re-read files and rewrite summaries repeatedly without realizing the actual problem is a stale step file.

### Observed Failure Mode

1. Agent advances from Step N to Step N+1 in its watcher
2. Must-do gate detects step mismatch (saved step != current watcher step) → blocks
3. Error message says "REQUIRED READING you must complete" — no mention of step mismatch
4. Agent re-reads all must-do files, rewrites summary (expensive, ~5 min wasted)
5. Gate still blocks — step file still says old step
6. Agent loops 3+ times before figuring out the step file is the problem

### Root Cause

The gate has 4 independent validation checks but only one error message. The agent cannot diagnose which check failed.

## Solution

Two changes to the must-do summary gate in `pre-write-gate.sh`:

### Change 1: Diagnostic Error Messages

When `NEED_SUMMARY=true`, include the specific reason. Track which check(s) failed using a variable, then include it in the block message:

- **No summary file**: "No must-do summary found at .claude/state/must-do-summary.md"
- **Step mismatch**: "Summary is stale — watcher is on '[current step]' but summary was written for '[saved step]'. Rewrite your summary AND update .claude/state/must-do-summary-step.txt"
- **Too short**: "Summary is too short (N chars, minimum 200)"
- **Missing mentions**: "Summary doesn't reference any required file basenames"

### Change 2: Fresh Summary Bypass

If the summary file was modified within the last 5 minutes AND passes the length + mentions checks, accept it regardless of step mismatch. Auto-update the step file to the current step.

This prevents the Catch-22 where the agent writes a fresh summary but the gate still rejects it because the step file is stale.

## Files Modified

- `C:\Users\exrov\.claude\hooks\pre-write-gate.sh` — must-do summary gate section (lines 98-201)

## Evaluation Criteria

1. When no summary exists, error message says "No must-do summary found"
2. When step mismatches, error message includes both old and new step text
3. When summary is too short, error message shows character count
4. When summary doesn't mention files, error message says so
5. Fresh summary (< 5 min old) with valid length + mentions passes even if step mismatches
6. Step file is auto-updated when fresh summary bypass triggers
7. All existing must-do gate behavior preserved (exempt paths, basename check, etc.)
8. Existing phase gate tests still pass (11/11)
