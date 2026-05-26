# Progress Notes — Harness Infrastructure

## Current: Sprint 26 COMPLETE — Ralph Auto-Deactivation on Verifier PASS

### Problem
ralph-mode.json stayed active:true after verifier returned PASS because the only hook processing verdicts (on-prompt-submit.sh) only fires on user prompts, not during autonomous agent turns.

### What Was Built
- Added ralph auto-deactivation section to `post-write-check.sh` (PostToolUse hook)
- When evidence-verdict.json is written with PASS while ralph active, immediately sets active:false
- Timestamp freshness check (epoch + ISO lexicographic fallback)
- atomic_write with printf fallback
- Both live and install copies synced and identical

### What Was NOT Changed
- on-prompt-submit.sh verdict processing (kept as fallback)
- pre-write-gate.sh ralph blocks
- pre-bash-gate.sh ralph blocks
- Phase validation, evidence checkpoint, write tracking sections

### Verification
- Independent sub-agent: 15/15 PASS
- bash -n: both copies pass
- git diff: no changes to on-prompt-submit.sh, pre-write-gate.sh, pre-bash-gate.sh

## Previous: Sprint 22 COMPLETE — Compound Reliability Foundations
## Previous: Sprint 21 COMPLETE — Segfault Detection + Stale Timeout
## Previous: Sprint 20 COMPLETE — Turn Packet System
## Previous: Sprint 13 COMPLETE — Evidence Checkpoint System
## Previous: Sprint 12 COMPLETE — Strategy Loop Breaker
