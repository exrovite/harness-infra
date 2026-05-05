# Sprint 20 Proposal: Turn Packet System

## Scope

Evolve `on-prompt-submit.sh` from a single-line status reporter into a structured turn packet assembler. Before the agent acts, it sees a sequenced checklist of what the harness expects — making correct behavior the path of least resistance. Gates remain untouched as safety nets.

## Deliverables

### D1: on-prompt-submit.sh — Turn Packet Assembler (refactor)

Replace the current flat CONTEXT_MSG approach with a structured multi-section packet:

**Section 1: State summary** (always present, one line)
- Phase, sprint, iteration, write count, watcher status — same data as today, same format

**Section 2: Action queue** (only when actions needed before code writes)
- Numbered list in dependency order, each item specifying tool and target path
- Gate conditions checked in order:
  1. Watcher not claimed → "1. Claim watcher slot via Bash: jq-update REGISTRY.json, write slot-N.md"
  2. Cron not active → "2. Start 3-min cron via CronCreate: */3 * * * *"
  3. Phase wrong for code → "Phase is {PHASE} — code writes locked, write specs to .claude/specs/"
  4. Sprint contract missing → "3. Write sprint contract to .claude/contracts/sprint-{N}-contract.md"
  5. Must-do summary missing → "4. Read must-do files and write summary to .claude/state/must-do-summary.md"
  6. Pre-flight MCQ due → "Note: MCQ gate will fire on next gated write"
- Items only appear when the condition is actually unmet — zero overhead when clear

**Section 3: Blocked-by** (only when hard blocks active)
- Phase-feedback FAIL → "BLOCKED BY: phase-feedback FAIL — read .claude/state/phase-feedback.md, fix issues, write phase-complete-marker.md"
- Evidence checkpoint pending → "BLOCKED BY: evidence checkpoint — spawn verifier sub-agent (brief at .claude/state/evidence-checkpoint.json)"
- Strategy loop detected → "BLOCKED BY: strategy loop — write .claude/state/strategy-ack.md (150+ chars, ## New Approach header)"

**Section 4: Exempt paths** (only when tools are locked)
- Lists: .claude/state/, .claude/contracts/, .claude/specs/, .openclaw/watchers/, .agent-memory/, .claude/pre-flight/, .claude/evidence/, agentwiki/

**Section 5: Current step + scope** (only when watcher active)
- Current TO-DO step from watcher slot file
- SCOPE section (first 200 chars) and MISTAKES TO AVOID (first 200 chars)

**Existing features preserved (integrated into packet structure):**
- Must-do summary injection (as part of section 5 or standalone)
- Evidence checkpoint injection (absorbed into section 3 blocked-by)
- Strategy loop nudge/block injection (absorbed into section 3 blocked-by)

### D2: lib-helpers.sh — Shared Condition Functions (~60 lines added)

New functions (no existing functions modified):
- `find_must_do_dir()` — returns must-do directory path or empty string (currently duplicated in 4+ scripts)
- `check_watcher_for_project()` — returns claimed watcher slot number or empty string
- `read_watcher_step_scope()` — extracts current TO-DO step, SCOPE, and MISTAKES from slot file

These functions centralize logic that both the packet assembler and (in a future sprint) the gates can call. For this sprint, only on-prompt-submit.sh calls them.

## NOT In Scope
- Changing any gate script (pre-write-gate.sh, pre-bash-gate.sh, pre-flight-gate.sh)
- Refactoring gates to call shared functions (future sprint)
- Adding new gates or removing existing ones
- Changing any gate's exit code or blocking behavior

## Acceptance Criteria (20 items)

### Packet Structure
1. Unblocked agents see Section 1 only — output under 200 chars
2. Action queue appears only when conditions are unmet
3. Action queue items are numbered in dependency order (watcher > cron > contract > must-do > MCQ)
4. Each action queue item specifies which tool to use and the target path
5. Hard blocks appear as "BLOCKED BY:" with 1-2 line resolution path
6. Exempt paths listed when tools are locked (watcher not claimed + writes >= 2)
7. Current watcher step + scope shown when watcher is active
8. Full packet stays under 1500 chars even with all sections active

### Gate Coverage
9. Watcher-not-claimed condition detected and queued
10. Cron-not-active condition detected and queued
11. Phase compliance detected (code writes locked during PLAN/NEGOTIATE/EVALUATE/COMPLETE)
12. Sprint contract absence detected and queued
13. Phase-feedback FAIL detected as hard block
14. Must-do summary absence detected and queued
15. Evidence checkpoint pending detected as hard block
16. Strategy loop detected as hard block (uses existing detect-strategy-loop.sh)

### Safety
17. Packet assembler only reads state files — never writes, never enforces (exit 0 always)
18. All existing on-prompt-submit.sh features preserved: must-do injection, evidence checkpoint injection, strategy loop injection
19. Gate scripts completely untouched — no changes to pre-write-gate.sh, pre-bash-gate.sh, pre-flight-gate.sh
20. lib-helpers.sh: only new functions added, no existing functions modified

## Verification

Independent sub-agent with bypassPermissions mode. Tests by:
- Simulating different harness states (unblocked, fresh session, blocked)
- Measuring output length for unblocked case (< 200 chars)
- Measuring output length for fully-blocked case (< 1500 chars)
- Checking action queue ordering matches dependency order
- Verifying each gate condition produces correct queue item or blocked-by entry
- Confirming gate scripts have zero diff from before implementation

## Key Implementation Constraints
- `sed 's|\\|/|g'` crashes on MSYS — use `tr '\\\\' '/'`
- Windows jq output has `\r\n` — strip with `| tr -d '\r'`
- `while IFS= read -r` needs `|| [ -n "$var" ]` for files without trailing newline
- `grep -E` doesn't support `\d` — use `[0-9]`
- `<<<` here-strings fail in hook subprocesses — use temp files
- Packet assembler runs on EVERY prompt — must be fast (no expensive operations)
- Watcher slot reading must use `pwd -W | tr '[:upper:]' '[:lower:]'` for project matching
