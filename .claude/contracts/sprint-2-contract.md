# Sprint 2 Contract: Phase-Appropriate Write Restrictions

## Scope

Add a phase gate to `pre-write-gate.sh` and `pre-bash-gate.sh` that blocks source code writes in non-BUILD phases.

## Deliverables

1. New gate block in `pre-write-gate.sh` — inserted before the existing contract gate
2. New gate block in `pre-bash-gate.sh` — inserted after bootstrap exemptions
3. Test script that verifies all 9 evaluation criteria

## Acceptance Criteria

1. Agent in PLAN phase: write to `src/foo.py` → BLOCKED
2. Agent in PLAN phase: write to `.claude/specs/x.md` → ALLOWED
3. Agent in NEGOTIATE phase: write to `src/foo.py` → BLOCKED
4. Agent in NEGOTIATE phase: write to `.claude/contracts/x.md` → ALLOWED
5. Agent in BUILD phase: write to `src/foo.py` → ALLOWED (contract gate still applies separately)
6. Agent in EVALUATE phase: write to `src/foo.py` → BLOCKED
7. `pre-bash-gate.sh`: bash command writing to `src/foo.py` in PLAN → BLOCKED
8. Exempt paths (`.claude/state/`, `.agent-memory/`, etc.) → ALLOWED in all phases
9. No `current-phase.json` → ALLOWED (no harness = no enforcement)

## Files Modified

- `C:\Users\exrov\.claude\hooks\pre-write-gate.sh`
- `C:\Users\exrov\.claude\hooks\pre-bash-gate.sh`

## Files Created

- `G:\harness infra\evidence\test-phase-gate.sh` (test script)

## Out of Scope

- Changing existing gates (contract, must-do, watcher)
- Modifying pre-flight-gate.sh
- Changing phase transition logic

## Verification Method

Bash test script that simulates each scenario by setting phase in a temp `current-phase.json` and checking exit codes from the gate scripts.
