# Turn Packet System — Product Spec

## Problem

The harness has ~8 independent gates that block writes. Each gate has its own resolution path. Agents discover these by trial and error — hitting a block, reading stderr, adapting, hitting the next block. This wastes tokens, creates frustration, and caused the sprint transition deadlock.

The `on-prompt-submit.sh` hook injects a one-line status but doesn't tell the agent what actions are needed to unlock writes.

## Solution

Evolve `on-prompt-submit.sh` from a status reporter into a **turn packet assembler**. Before the agent acts, it sees a sequenced checklist of what the harness expects — making correct behavior the path of least resistance.

The gates stay as safety nets. They should rarely fire because the agent already knows the correct path.

## What The Turn Packet Contains

**Section 1: State summary** (always present, one line)
- Phase, sprint, iteration, write count, watcher status — same as today

**Section 2: Action queue** (only when something is required before code writes)
- A numbered list of actions the agent must take, in dependency order
- Each action is specific: what to do, which tool to use, what path to write to
- Only lists actions that are actually blocked right now — not the full protocol
- When everything is clear, this section is absent (zero overhead for unblocked agents)

**Section 3: Blocked-by** (only when a hard block is active)
- Names the specific active block (phase-feedback FAIL, evidence checkpoint, strategy loop)
- States the exact resolution path in 1-2 lines

**Section 4: Exempt paths** (only when tools are locked)
- Lists the infrastructure paths that are always writable
- Prevents the agent from thinking everything is blocked

**Section 5: Current step + scope** (only when a watcher is active)
- Current TO-DO step from the watcher slot
- SCOPE and MISTAKES TO AVOID from watcher slot (truncated to stay lean)

## Gate-to-Packet Mapping

The packet assembler checks the same conditions the gates check, in the same order, but reports proactively:

| Gate condition | Turn packet behavior |
|---|---|
| No watcher claimed | "1. Claim watcher slot via Bash" |
| No cron reminder | "2. Start 3-min cron via CronCreate" |
| Wrong phase for code | "Phase is PLAN — code writes locked, write specs" |
| No sprint contract | "3. Write sprint contract to .claude/contracts/" |
| Phase-feedback FAIL | "BLOCKED BY: phase-feedback FAIL — read phase-feedback.md" |
| Must-do summary missing | "4. Read must-do files and write summary" |
| Evidence checkpoint pending | "BLOCKED BY: evidence checkpoint — spawn verifier" |
| Strategy loop detected | "BLOCKED BY: strategy loop — write strategy-ack.md" |
| Pre-flight MCQ due | "Note: MCQ gate will fire on next gated write" |

## Design Constraints

1. **Token budget**: Under 600 chars when unblocked (section 1 only). Up to 1500 when blocks active.
2. **No gate changes**: pre-write-gate.sh, pre-bash-gate.sh, pre-flight-gate.sh are untouched.
3. **One file changed**: Only on-prompt-submit.sh is modified.
4. **Dependency ordering**: Action queue respects gate order (watcher > contract > must-do > MCQ).
5. **Zero overhead when clear**: Unblocked agents see only a brief status line.
6. **Read-only checks**: Packet reads state files, never writes or enforces.

## What Success Looks Like

- Agent entering fresh session sees exactly what to do before writing code, in order
- Agent mid-session with all gates clear sees only a brief status line
- Sprint transition deadlock scenario cannot recur (packet would show "write contract" before agent tries)
- Gates fire <10% as often (they become true safety nets, not primary teachers)
