# MSYS/Git Bash `sed` Compatibility Report

**Created**: 2026-04-14 (Sprint 19)
**Status**: Active — 20 broken `sed` calls remain in JSON-escaping paths
**Severity**: Critical (causes permanent agent lockout in must-do gate)

---

## Executive Summary

The harness runs on Windows using Git Bash (MSYS2). MSYS's `sed` implementation interprets backslash characters in search/replacement patterns differently from GNU `sed` on Linux/macOS. This causes `sed` commands containing `\\` to crash with `unterminated 's' command` or `unknown option to 's'`.

This bug has appeared **three times** across 5 sprints, each time blocking agents for hours before diagnosis. It is the single most recurring bug in the harness infrastructure.

---

## Root Cause

### The MSYS `sed` Backslash Problem

On Linux/macOS, `sed` treats `\\` in a pattern as a literal backslash. On MSYS/Git Bash, the MSYS runtime performs its own backslash interpretation *before* `sed` sees the pattern, mangling the command.

```bash
# This works on Linux, crashes on MSYS:
echo 'C:\Users\test' | sed 's|\\|/|g'
# MSYS error: "unterminated `s' command"

# This also crashes:
echo 'test' | sed 's/\\/\\\\/g; s/"/\\"/g'
# MSYS error: "unknown option to `s'"
```

The MSYS runtime sees the `\\` sequences in the single-quoted string and performs path translation or escape interpretation, leaving `sed` with a malformed expression. This is **not a bash quoting issue** — single quotes prevent bash from interpreting the string, but MSYS operates at a lower level between bash and the actual binary.

### Why It Keeps Appearing

1. **All sed documentation shows `\\` as the way to match a literal backslash** — this is correct on Linux but broken on MSYS
2. **AI agents generate sed commands from documentation** — every model (Claude, GPT, Codex) will produce the Linux-correct pattern
3. **It works in local testing if the input doesn't contain backslashes** — the sed command only crashes when it actually tries to process the `\\` pattern
4. **New features add new loops** — the must-do system (Sprint 14) added 8 loops reading `must-do.md`, all using the same broken pattern
5. **No automated compatibility check exists** — there is no lint or test that catches `sed` with `\\` before deployment

---

## Incident History

### Incident 1: Watcher Project Matching (Sprint 15)

**Severity**: Critical — ALL projects affected
**Discovery**: PCW agent's watcher kept getting released mid-session
**Root cause**: Path normalization `sed 's|\\|/|g'` crashed silently → watcher project path never matched `pwd` → stale cleanup released it → agent permanently locked

**Files fixed** (4):
- `pre-write-gate.sh` — project path matching
- `pre-bash-gate.sh` — project path matching
- `on-session-end.sh` — session cleanup
- `on-prompt-submit.sh` — project path matching

**Fix**: `sed 's|\\|/|g'` → `tr '\\\\' '/'`

### Incident 2: Must-Do Basename Extraction (Sprint 19)

**Severity**: Critical — any project with `must-do.md` using backslash paths
**Discovery**: Agent on PCW project permanently blocked by must-do gate despite correct summary referencing `OCA-survey.md` multiple times
**Root cause**: Two bugs interacting:

1. `sed 's|\\|/|g'` at `pre-write-gate.sh:285` crashed → `basename ""` returned empty → `MENTIONS` stayed at 0 → gate blocked forever
2. `while IFS= read -r` skipped the last line of `must-do.md` when file had no trailing newline → loop body never executed → 0 basenames checked

**Files fixed** (5 files, 12 changes):

| File | sed→tr fixes | newline fixes |
|------|-------------|---------------|
| `pre-write-gate.sh` | 1 (line 285) | 6 loops |
| `pre-bash-gate.sh` | 0 | 1 loop |
| `on-prompt-submit.sh` | 0 | 1 loop |
| `generate-pre-flight-challenge.sh` | 1 (line 224) | 1 loop |
| `create-evidence-checkpoint.sh` | 0 | 1 loop |

**Fix**: `sed 's|\\|/|g'` → `tr '\\\\' '/'`, `while IFS= read -r var; do` → `while IFS= read -r var || [ -n "$var" ]; do`

### Incident 3 (Latent): JSON String Escaping — NOT YET FIXED

**Severity**: Medium — causes silent data loss in JSON output, not a blocking gate
**Status**: 20 broken `sed` calls remain across 7 files
**Impact**: When hook output includes Windows paths, JSON fields are silently empty or malformed. This degrades logging, fingerprinting, and evidence collection but does not block agents.

**Broken pattern**: `sed 's/\\/\\\\/g; s/"/\\"/g'` and `sed 's|\\|\\\\|g; s|"|\\"|g'`
**Purpose**: Escaping backslashes and quotes for JSON string embedding

**Affected files and locations**:

| File | Count | Lines |
|------|-------|-------|
| `collect-test-evidence.sh` | 7 | 111, 131, 154, 161, 168, 257, 289 |
| `post-write-check.sh` | 4 | 134, 167, 269, 322 |
| `on-prompt-submit.sh` | 2 | 179, 204 |
| `agent-call-tracker.sh` | 2 | 87, 91 |
| `detect-strategy-loop.sh` | 2 | 181, 182 |
| `classify-verification-need.sh` | 1 | 58 |
| `run-project-tests.sh` | 1 | 90 |
| `detect-test-runner.sh` | 1 | 147 |
| **Total** | **20** | |

**Fix**: Replace `sed` JSON escaping with `jq --arg`:
```bash
# BROKEN (MSYS):
SAFE=$(printf '%s' "$VALUE" | sed 's/\\/\\\\/g; s/"/\\"/g')
printf '{"key": "%s"}' "$SAFE"

