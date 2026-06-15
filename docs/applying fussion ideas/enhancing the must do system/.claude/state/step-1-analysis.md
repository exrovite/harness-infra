# Step 1 — Codebase Analysis (Must-Do Pack Builder)

## Codebase Structure
- `_install/hooks/` — PreToolUse/PostToolUse/Stop/UserPromptSubmit gates (pre-write-gate,
  pre-bash-gate, pre-flight-gate, on-prompt-submit, post-write-check, on-session-end).
- `_install/scripts/` — Layer-1/2 logic incl. `lib-helpers.sh` (watcher claim/lock/stale),
  `generate-pre-flight-challenge.sh`, `validate-phase.sh`.
- `tests/` — bash test suites (watcher, must-do, evidence, kill-switch, integration).
- Live mirror at `~/.claude/{hooks,scripts}` + `~/.openclaw/watchers/REGISTRY.json` (v3.0.0).
- State machine per-project in `.claude/state/`; specs in `.claude/specs/`.

## Identified Issues
- Must-do 5-file model is half-wired: discovery + MCQ honour all files, but the summary gate
  (`pre-write-gate.sh:268,317`), evidence readers (`:533,607,665`), and injection
  (`on-prompt-submit.sh:418,583`) hardcode `must-do.md` / `find … | head -1`.
- No ownership binding between a session and a specific must-do file → destructive "clear links"
  is unsafe under concurrency.
- The planning ritual (raw conversation capture, agreement, grounding links) is fully manual.
- No independent completeness check of the agreement vs the raw conversation.

## Applicable Patterns
- Watcher per-project pool (claim_pp / registry_lock / stale-reap) → reuse for must-do ownership
  (`slot-N` ↔ `must-do-N.md`).
- Transcript-on-disk path known to hooks → true raw capture by copying the `.jsonl`.
- Evidence-injection (harness feeds source files to an independent verifier) → model for the
  independent agreement validation.
- Catalogued MSYS-safe bash idioms (sed→tr, trailing-newline read loops, `\r` strip).

## Where the must-do system lives
- `_install/hooks/pre-write-gate.sh` — summary gate + evidence-checkpoint readers.
- `_install/scripts/generate-pre-flight-challenge.sh` — pre-flight MCQ (one per file).
- `_install/hooks/on-prompt-submit.sh` — must-do summary injection + strategy nudge.
- Live mirror: `~/.claude/{hooks,scripts}` (must stay in sync with `_install`).
- Watcher concurrency: `_install/scripts/lib-helpers.sh` (`watcher_claim_pp`, `registry_lock`,
  stale reap), registry `~/.openclaw/watchers/REGISTRY.json` (v3.0.0, per-project, max 5).

## 5-file model: where it IS wired vs half-wired
- IS: `pre-write-gate.sh:342` and `generate-pre-flight-challenge.sh:227` discover files via
  `find "$CAND_DIR" -maxdepth 1 -name "*.md"`; MCQ generator resolves `MUST_DO_RESOLVED[]` and emits
  one question per file (`Q6..5+MUST_DO_COUNT`).
- HALF-WIRED (hardcode `must-do.md` / `head -1`): summary gate (`pre-write-gate.sh:268,317`),
  evidence readers (`:533,607,665`), injection (`on-prompt-submit.sh:418,583`).
- Detection dirs honoured: `docs/must do`, `docs/must-do`, `.claude/must-do`.

## Reusable machinery (do not reinvent)
- Watcher claim/lock/stale-reap → must-do ownership (`slot-N` ↔ `must-do-N.md`).
- Transcript on disk at `…/projects/<proj>/<session-id>.jsonl`; hooks know the path → raw capture.
- Evidence-injection pattern (harness injects source files into verifier brief) → model for the
  independent agreement validation.

## Risks / constraints
- Destructive "clear links" is safe ONLY scoped to the caller's own file → must bind to ownership.
- Windows/MSYS bash pitfalls already catalogued in memory (sed→tr, trailing-newline read loops,
  `\r` strip, `head -1` fallbacks) — reuse the safe patterns.
- Two harness instances exist (root project + this docs subfolder); ship changes in `_install` and
  sync `~/.claude`.

## Conclusion
Single sprint: Part A rewires the half-wired gates to "caller's own file"; Part B adds the must-do
claim layer over the watcher registry, the transcript-capture hook, the pre-PLAN pack-builder step +
trigger/gate, and the independent agreement validation.
