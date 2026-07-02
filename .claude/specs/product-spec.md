# Product Spec — Sprint 50: Fix all audit findings; harness keeps working; beast mode works

(Previous sprint-34 spec preserved in git history.)

## What
Repair every defect found by the 2026-07-01 whole-harness audit
(`.claude/reports/audit-2026-07-01-remaining-problems.md`) without changing what the harness is
FOR: deterministic gates that keep any model on task, per-session isolation, and beast-mode
intuition that surfaces only RELEVANT, user-validated protocols.

## Why
The audit proved (live) that the gates can deadlock each other, that two enforcement mechanisms
are silently ineffective (MCQ answer-key leak, verify-hardening dead code), that beast-mode fires
on irrelevant matches, and that stale state misleads every new session.

## Outcome (WHAT, not HOW)
1. No gate combination can lock a session out of the actions the gates themselves demand
   (state writes, watcher claim, ack files, verifier spawns).
2. Enforcement that claims to verify actually verifies (MCQ, hardening, bash write detection).
3. Beast mode: read-only work is never blocked; surfaced protocols are genuine user-validated
   wins containing the concept; recall/gating still fires on real matches.
4. State and registry reflect reality (phase/sprint, no zombie entries, no misleading metadata).
5. Everything proven: TDD-first, full regression, live↔_install parity, independent verifier.

## Evaluation Criteria
Binding, binary criteria: `.claude/specs/evaluation-criteria-sprint-50.md` (AC1-AC18).
Headlines: AC1-AC4 deadlock cluster; AC5/AC6/AC8 enforcement integrity; AC7/AC9/AC10 robustness;
AC11/AC17 beast quality + functional proof; AC12/AC13 hygiene; AC14-AC16 parity/TDD/regression;
AC18 documented dispositions.

## Constraints
- `---` kill-switch and all existing green behaviour preserved (regression baseline = law).
- No new features; D3/D4/D6/D8 beast backlog stays out of scope.
- Every hook/script change mirrored byte-identical to `_install/`.

## Stop condition
Independent verifier renders PASS on all AC1-AC18; sprint report written; COMPLETE.
