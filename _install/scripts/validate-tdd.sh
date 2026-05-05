#!/bin/bash
# validate-tdd.sh — Layer 2: BUILD→EVALUATE gate for TDD evidence
# Called by evaluate-protocol-compliance.sh at phase transition.
# Checks tdd-events.jsonl for red→green temporal ordering (Signal 4),
# test file writes (Signal 1), and suspicious test runs (Signal 3).
#
# Binary pass/fail. If fail: sprint stays in BUILD.
#
# Usage: bash validate-tdd.sh [project-root]
# Exit: 0 = TDD evidence sufficient, 1 = TDD evidence insufficient

set -euo pipefail

source "$HOME/.claude/scripts/lib-helpers.sh" 2>/dev/null || true

PROJECT_ROOT="${1:-.}"
STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
TDD_DIR="${STATE_DIR}/tdd"
TDD_CONFIG="${TDD_DIR}/tdd-config.json"
EVENTS_FILE="${TDD_DIR}/tdd-events.jsonl"
REPORT_FILE="${TDD_DIR}/tdd-validation-report.md"

cd "$PROJECT_ROOT" 2>/dev/null || { echo "ERROR: Cannot cd to $PROJECT_ROOT" >&2; exit 1; }

# --- Early exit: TDD not configured ---
if [ ! -f "$TDD_CONFIG" ]; then
  echo "validate-tdd: No tdd-config.json — TDD enforcement not active, skipping." >&2
  exit 0
fi

TDD_REQUIRED=$(jq -r '.tdd_required // false' "$TDD_CONFIG" 2>/dev/null || echo "false")
if [ "$TDD_REQUIRED" != "true" ]; then
  echo "validate-tdd: tdd_required=false — skipping TDD validation." >&2
  exit 0
fi

FRAMEWORK=$(jq -r '.framework // "unknown"' "$TDD_CONFIG" 2>/dev/null || echo "unknown")
PASS=true
REPORT="# TDD Validation Report\n\n"
REPORT+="**Framework:** $FRAMEWORK\n"
REPORT+="**Timestamp:** $(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')\n\n"

# --- Check 1: Events file exists and has entries ---
if [ ! -f "$EVENTS_FILE" ]; then
  echo "validate-tdd: FAIL — No tdd-events.jsonl found. No test activity recorded." >&2
  REPORT+="## Check 1: Events File\n**FAIL** — No tdd-events.jsonl found.\n\n"
  PASS=false
else
  EVENT_COUNT=$(wc -l < "$EVENTS_FILE")
  REPORT+="## Check 1: Events File\n**PASS** — $EVENT_COUNT events recorded.\n\n"
  echo "validate-tdd: Events file found with $EVENT_COUNT entries." >&2
fi

# --- Check 2: Test files were written (Signal 1 evidence) ---
if [ -f "$EVENTS_FILE" ]; then
  TEST_FILE_COUNT=$(grep -c '"event":"TEST_FILE_WRITTEN"' "$EVENTS_FILE" 2>/dev/null || echo "0")
else
  TEST_FILE_COUNT=0
fi

if [ "$TEST_FILE_COUNT" -eq 0 ]; then
  echo "validate-tdd: WARNING — No TEST_FILE_WRITTEN events found." >&2
  REPORT+="## Check 2: Test Files Written\n**WARNING** — No test file write events recorded. Tests may have been pre-existing.\n\n"
  # Warning only, not a hard fail — tests may already exist in the project
else
  REPORT+="## Check 2: Test Files Written\n**PASS** — $TEST_FILE_COUNT test file(s) written.\n\n"
  echo "validate-tdd: $TEST_FILE_COUNT test file write(s) recorded." >&2
fi

# --- Check 3: Test runner was actually invoked (Signal 2 evidence) ---
if [ -f "$EVENTS_FILE" ]; then
  TEST_RUN_COUNT=$(grep -c '"event":"TEST_RUN"' "$EVENTS_FILE" 2>/dev/null || echo "0")
else
  TEST_RUN_COUNT=0
fi

if [ "$TEST_RUN_COUNT" -eq 0 ]; then
  echo "validate-tdd: FAIL — No TEST_RUN events. Agent never ran the test suite." >&2
  REPORT+="## Check 3: Test Runner Invoked\n**FAIL** — No genuine test runs recorded. Agent never executed the test suite.\n\n"
  PASS=false
else
  REPORT+="## Check 3: Test Runner Invoked\n**PASS** — $TEST_RUN_COUNT genuine test run(s) recorded.\n\n"
  echo "validate-tdd: $TEST_RUN_COUNT genuine test run(s) recorded." >&2
