# Sprint 36 Spec — Beast-Mode: Global Recall + Per-Project Lesson Pack

**Phase:** PLAN (WHAT, not HOW). Builds on Sprint 35 (mechanism proven) and the verbatim
agreement in `docs/applying fussion ideas/beast-mode-global-agreement-verbatim.md`
and the decision record `docs/applying fussion ideas/changes-to-the-idea.md` (D1–D10).

## 1. Problem (one sentence)
Beast-mode's machinery is global, but the grounding fires in **no** project (recall is wired
nowhere) and **no** project grows its own lessons (the populator is a dangling no-op) — so the
only place it can surface is harness infra, by accident of a hand-made fixture.

## 2. The agreed design this sprint delivers
> **Global system, per-project lessons.** Installed once (`~/.claude` + `_install`); every
> project runs the same machinery and surfaces *its own* `<project-root>/.beast/lessons.jsonl`.

Two gaps to close — and only these two:

- **G1 — Global recall wiring.** `beast-surface.sh` fires on the agent's consequential actions —
  **Write/Edit and file-writing Bash commands** — in **every** project, via the live `PreToolUse`
  path, gated by that project's `beast-mode.flag`. When the flag is absent, the harness is off, or
  the project has no lessons → **silence**. Non-file Bash (e.g. `ls`, `git status`) → silence.
- **G2 — Per-project lesson pack.** A `beast-pack.sh` that, on `beast-on` in a project, builds
  **that project's** `.beast/lessons.jsonl` from that project's own memory: mempalace filtered
  to the project + the project's git history (session history = future, NOT v1). Each lesson is a distilled,
  matchable unit (`id/scope/trigger/lesson/fix/dossier`), not a raw mempalace drawer.

## 3. Success at a glance (the thing we must be able to demonstrate IN REALITY)
In a **second project** (NOT harness infra):
1. `beast-on` there → `beast-pack.sh` produces that project's `.beast/lessons.jsonl` from its
   own seeded memory, with lessons referencing **that project's real atoms**.
2. A **real** Write/Edit **or file-writing Bash command** that touches a learned atom → the live
   `PreToolUse` hook surfaces the matching lesson to the agent.
3. Flag off, or harness off, or a project with no lessons → **no output** (silence).

## 4. Non-goals (explicitly deferred to Sprint 37)
- **Uptake as a hard gate** (block-until-reconciled on the main agent's own writes) — D9. Sprint
  36 recall is **inject-as-context only** (non-blocking), per D5.
- **Automated capture at birth events** (test red→green, verifier FAIL→PASS, revert) — D10/D9.
  Sprint 36 populates once from existing memory; live capture is next.

## 5. Constraints (inherited, non-negotiable)
- Judgment allowed **only at capture** (the pack, cold path). Recall stays a **pure function**.
- **No CMD windows / no per-write LLM** — the disruption that killed the old auto-capture.
- **Kill-switch superset honored**: harness off ⇒ beast contributes nothing (no recall, no pack).
- Lessons are **per-project**; do NOT introduce a shared global lesson store.
- MSYS-safe (tr not sed, `\r`-strip, no here-strings, read-loops tolerate no trailing newline).
- **Mirror every live change to `_install`** (parity verified).

## 6. Method mandate
**Functional TDD — test the implementation in reality.** Tests must drive the *actual* hook via
its real stdin contract in a *real second project sandbox* (not harness infra, not a mock), and
must include the **end-to-end round-trip**: pack builds lessons from real seeded memory → a real
tool action surfaces one of them. Tests written and shown failing before implementation.
An independent verifier reproduces the round-trip from scratch; default verdict FAIL.
