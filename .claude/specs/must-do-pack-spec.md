# Product Spec — Automated Must-Do Pack Builder

**Phase:** PLAN. High-level WHAT, not HOW. Decisions locked with the user 2026-06-15.
Source/raw conversation + full decision record: `docs/applying fussion ideas/enhancing the must do
system/core idea`.

## Problem
Automate the user's manual planning ritual: a planning conversation → compiled rough plan → placed
in a folder → linked from the must-do file so the must-do file is always the grounded "you are
here" index. Today this is manual. Also, the must-do system is intended as one folder / five files
but is only half-wired to that model.

## Outcome (what "done" looks like)
1. The must-do system genuinely supports **one folder, up to five files, one owner each** — every
   gate (summary, evidence, injection, pre-flight MCQ) operates on **the caller's own file**, not a
   hardcoded `must-do.md`.
2. When a planning conversation ends, a **pre-PLAN "build your must-do pack" step** runs that:
   - claims/owns a must-do file (tied to the session's watcher slot),
   - captures the originating conversation **in raw form** (hook copies transcript JSONL),
   - writes a compiled `rough-plan.md` / discussion-agreement,
   - has that agreement **independently validated against the raw conversation** for completeness
     before it is accepted (D-Validate),
   - clears **its own** must-do file and relinks the raw conversation + validated agreement + all
     grounding files.
3. The agent manages the must-do folder itself, safely, under multi-agent concurrency.

## Confirmed decisions (user said "yes to the five questions")
- **D-Own (F1):** must-do ownership binds to the watcher claim — `slot-N` ↔ `must-do-N.md`, same
  owner/lock/lifecycle. Reuse the per-project watcher pool; do NOT build a separate registry.
- **D-Raw (F2):** raw conversation captured by a hook copying the actual transcript JSONL (true
  raw). Agent separately writes `rough-plan.md`. Pack = `raw-conversation.jsonl` + `rough-plan.md`
  + links.
- **D-Clear (F3):** pack build clears/repopulates ONLY the caller's own file, never a sibling's.
- **D-Trigger (F4):** BOTH — explicit signal (kill-switch family, `/plan`-style token) as normal
  path + PLAN-entry gate blocking the first spec write until a claimed pack exists, as backstop.
- **D-Solo (F5):** alone in folder → keep `must-do.md` (no numbering); fan out to `must-do-2.md…`
  only under contention.
- **D-Validate (user correction 2026-06-15):** once the discussion is agreed, the agent writes the
  **discussion-agreement file**, which is then **validated by an independent agent against the raw
  conversation** for completeness — every agreed aspect must be present before the agreement is
  accepted as the grounding the must-do file links to. FAIL → revise; PLAN does not proceed until
  the agreement passes. (Mirrors the EVALUATE builder/verifier separation, applied to the plan
  itself.)

## Sequencing (D-Seq, confirmed 2026-06-15)
- **F6 DECIDED:** everything folds into a **single sprint** (user choice). No separate consistency
  sprint — the 5-file consistency fix and the ownership/auto-pack/validation layer ship together.

## Sprint 1 (single sprint — all of it)
- **Part A — 5-file consistency fix.** Replace hardcoded `must-do.md` / `find … | head -1` in the
  summary gate, evidence readers, and injection with "the caller's owned must-do file" resolution.
- **Part B — Ownership + auto-pack + validation.** Must-do claim layer over the watcher registry;
  transcript-capture hook; pre-PLAN pack-builder step + explicit signal + PLAN-entry gate; and the
  independent agreement-validation step (D-Validate) before the must-do file is accepted as grounding.

## Constraints / non-goals
- Reuse existing machinery (watcher pool locking, transcript path, evidence-injection pattern); do
  not invent parallel systems.
- Destructive clear must be provably scoped to the caller's own file (concurrency-safe).
- Ship in `_install` so all projects get it; keep solo/common case clean (no forced numbering).
- Backwards compatible: projects with no must-do folder are unaffected.

## Relationship to beast-mode
The must-do pack is the authoritative machine-grounded "what we're actually doing" record that the
beast-mode/fusion grounding packet also depends on. It is a dependency of well-grounded fusion.
