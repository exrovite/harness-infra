# Sprint 23 Proposal — Smoother Agent Journey

## What We're Building

Add forward visibility, gate type labels, and no-shortcut messaging to all harness gate scripts so agents can navigate the pipeline predictably instead of discovering gates by crashing into them.

## Deliverables

### D1: Shared gate-status function in lib-helpers.sh
- `compute_pending_gates()` function that checks which gates are still pending
- Inputs: current phase, sprint number, project path
- Outputs: formatted string of pending gates with [ADMIN] or [EVIDENCE] tags
- Checks: watcher claimed, cron set, contract exists, must-do folder exists + summary written, pre-flight pending, evidence checkpoint pending

### D2: Gate labels on all BLOCKED messages
- Every BLOCKED message in pre-write-gate.sh prefixed with `[ADMIN GATE]` or `[EVIDENCE GATE]`
- Every BLOCKED message in pre-bash-gate.sh prefixed with `[ADMIN GATE]` or `[EVIDENCE GATE]`
- Every BLOCKED message in pre-flight-gate.sh prefixed with `[ADMIN GATE]` or `[EVIDENCE GATE]`
- Evidence gates include "This cannot be shortcut" and "applies to ALL tasks regardless of complexity"
- Classification matches the spec exactly

### D3: Forward visibility ("GATES AHEAD") on all BLOCKED messages
- Each block appends upcoming gates section using compute_pending_gates()
- Already-cleared gates excluded
- Non-applicable gates excluded (e.g. no must-do folder = no must-do gate listed)
- Each upcoming gate shows its type ([ADMIN] or [EVIDENCE])

### D4: Turn packet pipeline status in on-prompt-submit.sh
- PENDING line injected during BUILD phase showing uncompleted gates
- Cleared gates drop from the line
- "All clear" when everything is satisfied
- No-shortcut process note injected

## Files Modified
1. `lib-helpers.sh` — add compute_pending_gates()
2. `pre-write-gate.sh` — add labels + gates-ahead to 19 blocks
3. `pre-bash-gate.sh` — add labels + gates-ahead to 13 blocks
4. `pre-flight-gate.sh` — add labels + gates-ahead to 4 blocks
5. `on-prompt-submit.sh` — add PENDING line + no-shortcut note

## Files NOT Modified
- Gate evaluation order: unchanged
- Gate pass/fail logic: unchanged
- Exemption lists: unchanged
- Exit codes: unchanged

## Acceptance Criteria

### Gate Labels (7 criteria)
- AC1: All 19 BLOCKED messages in pre-write-gate.sh have correct gate type prefix
- AC2: All 13 BLOCKED messages in pre-bash-gate.sh have correct gate type prefix
- AC3: All 4 BLOCKED messages in pre-flight-gate.sh have correct gate type prefix
- AC4: Admin gates labelled `[ADMIN GATE]`, evidence gates labelled `[EVIDENCE GATE]`
- AC5: Evidence gate blocks include "cannot be shortcut" language
- AC6: Evidence gate blocks include "all tasks regardless of complexity" language
- AC7: No gate is mislabelled (admin vs evidence matches spec classification)

### Forward Visibility (6 criteria)
- AC8: Block messages call compute_pending_gates() to append upcoming gates
- AC9: Upcoming gates show type tag ([ADMIN] or [EVIDENCE])
- AC10: Gates already satisfied are excluded from the list
- AC11: Gates not applicable to this project are excluded
- AC12: "GATES AHEAD" section appears after the existing block instructions
- AC13: Format is readable — one gate per line with arrow prefix

### Turn Packet (5 criteria)
- AC14: PENDING line appears in turn packet during BUILD phase
- AC15: Cleared gates are absent from PENDING line
- AC16: When all gates clear, shows "all clear" or equivalent
- AC17: PENDING line does NOT appear during PLAN/NEGOTIATE/EVALUATE/COMPLETE
- AC18: No-shortcut process note injected in turn packet

### Implementation Quality (5 criteria)
- AC19: compute_pending_gates() exists in lib-helpers.sh as a shared function
- AC20: Gate scripts source lib-helpers.sh and call the shared function (no duplication)
- AC21: bash -n passes on all 5 modified files
- AC22: No gate evaluation order, pass/fail logic, or exemption lists changed
- AC23: All existing block instructions preserved (labels and gates-ahead are additions only)

## Verification Method
Independent sub-agent reads all 5 modified files and checks each AC. For AC8-AC13, verifier traces compute_pending_gates() logic to confirm dynamic exclusion works. For AC22, verifier diffs gate logic sections against pre-change versions.

## Risk
- Medium complexity: 36 block messages to modify across 3 gate scripts
- Mitigation: shared function prevents logic duplication; labels are pure string prefixes
- Rollback: git revert single commit
