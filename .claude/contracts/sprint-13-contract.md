# Sprint 13 Contract: Evidence Checkpoint System

## Scope

Implement periodic evidence checkpoints that force verifier sub-agents to check process compliance during execution, with must-do source files injected by the harness (not the builder).

## Deliverables

### D1: create-evidence-checkpoint.sh (NEW — ~100 lines)
Standalone script. Called by post-write-check.sh when checkpoint triggers.
- Finds must-do folder (`docs/must do/`, `docs/must-do/`, `.claude/must-do/`)
- Reads must-do index file, extracts listed file paths
- Reads each source file content (truncate to 3000 chars each)
- Reads `.claude/state/must-do-summary.md`
- Gets modified files from `.agent-memory/working/session-context.md` (not git — works in non-git projects)
- If `.claude/state/evidence-paths.json` exists (agent provided paths after a FAIL): includes those paths in the brief so the next verifier checks those specific files
- Writes `.claude/state/evidence-checkpoint.json` with verifier instruction:
  - Check each declared phase for evidence
  - For each missing phase: name it specifically, say what was checked, tell agent to write paths to `.claude/state/evidence-paths.json` if evidence exists elsewhere
  - If agent-provided paths present: READ those files and judge if they're real evidence for the claimed phase
- Exit 0 on success, exit 1 if no must-do folder (caller handles gracefully)

### D2: pre-write-gate.sh — add checkpoint block (~35 lines inserted)
Position: after must-do summary gate, before watcher/cron gate.
- If `evidence-checkpoint.json` exists with `"status":"pending"`:
  - Exempt: `.claude/state/`, `.claude/evidence/`, `.openclaw/watchers/`, `.agent-memory/`, `.claude/contracts/`, `.claude/specs/`, `.claude/pre-flight/`, `agentwiki/`, Agent tool
  - Check for verdict file: `evidence-verdict.json`
    - If verdict PASS: delete checkpoint + verdict + evidence-paths files, allow write
    - If verdict FAIL: stay blocked, show the verdict's `summary` and `findings` (which phases missing, what was checked). Tell agent: "Either produce the missing evidence OR write the file paths to `.claude/state/evidence-paths.json` then delete the verdict to re-trigger verification"
    - If no verdict: block, tell agent to spawn verifier sub-agent. Include: "Do NOT tell the verifier what to check — the brief is already in its environment via .claude/state/evidence-checkpoint.json"
- MUST consume stdin data that pre-write-gate already reads (use existing `$INPUT_DATA`)

### D3: pre-bash-gate.sh — mirror checkpoint block (~25 lines inserted)
Same logic as D2. Position: after strategy loop block, before watcher/cron check.
- Same exemption: if command targets `.claude/state/`, `.claude/evidence/` etc → allow
- Uses existing `$COMMAND` variable for path detection

### D4: on-prompt-submit.sh — add checkpoint injection (~15 lines inserted)
Position: after must-do summary injection, before strategy loop breaker.
- If `evidence-checkpoint.json` exists with `"status":"pending"`:
  - Append to CONTEXT_MSG: "[EVIDENCE CHECKPOINT] Writes blocked. Spawn a verifier sub-agent. Brief at .claude/state/evidence-checkpoint.json — the verifier must read it."
- No injection when no checkpoint active.

### D5: post-write-check.sh — add counter + trigger (~40 lines inserted)
Position: end of script (after existing write tracking).
- Read/create `.claude/state/checkpoint-counter.json`: `{"writes": N, "last_step": "..."}`
- Increment writes count
- Read current watcher step from `.claude/pre-flight/gate-counter.json` (reuse existing step tracking — no duplicate watcher reads)
- If step changed from last_step: reset counter to 0, trigger checkpoint
- If writes >= threshold (read from `.claude/state/checkpoint-config.json` or default 15):
  - Only if must-do summary exists
  - Only if no active checkpoint (`evidence-checkpoint.json` doesn't exist)
  - Call `create-evidence-checkpoint.sh`
  - Reset counter to 0

## Acceptance Criteria (24 items)

### Trigger Logic
1. Checkpoint triggers after 15 writes when must-do summary exists
2. Checkpoint triggers immediately on watcher step change
3. No trigger when no must-do summary exists
4. No trigger when checkpoint already active
5. Counter resets after PASS verdict
6. Counter does NOT reset after FAIL verdict

### Block Gate
7. Source code writes blocked when checkpoint pending
8. `.claude/state/` writes allowed (verdict writable)
9. `.claude/evidence/` writes allowed (evidence writable)
10. Agent tool calls allowed (must spawn verifier)
11. Block clears on PASS verdict (checkpoint + verdict files deleted)
12. Block persists on FAIL verdict

### Checkpoint Brief
13. Brief contains must-do summary text
14. Brief contains must-do source file contents (truncated 3000 chars each)
15. Brief contains modified files list
16. Brief contains verifier instruction
17. On re-verification: brief includes agent-provided paths from `.claude/state/evidence-paths.json` if it exists

### Iterative Feedback Loop
18. FAIL verdict names each missing phase specifically (not just "FAIL")
19. FAIL verdict tells agent: "if evidence exists elsewhere, write the paths to `.claude/state/evidence-paths.json` and re-verify"
20. On re-verification, verifier instruction includes the agent-provided paths so verifier checks those specific files
21. Agent cannot dismiss a FAIL — must either produce the evidence OR point to where it already exists

### Injection
22. on-prompt-submit injects alert when checkpoint pending
23. Injection under 300 chars
24. No injection when no checkpoint active

### Non-Interference
25. Projects without must-do: zero effect on write flow
26. Projects without must-do: zero injection on prompt
27. Must-do summary gate unchanged
28. Pre-flight MCQ still fires after checkpoint clears
29. Strategy loop breaker unchanged

## Verification
Independent sub-agent with bypassPermissions mode. Tests each criterion by:
- Creating temp directories simulating projects with/without must-do
- Running hook scripts with mock inputs
- Checking exit codes and stderr output
- Validating JSON file contents

## Key Implementation Constraints
- PostToolUse hooks read tool context via STDIN JSON — use `HOOK_INPUT=$(cat)` at top
- No `sed 's|\\|/|g'` — use `tr '\\\\' '/'` for MSYS
- No `\d` in grep -E — use `[0-9]`
- No `<<<` here-strings — use temp files
- Strip `\r` from jq output with `| tr -d '\r'`
- Must-do folder check must be FIRST in any new code path — fast exit for projects without it
- `create-evidence-checkpoint.sh` must handle missing/corrupt files gracefully (no set -e traps)
