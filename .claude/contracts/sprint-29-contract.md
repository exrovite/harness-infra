# Sprint 29 Contract — Orphaned Evidence-Checkpoint Auto-Resolve

**Phase target**: PLAN -> NEGOTIATE -> BUILD -> EVALUATE -> COMPLETE
**Source spec**: .claude/specs/orphaned-checkpoint-fix-spec.md
**Rev 2 (2026-06-02)**: freshness guard changed to FILE MTIME (verdicts often omit checked_at — confirmed PCW Sprint 48)

## Acceptance Criteria

### Shared helper (lib-helpers.sh)
- AC1: `clear_evidence_checkpoint_if_pass` exists in lib-helpers.sh and is sourceable
- AC2: Given phase=BUILD, a pending checkpoint, and a FRESH PASS verdict, the
  helper removes evidence-checkpoint.json, evidence-verdict.json,
  evidence-paths.json, evidence-remediation.md and resets checkpoint-counter.json
  to `{"writes":0,"last_step":""}`
- AC3: Helper prints the token `cleared` to stdout AND returns 0 when it clears,
  so callers can decide whether to inject a note; returns non-zero with no output otherwise
- AC4: Helper is idempotent — calling it again after a clear is a safe no-op
  (returns non-zero, no errors, no spurious output)

### Freshness guard (mtime-based)
- AC5: Given a STALE verdict (verdict FILE older than the checkpoint FILE — left
  over from before the current checkpoint), the helper does NOT clear; checkpoint
  + verdict remain on disk
- AC6: Freshness is determined by FILE MTIME: clear only if mtime(verdict) >=
  mtime(checkpoint). A verdict that OMITS checked_at is judged by mtime and is NOT
  auto-rejected. When BOTH an explicit verdict timestamp AND checkpoint
  triggered_at are present and parseable, that comparison is applied as an
  ADDITIONAL gate (verdict_ts >= triggered_at)
- AC7: mtime read (stat --format='%Y') and timestamp parsing (date -d, tolerant of
  +01:00 offset and 'Z') are Windows/MSYS-safe; unparseable values fall back to the
  mtime comparison rather than hard-failing

### Negative cases
- AC8: Given a FAIL verdict, the helper does NOT clear (remediation path preserved)
- AC9: Given phase != BUILD (PLAN/NEGOTIATE/EVALUATE/COMPLETE), the helper does
  NOT clear (matches existing gate scoping)
- AC10: Given no checkpoint file, the helper is a no-op and returns non-zero cleanly

### Integration — pre-write-gate.sh
- AC11: The inline PASS-clear at ~551-556 is replaced by a call to the shared
  helper; `bash -n pre-write-gate.sh` passes
- AC12: A BUILD-phase non-exempt source write with pending+FRESH-PASS still clears
  the checkpoint (no regression) — verified by driving the hook with real stdin JSON

### Integration — post-write-check.sh
- AC13: After an EXEMPT write (e.g. phase-complete-marker.md) during BUILD with a
  pending+FRESH-PASS checkpoint, post-write-check.sh clears the checkpoint —
  verified by invoking the hook with real PostToolUse stdin JSON
- AC14: post-write-check.sh does NOT clear when verdict is FAIL or stale
- AC15: `bash -n post-write-check.sh` passes

### Integration — on-prompt-submit.sh
- AC16: With a pending+FRESH-PASS checkpoint at turn start, on-prompt-submit.sh
  clears it and the injected context contains a `[CHECKPOINT RESOLVED]` marker —
  verified by invoking the hook with real UserPromptSubmit stdin JSON
- AC17: With a pending+FAIL or stale-PASS checkpoint, on-prompt-submit.sh injects
  NO resolved marker and leaves files in place
- AC18: `bash -n on-prompt-submit.sh` passes

### Regression / safety
- AC19: Projects with NO evidence-checkpoint.json see zero new output or behavior
  from all three hooks (clean-run smoke test)
- AC20: All modified shell files pass `bash -n`; helper is additive; no FAIL logic
  or existing gate removed

## TDD Tests (functional — run against the REAL hooks in a temp sandbox)

Each test builds a throwaway STATE_DIR with crafted JSON + controlled file mtimes,
invokes the real script, and asserts on the resulting files / output. Tests MUST
FAIL before implementation.

- T1 (AC2/AC3): BUILD + pending + fresh PASS (verdict file newer) -> helper prints
  'cleared', exit 0, all 4 evidence files gone, counter reset.
- T2 (AC4): call helper twice -> second call exits non-zero, no stdout/stderr noise.
- T3 (AC5): verdict file OLDER than checkpoint file -> helper does NOT clear; files remain.
- T4 (AC6): verdict OMITS checked_at but file is newer than checkpoint -> CLEARS (mtime path).
- T5 (AC8): FAIL verdict (file newer) -> does NOT clear.
- T6 (AC9): phase=COMPLETE + pending + fresh PASS -> does NOT clear.
- T7 (AC12): drive pre-write-gate.sh via stdin JSON, non-exempt source write,
  BUILD + pending + fresh PASS -> checkpoint cleared, exit 0 (write allowed).
- T8 (AC13): drive post-write-check.sh via stdin JSON, phase-complete-marker.md write,
  BUILD + pending + fresh PASS -> checkpoint cleared.
- T9 (AC16): drive on-prompt-submit.sh via stdin JSON, pending + fresh PASS ->
  checkpoint cleared AND injected output contains [CHECKPOINT RESOLVED].

## Done = all 20 ACs pass + all 9 TDD tests green, confirmed by independent verifier.

## Rev 3 addendum (2026-06-02) — pre-bash-gate single-source-of-truth
Concept validator found pre-bash-gate.sh has its OWN inline PASS-clear (lines 384-387)
that was NOT routed through the helper and is NOT freshness-guarded — a STALE PASS
could clear a checkpoint via a file-writing Bash command. Closing the sprint's own
single-source-of-truth goal.

- AC21: pre-bash-gate.sh's inline PASS-clear is replaced by a call to
  clear_evidence_checkpoint_if_pass (freshness-guarded); FAIL/remediation block and
  all exit-2 paths unchanged; `bash -n pre-bash-gate.sh` passes.

### TDD
- T10 (AC21): drive pre-bash-gate.sh via stdin with a file-writing Bash command,
  BUILD + pending checkpoint + STALE PASS (verdict file OLDER than checkpoint) ->
  checkpoint is NOT cleared (the guard now blocks the stale clear). And with a FRESH
  PASS (verdict newer) -> checkpoint IS cleared.
