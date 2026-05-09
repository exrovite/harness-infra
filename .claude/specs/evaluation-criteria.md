# Smoother Agent Journey — Evaluation Criteria (Sprint 23)

## Gate Labels (Change 1)
- EC1: Every BLOCKED message in pre-write-gate.sh has `[ADMIN GATE]` or `[EVIDENCE GATE]` prefix
- EC2: Every BLOCKED message in pre-bash-gate.sh has `[ADMIN GATE]` or `[EVIDENCE GATE]` prefix
- EC3: Every BLOCKED message in pre-flight-gate.sh has `[ADMIN GATE]` or `[EVIDENCE GATE]` prefix
- EC4: Evidence gate blocks include "This cannot be shortcut" or equivalent messaging
- EC5: Labels match the classification in the spec (admin gates labelled admin, evidence gates labelled evidence)

## Forward Visibility (Change 2)
- EC6: Admin gate blocks include a "GATES AHEAD" section listing upcoming gates
- EC7: Evidence gate blocks include a "GATES AHEAD" section listing upcoming gates
- EC8: Gates already cleared (e.g. contract exists) are NOT listed in "GATES AHEAD"
- EC9: Gates that don't apply (e.g. no must-do folder) are NOT listed in "GATES AHEAD"
- EC10: Gate type ([ADMIN] or [EVIDENCE]) shown for each upcoming gate

## Turn Packet (Change 3)
- EC11: on-prompt-submit.sh injects a PENDING line showing uncompleted gates
- EC12: Cleared gates drop from the PENDING line
- EC13: When all gates clear, line shows "all clear" or equivalent
- EC14: PENDING line only appears during BUILD phase

## No-Shortcut Messaging (Change 4)
- EC15: Turn packet includes process-applies-to-all-tasks note
- EC16: Evidence gate blocks include "applies to ALL tasks regardless of complexity" or equivalent

## Shared Function (Implementation Quality)
- EC17: lib-helpers.sh contains a compute_pending_gates() or equivalent shared function
- EC18: Gate-check logic is NOT duplicated across scripts — scripts call the shared function
- EC19: bash -n passes on all modified files (no syntax errors)

## No Regressions
- EC20: No gate evaluation order changed
- EC21: No gate pass/fail logic changed
- EC22: No exemption lists changed
- EC23: All existing block messages still contain their original instructions (labels/visibility are additions, not replacements)
