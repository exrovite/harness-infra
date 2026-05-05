# Context Snapshot: Sprint 21 Cognitive Guidance Layer

- Task statement: Implement .claude/contracts/sprint-21-contract.md in G:\harness infra under Ralph persistence.
- Desired outcome: on-prompt-submit.sh injects phase guidance, task-size protocol advisories, EVALUATE verifier rules, and fix-cycle STUCK ceiling while preserving existing hook behavior and leaving gate scripts untouched.
- Known facts/evidence:
  - Sprint contract defines deliverables D1-D4 and 33 acceptance criteria.
  - Changes are primarily scoped to .claude/hooks/on-prompt-submit.sh; lib-helpers.sh additive changes only if needed.
  - Gate scripts pre-write-gate.sh, pre-bash-gate.sh, pre-flight-gate.sh must have zero diff.
- Constraints:
  - No new dependencies.
  - Hard cap raised from 1490 to 2000.
  - Guidance hardcoded per phase, bounded/static lookups.
  - MSYS shell constraints: avoid problematic sed, strip jq CR, no grep \d, avoid here-strings in hook subprocesses.
- Unknowns/open questions:
  - Exact existing hook structure and test harness locations pending inspection.
  - Current strategy-loop state schema pending inspection.
- Likely codebase touchpoints:
  - .claude/hooks/on-prompt-submit.sh
  - .claude/hooks/lib-helpers.sh only if additive helpers are needed
  - existing tests/scripts for hook packet simulation, if present
