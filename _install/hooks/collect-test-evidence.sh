#!/bin/bash
# collect-test-evidence.sh — Layer 2: PostToolUse/Bash hook for TDD evidence collection
# Fires after every Bash tool use. During BUILD phase with TDD enabled,
# captures test runner invocations, exit codes, and framework output markers.
#
# Implements Signals 2 and 3 from phantom-tdd-enforcement-spec.md
#
# Output: appends to .claude/state/tdd/tdd-events.jsonl
# Stdout: JSON hookSpecificOutput (consumed by Claude Code)
# Stderr: diagnostics only

# Read tool context from stdin before set -e (stdin may be empty for some invocations)
HOOK_INPUT=$(cat 2>/dev/null) || true

set -euo pipefail

source "$HOME/.claude/scripts/lib-helpers.sh" 2>/dev/null
if ! type append_jsonl >/dev/null 2>&1; then
  # lib-helpers not available — can't log evidence, exit with valid hook output
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"TDD: lib-helpers.sh missing, evidence collection disabled"}}'
  exit 0
fi

STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
TDD_DIR="${STATE_DIR}/tdd"
TDD_CONFIG="${TDD_DIR}/tdd-config.json"
EVENTS_FILE="${TDD_DIR}/tdd-events.jsonl"
PHASE_FILE="${STATE_DIR}/current-phase.json"

CONTEXT_MSG=""

