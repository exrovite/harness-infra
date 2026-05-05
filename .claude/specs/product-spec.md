# Turn Packet System — Product Spec

## Problem

The harness has many independent gates that block writes. Agents discover them by trial and error: act, get blocked, read stderr, adapt, hit the next block. This wastes tokens and caused the sprint transition deadlock.

The current `on-prompt-submit.sh` injects status, but not the full operating frame: required setup, read-first files, blockers, exempt paths, current step, and what done looks like.

## Solution

Evolve `on-prompt-submit.sh` into a **turn packet assembler**. Before the agent acts, it sees a concise cockpit packet that makes correct behavior the path of least resistance.

The gates stay as safety nets. They should rarely fire because the agent already knows the correct path.

## What The Turn Packet Contains

**Section 1: State summary**
- Phase, sprint, iteration, write count, watcher status.

**Section 2: Read first**
- Existing sprint contract when present.
- Must-do index/source docs when summary is missing.

**Section 3: Action queue**
- Numbered actions required before code writes, in dependency order.
- Each action states the tool and target path.

**Section 4: Blocked-by**
- Hard blockers with exact resolution path.
- Includes phase-feedback FAIL, evidence checkpoint sub-states, and strategy loop tier 2.
- Strategy tier 1 is a warning, not a hard block.

**Section 5: Exempt paths**
- Infrastructure paths that remain writable when tools are locked.

**Section 6: Watcher cockpit**
- Current unchecked step.
- SCOPE.
- MISTAKES TO AVOID.
- DONE WHEN / COMPLETION CRITERIA.

## Gate-to-Packet Mapping

| Gate condition | Turn packet behavior |
|---|---|
| No watcher claimed | Queue `Claim watcher` via Bash |
| No cron reminder | Queue `Start reminder` via CronCreate |
| Wrong phase for code | Show writes-locked/mode guidance |
| No sprint contract | Queue contract write in NEGOTIATE or BUILD |
| Phase-feedback FAIL | `BLOCKED BY: phase-feedback FAIL` |
| Must-do summary missing | Read must-do docs and queue summary write |
| Evidence checkpoint pending | `BLOCKED BY` with exact sub-state guidance |
| Strategy loop detected | Tier 1 warning or tier 2 `BLOCKED BY` |
| Pre-flight MCQ due | Note that MCQ fires on next gated write |

## Design Constraints

1. **Token budget**: steady watcher cockpit under 600 chars; full blocked packet under 1500 chars.
2. **No gate changes**: pre-write, pre-bash, and pre-flight gates are untouched.
3. **Touchpoints**: `on-prompt-submit.sh` plus helper additions in `lib-helpers.sh`.
4. **Dependency ordering**: watcher > cron > contract > must-do > MCQ.
5. **Read-only packet assembly**: packet condition checks do not enforce and exit 0.
6. **Preserve existing features**: must-do injection/log, evidence checkpoint guidance, strategy loop state behavior.

## What Success Looks Like

- Fresh session sees exactly what to do before writing code, in order.
- Active watcher session sees current step and done criteria before acting.
- Agent knows what to read first instead of discovering it from a gate.
- Sprint transition deadlock cannot recur: missing contract is surfaced in NEGOTIATE before BUILD work.
- Gates become guardrails instead of the primary teaching mechanism.