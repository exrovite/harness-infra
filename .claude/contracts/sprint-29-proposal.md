# Sprint 29 Proposal — Orphaned Evidence-Checkpoint Auto-Resolve

## What I will build

A deterministic auto-resolve for pending evidence-checkpoints that hold a FRESH
PASS verdict, so a task that ends at verifier PASS does not leave the harness
stuck in a PENDING/BUILD state.

### Changes
1. **lib-helpers.sh** — new shared function `clear_evidence_checkpoint_if_pass`
   that encapsulates the exact PASS-clear (rm checkpoint/verdict/paths/remediation,
   reset counter) WITH a freshness guard (verdict timestamp >= checkpoint
   triggered_at). Single source of truth.
2. **pre-write-gate.sh** — refactor the existing inline PASS-clear (551-556) to
   call the shared helper (no behavior change, just dedup).
3. **post-write-check.sh** — after any Write/Edit, call the helper so an exempt
   final write (phase-complete-marker.md, progress notes) consumes the PASS.
4. **on-prompt-submit.sh** — at turn start, call the helper; if it cleared,
   inject a one-line `[CHECKPOINT RESOLVED]` note.

### Self-review (sceptical evaluator)
- Risk: double-clear race between gate and post-write. Mitigated — helper is
  idempotent (rm -f on already-gone files is a no-op; clearing twice is safe).
- Risk: clearing on a stale PASS. Mitigated — freshness guard rejects verdicts
  older than the checkpoint.
- Risk: regression to FAIL path. Mitigated — helper only acts on verdict==PASS;
  FAIL untouched.
- Risk: BUILD-only scoping lost. Mitigated — helper checks phase==BUILD like gate.

## How success is verified
Independent sub-agent runs the 9 TDD tests below against the real hooks in a
temp sandbox and confirms each. Verifier defaults to FAIL.
