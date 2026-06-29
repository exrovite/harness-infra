#!/bin/bash
# detect-loop.sh — Negative loop detector (Layer 2)
# Checks git log for same files modified 4+ times in 10 commits.
# Checks test results for repeating failures.
# DUAL-PATH: known fix → inject to next-fix.md, no known fix → block agent.
# BLOCKS execution, does not advise.
#
# Usage: bash detect-loop.sh
# Exit: 0 = no loop, 1 = loop detected (fix injected or agent blocked)

REPEAT_THRESHOLD=8
STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
# resolve STATE_DIR to the PROJECT ROOT (avoid creating a nested .claude in a subdir cwd)
if [ -z "${HARNESS_STATE_DIR:-}" ]; then . "$HOME/.claude/scripts/lib-helpers.sh" 2>/dev/null; type find_project_state_dir >/dev/null 2>&1 && { _r="$(find_project_state_dir "$(pwd -W 2>/dev/null || pwd)" 2>/dev/null)"; [ -n "$_r" ] && STATE_DIR="$_r"; }; fi
KNOWN_FIXES="${STATE_DIR}/../protocols/known-fixes.md"

# Only run if we're in a git repo
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  exit 0
fi

# Check git for repeated modifications to same files
MOST_MODIFIED=$(git log --name-only --pretty=format: -10 2>/dev/null | grep -v '^$' | sort | uniq -c | sort -rn | head -1)
REPEAT_COUNT=$(printf "%s" "$MOST_MODIFIED" | awk '{print $1}')
REPEAT_FILE=$(printf "%s" "$MOST_MODIFIED" | awk '{print $2}')

if [ -n "$REPEAT_COUNT" ] && [ "$REPEAT_COUNT" -ge "$REPEAT_THRESHOLD" ] 2>/dev/null; then
  printf "detect-loop: LOOP DETECTED — %s modified %s times in last 10 commits\n" "$REPEAT_FILE" "$REPEAT_COUNT" >&2

  # PATH 1: Search known-fixes.md for matching symptom
  KNOWN_FIX=""
  if [ -f "$KNOWN_FIXES" ]; then
    # Extract symptom fields and check if repeat file matches any
    KNOWN_FIX=$(grep -B1 -A10 "$REPEAT_FILE" "$KNOWN_FIXES" 2>/dev/null | head -15)
  fi

  if [ -n "$KNOWN_FIX" ]; then
    # Known fix exists — inject directly into next-fix.md
    mkdir -p "$STATE_DIR" 2>/dev/null
    {
      printf "%s\n\n" "# MANDATORY FIX — DO NOT IMPROVISE"
      printf "A negative loop was detected on file: %s\n" "$REPEAT_FILE"
      printf "Modified %s times in last 10 commits.\n" "$REPEAT_COUNT"
      printf "%s\n\n" "This has a KNOWN FIX. Apply it exactly:"
      printf "%s\n" "$KNOWN_FIX"
    } > "${STATE_DIR}/next-fix.md"

    bash "$HOME/.claude/scripts/notify.sh" "Loop detected on $REPEAT_FILE. Known fix injected into next-fix.md." 2>/dev/null
    printf "detect-loop: Known fix injected to next-fix.md\n" >&2
  else
    # PATH 2: No known fix — BLOCK agent and wait for human
    mkdir -p "$STATE_DIR" 2>/dev/null
    {
      printf "BLOCKED\n"
      printf "Negative loop on %s (modified %s times in 10 commits).\n" "$REPEAT_FILE" "$REPEAT_COUNT"
      printf "No known fix found.\n"
      printf "Awaiting human instruction.\n"
    } > "${STATE_DIR}/agent-blocked.md"

    bash "$HOME/.claude/scripts/notify.sh" "Loop detected on $REPEAT_FILE. No known fix. Agent PAUSED." 2>/dev/null
    printf "detect-loop: No known fix. Agent BLOCKED.\n" >&2
  fi

  exit 1
fi

# Check test results for repeating failures (if test result files exist)
LAST_FAILURES=$(find "$STATE_DIR" -name "test-results-*.md" -newer "$STATE_DIR/current-phase.json" 2>/dev/null | xargs grep "FAIL" 2>/dev/null | tail -9)
UNIQUE_FAILURES=$(printf "%s" "$LAST_FAILURES" | sort -u | wc -l)
TOTAL_FAILURES=$(printf "%s" "$LAST_FAILURES" | wc -l)

if [ "$TOTAL_FAILURES" -gt 6 ] && [ "$UNIQUE_FAILURES" -lt 3 ] 2>/dev/null; then
  printf "detect-loop: REPEATING TEST FAILURES — %s total, only %s unique\n" "$TOTAL_FAILURES" "$UNIQUE_FAILURES" >&2
  mkdir -p "$STATE_DIR" 2>/dev/null
  {
    printf "BLOCKED\n"
    printf "Same test failures repeating across runs.\n"
    printf "Total failures: %s, Unique: %s\n" "$TOTAL_FAILURES" "$UNIQUE_FAILURES"
    printf "STOP. You are not making progress.\n"
  } > "${STATE_DIR}/agent-blocked.md"

  bash "$HOME/.claude/scripts/notify.sh" "Repeating test failures detected. Agent PAUSED." 2>/dev/null
  exit 1
fi

printf "detect-loop: No loop detected. Proceed.\n" >&2
exit 0
