# Test Spec: Sprint 20 Turn Packet System

## Static checks
- Diff/compare gate scripts before and after to prove pre-write-gate.sh, pre-bash-gate.sh, and pre-flight-gate.sh are untouched.
- Diff lib-helpers.sh to prove only new helper functions are added.

## Behavioral hook scenarios
1. Unblocked BUILD state with project watcher active and no pending blocks: output is one harness/state line plus preserved optional must-do summary only when applicable; state line is under 200 chars.
2. Fresh/locked state with no project watcher and writes >=2: output includes ordered watcher claim and cron setup actions plus exempt paths.
3. BUILD with missing sprint contract: action queue includes contract write path.
4. Must-do directory exists and summary missing: action queue includes must-do summary action.
5. Pre-flight counter indicates next gated write triggers MCQ: output includes MCQ approaching note.
6. Non-BUILD phase: output indicates writes locked/mode, without treating phase compliance as a soft action queue item.
7. Phase feedback file exists: output includes BLOCKED BY: phase-feedback FAIL resolution.
8. Evidence checkpoint pending with no verdict: output asks for verifier sub-agent.
9. Evidence FAIL without remediation: output asks for remediation file.
10. Evidence FAIL with remediation: output asks for evidence artifacts, verdict deletion, and new verifier.
11. Strategy loop tier-1: output warning/nudge, not BLOCKED BY.
12. Strategy loop tier-2: output BLOCKED BY: strategy loop and ack instructions.
13. Project watcher active: output includes current TODO step, scope, and mistakes text.
14. Worst-case packet remains under 1500 chars.

## Regression commands
- Syntax check changed shell files with ash -n.
- Run a local scenario simulation script invoking on-prompt-submit.sh under temporary state directories and registry HOME.
- Run independent architect verification after tests pass.
