# Sprint 17 Contract — Evidence Checkpoint Remediation Gate

## Scope
When evidence checkpoint FAIL verdict is active, require agent to write a remediation plan before allowing evidence writes.

## Deliverables
1. pre-write-gate.sh: conditional `.claude/evidence/` exemption + remediation validation on FAIL
2. pre-bash-gate.sh: mirror changes
3. on-prompt-submit.sh: inject remediation instructions on FAIL
4. create-evidence-checkpoint.sh: clear stale remediation on new checkpoint

## Acceptance Criteria
- C1: `.claude/evidence/` writes blocked when FAIL + no valid remediation plan
- C2: `.claude/evidence/` writes allowed when FAIL + valid remediation plan exists
- C3: Remediation plan requires: 200+ chars, references failed phase, references must-do doc
- C4: PASS verdict clears remediation plan along with other checkpoint files
- C5: New checkpoint creation clears stale remediation from previous cycle
- C6: Prompt injection tells agent about remediation requirement on FAIL
- C7: `.claude/state/` always writable (agent can write the plan while blocked)
