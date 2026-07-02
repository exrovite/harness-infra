# Session Handoff — 2026-07-02T03:52:49+01:00
# Phase: CRASH_RECOVERY

## Completed Features
9624563 Sprint 49: fix must-do ownership churn (greedy resolver) + full heartbeat coverage
18a2ed9 Sprint 48: hard session isolation (liveness-aware) + stale must-do property cleanup
e4fa02e Sprint 47: whole-harness session-scoping audit + intelligent stale-slot reap (AC30)
46a6433 Project checkpoint: multi-session hardening (Sprints 42-46) + complete install pack + CHANGELOG
819bab3 Sprint 46: per-session must-do SUMMARY lane (stop agents overwriting each other's summary)
88834aa Sprint 45: default per-session must-do file fan-out (fix multi-session OWNERSHIP deadlock)
3884d08 Sprint 44: the REAL fresh-folder .claude creator was startup-recovery.sh
430ab59 Sprint 43: stop the harness creating .claude in new/non-project folders
2cdd536 Sprint 42: stop the harness creating nested .claude project roots
5f8b1f9 Sprint 41: validated-protocol surfacing + enforced adherence (independent-checked)
0600641 Sprint 40: fix beast-mode relevance (precise triggers + working semantic recall)
0e3988e Sprint 39: wire mempalace semantic READ into beast recall (D6)
f71c712 docs: add beast-mode intuition-layer program report
a6284f4 Sprint 38: beast-mode forcing (D9 reconcile-gate) + in-work interjection
4d4d1d2 Add Sprint 37 journey & outcomes report (why/how/what)
55bc603 Sprint 35 (foundation): commit beast-surface + toggle/intuition tests & docs into install pack
8bf2d22 Sprint 36: beast-mode global recall + per-project deterministic pack
bd3a3f1 Sprint 37: session-aware must-do file-exists branch (archive-not-delete)
99353ff Kill-switch is cwd-independent: resolve the OFF flag by project root
7b07edb Kill-switch banner reads UNLOCKED / LOCKED

## Current Codebase State


## Files Modified This Session
  - .agent-memory/MEMORY_MANIFEST.json
  - .agent-memory/episodic/decisions/transitions.jsonl
  - .agent-memory/episodic/sessions/2026-06-16_04-18-45.md
  - .agent-memory/episodic/sessions/2026-06-19_02-29-39.md
  - .agent-memory/episodic/sessions/2026-06-19_02-49-07.md
  - .agent-memory/episodic/sessions/2026-06-19_02-55-21.md
  - .agent-memory/episodic/sessions/2026-06-19_02-56-10.md
  - .agent-memory/episodic/sessions/2026-06-19_03-01-58.md
  - .agent-memory/episodic/sessions/2026-06-19_03-21-40.md
  - .agent-memory/episodic/sessions/2026-06-19_03-27-28.md
  - .agent-memory/episodic/sessions/2026-06-19_03-47-21.md
  - .agent-memory/episodic/sessions/2026-06-19_09-36-40.md
  - .agent-memory/episodic/sessions/2026-06-19_09-42-21.md
  - .agent-memory/episodic/sessions/2026-06-20_04-34-26.md
  - .agent-memory/episodic/sessions/2026-06-20_04-52-11.md
  - .agent-memory/episodic/sessions/2026-06-20_05-54-05.md
  - .agent-memory/episodic/sessions/2026-06-20_06-51-58.md
  - .agent-memory/episodic/sessions/2026-06-20_07-47-04.md
  - .agent-memory/episodic/sessions/2026-06-20_07-52-21.md
  - .agent-memory/episodic/sessions/2026-06-21_02-13-28.md

## Architectural Decisions Made
# Progress Notes

## 2026-07-01 — Whole-harness audit (session 624b9285)
User asked for all remaining problems. Full report: `.claude/reports/audit-2026-07-01-remaining-problems.md`.
Headline: live-fire gate-cycle deadlock (watcher admin lock × beast-protocol-gate × must-do gate, A1-A5),
pre-flight challenge embeds its own answer key (B3), zombie `.instances[]` + phantom-cron leak (C1/C2),
broken verify-hardening (C3), stale phase state Sprint 35 vs HEAD Sprint 49 (E1), noisy validated-wins (D1).
No fixes applied — report only. Suggested fix order is in the report.

---

# (previous) Progress Notes — Sprint 35: Beast-Mode (intuition grounding)

## Status: BUILD complete, awaiting independent validation of the control proof.

## Built
- **Helpers** (`lib-helpers.sh`): `beast_is_on` / `beast_enable` / `beast_disable`,
  project-root resolved, atomic. Mirror of the harness_* helpers.
- **Toggle** (`on-prompt-submit.sh`): `beast-on` / `beast-off` exact-match, full truth
  table — `beast-on` auto-enables the harness first if disabled (prints the exact
  `[HARNESS RE-ENABLED — beast mode requires active gates]` notice); `beast-off` leaves
  harness on; `---` drops both; `===` restores harness only. Superset rule enforced.
- **Intuition core** (`beast-surface.sh`): deterministic recall. Scans an action's stable
  atoms (scope glob + trigger regex) against `.beast/lessons.jsonl`; emits an adversarial
  injection naming matched lessons + fixes, or SILENCE. Pure, no LLM at recall.
- **Lesson store** (`.beast/lessons.jsonl`): two genuinely-true project lessons
  (MSYS sed→tr; cwd-vs-project-root / `find_project_state_dir`, commit 99353ff).
- **_install mirror**: on-prompt-submit.sh, lib-helpers.sh, beast-surface.sh — parity OK.

## Tests (TDD-first, all green)
- `tests/test-beast-toggle.sh` 21/21 (live hook, truth table).
- `tests/test-beast-surface.sh` 9/9 (deterministic surfacing).
- `tests/test-intuition-control.sh` 8/8 (machine-produced injection carries the
  unguessable symbol; silence on unrelated).
- `tests/test-killswitch.sh` 22/22 (regression, unchanged).

## Proof of control (the goal)
`.claude/evidence/intuition-control-proof.md`. A/B with real sub-agents, project-specific
unguessable lesson, N=3:
- Reconciled ("M2 applies"): ON 3/3, OFF 0/3.
- Project-correct resolution: ON 3/3, OFF 0/3 (OFF reproduced the documented bug).
- Negative control (sed lesson the model already knows): no delta — method is sound.

## Next
Independent rigorous validator must REPRODUCE the A/B itself and render PASS/FAIL on
"the agent is controlled by the intuition system."

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
