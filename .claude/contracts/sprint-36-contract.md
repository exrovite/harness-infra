# Sprint 36 — Contract: Beast-Mode Global Recall + Per-Project Pack

**Status:** PROPOSED (awaiting user go-ahead to BUILD).
**Spec:** `.claude/specs/beast-mode-global-recall-spec.md` ·
**Criteria:** `.claude/specs/evaluation-criteria-sprint-36.md` ·
**Proposal:** `.claude/contracts/sprint-36-proposal.md`
**Agreement of record:** `docs/applying fussion ideas/beast-mode-global-agreement-verbatim.md`

## Scope (this sprint builds exactly this)
Close the two gaps that make beast-mode global-in-machinery but inert-in-practice:
**G1** global recall wiring (fires in any project, project-root-resolved, flag-gated,
kill-switch-honoring, silent by default) and **G2** a per-project lesson pack that builds a
project's own `.beast/lessons.jsonl` from that project's own memory. Recall is **inject-only**
(non-blocking). No uptake gate, no birth-event capture (Sprint 37).

## Acceptance criteria (binary, reality-tested)

### Recall wiring
- **C1.** `beast-recall-hook.sh` exists; on Write/Edit it runs `beast-surface.sh` and, on a
  non-empty surface, emits valid JSON `hookSpecificOutput.additionalContext` carrying the packet;
  empty surface → no additionalContext.
- **C2.** Project-root resolved: invoked from a second project dir it reads THAT project's
  `.beast/lessons.jsonl`, never harness infra's.
- **C3.** Gated by the project's `beast-mode.flag` (absent ⇒ no injection even with lessons).
- **C4.** Kill-switch superset: project harness disabled ⇒ hook emits nothing.
- **C5.** Silent by default: flag on + no lessons, and flag on + non-matching action ⇒ empty.
- **C6.** Wired in `settings.json` `PreToolUse` for **Write|Edit AND Bash** (file-writing
  commands), byte-mirrored to `_install`.
- **C6b.** Bash recall: a file-writing Bash command (mirroring `pre-bash-gate.sh`'s detection —
  redirect/tee/sed -i/heredoc/cp/mv/python-write) whose target/content matches a lesson surfaces
  it; a non-file Bash command (e.g. `ls`, `git status`) produces **no** injection.

### Pack
- **C7.** `beast-pack.sh` writes `<project-root>/.beast/lessons.jsonl` with ≥1 schema-valid
  lesson (`id,scope,trigger,lesson,fix,dossier` present; valid JSONL).
- **C8.** Lessons reference the project's **own seeded atoms** (file/symbol/error/commit) from an
  isolated test wing + git — not generic knowledge. **v1 distillation is DETERMINISTIC**: lessons
  are built mechanically from mempalace **KG facts** + **git fix-commits** (no LLM at pack time).
- **C9.** Per-project isolation: packing X never writes Y's `.beast/`; no shared global store.
- **C10.** Idempotent: re-running adds no duplicate lessons.
- **C11.** Headless: completes with no interactive CMD windows; any distillation invoked headless.
- **C12.** Invoked once via the existing `beast-on` branch, guarded by `beast-packed.flag`;
  byte-mirrored to `_install`.

### End-to-end round-trip (headline)
- **C13.** In a fresh `mktemp` second project: seed → `beast-pack.sh` → real Write touching a
  packed atom → live `beast-recall-hook.sh` surfaces that lesson. Connected via real files only.
- **C14.** Negative arms in the same sandbox: flag OFF ⇒ silence; unrelated atom ⇒ silence.
- **C15.** Determinism: identical action + lessons ⇒ byte-identical recall output on repeat.

### Regression, safety, process
- **C16.** Sprint 35 suites green: toggle 21/21, surface 9/9, intuition-control 8/8, killswitch 22/22.
- **C17.** Beast-OFF / no-`.beast/` projects: zero behavioral change on Write/Edit; no errors.
- **C18.** `bash -n` clean on all new/changed scripts; live↔`_install` parity verified.
- **C19.** TDD-first: `test-beast-recall-wiring.sh`, `test-beast-pack.sh`,
  `test-beast-roundtrip.sh` each shown FAILING before implementation, all green at EVALUATE.
- **C20.** Independent verifier reproduces C13–C15 in its **own** fresh sandbox + seed, does not
  read progress notes, default-FAIL; verdict written to `.claude/evidence/`.

## Notes / boundaries
- **N1 — mempalace test isolation:** all pack tests point at an **isolated, env-pointed test
  wing**; the real ~95k-drawer palace is never read or written by tests.
- **N2 — distillation boundary (v1 = deterministic):** the pack builds lessons mechanically from
  mempalace **KG facts** + **git fix-commits** — **no LLM at pack time** for v1. This makes capture
  itself reproducible (no model dependency). Recall remains a pure function. LLM-assisted richer
  dossiers are a future option, explicitly NOT in this sprint.
- **N3 — second-project mandate:** "in reality" means a project dir that is NOT `G:/harness infra`;
  fixtures created by the test/verifier at runtime, not pre-planted.
- **N4 — non-blocking recall:** Sprint 36 injects context only; converting it to a
  block-until-reconciled gate is Sprint 37 and MUST NOT be built here.

## Definition of done
All C1–C20 pass; open decisions O1–O3 resolved (defaults stand unless user overrides);
phase-complete-marker written; live + `_install` in parity; report appended to `.claude/reports/`.
