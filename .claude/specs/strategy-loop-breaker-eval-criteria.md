# Strategy Loop Breaker — Evaluation Criteria (Rev 4, final)

## Detection Accuracy

1. **No false positives on normal iteration**: Editing the same file 5+ times with different errors each time does NOT trigger any signal combination
2. **All-three-signals required**: Nudge is NEVER issued unless all 3 signals are simultaneously true
3. **Same output fingerprint detection works**: When the same normalised last-line fingerprint (ANSI stripped, digits stripped, whitespace collapsed) appears in 3+ consecutive failing commands, Signal 1 fires
4. **Consecutive failure detection works**: When 3+ substantive commands fail in a row without a success between them, Signal 2 fires
5. **File churn detection works**: When the same file appears in `files_edited_since_last` across 3+ consecutive failure entries, Signal 3 fires
6. **Reset on strategy change**: When a success entry appears, OR the output fingerprint changes, OR the churned files change, the nudge counter resets to 0
7. **Framework-agnostic**: Detection works for pytest failures, npm build errors, cargo build errors, tsc type errors, and lint failures — all using the same mechanism (exit code + output fingerprint)
8. **First entry safe**: The first failure entry in a session has `files_edited_since_last: []`, so Signal 3 requires minimum 4 consecutive failures to fire (not 3)

## Command Failure Capture

9. **Failing commands logged**: Any substantive Bash command with confirmed exit code > 0 appends a failure entry to `.claude/state/bash-failure-log.jsonl`
10. **Success commands logged**: Any substantive Bash command with confirmed exit code 0 appends a `{"success": true}` entry
11. **Unknown exit codes excluded**: Commands where exit code cannot be determined from output are NOT logged as either success or failure
12. **Trivial commands excluded**: `ls`, `cat`, `pwd`, `echo`, `printf`, `cd`, `which`, `type`, `whoami`, `date`, `wc`, `file`, `stat`, `readlink`, `basename`, `dirname`, `source`, `export`, `set`, `unset`, `alias`, `true`, `false`, `test`, `[` do NOT create log entries
13. **Data query commands excluded**: `jq`, `grep`, `rg`, `find`, `sed`, `awk`, `sort`, `uniq`, `tr`, `cut`, `xargs` do NOT create log entries
14. **All git commands excluded**: Any sub-command whose first token is `git` does NOT create log entries
15. **Chained command handling**: Commands are split on `&&`, `||`, `;`, and `|`. If ANY sub-command's first token is non-excluded, the entire command is logged. Only excluded if ALL sub-commands are trivial.
16. **Subshell and env-var prefix handling**: Leading `(` stripped before token extraction. `VAR=value` prefixes (matching `[A-Z_]+=`) stripped to extract actual command token.
17. **Log entry fields**: Each failure entry contains `ts`, `cmd_fingerprint`, `exit_code`, `output_fingerprint`, `files_edited_since_last`
18. **files_edited_since_last populated correctly**: Lists files from `unverified-writes.jsonl` with timestamps after the previous failure entry's timestamp; empty `[]` for the first entry in a session
19. **Log bounded**: `bash-failure-log.jsonl` is trimmed to 50 entries max during the session
20. **Log cleared on session start**: `startup-recovery.sh` deletes or truncates `bash-failure-log.jsonl` at session start to prevent stale cross-session data

## Script Placement

21. **Failure logging runs unconditionally**: The general failure/success logging in `collect-test-evidence.sh` executes BEFORE the BUILD/TDD early-exit gates, so it works in ALL phases regardless of TDD configuration
22. **Existing TDD logic unaffected**: The BUILD/TDD gating and TDD-specific evidence collection in `collect-test-evidence.sh` continues to work exactly as before

## Tier 1 — Nudge

23. **Nudge appears in agent prompt**: When `detect-strategy-loop.sh` returns exit 1, the next `on-prompt-submit` output includes the nudge message
24. **Nudge lists must-do files**: The nudge message includes specific file paths from the project's must-do folder
25. **Mistake files highlighted**: Files with "mistake" in their name appear first, marked as `(PRIORITY)`
26. **Nudge counter increments**: Each detection increments `nudge_count` in `strategy-loop-state.json`
27. **Nudge cooldown**: `nudge_count` only increments if `last_nudge_ts` is more than 60 seconds ago — prevents rapid prompt submissions from escalating to Tier 2 before the agent acts on a nudge
28. **Agent can continue**: Tier 1 nudge does NOT block writes — it is advisory only
28. **No must-do fallback**: If project has no must-do folder, nudge uses generic message: "Review your knowledge base, AgentWiki, and strategy documents"

## Tier 2 — Hard Block

29. **Block triggers after 3 nudges**: When `nudge_count >= 3` and all 3 signals still active, `strategy-loop-state.json` sets `blocked: true`
30. **Block enforced in pre-write-gate.sh**: Source code writes blocked when `blocked: true`
31. **Block enforced in pre-bash-gate.sh**: File-writing Bash commands blocked when `blocked: true`
32. **Block message is actionable**: Tells the agent to read must-do files and write `.claude/state/strategy-ack.md`
33. **Harness paths exempt**: Writes to `.claude/state/`, `.openclaw/watchers/`, `.agent-memory/`, `.claude/contracts/`, `.claude/specs/`, `.claude/pre-flight/`, `agentwiki/` are never blocked by this gate

## Block Clearing

34. **Ack clears block**: Writing `.claude/state/strategy-ack.md` with valid content sets `blocked: false` and resets `nudge_count` to 0
35. **Ack must reference must-do file (when available)**: If must-do folder exists, ack must contain at least one must-do file basename (grep check). If no must-do folder exists, this check is skipped.
36. **Ack minimum length**: At least 150 characters
37. **Ack structure required**: Contains a `## New Approach` section header
38. **Ack deleted after clearing**: The file is removed so it cannot be reused on a subsequent loop
39. **Failure log cleared on ack**: `bash-failure-log.jsonl` is truncated when ack clears the block — clean slate after strategy change
40. **Ack validation location**: Validation happens inside `pre-write-gate.sh` (and `pre-bash-gate.sh`). On the next Write/Edit after ack is written, the gate validates ack, clears block, and allows the write in a single pass.
41. **No-must-do Tier 2 not deadlocked**: When no must-do folder exists, the ack only needs to pass the 150-char minimum and "## New Approach" header checks — agent is never permanently locked.

## Deconfliction

42. **detect-loop.sh takes priority**: If `agent-blocked.md` exists, the strategy loop breaker exits cleanly at step 2 of its algorithm — no nudge, no block
43. **Nudge counter resets after external block resolves**: When `agent-blocked.md` is removed, `nudge_count` resets to 0 to prevent premature Tier 2
44. **Independent state**: Corrupting or deleting `strategy-loop-state.json` causes graceful fallback (initialise to nudge_count=0, blocked=false) — not a crash
45. **Missing bash-failure-log.jsonl**: If the log doesn't exist, detection returns "no loop" (exit 0)

## Integration

46. **No new hook scopes**: System extends existing PostToolUse/Bash (`collect-test-evidence.sh`) and adds gate sections to existing PreToolUse/Write|Edit hooks — no new tool scopes registered in settings.json
47. **Existing gates unaffected**: Phase gate, contract gate, must-do summary gate, pre-flight gate all continue to work independently
48. **Re-entry works**: After ack clears a block and the agent loops again with the same signals, Tier 1 re-enters from nudge_count=0 with a fresh failure log
