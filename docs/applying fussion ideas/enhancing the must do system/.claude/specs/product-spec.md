# Product Spec — Automated Must-Do Pack Builder

Canonical PLAN spec for this harness instance. Full detail + locked decisions live in the root
project specs: `G:/harness infra/.claude/specs/must-do-pack-spec.md` and
`.../must-do-pack-evaluation-criteria.md`. This file mirrors the essentials.

## Problem
Automate the manual planning ritual (conversation → rough plan → folder → linked from must-do file)
so the agent manages the must-do folder itself. The must-do system is intended as one folder / up
to five files but is only half-wired to that model.

## Outcome
1. Every must-do gate (summary, evidence, injection, pre-flight MCQ) operates on **the caller's own
   must-do file**, not a hardcoded `must-do.md`.
2. A pre-PLAN "build your must-do pack" step: claims a must-do file (bound to the watcher slot),
   captures the raw conversation (hook copies transcript JSONL), the agent writes a discussion
   agreement / rough plan, an **independent agent validates that agreement against the raw
   conversation** for completeness, then the caller's own file is cleared and relinked to the raw
   conversation + validated agreement + grounding files.
3. Safe under multi-agent concurrency (reuse watcher pool lock).

## Locked decisions
- **D-Own:** must-do ownership binds to the watcher claim — `slot-N` ↔ `must-do-N.md`.
- **D-Raw:** raw conversation captured by a hook copying the transcript JSONL (true raw); agent
  writes `rough-plan.md` separately.
- **D-Clear:** pack build clears/repopulates ONLY the caller's own file.
- **D-Trigger:** explicit signal (normal path) + PLAN-entry gate (backstop).
- **D-Solo:** alone → keep `must-do.md` (no numbering); fan out only under contention.
- **D-Validate:** independent agent validates the discussion agreement vs the raw conversation for
  completeness before it is accepted as grounding.
- **D-Seq:** single sprint — consistency fix + ownership/auto-pack/validation ship together.

## Single sprint
- **Part A:** 5-file consistency fix (replace hardcoded `must-do.md` / `find … | head -1` in summary
  gate, evidence readers, injection with caller's-own-file resolution).
- **Part B:** must-do claim layer over the watcher registry; transcript-capture hook; pre-PLAN
  pack-builder step + explicit signal + PLAN-entry gate; independent agreement validation.

## Constraints
- Reuse watcher pool locking, transcript path, evidence-injection pattern — no parallel systems.
- Destructive clear provably scoped to caller's own file (concurrency-safe).
- Ship in `_install`; sync live `~/.claude`. Back-compat: no must-do folder → unaffected.

## Acceptance Criteria
Full checklist in `.claude/specs/evaluation-criteria.md` (C1–C20). Headline:
- Part A: every must-do gate resolves the caller's own file; no regression to MCQ or single-file/no-folder cases.
- Part B: watcher-bound ownership; pre-PLAN pack-builder captures raw transcript + agreement;
  independent agent validates the agreement vs the raw conversation before it grounds the must-do file.
- Shipped in `_install`, live synced, tests passing, no regressions, concurrency-safe.
