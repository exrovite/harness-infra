# Sprint 50 Proposal — Fix all audit findings (audit-2026-07-01-remaining-problems.md)

Goal (user): "fix all found errors making sure the harness still works properly at the end.
ensure beast mode does what it is meant to do."

## What will be built
1. **Deadlock cluster** — watcher admin lock gets state/Agent exemptions (A1/A4); must-do summary
   gate exempts Agent/empty targets (A3); beast-protocol-gate stops scanning read-only Bash and
   gains a Bash-side ack/state exemption (A2); `.claude/evidence/` added to all missing exemption
   lists (B1).
2. **Enforcement integrity** — MCQ answer key moved out of challenge.md + distractor uniqueness
   (B3); verify-hardening `last_reset` fix so the 5-strike rule works (C3); pre-bash write
   detection catches `>>`, `dd of=`, `git apply`, `patch`, `perl -e` (B2).
3. **Correctness/robustness** — per-session write counter (A5); packet trims low-value sections
   before hard truncation (B4); space-safe quoting in build-mustdo-pack + startup-recovery (C4/C5).
4. **Beast quality** — beast-wins-extract filters report-request quotes / requires the concept in
   the quote; regenerate validated-wins (D1). Beast functional check: relevant recall still fires,
   read-only commands unblocked, all beast suites green.
5. **Hygiene** — registry prune (.instances zombies, placeholder slots) (C1/E4); state dir refresh
   + archive of dead artifacts (E1/E2); backlog.json / knowledge-gaps.json regenerated (E3).

## Explicit dispositions (documented, not code-fixed)
- A6 headless-claude auth: machine-level GLM env; workaround documented.
- "Phantom crons" (audit C2): CronCreate jobs are session-only and die with the session; the reaped
  registry entry removes the id — no orphan process exists. Non-issue, documented.
- B5 fallback: project-level counting only ever runs with no session id (tests); documented.
- cron_pause churn: pause suppresses the printed reminder by design; the job still firing is a
  Claude-Code scheduler property; guidance documented.
- D3/D4/D6/D8: acknowledged beast backlog, out of scope.

## Sceptical self-review
- Risk: loosening the watcher lock too far → only harness-state paths + Agent exempted; source
  writes still locked; TDD asserts both directions.
- Risk: beast gate change silences real surfacing → Write/Edit path unchanged; Bash still gated
  when the command writes non-state files; tests assert a concept-touching source write without an
  ack is still blocked.
- Risk: breaking 43 existing suites → full regression run is a contract criterion.

## Verification
TDD suite written FIRST (must fail), full tests/ regression, live↔_install parity, independent
verifier sub-agent renders PASS/FAIL against the contract. Acceptance criteria:
.claude/specs/evaluation-criteria-sprint-50.md and the contract's C-list.
