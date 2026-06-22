# Sprint 36 — Proposal: Beast-Mode Global Recall + Per-Project Pack

**Phase:** NEGOTIATE. Spec: `.claude/specs/beast-mode-global-recall-spec.md`.
Criteria: `.claude/specs/evaluation-criteria-sprint-36.md`.

## 1. What I will build
1. **`beast-recall-hook.sh`** (new, `~/.claude/hooks/`) — a thin `PreToolUse` adapter:
   - resolves project root; if harness disabled (kill-switch) → exit silent;
   - if project `beast-mode.flag` absent → exit silent;
   - else pipe the tool_input to `beast-surface.sh`; if it emits a packet, wrap it as
     `{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"<packet>"}}`
     on stdout (non-blocking — inject only, per D5); else emit nothing.
   - Wire into `settings.json` `PreToolUse` matchers **`Write|Edit` and `Bash`** (Bash: surface
     only on file-writing commands, mirroring `pre-bash-gate.sh` detection). Mirror to `_install`.
2. **`beast-pack.sh`** (new, `~/.claude/scripts/`) — the one-time per-project populator:
   - resolves the project; queries **that project's** memory: mempalace (filtered to the
     project's wing) + `git log` — **v1 sources are mempalace + git only** (no session transcripts);
   - **deterministically** builds schema-valid lessons (`id/scope/trigger/lesson/fix/dossier`)
     from mempalace **KG facts** + **git fix-commits** (no LLM at pack time), written to
     `<project-root>/.beast/lessons.jsonl`; idempotent (no dup ids); headless (no CMD windows);
   - invoked once by the existing `beast-on` branch (the `[ -x beast-pack.sh ]` call that is
     currently a no-op), guarded by `beast-packed.flag`.
3. **Three functional test suites** (reality, second-project sandbox), TDD-first.

## 2. Staging within the sprint
- **36a Recall wiring (G1)** — smallest live slice; proves "fires in any project."
- **36b Pack (G2)** — proves "each project grows its own lessons."
- **36c Round-trip (C)** — connects them end-to-end in a second project; the headline proof.
(Build in this order; each stage green before the next.)

## 3. Functional TDD plan (how "tested in reality" is concrete)
- **Recall:** feed `beast-recall-hook.sh` the *exact* PreToolUse stdin JSON Claude Code sends,
  inside `mktemp` project dirs with/without flag, with/without lessons, harness on/off; assert
  the additionalContext JSON is present/absent and well-formed. Driven via the **live** hook.
- **Pack:** seed an **isolated mempalace test wing** with known project facts (env-pointed so we
  never touch the real 95k palace); run `beast-pack.sh`; assert produced lessons reference the
  seeded atoms, schema-valid, idempotent on re-run.
- **Round-trip:** in one sandbox, `beast-pack.sh` → then a real Write action touching a packed
  atom → live recall hook surfaces that lesson. Negative arms: flag off, unrelated atom.
- Independent verifier rebuilds its own sandbox + seed and reproduces the round-trip.

## 4. Risks & mitigations
- **mempalace coupling in tests** → use an isolated, env-pointed test wing; never the live palace.
- **LLM distillation non-determinism** → the *mechanics* (query, schema, JSONL, idempotency,
  round-trip surfaceability) are the graded contract; distillation quality is bounded by schema
  validity + "references a real seeded atom", not exact bytes.
- **PreToolUse output contract drift** → pin to the documented `hookSpecificOutput.additionalContext`
  shape; A1 test asserts valid JSON the harness accepts.
- **Latency on every Write** → recall is a fast pure scan; D2 guards "zero change when OFF/no lessons".

## 5. Skeptical self-review (as an adversarial evaluator)
- *"Does this actually prove 'works in every project', or just in a second hand-made one?"* — The
  round-trip uses a `mktemp` project the test creates fresh; the verifier uses its **own** fresh
  one. Two distinct non-harness-infra projects ⇒ the claim is about the mechanism, not a fixture.
- *"Is recall really deterministic once an LLM built the lessons?"* — Yes: the LLM only runs at
  **pack** time (cold path). Recall (`beast-surface.sh`) is the unchanged pure function; C3 asserts
  byte-identical repeat. The adapter adds no judgment.
- *"Could the pack 'cheat' by writing generic lessons that always match?"* — B2 requires lessons to
  reference **seeded project-specific atoms**; a generic lesson fails B2. Over-broad triggers are a
  known watch-item (carried from Sprint 35) — C2's unrelated-atom arm catches false-positives.
- *"Does this secretly build the Sprint 37 gate?"* — No. Recall is inject-only (additionalContext),
  non-blocking. No block-until-reconciled, no birth-event capture. Scope boundary explicit in §6.
- **Verdict on the proposal:** scope is a clean vertical slice, each criterion is reality-testable,
  the deferrals are honest. Proceed to contract.

## 6. Out of scope (Sprint 37)
Block-until-reconciled uptake gate (D9); automated capture at birth events (D10); the threshold-
gated semantic-net ranking and tripwire/dossier two-grain *store* beyond what the pack emits.

## 7. Open decisions — RESOLVED (user, 2026-06-22)
- **O1 → Write/Edit AND Bash file-writes.** Recall wires into PreToolUse for Write|Edit *and*
  file-writing Bash commands (mirror `pre-bash-gate.sh` detection). See contract C6/C6b.
- **O2 → mempalace + git for v1.** No session-transcript parsing this sprint.
- **O3 → Deterministic first.** Lessons built mechanically from mempalace KG facts + git
  fix-commits; **no LLM at pack time** in v1. See contract C8/N2.
