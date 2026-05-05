# Spec: Phase-Appropriate Write Restrictions

## Problem

Agents can bypass the harness state machine by never advancing past PLAN. The contract gate only fires in BUILD, so an agent that stays in PLAN forever can write unlimited source code with no spec, no contract, and no scope boundary. This was observed in the Descript Clone project: 58 writes, zero specs, zero contracts, still in PLAN/sprint 0.

## Solution

Add a **phase gate** to `pre-write-gate.sh` and `pre-bash-gate.sh` that restricts which files can be written in each phase. Source code writes are only allowed in BUILD.

## Phase Permissions

| Phase | Allowed Writes | Blocked |
|-------|---------------|---------|
| PLAN | specs, state, watchers, agent-memory, pre-flight, agentwiki, progress files | source code, tests, config |
| NEGOTIATE | + contracts, proposals | source code, tests, config |
| BUILD | everything (existing contract gate still applies) | — |
| EVALUATE | state, evaluation-results, pre-flight | source code, tests |
| COMPLETE | state, handoff | source code, tests |

## Exempt Paths (always writable in any phase)

These paths are infrastructure — agents must always be able to update them:
- `.claude/state/`
- `.claude/specs/`
- `.claude/contracts/`
- `.claude/pre-flight/`
- `.openclaw/watchers/`
- `.agent-memory/`
- `agentwiki/`
- `claude-progress.txt`
- `features.json`
- `tests.json`
- `CLAUDE.md`

## Detection Logic

A file is "source code" if its normalized path does NOT match any exempt pattern. This is a blocklist-free approach — we don't try to enumerate code extensions. Instead, we allow known infrastructure paths and block everything else in non-BUILD phases.

## Implementation

### File 1: `pre-write-gate.sh`

Insert a new gate block BEFORE the contract gate (which only fires in BUILD). The new block:
1. Reads current phase from `current-phase.json`
2. Extracts target file path from stdin (already read as `INPUT_DATA`)
3. Checks if target matches any exempt path
4. If not exempt AND phase is not BUILD: block with message telling agent which phase it's in and what it needs to do to advance

### File 2: `pre-bash-gate.sh`

Same logic applied to detected file-writing bash commands. After the existing bootstrap exemptions, add phase check.

## Block Messages

Each non-BUILD phase gets a specific message:
- **PLAN**: "You are in PLAN phase. Write your spec to .claude/specs/ first, then advance to NEGOTIATE."
- **NEGOTIATE**: "You are in NEGOTIATE phase. Write your sprint contract first, then advance to BUILD."
- **EVALUATE**: "You are in EVALUATE phase. Spawn an independent verifier — don't write code yourself."
- **COMPLETE**: "Task is COMPLETE. Start a new sprint if more work is needed."

## What This Does NOT Change

- BUILD phase: unchanged (existing contract gate still applies)
- Read tool: unaffected (no gate on reads)
- Exempt paths: always writable regardless of phase
- Free write count: unchanged (2 free writes before watcher required)

## Evaluation Criteria

1. Agent in PLAN phase cannot write to a source code file (e.g., `src/foo.py`)
2. Agent in PLAN phase CAN write to `.claude/specs/`
3. Agent in NEGOTIATE phase cannot write to source code
4. Agent in NEGOTIATE phase CAN write to `.claude/contracts/`
5. Agent in BUILD phase can write source code (with contract)
6. Agent in EVALUATE phase cannot write source code
7. pre-bash-gate.sh applies the same restriction
8. Exempt paths work in all phases
9. Projects without `current-phase.json` are unaffected (exit 0)
