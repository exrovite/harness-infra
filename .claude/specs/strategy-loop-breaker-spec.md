# Strategy Loop Breaker — Product Spec (Rev 4)

## Problem

Agents use the knowledge base and must-do documents at the start of a task, but when they enter a loop — trying the same approach repeatedly with minor tweaks — they don't recognise they're looping and never go back to check for alternative strategies.

The knowledge is already there. The must-do folder already contains proven strategies and documented mistakes. The agent just needs to be told: "You're looping. Go re-read your options."

## What This System Does

Detects when an agent is stuck in a strategy loop (tunnel vision) and intervenes in two escalating tiers:

### Tier 1 — Nudge
When all three loop signals fire simultaneously, inject a prompt into the agent's context:
- "You appear to be looping on [problem area]. Have you considered other approaches?"
- List the must-do files relevant to the current task
- Prioritise files with "mistake" in the filename
- Agent has agency — it can acknowledge and continue

### Tier 2 — Hard Block
After 3 nudges with the agent still looping (all 3 signals still true):
- Block all source code writes (in BOTH `pre-write-gate.sh` AND `pre-bash-gate.sh`)
- Agent must:
  1. Read the listed must-do files
  2. Write a strategy acknowledgment file naming the specific new approach
- Writes unblock only after acknowledgment

---

## Three Detection Signals (ALL required)

No single signal means "loop." All three together = definitive loop. These signals are **framework-agnostic** — they work for tests, builds, lints, type-checks, any command.

### Signal 1: Same Output Fingerprint Repeating

The agent runs a Bash command that fails (exit code > 0). It edits code. It runs a similar command. It fails again with a similar output pattern. The **output fingerprint** is: the last non-empty line of the combined stdout+stderr output, with all digits stripped and whitespace collapsed. If the same fingerprint appears in 3+ consecutive failing commands, Signal 1 fires.

**Why last line, not first**: Error messages and failure summaries typically appear at the END of command output (after progress bars, build status, compilation output). The last non-empty line is the most likely to contain the actual error.

**Why combined output, not stderr only**: Claude Code's PostToolUse hook provides stdout and stderr mixed together in `tool_result` as a single string. There is no separate stderr field. Using the last line of combined output is the only reliable approach.

**Normalisation**: `last_nonempty_line | sed 's/\x1b\[[0-9;]*m//g' | sed 's/[0-9]//g' | tr -s ' '` — strip ANSI escape codes, strip digits, collapse whitespace.

**Known limitation**: Stripping digits means parameterised messages like "expected 2 arguments, got 3" and "expected 5 arguments, got 1" produce the same fingerprint. This is acceptable — if the same TYPE of error keeps recurring, it's the same root cause even if the numbers differ. The triple-signal requirement prevents false positives.

### Signal 2: Consecutive Command Failures Without Success

The agent runs substantive commands that fail (exit code > 0) N times in a row without a single success (exit code 0) in between. Threshold: 3 consecutive failures.

**Why this works**: During productive iteration, the agent occasionally succeeds. When nothing succeeds for 3+ attempts, the current approach isn't working.

**What counts as substantive**: Only commands that represent actual work — NOT trivial/read-only commands. See the Excluded Commands section below.

**Exit code extraction**: Claude Code's `tool_result` may contain an exit code in the text (e.g., `exit code: N`). If no exit code is found in the output text, the command is logged as "unknown" and excluded from consecutive-failure counting. Only commands with a confirmed non-zero exit code count as failures.

### Signal 3: Same Files Edited Between Failures

Between consecutive failing commands (while Signals 1+2 are active), the agent edits the same file(s). The write log (`unverified-writes.jsonl`) already tracks every Write/Edit with file path and timestamp. If the same file appears in 3+ inter-failure edit windows, the agent is churning on the same code without making progress.

**First failure entry**: For the first failure logged in a session (no previous entry to reference), `files_edited_since_last` is set to an empty list `[]`. This means Signal 3 cannot fire until the second failure at the earliest, and practically requires 4 failures minimum for all 3 signals to fire (first entry has no files, second+ entries do). This is intentional — it prevents false positives at session start.

