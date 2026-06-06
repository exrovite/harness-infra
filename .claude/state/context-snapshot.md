# Context Snapshot — Sprint 27 GPU Test Coordination

## Target Files
- `lib-helpers.sh` (292 lines) — shared helpers, has registry_lock/unlock pattern to follow for test lock
- `validate-phase.sh` (198 lines) — phase 3 (BUILD) runs tests at lines 116-123, no timeout, no config
- `pre-bash-gate.sh` — PreToolUse hook, reads stdin JSON, detects file-writing patterns
- `post-write-check.sh` (365 lines) — PostToolUse hook, reads stdin JSON via HOOK_INPUT=$(cat)
- `on-prompt-submit.sh` (760 lines) — UserPromptSubmit hook, assembles turn packet

## Key Patterns
- Atomic lock: `mkdir "$LOCKDIR"` (registry_lock at lib-helpers.sh:84)
- PID tracking: `printf '%s' "$$" > "$LOCKDIR/pid"` (lib-helpers.sh:97)
- Stdin reading: hooks use `HOOK_INPUT=$(cat)` or `INPUT=$(cat)` at top
- Windows compat: `tr -d '\r'` on all jq output, `tr '\\' '/'` not sed for path normalization
- MSYS: no setsid available, need `cmd //c start //b` or background+timeout fallback

## validate-phase.sh Test Section (lines 116-123)
```
TEST_EXIT=0
if [ -f "package.json" ] && grep -q '"test"' "package.json"; then
  npm test > "${STATE_DIR}/test-output.txt" 2>&1
  TEST_EXIT=$?
elif [ -f "pytest.ini" ] || [ -f "setup.py" ] || [ -f "pyproject.toml" ]; then
  python -m pytest > "${STATE_DIR}/test-output.txt" 2>&1
  TEST_EXIT=$?
fi
```
This is what gets replaced with timeout+lock+config+dedup+result-file logic.

## File Locations
- Live hooks: C:\Users\exrov\.claude\hooks\
- Live scripts: C:\Users\exrov\.claude\scripts\
- Install hooks: G:\harness infra\_install\hooks\
- Install scripts: G:\harness infra\_install\scripts\

## MSYS Process Group Notes
- `setsid` not available on MSYS/Git Bash
- `timeout` command IS available (from GNU coreutils via MSYS)
- `timeout --kill-after=5 60 command` works and kills process group
- `taskkill //PID N //T //F` kills process tree on Windows (fallback)
