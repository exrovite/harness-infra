#!/bin/bash
# on-test-failure.sh — Harness-internal script (NOT a Claude Code hook)
# Called by run-harness.sh when validate-phase.sh or test suite returns non-zero.
# SEARCH ALGORITHM: reads known-fixes.md line by line, extracts Symptom fields,
# greps failure output for each symptom (case-insensitive).
# If match: writes fix to next-fix.md. If no match: agent proceeds with own approach.
#
# Usage: bash on-test-failure.sh <failure_output_file>

FAILURE_FILE="$1"
STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
# resolve STATE_DIR to the PROJECT ROOT (avoid creating a nested .claude in a subdir cwd)
if [ -z "${HARNESS_STATE_DIR:-}" ]; then . "$HOME/.claude/scripts/lib-helpers.sh" 2>/dev/null; type find_project_state_dir >/dev/null 2>&1 && { _r="$(find_project_state_dir "$(pwd -W 2>/dev/null || pwd)" 2>/dev/null)"; if [ -n "$_r" ]; then STATE_DIR="$_r"; else exit 0; fi; }; fi
KNOWN_FIXES=".claude/protocols/known-fixes.md"

# If no failure file provided, try reading from state
if [ -z "$FAILURE_FILE" ] || [ ! -f "$FAILURE_FILE" ]; then
  FAILURE_FILE="${STATE_DIR}/test-output.txt"
fi

if [ ! -f "$FAILURE_FILE" ]; then
  printf "on-test-failure: No failure output to analyze.\n" >&2
  exit 0
fi

if [ ! -f "$KNOWN_FIXES" ]; then
  printf "on-test-failure: No known-fixes.md found. Agent proceeds with own approach.\n" >&2
  exit 0
fi

FAILURE_OUTPUT=$(cat "$FAILURE_FILE" 2>/dev/null)

# Search known-fixes.md for matching symptoms
while IFS= read -r line; do
  # Look for Symptom fields
  if printf "%s" "$line" | grep -q '^\- \*\*Symptom\*\*:' 2>/dev/null; then
    SYMPTOM=$(printf "%s" "$line" | sed 's/.*\*\*Symptom\*\*: *//')

    # Check if failure output contains this symptom (case-insensitive)
    if printf "%s" "$FAILURE_OUTPUT" | grep -qi "$SYMPTOM" 2>/dev/null; then
      # Read the fix block (next ~10 lines until next ## or empty line)
      FIX_BLOCK=$(grep -A10 "$SYMPTOM" "$KNOWN_FIXES" 2>/dev/null | head -12)

      # Write fix directly into agent's instruction file
      mkdir -p "$STATE_DIR" 2>/dev/null
      {
        printf "%s\n\n" "# KNOWN FIX FOUND — APPLY EXACTLY"
        printf "Matched symptom: %s\n\n" "$SYMPTOM"
        printf "%s\n\n" "$FIX_BLOCK"
        printf "%s\n" "After applying, run tests again. Do not modify the fix."
      } > "${STATE_DIR}/next-fix.md"

      bash "$HOME/.claude/scripts/notify.sh" "Known fix matched for: $SYMPTOM" 2>/dev/null
      printf "on-test-failure: Known fix matched and injected for symptom: %s\n" "$SYMPTOM" >&2
      exit 0
    fi
  fi
done < "$KNOWN_FIXES"

printf "on-test-failure: No known fix matched. Agent proceeds with own approach.\n" >&2
exit 0
