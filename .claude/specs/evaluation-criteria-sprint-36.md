# Sprint 36 — Evaluation Criteria (functional, tested in reality)

Every criterion is checked by driving the **real** scripts/hooks (live `~/.claude`), in a
**second project sandbox** that is NOT `G:/harness infra`, using the real stdin contract — no
mocks of the thing under test. Independent verifier reproduces; default FAIL.

## A — Global recall wiring (G1)
- **A1.** A new `PreToolUse` hook (`beast-recall-hook.sh`) runs `beast-surface.sh` on **Write/Edit
  and file-writing Bash** actions and emits its non-empty output as the hook's
  `hookSpecificOutput.additionalContext` (valid JSON on stdout). Empty surface → hook emits
  nothing / no additionalContext.
- **A2.** Recall is **project-root resolved**: run from a second project dir, it reads *that*
  project's `.beast/lessons.jsonl`, not harness infra's. (Reuses the existing root-walk.)
- **A3.** **Gated by the project's `beast-mode.flag`**: flag present → surfacing can fire; flag
  absent → hook produces no injection even when lessons exist.
- **A4.** **Kill-switch superset**: when the project's harness is disabled (`harness-disabled.flag`
  / resolved), the recall hook emits nothing — beast contributes zero while the harness is off.
- **A5.** **Silence by default**: a project with the flag on but no `.beast/lessons.jsonl`, and an
  action that matches no lesson, both produce empty output.
- **A6.** Wired in `settings.json` `PreToolUse` for **Write|Edit AND Bash**, and **mirrored to
  `_install`**.
- **A7.** **Bash file-write recall (grades contract C6b):** a file-writing Bash command (redirect /
  tee / `sed -i` / heredoc / `cp` / `mv` / python-write — mirroring `pre-bash-gate.sh` detection)
  whose target/content matches a lesson → the lesson is surfaced; a non-file Bash command
  (`ls`, `git status`) → **silence**.

## B — Per-project lesson pack (G2)
- **B1.** `beast-pack.sh` run in a project writes `<project-root>/.beast/lessons.jsonl` with ≥1
  schema-valid lesson (`id,scope,trigger,lesson,fix,dossier` all present; valid JSONL).
- **B2.** Lessons are **sourced from that project's own memory** — given a project with **known
  seeded** mempalace content (isolated test wing) + git history, the produced lessons reference
  **those** project-specific atoms (file/symbol/error/commit), not generic knowledge.
- **B3.** **Per-project isolation**: packing project X never writes into project Y's `.beast/`,
  and never creates a shared global store.
- **B4.** **Idempotent / no-dup**: re-running the pack does not duplicate existing lessons.
- **B5.** **No CMD windows / non-disruptive**: the pack runs to completion without spawning
  interactive console windows; any LLM distillation (cold-path, allowed) is invoked headlessly.
- **B6.** Mirrored to `_install`; MSYS-safe.

## C — End-to-end round-trip (the proof the user asked for)
- **C1.** In a **second project sandbox**: seed memory → `beast-pack.sh` builds its lessons →
  feed the real `beast-recall-hook.sh` a real action touching a **packed** atom — exercised on
  **both** a Write/Edit and a file-writing Bash command — and the matching lesson is surfaced in
  each. Pack and recall are connected through the real files only.
- **C2.** **Negative arm**: the same action in the same sandbox with the flag OFF → silence;
  and an action touching an unrelated atom → silence. (Proves it's the system, not the task.)
- **C3.** **Determinism**: identical action + identical lessons → byte-identical recall output on
  repeat.

## D — Regression & safety
- **D1.** Sprint 35 suites still green: `test-beast-toggle.sh` (21/21), `test-beast-surface.sh`
  (9/9), `test-intuition-control.sh` (8/8), `test-killswitch.sh` (22/22).
- **D2.** Projects with beast OFF and projects with no `.beast/` see **zero** behavioral change
  on Write/Edit **or Bash** (no added latency-by-blocking, no spurious context, no errors).
- **D3.** `bash -n` clean on every new/changed script; live↔`_install` byte parity verified.

## E — Process
- **E1.** TDD-first: each new suite committed/shown **failing** before implementation exists.
- **E2.** New functional suites: `tests/test-beast-recall-wiring.sh`,
  `tests/test-beast-pack.sh`, `tests/test-beast-roundtrip.sh` — all green at EVALUATE.
- **E3.** **Independent verifier** reproduces C1–C3 from scratch (its own sandbox, its own seed),
  does not read progress notes, defaults to FAIL. Verdict recorded in `.claude/evidence/`.
