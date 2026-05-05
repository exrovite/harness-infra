#!/bin/bash
# run-claude-safe.sh — Retry wrapper for Claude CLI invocations
# Wraps every `claude` call with exponential backoff (3 retries, 60s→120s→240s).
# Takes prompt via FILE (stdin pipe, not command-line args) to avoid shell length limits.
# On final failure: write handoff, notify, block.
#
# Usage: bash run-claude-safe.sh <prompt_file> [permission_mode]
# Exit: 0 = success, 1 = all retries failed

PROMPT_FILE="$1"
MODE="${2:-auto-accept}"
MAX_RETRIES=3
RETRY_DELAY=60
ATTEMPT=0

if [ ! -f "$PROMPT_FILE" ]; then
  printf "run-claude-safe: ERROR — prompt file not found: %s\n" "$PROMPT_FILE" >&2
  exit 1
fi

while [ "$ATTEMPT" -lt "$MAX_RETRIES" ]; do
  # Pipe prompt file to claude via stdin
  cat "$PROMPT_FILE" | claude --permission-mode "$MODE"
  EXIT_CODE=$?

  if [ "$EXIT_CODE" -eq 0 ]; then
    exit 0
  fi

  ATTEMPT=$(( ATTEMPT + 1 ))

  if [ "$ATTEMPT" -lt "$MAX_RETRIES" ]; then
    bash "$HOME/.claude/scripts/notify.sh" "Session failed (exit $EXIT_CODE). Retry $ATTEMPT/$MAX_RETRIES in ${RETRY_DELAY}s." 2>/dev/null
    printf "run-claude-safe: Retry %s/%s in %ss (exit code %s)\n" "$ATTEMPT" "$MAX_RETRIES" "$RETRY_DELAY" "$EXIT_CODE" >&2
    sleep "$RETRY_DELAY"
    RETRY_DELAY=$(( RETRY_DELAY * 2 ))  # Exponential backoff: 60→120→240
  fi
done

# All retries exhausted — save state and block
bash "$HOME/.claude/scripts/write-handoff.sh" "SESSION_CRASH_FINAL" 2>/dev/null
bash "$HOME/.claude/scripts/notify.sh" "Session failed $MAX_RETRIES times. State saved. Agent paused." 2>/dev/null

STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
mkdir -p "$STATE_DIR" 2>/dev/null
printf "BLOCKED\nClaude session failed repeatedly. Last exit code: %s\n" "$EXIT_CODE" > "${STATE_DIR}/agent-blocked.md"

printf "run-claude-safe: ALL RETRIES EXHAUSTED. Agent blocked.\n" >&2
exit 1
