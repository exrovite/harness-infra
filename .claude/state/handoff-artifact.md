# Session Handoff — 2026-04-08T17:14:25+01:00
# Phase: CRASH_RECOVERY

## Completed Features
(not a git repo)

## Current Codebase State


## Files Modified This Session
  - C:/Users/exrov/.claude/hooks/collect-test-evidence.sh
  - C:/Users/exrov/.claude/hooks/on-prompt-submit.sh
  - C:/Users/exrov/.claude/hooks/pre-bash-gate.sh
  - C:/Users/exrov/.claude/hooks/pre-write-gate.sh
  - C:/Users/exrov/.claude/scripts/detect-strategy-loop.sh
  - C:/Users/exrov/.claude/scripts/startup-recovery.sh
  - G:/harness infra/.claude/contracts/sprint-12-contract.md
  - G:/harness infra/.claude/contracts/sprint-12-proposal.md
  - G:/harness infra/.claude/specs/strategy-loop-breaker-eval-criteria.md
  - G:/harness infra/.claude/specs/strategy-loop-breaker-spec.md

## Architectural Decisions Made
# Progress Notes — Harness Infrastructure

## Current: Memory Hardening Fix
- Fixed MANIFEST sessions_count stuck at 1 (jq path mismatch)
- Fixed "No git history" in session summaries (non-git fallback)
- Fixed empty modified files in session-context.md (non-git fallback)

## Previous: Sprint 4 BUILD COMPLETE — Ready for EVALUATE

## Sprint 4: Gate Frequency Reduction

### What Was Built
Counter logic in `pre-flight-gate.sh` (lines 54-103, 116-120) that:
- Fires gate on writes 1, 5, 9, 13... (every 4th write)
- Allows 3 free writes between each gate (exit 0 without MCQ)
- Detects step changes via first unchecked TO-DO item comparison
- Resets counter to 0 on step change, immediately fires gate
- Persists state in `.claude/pre-flight/gate-counter.json`

### Counter State File
```json
{"write_count": N, "last_step": "current step text"}
```

### Edge Cases Handled
- Missing counter file → initialize (write_count=0, last_step=""), gate fires
- Corrupt JSON → re-initialize, gate fires
- All TO-DO checked → sentinel "(no unchecked steps remain)", counter works normally
- Both `## TO-DO` and `## TO-DO LIST` headers matched by sed pattern

### Test Results
| Test | Expected | Actual |
|------|----------|--------|
| Write 1 (no counter) | exit 2 | exit 2 |
| Write 2 (counter=1) | exit 0 | exit 0 |
| Write 3 (counter=2) | exit 0 | exit 0 |
| Write 4 (counter=3) | exit 0 | exit 0 |
| Write 5 (counter=4) | exit 2 | exit 2 |
| Counter persists | JSON with both fields | Correct |
| Step change | exit 2 | exit 2 |
| Corrupt JSON | exit 2 (re-init) | exit 2 |
| Exemptions | exit 0 each | exit 0 each |
| No watcher | exit 0 | exit 0 |
| bash -n | PASS | PASS |

## Sprint 3 (Previous): Pre-Flight Gate System
- Distractor pool, generator, validator, hook, watcher templates
- All 24 criteria verified and passed
- Report: `.claude/reports/sprint-3-pre-flight-gate-report.md`

## Known Issues / Deferred Work
No deferred work

## Active Sprint Contract
| # | Criterion |
|---|-----------|
| 1 | No summary → error says "No must-do summary found" |
| 2 | Stale step → error includes both old and new step text |
| 3 | Too short → error shows character count and 200 minimum |
| 4 | Missing mentions → error says "doesn't reference any required file" |
| 5 | Fresh summary (< 5 min) with valid length + mentions → allowed despite step mismatch |
| 6 | Fresh bypass auto-updates step file to current watcher step |
| 7 | Exempt paths still pass unchanged |
| 8 | No must-do folder → allowed (no false blocks) |
| 9 | Existing phase gate tests pass (11/11) |

## Files Modified

- `C:\Users\exrov\.claude\hooks\pre-write-gate.sh` (must-do section only)

## Files Created

- `G:\harness infra\evidence\test-must-do-gate.sh`

## Verification

- Run `evidence/test-must-do-gate.sh` — all tests pass
- Run `evidence/test-phase-gate.sh` — 11/11 pass (regression check)
# Sprint 8 — Exempt .md files from phase gate in PLAN/NEGOTIATE

## Scope
Allow markdown (.md) files to be written in PLAN and NEGOTIATE phases. Markdown is documentation, not source code.

## Acceptance Criteria
1. PLAN phase + .md file → allowed
2. PLAN phase + .js/.py/.ts file → still blocked
3. NEGOTIATE phase + .md file → allowed
4. EVALUATE phase + .md file → still blocked (only PLAN/NEGOTIATE get the exemption)
5. BUILD phase unchanged
6. Bash gate has same exemption
7. Existing tests still pass
# Sprint 9 — Extend .md exemption to all phases

## Scope
Markdown files should be writable in ALL non-BUILD phases, not just PLAN/NEGOTIATE.

## Acceptance Criteria
1. PLAN + .md → allowed
2. NEGOTIATE + .md → allowed
3. EVALUATE + .md → allowed
4. COMPLETE + .md → allowed
5. All phases + .js/.py → still blocked
6. Bash gate has same exemption
7. Existing tests pass

## Test Status
bash: /c/Users/exrov/.claude/scripts/validate.sh: No such file or directory
Validation script not available

## What To Do Next
Read .claude/state/active-instructions.md for current phase instructions.