# FIXED:
jq -n --arg v "$VALUE" '{"key": $v}'
```

---

## The Two Affected Patterns

### Pattern A: Backslash-to-Forward-Slash (Path Normalization)

**Purpose**: Convert `G:\path\to\file` → `G:/path/to/file`

```bash
# BROKEN (crashes on MSYS):
normalized=$(printf '%s' "$path" | sed 's|\\|/|g')

# FIXED:
normalized=$(printf '%s' "$path" | tr '\\\\' '/')
```

**Why `tr` works**: `tr` is a simple character-by-character translator. It doesn't use regex or interpret its arguments the same way `sed` does. MSYS doesn't mangle `tr` arguments.

**Why `tr '\\\\'`**: In single quotes, `\\\\` is four characters: `\`, `\`, `\`, `\`. The shell passes these literally to `tr`. `tr` interprets `\\` as an escaped backslash (one literal `\`), repeated twice = still one `\` in its character set. Using just `'\\'` (two chars) also works but produces a portability warning.

**Status**: All 6 instances fixed (Sprint 15 + Sprint 19).

### Pattern B: JSON String Escaping

**Purpose**: Escape `\` and `"` for safe embedding in JSON strings

```bash
# BROKEN (crashes on MSYS):
safe=$(printf '%s' "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')

# FIXED — Option 1 (jq --arg, preferred):
jq -n --arg v "$value" '{"key": $v}'

# FIXED — Option 2 (jq --arg for variable, then use in template):
SAFE=$(jq -rn --arg v "$value" '$v')

# FIXED — Option 3 (awk, when jq is too heavy):
safe=$(printf '%s' "$value" | awk '{gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); print}')
```

**Status**: 20 instances remain unfixed. These are lower priority since they affect logging/diagnostics rather than gating.

---

## The Trailing Newline Companion Bug

### Problem

`while IFS= read -r var; do ... done < file` skips the last line if the file has no trailing newline. The `read` builtin returns a non-zero exit code on EOF (even if it read data into `$var`), so the `while` loop exits before processing the last line.

### Why It Matters Here