---

## Command Failure Capture

### Script Placement

The general failure logging is added to `collect-test-evidence.sh` but placed **BEFORE** the existing BUILD/TDD early-exit gates. The execution flow becomes:

```
1. Read hook input (existing)
2. >> NEW: General failure/success logging (runs unconditionally)
3. Early-exit if not BUILD phase (existing)
4. Early-exit if TDD not required (existing)
5. TDD-specific evidence collection (existing)
```

This ensures the strategy loop breaker works in ALL phases and regardless of TDD configuration, while the existing TDD evidence collection remains properly gated.

### What Gets Logged — Failures

For ANY substantive Bash command with confirmed exit code > 0, append to `.claude/state/bash-failure-log.jsonl`:
```json
{
  "ts": "ISO-8601",
  "cmd_fingerprint": "first 80 chars of command",
  "exit_code": 1,
  "output_fingerprint": "last nonempty line, digits stripped, whitespace collapsed",
  "files_edited_since_last": ["file1.py", "file2.py"]
}
```

The `files_edited_since_last` field is populated by reading `unverified-writes.jsonl` entries with timestamps after the previous failure log entry's timestamp. If no previous entry exists (first failure in session), this field is `[]`.

### What Gets Logged — Successes

For substantive commands with confirmed exit code 0, append a minimal success marker:
```json
{"ts": "ISO-8601", "success": true}
```
This resets the consecutive-failure counter.

### Excluded Commands

Commands are excluded by checking whether ALL sub-commands are trivial. The command string is split on `&&`, `||`, `;`, and `|` into sub-commands. For each sub-command, extract the first token (the part before the first space). If **every** sub-command's first token is in the exclusion list, the entire command is excluded. If **any** sub-command's first token is NOT excluded, the command is logged.

This ensures `cd dir && npm test` is logged (because `npm` is not excluded), while `cd dir && ls` is excluded (both `cd` and `ls` are excluded).

**Trivial/read-only commands** (excluded tokens):
`ls`, `cat`, `head`, `tail`, `pwd`, `echo`, `printf`, `cd`, `which`, `type`, `whoami`, `date`, `wc`, `file`, `stat`, `readlink`, `basename`, `dirname`, `source`, `export`, `set`, `unset`, `alias`, `true`, `false`, `test`, `[`

**Data query commands** (excluded tokens):
`jq`, `grep`, `rg`, `find`, `sed`, `awk`, `sort`, `uniq`, `tr`, `cut`, `xargs`

**All git commands** (excluded tokens):
Any sub-command whose first token is `git` — both read-only (`git status`, `git log`) and write (`git commit`, `git push`). A failed `git commit` due to a hook failure is a git problem, not a strategy loop.

**Subshells and env vars**: Commands starting with `(` have the parenthesis stripped before token extraction. Commands with `VAR=value` prefixes (matching `[A-Z_]+=`) have the prefix stripped to extract the actual command token (e.g., `ENV=prod npm test` → token is `npm`).

### Session Boundary

`bash-failure-log.jsonl` is **cleared on session start** by `startup-recovery.sh`. This prevents stale failures from previous sessions triggering false signals. The file is also trimmed to 50 entries maximum during the session (in case of very long sessions).

---

## Detection Script: `detect-strategy-loop.sh`

A new Layer 2 script that reads `bash-failure-log.jsonl` and returns one of:
- `none` — no loop detected (exit 0)
- `nudge` — all 3 signals active, recommend nudge (exit 1)
- `block` — all 3 signals active AND nudge count >= 3 (exit 2)

### Algorithm

