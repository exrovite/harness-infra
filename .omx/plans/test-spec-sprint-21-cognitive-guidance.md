# Test Spec: Sprint 21 Cognitive Guidance Layer

## Verification Commands
- `bash -n ~/.claude/hooks/on-prompt-submit.sh`
- Phase simulations for PLAN, NEGOTIATE, BUILD, EVALUATE, COMPLETE, UNKNOWN.
- Watcher SCOPE simulations for LIGHTWEIGHT, FULL, and STANDARD.
- Strategy-loop state simulations for default/custom max fix cycles and sprint reset.
- Packet length measurements for required scenarios.
- Hash/diff confirmation that pre-write-gate.sh, pre-bash-gate.sh, and pre-flight-gate.sh are unchanged.

## Acceptance Mapping
Use `.omx/tests/sprint21/verify-sprint21.sh` to print explicit PASS/FAIL for all 33 contract criteria where possible, plus manual evidence for untouched gate scripts.