`must-do.md` files are created by users, often with a single line and no trailing newline. When the file contains one path and no `\n`, the entire loop body never executes. Combined with the sed bug, this created a double-failure: even fixing one bug left the other blocking agents.

### Fix

```bash
# BROKEN (skips last line without trailing newline):
while IFS= read -r line; do
  process "$line"
done < file

# FIXED:
while IFS= read -r line || [ -n "$line" ]; do
  process "$line"
done < file
```

The `|| [ -n "$line" ]` clause continues the loop one more iteration when `read` returns non-zero (EOF) but still populated `$line` with data.

### Where To Apply

Any `while read` loop that reads from a user-created file (not auto-generated JSON/JSONL). Auto-generated files reliably end with newlines; user-created files do not.

---

## Prevention Rules

### Rule 1: Never Use `sed` With Backslash Patterns on This Machine

```
# BANNED — will crash on MSYS:
sed 's|\\|...|g'
sed 's/\\/..../g'
sed 's/..../\\\\/g'

# USE INSTEAD:
tr '\\\\' '/'           # for path normalization
jq --arg v "$val" ...   # for JSON escaping
awk '{gsub(...)}' ...   # for general substitution
```

### Rule 2: Always Guard `while read` Loops for Missing Trailing Newlines

```bash
# When reading user-created files:
while IFS= read -r line || [ -n "$line" ]; do
```

### Rule 3: Audit New Code Before Deploying

Before any new script or hook is deployed, scan for:
```bash
grep -rn "sed.*\\\\\\\\" scripts/ hooks/
grep -rn "while IFS= read -r" scripts/ hooks/ | grep -v '|| \['
```

The first grep finds sed with backslash patterns. The second finds `while read` without the trailing newline guard.

### Rule 4: Document the Constraint

Every new script should include this comment header if it runs on MSYS:
```bash
# MSYS/Git Bash compatibility:
# - Do NOT use sed with \\ patterns (crashes on MSYS)
# - Use tr for path normalization, jq --arg for JSON escaping
# - Use 'while read || [ -n ]' for user-created files
```

### Rule 5: Test With Backslash Input

When testing any hook that processes file paths, always test with a Windows-style backslash path:
```bash
echo 'G:\test\path\file.md' | your_command
```

If this crashes or produces empty output, the command is broken.

---

## Outstanding Work

### Priority 1: Fix Remaining 20 JSON-Escaping `sed` Calls

These are currently producing silent data loss when paths contain backslashes. While not gate-blocking, they degrade:
- Test evidence fingerprinting (`collect-test-evidence.sh`)
- Write tracking (`post-write-check.sh`)
- Strategy loop detection (`detect-strategy-loop.sh`)
- Agent call tracking (`agent-call-tracker.sh`)

Each should be replaced with `jq --arg` following the pattern established in `create-evidence-checkpoint.sh:100`.

### Priority 2: Add a Lint Check

Create a pre-commit or CI check that scans `.sh` files for:
- `sed` with `\\` in patterns
- `while IFS= read -r` without `|| [ -n `

This would catch the bug at development time rather than in production.

---

## Appendix: MSYS Architecture Context

Git Bash on Windows uses MSYS2, a compatibility layer that translates POSIX paths and arguments for Windows binaries. MSYS2 has a "path conversion" feature that automatically converts `/c/Users/...` to `C:\Users\...` when passing arguments to non-MSYS binaries.

This conversion also affects `sed` patterns. When MSYS sees `\\` in a command-line argument, it may interpret it as a path separator escape and translate it, corrupting the `sed` expression before `sed` ever sees it.

This is a known MSYS2 behavior documented at:
- MSYS2 environment variables: `MSYS2_ARG_CONV_EXCL` can disable conversion for specific arguments
- Setting `MSYS_NO_PATHCONV=1` disables all path conversion (but breaks other things)

The `tr` and `jq` workarounds avoid the issue entirely by not using patterns that trigger MSYS's path conversion heuristic.
