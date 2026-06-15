# Progress Notes — Must-Do Pack Builder (BUILD sprint 1)

## KEY DISCOVERY (changes the build)
The **multilane instances system (Sprint 31a)** in `_install/scripts/lib-helpers.sh` ALREADY provides
must-do ownership:
- `lane_paths L` sets `MUSTDO_FILE`: lane 1 (or empty) → `docs/must do/must-do.md`; lanes 2–5 →
  `docs/must do/must-do-$((L-1)).md`.
- `resolve_instance PAYLOAD PROJECT EVENT [REG]` is the chokepoint: reads session_id, finds/claims a
  lane (claims only at UserPromptSubmit), sets `MUSTDO_FILE` + all `*_DIR`.
- Opt-in gated by `.claude/multi-lane.json`; without it everything resolves to lane 1 = flat = current
  behavior (zero regression).

**Implication:** D-Own (slot-N ↔ must-do-N.md) ≈ already implemented via lanes. So:
- **Part A** = make the hardcoded `must-do.md` sites use the lane-resolved `MUSTDO_FILE` instead of
  literal `must-do.md` / `find … | head -1`. Sites: pre-write-gate.sh summary (:268,:317) + evidence
  readers (:533,:607,:665); on-prompt-submit.sh injection (:418,:583).
- **Part B** = pack-builder (`build-mustdo-pack.sh`) + transcript capture (raw .jsonl) + agreement
  validation (`validate-agreement.sh`) + trigger (explicit signal + PLAN-entry gate). The "claim" is
  `instance_claim_lane` (already exists).

## Plan of attack (TDD)
1. `tests/test-mustdo-pack.sh` — failing tests for: lane MUSTDO_FILE resolution used by gates (A),
   pack-builder clears own file only (C11), transcript capture (C10), agreement validation (C14-17).
2. Implement Part A rewiring.
3. Implement `build-mustdo-pack.sh` + `validate-agreement.sh`.
4. Mirror `_install` → live `~/.claude`; run full suites.

## Status: starting TDD test file.

## BUILD COMPLETE (2026-06-15)
Part A (C1-C6): rewired all hardcoded must-do.md sites in pre-write-gate.sh (summary gate x2, find-block, evidence readers x3) + on-prompt-submit.sh (injection + strategy nudge) to route through `mustdo_file_for_dir` (lane-aware owned-file resolution). Synced _install -> live.
Part B (C7-C13): C7-C9/C13 ride on existing lane+watcher pool (D-Own reuse). build-mustdo-pack.sh (C10/C11, scoped clear) + validate-agreement.sh (C14-C17) live in both _install + ~/.claude. +++pack explicit signal wired in on-prompt-submit.sh; opt-in PLAN-entry gate backstop (.claude/mustdo-pack.json {"require_pack":true}) in pre-write-gate.sh (C12).
Tests: tests/test-mustdo-pack.sh now 25/25 (Part A helper + B scripts + C structural wiring + D live-hook integration). All 12 repo suites green = zero regression (C19).
Scripts registered in SCRIPT_REGISTRY.json (total_scripts=21).
NEXT: EVALUATE — independent verifier against C1-C20.