1. If `bash-failure-log.jsonl` does not exist or is empty -> exit 0
2. If `agent-blocked.md` exists (detect-loop.sh fired) -> exit 0 (deconfliction)
3. Read last 10 entries from `bash-failure-log.jsonl`
4. Find consecutive failures from the tail (entries without `"success": true` between them)
5. If fewer than 3 consecutive failures -> exit 0 (Signal 2 not met)
6. Extract output fingerprints from those consecutive failures
7. Count matching fingerprints (most common fingerprint vs total)
8. If the most common fingerprint appears fewer than 3 times -> exit 0 (Signal 1 not met)
9. Collect all files from `files_edited_since_last` across those entries
10. Count file occurrences — if no single file appears in 3+ entries -> exit 0 (Signal 3 not met)
11. All 3 signals active -> read `.claude/state/strategy-loop-state.json`
12. If state file missing or invalid JSON -> initialise to `nudge_count: 0, blocked: false`
13. If nudge_count < 3 -> exit 1 (nudge)
14. If nudge_count >= 3 -> exit 2 (block)

### Reset Conditions

The nudge counter in `strategy-loop-state.json` resets to 0 when:
- A `"success": true` entry appears in the failure log (agent's command succeeded)
- The dominant output fingerprint changes (different error = different problem)
- The most-churned file changes (agent moved to different files)
- `agent-blocked.md` is removed after a detect-loop.sh resolution (prevents premature Tier 2 after external block clears)

Reset is performed by `detect-strategy-loop.sh` itself — it compares current fingerprint/files against `last_output_fingerprint` and `last_churn_files` in the state file.

---

## State Tracking

`.claude/state/strategy-loop-state.json`:
```json
{
  "nudge_count": 0,
  "last_nudge_ts": null,
  "last_output_fingerprint": "",
  "last_churn_files": [],
  "blocked": false
}
```

---

## Integration Points

### Nudge Injection (on-prompt-submit.sh)

Add a section that calls `detect-strategy-loop.sh`.
- If exit 1 (nudge): increment nudge_count in state file, inject message listing must-do files with "mistake" files marked as PRIORITY. **Cooldown**: only increment if `last_nudge_ts` is more than 60 seconds ago — prevents rapid prompt submissions from escalating to Tier 2 before the agent has a chance to act on the nudge.
- If exit 2 (block): set `blocked: true` in state file, inject message warning that writes are now blocked until strategy-ack.md is written.

### Block Gate (pre-write-gate.sh AND pre-bash-gate.sh)

Add a section that checks `strategy-loop-state.json`:
- If `blocked: true`, check whether `.claude/state/strategy-ack.md` exists and passes validation (see Block Clearing below)
- If ack valid: clear the block (set `blocked: false`, reset `nudge_count`, delete ack, truncate failure log) and allow the write
- If ack missing or invalid: block source code writes with actionable message
- Same exemption list as other gates: `.claude/state/`, `.openclaw/watchers/`, `.agent-memory/`, `.claude/contracts/`, `.claude/specs/`, `.claude/pre-flight/`, `agentwiki/`

The ack validation happens **inside `pre-write-gate.sh` (and `pre-bash-gate.sh`)** — the same place that checks the block. This means the agent writes the ack, then on the next Write/Edit attempt, the gate validates the ack, clears the block, and allows the write in a single pass.

### Block Clearing — strategy-ack.md Validation

The acknowledgment file must:
1. **Reference at least one must-do file by basename** (grep check) — **only if must-do folder exists**. If no must-do folder exists, this check is skipped.
2. **Be at least 150 characters** (prevents one-liners)
3. **Contain a "## New Approach" section header** (structural check)

When no must-do folder exists, only checks 2 and 3 apply. The agent can still be blocked and must still pause and write about a new approach, but isn't required to reference files that don't exist.

This validation is deliberately **not trying to judge strategy quality**. The mechanism works by:
- **Forcing a pause** — the agent must stop coding and write prose
- **Forcing a re-read** — the agent must reference must-do files
- **Breaking the tunnel vision** — the act of stepping back is itself the intervention

The ack file is **deleted after clearing** so it can't be reused if the agent loops again.

When the ack clears the block:
1. Set `blocked: false` in `strategy-loop-state.json`
2. Reset `nudge_count` to 0
3. Delete `strategy-ack.md`
4. Truncate `bash-failure-log.jsonl` (remove all entries — clean slate after strategy change)

### Deconfliction with detect-loop.sh

| | detect-loop.sh | strategy loop breaker |
|---|---|---|
| **Signal** | Git commit history | Bash command failures + write log |
| **Scope** | Cross-session (git) | Within-session (JSONL logs) |
| **Response** | Inject known-fix or hard-block | Nudge -> block -> ack |

If both fire: `detect-loop.sh` takes priority. The strategy loop breaker checks for `agent-blocked.md` at step 2 of its algorithm and exits cleanly if present.

When `agent-blocked.md` is removed (human resolved the detect-loop block), the strategy loop breaker resets its nudge_count to 0 to avoid a premature Tier 2 block.

---

## Must-Do Integration

The nudge/block message lists files from the project's must-do folder:
1. Find `docs/must do/must-do.md` (or `docs/must-do/` or `.claude/must-do/`)
2. Read the file list from it
3. Sort: files with "mistake" in the filename come first, marked as `(PRIORITY)`
4. If no must-do folder exists: fall back to generic message: "Review your knowledge base, AgentWiki, and any strategy documents for alternative approaches."

---

## What This Does NOT Do

- Does not create new knowledge stores (reuses must-do)
- Does not replace `detect-loop.sh` (different scope — git vs session)
- Does not add new hook scopes (extends existing PostToolUse/Bash hook; adds gate sections to existing PreToolUse hooks)
- Does not require LLM judgment for detection (exit codes + string matching)
- Does not try to semantically validate strategy quality (forces process instead)
- Does not permanently block the agent (ack clears the block, ack is then deleted)
- Does not fire on read-only, trivial, or git commands (excluded command list)
- Does not depend on BUILD phase or TDD being enabled (failure logging runs unconditionally)

---

## Escalation Path Summary

```
Normal work
  -> Command fails, agent edits, command fails again (same error, same files)
  -> 3 consecutive failures with matching fingerprint + same files
  -> All 3 signals fire
  -> Tier 1: Nudge injected ("you may be looping, read these files")
  -> Agent continues (has agency to try once more)
  -> Still failing after nudge
  -> Nudge count reaches 3
  -> Tier 2: Writes blocked
  -> Agent reads must-do files, writes strategy-ack.md
  -> Writes unblocked, nudge counter reset, ack deleted, failure log cleared
  -> If same signals fire again -> re-enter Tier 1 from scratch
```

---

## Known Limitations (acknowledged, not bugs)

1. **Ack is gameable**: The agent can write a generic ack. We accept this because the purpose is to force a pause and a re-read, not to validate strategy quality. The pause itself is the intervention.

2. **Flaky external failures can trigger false positives**: An environmental failure (e.g., "connection refused") will produce the same fingerprint repeatedly during legitimate work. Mitigation: requiring all 3 signals (same error AND same files AND no successes) makes this unlikely unless the agent is genuinely stuck.

3. **Silent loops without commands**: An agent that loops by only editing files (never running commands) won't be detected. The existing watcher cron and `detect-loop.sh` (git-based) cover this gap.

4. **Digit-stripped fingerprinting is lossy**: Stripping digits makes "expected 2 arguments, got 3" and "expected 5 arguments, got 1" the same fingerprint. By design — same error type = same root cause. Triple-signal prevents false positives.

5. **Exit code extraction is heuristic**: Claude Code doesn't provide exit codes as a structured field. They are parsed from output text patterns. Commands where the exit code can't be determined are excluded from failure counting (neither success nor failure).

6. **`|| true` bypass**: An agent using `command || true` forces exit code 0, bypassing detection. This is unusual agent behavior and would likely be caught by other mechanisms (watcher cron, manual review).

7. **Pipeline exit code masking**: `npm test | tee output.log` reports `tee`'s exit code (0), not `npm test`'s. This makes piped failing commands invisible to the system. Mitigation: agents rarely pipe test/build output through other commands, and the heuristic exit code extraction (limitation 5) may still catch failure markers in the output text.
