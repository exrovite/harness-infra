# Evaluation Criteria — Sprint 26: Ralph Auto-Deactivation

## Functional
1. post-write-check.sh contains a ralph verdict processing section
2. The section only triggers when the written file is evidence-verdict.json
3. The section only triggers when the ralph state file has active:true
4. When evidence-verdict.json has verdict "PASS" with a fresh timestamp, the ralph state file is updated to active:false
5. The update includes last_verdict:"PASS" and last_verdict_at:<timestamp>
6. Uses iso_newer_than or equivalent timestamp comparison
7. Uses atomic_write when available (same pattern as on-prompt-submit.sh)

## Non-Regression
8. on-prompt-submit.sh verdict processing code is unchanged
9. pre-write-gate.sh ralph blocks are unchanged
10. pre-bash-gate.sh ralph blocks are unchanged
11. Existing phase validation logic in post-write-check.sh is unchanged
12. Existing evidence checkpoint logic in post-write-check.sh is unchanged
13. Existing write tracking logic in post-write-check.sh is unchanged

## Sync
14. Live copy and install copy of post-write-check.sh are identical for the modified sections

## Syntax
15. bash -n passes on both copies of post-write-check.sh