# --- Get Bash command and output from stdin JSON (needed by both strategy loop and TDD) ---
COMMAND=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
TOOL_OUTPUT=$(printf '%s' "$HOOK_INPUT" | jq -r '(.tool_result | if type == "object" then .stdout else . end) // ""' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":""}}'
  exit 0
fi

# ============================================================
# STRATEGY LOOP BREAKER — General failure/success logging
# Runs UNCONDITIONALLY (not gated by BUILD/TDD).
# Logs substantive command results to bash-failure-log.jsonl
# for strategy loop detection by detect-strategy-loop.sh.
# ============================================================

SLB_FAILURE_LOG="${STATE_DIR}/bash-failure-log.jsonl"

# --- Check if command is excluded (trivial/read-only/git) ---
# Split command on &&, ||, ;, | into sub-commands.
# Check first token of each. If ALL are excluded, skip logging.
SLB_EXCLUDED_TOKENS="ls cat head tail pwd echo printf cd which type whoami date wc file stat readlink basename dirname source export set unset alias true false test [ jq grep rg find sed awk sort uniq tr cut xargs git"

# Split on &&, ||, ;, | and check each sub-command's first token
SLB_ALL_EXCLUDED=true
SLB_SPLIT_FILE=$(mktemp 2>/dev/null || echo "/tmp/slb_split_$$")
printf '%s' "$COMMAND" | awk '{gsub(/&&/,"\n"); gsub(/\|\|/,"\n"); gsub(/;/,"\n"); gsub(/\|/,"\n"); print}' > "$SLB_SPLIT_FILE"
while IFS= read -r SLB_SUB; do
  SLB_SUB=$(printf '%s' "$SLB_SUB" | sed 's/^[[:space:]]*//')
  [ -z "$SLB_SUB" ] && continue
  SLB_TOKEN=$(printf '%s' "$SLB_SUB" | awk '{print $1}')
  # Strip leading ( for subshells
  SLB_TOKEN="${SLB_TOKEN#\(}"
  # Strip VAR=value prefixes (e.g., ENV=prod npm test -> npm)
  while printf '%s' "$SLB_TOKEN" | grep -qE '^[A-Za-z_]+=' 2>/dev/null; do
    SLB_SUB=$(printf '%s' "$SLB_SUB" | sed 's/^[A-Za-z_]*=[^ ]* *//')
    SLB_TOKEN=$(printf '%s' "$SLB_SUB" | awk '{print $1}')
    SLB_TOKEN="${SLB_TOKEN#\(}"
    [ -z "$SLB_TOKEN" ] && break
  done
  [ -z "$SLB_TOKEN" ] && continue
  # Check token against exclusion list
  SLB_TOKEN_EXCLUDED=false
  for EXCL in $SLB_EXCLUDED_TOKENS; do
    if [ "$SLB_TOKEN" = "$EXCL" ]; then
      SLB_TOKEN_EXCLUDED=true
      break
    fi
  done
  if [ "$SLB_TOKEN_EXCLUDED" = false ]; then
    SLB_ALL_EXCLUDED=false
    break
  fi
done < "$SLB_SPLIT_FILE"
rm -f "$SLB_SPLIT_FILE" 2>/dev/null

if [ "$SLB_ALL_EXCLUDED" = false ]; then
  # --- Extract exit code (reuse existing patterns) ---
  SLB_EXIT="unknown"
  if printf '%s' "$TOOL_OUTPUT" | grep -qoE '[Ee]xit code: [0-9]+' 2>/dev/null; then
    SLB_EXIT=$(printf '%s' "$TOOL_OUTPUT" | grep -oE '[Ee]xit code: [0-9]+' | tail -1 | grep -oE '[0-9]+$')
  fi

  if [ "$SLB_EXIT" != "unknown" ]; then
    SLB_TS=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')

    if [ "$SLB_EXIT" = "0" ]; then
      # Success — log minimal marker
      append_jsonl "{\"ts\":\"${SLB_TS}\",\"success\":true}" "$SLB_FAILURE_LOG"
    else
      # Failure — compute output fingerprint
      # Last nonempty line, strip ANSI escapes + digits, collapse whitespace
      SLB_FP_FILE=$(mktemp 2>/dev/null || echo "/tmp/slb_fp_$$")
      printf '%s' "$TOOL_OUTPUT" > "$SLB_FP_FILE"
      SLB_LAST_LINE=$(sed 's/\x1b\[[0-9;]*m//g' "$SLB_FP_FILE" | grep -v '^[[:space:]]*$' | tail -1)
      rm -f "$SLB_FP_FILE" 2>/dev/null
      SLB_FINGERPRINT=$(printf '%s' "$SLB_LAST_LINE" | sed 's/[0-9]//g' | tr -s ' ' | head -c 200)

      # Command fingerprint: first 80 chars, escaped for JSON
      SLB_CMD_FP=$(printf '%s' "$COMMAND" | head -c 80 | sed 's/\\/\\\\/g; s/"/\\"/g')

      # Files edited since last failure entry
      SLB_FILES_JSON="[]"
      SLB_LAST_FAIL_TS=""
      if [ -f "$SLB_FAILURE_LOG" ]; then
        SLB_LAST_FAIL_TS=$(tac "$SLB_FAILURE_LOG" 2>/dev/null | grep -v '"success"' | head -1 | jq -r '.ts // empty' 2>/dev/null | tr -d '\r')
      fi
      UNVERIFIED="${STATE_DIR}/unverified-writes.jsonl"
      if [ -f "$UNVERIFIED" ] && [ -n "$SLB_LAST_FAIL_TS" ]; then
        SLB_FILES_JSON=$(jq -rs --arg since "$SLB_LAST_FAIL_TS" \
          '[.[] | select(.ts > $since) | .file] | unique' \
          "$UNVERIFIED" 2>/dev/null || echo "[]")
      fi
      # Ensure valid JSON array
      if ! printf '%s' "$SLB_FILES_JSON" | jq '.' >/dev/null 2>&1; then
        SLB_FILES_JSON="[]"
      fi

      # Escape fingerprint for JSON
      SLB_FP_SAFE=$(printf '%s' "$SLB_FINGERPRINT" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r')

      append_jsonl "{\"ts\":\"${SLB_TS}\",\"cmd_fingerprint\":\"${SLB_CMD_FP}\",\"exit_code\":${SLB_EXIT},\"output_fingerprint\":\"${SLB_FP_SAFE}\",\"files_edited_since_last\":${SLB_FILES_JSON}}" "$SLB_FAILURE_LOG"
    fi

    # Trim log to 50 entries
    trim_jsonl "$SLB_FAILURE_LOG" 50
  fi
fi
# ============================================================
# END STRATEGY LOOP BREAKER
# ============================================================

# --- Early exit: only active during BUILD phase ---
if [ -f "$PHASE_FILE" ]; then
  CURRENT_PHASE=$(jq -r '.phase // empty' "$PHASE_FILE" 2>/dev/null || true)
else
  CURRENT_PHASE=""
fi

if [ "$CURRENT_PHASE" != "BUILD" ]; then
  # Not in BUILD phase — no TDD evidence collection needed
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}' \
    "$(printf '%s' "$CONTEXT_MSG" | sed 's|\\|\\\\|g; s|"|\\"|g')"
  exit 0
fi

# --- Early exit: TDD not required ---
if [ ! -f "$TDD_CONFIG" ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}' \
    "$(printf '%s' "$CONTEXT_MSG" | sed 's|\\|\\\\|g; s|"|\\"|g')"
  exit 0
fi

TDD_REQUIRED=$(jq -r '.tdd_required // false' "$TDD_CONFIG" 2>/dev/null || echo "false")
if [ "$TDD_REQUIRED" != "true" ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}' \
    "$(printf '%s' "$CONTEXT_MSG" | sed 's|\\|\\\\|g; s|"|\\"|g')"
  exit 0
fi

# --- Signal 2: Test Runner Invocation Detection ---
# Pattern matches common test runner commands
TEST_PATTERN='(pytest|py\.test|npm test|npx jest|npx vitest|npx mocha|cargo test|go test|python -m (unittest|pytest)|python3 -m (unittest|pytest)|dotnet test|ruby -Itest|rspec|bundle exec rspec|mocha|yarn test|rake test|npx ava|npx tap)'

if echo "$COMMAND" | grep -qiE "$TEST_PATTERN"; then
  echo "TDD evidence: test runner command detected: $COMMAND" >&2

  mkdir -p "$TDD_DIR" 2>/dev/null

  TS=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')

  # Extract exit code from tool output
  # Claude Code reports exit codes in output; try multiple patterns
  EXIT_CODE="unknown"
  if echo "$TOOL_OUTPUT" | grep -qoP 'exit code: \K\d+' 2>/dev/null; then
    EXIT_CODE=$(echo "$TOOL_OUTPUT" | grep -oP 'exit code: \K\d+' | tail -1)
  elif echo "$TOOL_OUTPUT" | grep -qoP 'Exit code: \K\d+' 2>/dev/null; then
    EXIT_CODE=$(echo "$TOOL_OUTPUT" | grep -oP 'Exit code: \K\d+' | tail -1)
  elif echo "$TOOL_OUTPUT" | grep -qE '(PASSED|passed|OK)' 2>/dev/null; then
    # Heuristic: if output contains pass markers and no failure markers
    if ! echo "$TOOL_OUTPUT" | grep -qiE '(FAILED|FAIL|ERROR|failures)' 2>/dev/null; then
      EXIT_CODE="0"
    fi
  fi

  # --- Signal 3: Genuine Framework Output Verification ---
  GENUINE=false
  FRAMEWORK_DETECTED=""

  # pytest: "= FAILURES =" or "= ERRORS =" or "X passed"
  if echo "$TOOL_OUTPUT" | grep -qE '={3,} (FAILURES|ERRORS|short test summary|([0-9]+ passed))'; then
    GENUINE=true
    FRAMEWORK_DETECTED="pytest"
  fi

  # Jest/Vitest: "Tests:  N passed" or "Tests:  N failed"
  if echo "$TOOL_OUTPUT" | grep -qE 'Tests?:[[:space:]]+[0-9]+ (passed|failed)'; then
    GENUINE=true
    FRAMEWORK_DETECTED="${FRAMEWORK_DETECTED:+$FRAMEWORK_DETECTED,}jest-or-vitest"
  fi

  # Go: "ok  package  0.123s" or "FAIL  package  0.123s"
  if echo "$TOOL_OUTPUT" | grep -qE '^(ok|FAIL)[[:space:]]+[^[:space:]]+[[:space:]]+[0-9.]+s'; then
    GENUINE=true
    FRAMEWORK_DETECTED="${FRAMEWORK_DETECTED:+$FRAMEWORK_DETECTED,}go"
  fi

  # Cargo/Rust: "test result: ok. N passed" or "test result: FAILED. N passed"
  if echo "$TOOL_OUTPUT" | grep -qE 'test result: (ok|FAILED)\. [0-9]+ passed'; then
    GENUINE=true
    FRAMEWORK_DETECTED="${FRAMEWORK_DETECTED:+$FRAMEWORK_DETECTED,}cargo"
  fi

  # Python unittest: "Ran N tests" or "Ran N test"
  if echo "$TOOL_OUTPUT" | grep -qE 'Ran [0-9]+ tests?'; then
    GENUINE=true
    FRAMEWORK_DETECTED="${FRAMEWORK_DETECTED:+$FRAMEWORK_DETECTED,}unittest"
  fi

  # Python unittest summary: "OK (skipped=N)" or "FAILED (failures=N)"
  if echo "$TOOL_OUTPUT" | grep -qE '^(OK|FAILED) \(.*\)$'; then
    GENUINE=true
    FRAMEWORK_DETECTED="${FRAMEWORK_DETECTED:+$FRAMEWORK_DETECTED,}unittest-summary"
  fi

  # .NET: "Passed!  - Failed:" or "Total tests: N"
  if echo "$TOOL_OUTPUT" | grep -qE '(Passed!|Failed!|Total tests: [0-9]+)'; then
    GENUINE=true
    FRAMEWORK_DETECTED="${FRAMEWORK_DETECTED:+$FRAMEWORK_DETECTED,}dotnet"
  fi

  # RSpec: "N examples, N failures"
  if echo "$TOOL_OUTPUT" | grep -qE '[0-9]+ examples?, [0-9]+ failures?'; then
    GENUINE=true
    FRAMEWORK_DETECTED="${FRAMEWORK_DETECTED:+$FRAMEWORK_DETECTED,}rspec"
  fi

  # Mocha: "N passing" or "N failing"
  if echo "$TOOL_OUTPUT" | grep -qE '[0-9]+ passing'; then
    GENUINE=true
    FRAMEWORK_DETECTED="${FRAMEWORK_DETECTED:+$FRAMEWORK_DETECTED,}mocha"
  fi

  # --- Build event JSON ---
  # Sanitize command for JSON embedding (escape backslashes first, then quotes)
  SAFE_CMD=$(printf '%s' "$COMMAND" | sed 's|\\|\\\\|g; s|"|\\"|g' | head -c 200)

  # Format exit_code as number if numeric, quoted string otherwise
  if echo "$EXIT_CODE" | grep -qE '^[0-9]+$'; then
    EXIT_CODE_JSON="$EXIT_CODE"
  else
    EXIT_CODE_JSON="\"$EXIT_CODE\""
  fi

  if [ "$GENUINE" = true ]; then
    EVENT_JSON=$(printf '{"ts":"%s","event":"TEST_RUN","cmd":"%s","exit_code":%s,"genuine":true,"framework":"%s"}' \
      "$TS" "$SAFE_CMD" "$EXIT_CODE_JSON" "$FRAMEWORK_DETECTED")
    CONTEXT_MSG="TDD: test run recorded (genuine $FRAMEWORK_DETECTED output, exit=$EXIT_CODE)"
    echo "TDD evidence: genuine framework output detected ($FRAMEWORK_DETECTED)" >&2
  else
    EVENT_JSON=$(printf '{"ts":"%s","event":"SUSPICIOUS_TEST_RUN","cmd":"%s","exit_code":%s,"genuine":false,"reason":"no recognized framework output"}' \
      "$TS" "$SAFE_CMD" "$EXIT_CODE_JSON")
    CONTEXT_MSG="TDD WARNING: test command detected but no genuine framework output markers found"
    echo "TDD evidence: SUSPICIOUS — no recognized framework output markers" >&2
  fi

  append_jsonl "$EVENT_JSON" "$EVENTS_FILE"

  # Trim events file to prevent unbounded growth (keep last 200 entries)
  trim_jsonl "$EVENTS_FILE" 200
else
  # Not a test command — no evidence to collect
  CONTEXT_MSG=""
fi

# --- Output hook response ---
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}' \
  "$(printf '%s' "$CONTEXT_MSG" | sed 's|\\|\\\\|g; s|"|\\"|g')"
