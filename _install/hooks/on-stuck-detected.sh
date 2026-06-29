#!/bin/bash
# on-stuck-detected.sh — Harness-internal script (NOT a Claude Code hook)
# Called by run-harness.sh when STUCK triggers fire.
# DUAL-PATH: known fix → inject to next-fix.md, no fix → block agent + wait for human.
#
# Usage: bash on-stuck-detected.sh

STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
# resolve STATE_DIR to the PROJECT ROOT (avoid creating a nested .claude in a subdir cwd)
if [ -z "${HARNESS_STATE_DIR:-}" ]; then . "$HOME/.claude/scripts/lib-helpers.sh" 2>/dev/null; type find_project_state_dir >/dev/null 2>&1 && { _r="$(find_project_state_dir "$(pwd -W 2>/dev/null || pwd)" 2>/dev/null)"; [ -n "$_r" ] && STATE_DIR="$_r"; }; fi

mkdir -p "$STATE_DIR" 2>/dev/null

# Run detect-loop.sh to check git history
bash "$HOME/.claude/scripts/detect-loop.sh" 2>/dev/null
LOOP_EXIT=$?

if [ $LOOP_EXIT -ne 0 ]; then
  # detect-loop.sh already handled injection or blocking
  # Check which path was taken
  if [ -f "${STATE_DIR}/next-fix.md" ]; then
    printf "on-stuck-detected: Known fix injected by detect-loop.sh. Agent will apply it.\n" >&2
  elif [ -f "${STATE_DIR}/agent-blocked.md" ]; then
    printf "on-stuck-detected: Agent blocked by detect-loop.sh. Harness will handle wait-for-human.\n" >&2
    bash "$HOME/.claude/scripts/notify.sh" "Loop detected, no known fix. Agent PAUSED. Awaiting instruction." 2>/dev/null
    # NOTE: Do NOT call wait-for-human.sh here — the harness calls it after this hook exits
  fi
  exit 1
fi

# If detect-loop didn't fire but we're still stuck (progress stall or confusion)
# Check progress stall: is progress-notes.md older than 5 minutes?
PROGRESS_FILE="${STATE_DIR}/progress-notes.md"
if [ -f "$PROGRESS_FILE" ]; then
  LAST_MODIFIED=$(stat -c %Y "$PROGRESS_FILE" 2>/dev/null || stat -f %m "$PROGRESS_FILE" 2>/dev/null || printf "0")
  NOW=$(date +%s)
  STALE_SECONDS=$(( NOW - LAST_MODIFIED ))
  if [ "$STALE_SECONDS" -gt 300 ]; then
    printf "on-stuck-detected: Progress stall — %ss since last update to progress-notes.md\n" "$STALE_SECONDS" >&2
    {
      printf "BLOCKED\n"
      printf "Progress stall detected (%ss since last progress update).\n" "$STALE_SECONDS"
      printf "Agent has not made progress for 5+ minutes.\n"
      printf "Awaiting human instruction.\n"
    } > "${STATE_DIR}/agent-blocked.md"

    bash "$HOME/.claude/scripts/notify.sh" "Progress stall detected (${STALE_SECONDS}s). Agent PAUSED." 2>/dev/null
    # NOTE: Do NOT call wait-for-human.sh here — the harness calls it after this hook exits
    exit 1
  fi
fi

printf "on-stuck-detected: No stuck condition confirmed.\n" >&2
exit 0
