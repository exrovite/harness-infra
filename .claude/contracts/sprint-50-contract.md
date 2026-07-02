# Sprint 50 Contract — Fix all audit findings; harness keeps working; beast mode works

User goal: "Please fix all found errors making sure the harness still works properly at the end.
ensure beast mode does what it is meant to do."

Findings source: `.claude/reports/audit-2026-07-01-remaining-problems.md`.
Acceptance criteria: `.claude/specs/evaluation-criteria-sprint-50.md` (AC1-AC18) — binding.

## Scope (build)
1. Gate exemption & Agent-tool consistency (AC1-AC4): pre-write-gate watcher lock exemptions
   (.claude/state/, watchers, pre-flight, contracts, specs, agent-memory, evidence + Agent tool);
   must-do summary gate Agent/empty-target exemption; beast-protocol-gate read-only Bash pass +
   Bash ack/state exemption; `.claude/evidence/` in all exemption lists.
2. Enforcement integrity (AC5, AC6, AC8): pre-bash write detection additions; MCQ answer-key
   sidecar + distractor uniqueness; verify-hardening last_reset fix.
3. Robustness (AC7, AC9, AC10): packet staged trimming; per-session write counter; quoting fixes.
4. Beast quality + proof (AC11, AC17): wins-extract filtering + regenerated wins; functional check.
5. Hygiene (AC12, AC13): registry prune; state refresh/archive; memory metadata regenerated.
6. Parity + verification (AC14-AC16, AC18): _install mirror, TDD-first red run, baseline + full
   regression, dispositions in the sprint report.

## Out of scope
D3/D4/D6/D8 beast backlog; multilane rewrite beyond registry prune; new features; GLM env changes.

## Verification protocol
- Capture pre-sprint regression baseline FIRST.
- TDD suite must FAIL before fixes (red run saved as evidence).
- After build: full regression, parity check, beast functional check.
- Independent verifier sub-agent (does not read progress notes) renders PASS/FAIL per AC with
  evidence; verdict to `.claude/state/evidence-verdict.json`.
- Sprint completes only on verifier PASS.

## Success = all of AC1-AC18 PASS.
