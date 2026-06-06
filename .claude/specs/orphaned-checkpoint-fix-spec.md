# Orphaned Evidence-Checkpoint Fix — Product Spec (Sprint 29)

## Problem

The evidence-checkpoint system blocks BUILD-phase source writes until an independent
verifier returns a PASS verdict. The PASS-clear is implemented ONLY inside the
PRE-write gate (`pre-write-gate.sh:551-556`), and it runs as a *side-effect of the
next non-exempt source write during BUILD*:

```
if [ "$EC_RESULT" = "PASS" ]; then
    rm -f "$EC_CHECKPOINT" "$EC_VERDICT" "$EC_PATHS"
    printf '{"writes":0,"last_step":""}' > checkpoint-counter.json
```

This means: a pending checkpoint clears only if the agent attempts ANOTHER
non-exempt source write after the verifier passes.

## The Gap (observed live in Private Content Wizard, 2026-05-31)

When a task FINISHES at the verifier PASS — e.g. a documentation-only sprint, or
any sprint whose last action before completion is an EXEMPT write
(phase-complete-marker.md, progress-notes.md, contracts, specs) — there is no
subsequent non-exempt source write to trigger the clear. The result:

- `evidence-checkpoint.json` stays `status: "pending"` forever
- `evidence-verdict.json` holds an unconsumed `PASS`
- The harness reports a PENDING checkpoint and will not cleanly flip to COMPLETE
- The NEXT sprint inherits a stuck BUILD state — the exact "previous phase never
  completed" failure Sprint 28 was built to prevent

## Solution

Make a pending evidence-checkpoint with a FRESH PASS verdict auto-resolve at task
end, independent of any later non-exempt source write. Add the same PASS-clear at
deterministic trigger points that fire when a task winds down:

1. **post-write-check.sh** (PostToolUse on Write/Edit) — fires on EVERY write,
   including exempt ones. When it sees a pending checkpoint + fresh PASS verdict,
   clear it. This catches the common "last action is phase-complete-marker.md /
   progress-notes write" case.

2. **on-prompt-submit.sh** (UserPromptSubmit) — fires at the start of every turn.
   If a pending checkpoint + fresh PASS verdict is present, clear it and inject a
   short confirmation note. This catches the "agent stopped, user sends next
   prompt" case.

The clear logic must be IDENTICAL to the gate's existing behavior (same files
removed, same counter reset) so there is a single source of truth for "what a
PASS-clear does."

## Freshness Guard (critical)

Only clear on a PASS whose timestamp is NOT older than the checkpoint it answers.
A PASS must correspond to the CURRENT pending checkpoint, never a stale verdict
left from a prior checkpoint. Compare the verdict timestamp
(`checked_at`/`timestamp`/`verdict_at`) against the checkpoint `triggered_at`:
the verdict must be >= triggered_at. If the verdict is older, do NOT clear
(it is stale — a new verification is required).

## What Stays Unchanged

- BUILD-phase scoping: evidence checkpoint only applies in BUILD (unchanged)
- FAIL handling + remediation-plan validation (untouched)
- The verifier protocol and verdict format (untouched)
- The existing pre-write-gate PASS-clear (stays — this is additive defense in depth)

## What Success Looks Like

- A doc-only sprint ending at verifier PASS auto-clears its pending checkpoint
  WITHOUT any further source write
- A sprint whose final action is writing phase-complete-marker.md auto-clears
- A STALE PASS (older than the current checkpoint) does NOT clear — re-verify required
- A FAIL verdict does NOT clear (remediation still enforced)
- Projects with no checkpoint are unaffected (zero new behavior)
- No double-clear errors when both the gate and the new trigger see the same PASS

## Design Constraints

1. Single source of truth for the clear action — extract to a shared helper in
   lib-helpers.sh (e.g. `clear_evidence_checkpoint_if_pass`) used by all 3 sites
2. PostToolUse reads tool context via STDIN JSON (HOOK_INPUT=$(cat)), not env vars
3. Windows/MSYS-safe: tr -d '\r', no `sed 's|\|/|g'`, temp files not here-strings
4. jq dual-path for timestamp fields; tolerate missing/non-JSON verdict gracefully
5. Hooks emit JSON to stdout, diagnostics to stderr only