fi

# --- Check 4: Suspicious test runs flagged (Signal 3 evidence) ---
if [ -f "$EVENTS_FILE" ]; then
  SUSPICIOUS_COUNT=$(grep -c '"event":"SUSPICIOUS_TEST_RUN"' "$EVENTS_FILE" 2>/dev/null || echo "0")
else
  SUSPICIOUS_COUNT=0
fi

if [ "$SUSPICIOUS_COUNT" -gt 0 ]; then
  echo "validate-tdd: WARNING — $SUSPICIOUS_COUNT suspicious test run(s) with no framework output markers." >&2
  REPORT+="## Check 4: Suspicious Runs\n**WARNING** — $SUSPICIOUS_COUNT test command(s) produced no recognized framework output.\n\n"
  # If ALL runs are suspicious and NONE are genuine, that's a fail
  if [ "$TEST_RUN_COUNT" -eq 0 ]; then
    REPORT+="**FAIL** — Only suspicious runs found, no genuine framework output detected.\n\n"
    PASS=false
  fi
else
  REPORT+="## Check 4: Suspicious Runs\n**PASS** — No suspicious test runs.\n\n"
fi

# --- Check 5: Red→Green temporal ordering (Signal 4 — core TDD check) ---
if [ -f "$EVENTS_FILE" ] && [ "$TEST_RUN_COUNT" -gt 0 ]; then
  # Find first failing test run (any non-zero exit code)
  FIRST_FAIL_TS=$(grep '"event":"TEST_RUN"' "$EVENTS_FILE" | grep -v '"exit_code":0' | grep -v '"exit_code":"unknown"' | head -1 | jq -r '.ts // empty' 2>/dev/null || true)

  # Find last passing test run (exit code 0)
  LAST_PASS_TS=$(grep '"event":"TEST_RUN"' "$EVENTS_FILE" | grep '"exit_code":0' | tail -1 | jq -r '.ts // empty' 2>/dev/null || true)

  # Also check for exit_code as number 0 vs string "0"
  if [ -z "$LAST_PASS_TS" ]; then
    LAST_PASS_TS=$(grep '"event":"TEST_RUN"' "$EVENTS_FILE" | grep '"exit_code":"0"' | tail -1 | jq -r '.ts // empty' 2>/dev/null || true)
  fi

  if [ -z "$FIRST_FAIL_TS" ]; then
    echo "validate-tdd: FAIL — No RED phase. No failing test runs recorded." >&2
    REPORT+="## Check 5: Red-Green Ordering\n**FAIL** — No RED phase detected. TDD requires tests to fail before passing.\n\n"
    PASS=false
  elif [ -z "$LAST_PASS_TS" ]; then
    echo "validate-tdd: FAIL — No GREEN phase. No passing test runs recorded." >&2
    REPORT+="## Check 5: Red-Green Ordering\n**FAIL** — No GREEN phase detected. Tests never passed.\n\n"
    PASS=false
  elif [[ "$FIRST_FAIL_TS" > "$LAST_PASS_TS" ]]; then
    echo "validate-tdd: FAIL — Last test run is still failing (red after green)." >&2
    REPORT+="## Check 5: Red-Green Ordering\n**FAIL** — Last test run still failing. Red=$FIRST_FAIL_TS, Green=$LAST_PASS_TS\n\n"
    PASS=false
  else
    echo "validate-tdd: PASS — Red→Green ordering confirmed. Red=$FIRST_FAIL_TS, Green=$LAST_PASS_TS" >&2
    REPORT+="## Check 5: Red-Green Ordering\n**PASS** — Red→Green confirmed.\n- First failure: $FIRST_FAIL_TS\n- Last pass: $LAST_PASS_TS\n\n"
  fi
else
  if [ "$TEST_RUN_COUNT" -eq 0 ]; then
    REPORT+="## Check 5: Red-Green Ordering\n**SKIP** — No test runs to analyze.\n\n"
  fi
fi

# --- Summary ---
if [ "$PASS" = true ]; then
  REPORT+="## Result\n**PASS** — TDD evidence is sufficient.\n"
  echo "validate-tdd: PASS — All TDD evidence checks passed." >&2
else
  REPORT+="## Result\n**FAIL** — TDD evidence is insufficient. Sprint must return to BUILD.\n"
  echo "validate-tdd: FAIL — TDD evidence insufficient." >&2
fi

# Write report
mkdir -p "$TDD_DIR" 2>/dev/null
printf "%b" "$REPORT" > "$REPORT_FILE"

if [ "$PASS" = true ]; then
  exit 0
else
  exit 1
fi
