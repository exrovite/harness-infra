# Sprint 1 Contract — Automated Must-Do Pack Builder

## Scope (locked)
Single sprint, Parts A + B. Decisions: D-Own, D-Raw, D-Clear, D-Trigger, D-Solo, D-Validate, D-Seq.

## Deliverables
1. `lib-helpers.sh`: `mustdo_resolve_owned_file`, `mustdo_claim` (watcher-bound), helpers reuse
   `registry_lock` / stale-reap. (D-Own, D-Solo)
2. Rewire hardcoded must-do sites to the resolver: `pre-write-gate.sh` (summary + 3 evidence
   readers), `on-prompt-submit.sh` (2 injection sites). (Part A)
3. `build-mustdo-pack.sh`: clears caller's own file only, scaffolds `rough-plan.md`, relinks raw +
   agreement + grounding. (D-Clear)
4. Transcript-capture step: copy session `.jsonl` → `raw-conversation.jsonl`. (D-Raw)
5. Trigger: explicit signal + PLAN-entry gate backstop. (D-Trigger)
6. `validate-agreement.sh`: independent completeness check of agreement vs raw conversation. (D-Validate)
7. `tests/test-mustdo-pack.sh` covering C1–C20.
8. Mirror to `_install/`; sync live `~/.claude`.

## Acceptance (verified independently)
All of C1–C20 in `.claude/specs/evaluation-criteria.md`. Independent verifier required at EVALUATE.

## TDD
Tests written first and failing before implementation. Run full existing suites (watcher, must-do,
evidence, kill-switch) after each feature — zero regressions (C19).

## Done when
C1–C20 pass under an independent verifier; `_install` + live synced; all suites green.
