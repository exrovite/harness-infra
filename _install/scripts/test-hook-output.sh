#!/bin/bash
# test-hook-output.sh — TDD test for PostToolUse hook JSON output
# Tests that post-write-check.sh outputs valid JSON with hookSpecificOutput.additionalContext
# This test should FAIL before the fix and PASS after.

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HOME/.claude/hooks/post-write-check.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

assert_pass() {
  PASS=$((PASS + 1))
  printf "${GREEN}  PASS${NC}: %s\n" "$1"
}

assert_fail() {
  FAIL=$((FAIL + 1))
  printf "${RED}  FAIL${NC}: %s\n" "$1"
}

printf "\n${YELLOW}=== PostToolUse Hook Output Tests ===${NC}\n\n"

# --- Test 1: Hook script exists ---
printf "Test 1: Hook script exists\n"
if [ -f "$HOOK" ]; then
  assert_pass "post-write-check.sh exists"
else
  assert_fail "post-write-check.sh not found at $HOOK"
fi

# --- Test 2: Hook produces stdout ---
printf "Test 2: Hook produces stdout output\n"
# Run from a project directory that has .claude/state (harness infra)
STDOUT=$(cd "G:/harness infra" && bash "$HOOK" 2>/dev/null)
if [ -n "$STDOUT" ]; then
  assert_pass "Hook produces stdout (length: ${#STDOUT} chars)"
else
  assert_fail "Hook produces NO stdout — Claude will never see this hook fired"
fi

# --- Test 3: Stdout is valid JSON ---
printf "Test 3: Stdout is valid JSON\n"
if [ -n "$STDOUT" ]; then
  if printf '%s' "$STDOUT" | jq . >/dev/null 2>&1; then
    assert_pass "Stdout is valid JSON"
  else
    assert_fail "Stdout is NOT valid JSON: $(printf '%s' "$STDOUT" | head -c 200)"
  fi
else
  assert_fail "No stdout to validate as JSON (prerequisite failed)"
fi

# --- Test 4: JSON has hookSpecificOutput key ---
printf "Test 4: JSON contains hookSpecificOutput\n"
if [ -n "$STDOUT" ]; then
  HAS_KEY=$(printf '%s' "$STDOUT" | jq 'has("hookSpecificOutput")' 2>/dev/null)
  if [ "$HAS_KEY" = "true" ]; then
    assert_pass "hookSpecificOutput key present"
  else
    assert_fail "hookSpecificOutput key MISSING from JSON output"
  fi
else
  assert_fail "No stdout to check for hookSpecificOutput (prerequisite failed)"
fi

# --- Test 5: JSON has hookSpecificOutput.additionalContext ---
printf "Test 5: JSON contains hookSpecificOutput.additionalContext\n"
if [ -n "$STDOUT" ]; then
  CONTEXT=$(printf '%s' "$STDOUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
  if [ -n "$CONTEXT" ]; then
    assert_pass "additionalContext present: $(printf '%s' "$CONTEXT" | head -c 120)"
  else
    assert_fail "additionalContext is MISSING or empty"
  fi
else
  assert_fail "No stdout to check for additionalContext (prerequisite failed)"
fi

# --- Test 6: additionalContext contains phase info ---
printf "Test 6: additionalContext contains phase information\n"
if [ -n "$CONTEXT" ]; then
  if printf '%s' "$CONTEXT" | grep -qi "phase"; then
    assert_pass "Phase info found in additionalContext"
  else
    assert_fail "No phase info in additionalContext"
  fi
else
  assert_fail "No additionalContext to check (prerequisite failed)"
fi

# --- Test 7: additionalContext contains write count ---
printf "Test 7: additionalContext contains write count\n"
if [ -n "$CONTEXT" ]; then
  if printf '%s' "$CONTEXT" | grep -qi "write"; then
    assert_pass "Write count info found in additionalContext"
  else
    assert_fail "No write count in additionalContext"
  fi
else
  assert_fail "No additionalContext to check (prerequisite failed)"
fi

# --- Test 8: hookEventName is PostToolUse ---
printf "Test 8: hookEventName is PostToolUse\n"
if [ -n "$STDOUT" ]; then
  EVENT_NAME=$(printf '%s' "$STDOUT" | jq -r '.hookSpecificOutput.hookEventName // empty' 2>/dev/null)
  if [ "$EVENT_NAME" = "PostToolUse" ]; then
    assert_pass "hookEventName is PostToolUse"
  else
    assert_fail "hookEventName is '${EVENT_NAME}' (expected 'PostToolUse')"
  fi
else
  assert_fail "No stdout to check hookEventName (prerequisite failed)"
fi

# --- Test 9: No non-JSON text on stdout ---
printf "Test 9: No non-JSON text leaked to stdout\n"
if [ -n "$STDOUT" ]; then
  # Count the number of JSON objects — should be exactly 1
  JSON_COUNT=$(printf '%s' "$STDOUT" | jq -s 'length' 2>/dev/null)
  if [ "$JSON_COUNT" = "1" ]; then
    assert_pass "Exactly one JSON object on stdout (clean output)"
  else
    assert_fail "Multiple items or non-JSON text on stdout (count: ${JSON_COUNT})"
  fi
else
  assert_fail "No stdout to validate (prerequisite failed)"
fi

# --- Summary ---
printf "\n${YELLOW}=== Results ===${NC}\n"
printf "  Passed: ${GREEN}%d${NC}\n" "$PASS"
printf "  Failed: ${RED}%d${NC}\n" "$FAIL"
printf "  Total:  %d\n\n" "$((PASS + FAIL))"

if [ "$FAIL" -gt 0 ]; then
  printf "${RED}TESTS FAILED${NC} — Hook output is broken, Claude cannot see hook results.\n\n"
  exit 1
else
  printf "${GREEN}ALL TESTS PASSED${NC} — Hook output is correctly formatted for Claude visibility.\n\n"
  exit 0
fi
