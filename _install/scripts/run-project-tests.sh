#!/bin/bash
# run-project-tests.sh — Layer 1: Independent harness test execution (Signal 5 nuclear backstop)
# Called by harness at BUILD→EVALUATE gate, AFTER validate-tdd.sh passes.
# The harness runs the actual test suite — agent does NOT self-report results.
#
# This is the final authority: if the harness can't run tests and get exit 0, the sprint fails.
#
# Usage: bash run-project-tests.sh [project-root]
# Exit: 0 = tests pass, 1 = tests fail or cannot run

set -euo pipefail

source "$HOME/.claude/scripts/lib-helpers.sh" 2>/dev/null || { echo "WARNING: lib-helpers.sh not found, event logging disabled" >&2; }

PROJECT_ROOT="${1:-.}"
STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
TDD_DIR="${STATE_DIR}/tdd"
TDD_CONFIG="${TDD_DIR}/tdd-config.json"
LOG_FILE="${TDD_DIR}/harness-test-run.log"
FEEDBACK_FILE="${STATE_DIR}/phase-feedback.md"

cd "$PROJECT_ROOT" 2>/dev/null || { echo "ERROR: Cannot cd to $PROJECT_ROOT" >&2; exit 1; }

# --- Early exit: no TDD config means no test command known ---
if [ ! -f "$TDD_CONFIG" ]; then
  echo "run-project-tests: No tdd-config.json found — cannot determine test command." >&2
  echo "run-project-tests: Falling back to legacy test detection..." >&2

  # Fallback: try common patterns (matches evaluate-protocol-compliance.sh check #4)
  if [ -f "package.json" ] && grep -q '"test"' "package.json" 2>/dev/null; then
    TEST_CMD="npm test"
  elif command -v pytest >/dev/null 2>&1 && { [ -f "pytest.ini" ] || [ -f "pyproject.toml" ] || [ -f "setup.cfg" ]; }; then
    TEST_CMD="python -m pytest"
  elif [ -f "Cargo.toml" ]; then
    TEST_CMD="cargo test"
  elif [ -f "go.mod" ]; then
    TEST_CMD="go test ./..."
  else
    echo "run-project-tests: No test framework detected and no tdd-config.json. Skipping." >&2
    exit 0
  fi
else
  TEST_CMD=$(jq -r '.test_cmd // empty' "$TDD_CONFIG" 2>/dev/null)
  if [ -z "$TEST_CMD" ]; then
    echo "run-project-tests: tdd-config.json exists but test_cmd is empty." >&2
    exit 1
  fi
fi

echo "run-project-tests: Running test command: $TEST_CMD" >&2

mkdir -p "$TDD_DIR" 2>/dev/null

# --- Execute tests independently ---
# Use eval to handle commands with arguments (e.g., "go test ./...")
# TEST_CMD comes from tdd-config.json which is written by detect-test-runner.sh (trusted Layer 2 script)
set +e
eval "$TEST_CMD" > "$LOG_FILE" 2>&1
HARNESS_EXIT=$?
set -e

echo "run-project-tests: Test command exited with code $HARNESS_EXIT" >&2

if [ $HARNESS_EXIT -ne 0 ]; then
  echo "run-project-tests: FAIL — Tests do not pass (exit code $HARNESS_EXIT)." >&2

  # Write last 30 lines of test output as phase feedback for the agent
  {
    echo "# Test Failure — Harness Independent Run"
    echo ""
    echo "**Test command:** \`$TEST_CMD\`"
    echo "**Exit code:** $HARNESS_EXIT"
    echo ""
    echo "## Last 30 lines of output"
    echo '```'
    tail -30 "$LOG_FILE"
    echo '```'
    echo ""
    echo "Fix these failures and re-run tests before marking BUILD as complete."
  } > "$FEEDBACK_FILE"

  exit 1
fi

echo "run-project-tests: PASS — All tests pass." >&2

# Log the harness-executed test run as evidence
TS=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
EVENTS_FILE="${TDD_DIR}/tdd-events.jsonl"
SAFE_CMD=$(printf '%s' "$TEST_CMD" | sed 's|\\|\\\\|g; s|"|\\"|g')
EVENT_JSON=$(printf '{"ts":"%s","event":"HARNESS_TEST_RUN","cmd":"%s","exit_code":0,"source":"harness"}' \
  "$TS" "$SAFE_CMD")
if type append_jsonl >/dev/null 2>&1; then
  append_jsonl "$EVENT_JSON" "$EVENTS_FILE"
fi

exit 0
