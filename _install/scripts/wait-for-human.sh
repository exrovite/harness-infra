#!/bin/bash
# wait-for-human.sh — Timeout + state save
# Blocks until human-response.md appears or timeout (default 30min).
# On timeout: saves state, generates resume-on-reply.sh, notifies.
# Sends reminders every 10min.
#
# Usage: bash wait-for-human.sh [timeout_minutes]
# Exit: 0 = human responded, 1 = timed out (state saved)

TIMEOUT_MINUTES="${1:-30}"
TIMEOUT_SECONDS=$(( TIMEOUT_MINUTES * 60 ))
ELAPSED=0
STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
RESPONSE_FILE="${STATE_DIR}/human-response.md"

bash "$HOME/.claude/scripts/notify.sh" "Agent blocked. Awaiting your instruction. Will auto-save in ${TIMEOUT_MINUTES}m if no response." 2>/dev/null

while [ ! -f "$RESPONSE_FILE" ]; do
  sleep 10
  ELAPSED=$(( ELAPSED + 10 ))

  if [ "$ELAPSED" -ge "$TIMEOUT_SECONDS" ]; then
    # Timeout — save state and exit
    bash "$HOME/.claude/scripts/write-handoff.sh" "BLOCKED_TIMEOUT" 2>/dev/null
    bash "$HOME/.claude/scripts/notify.sh" "No response after ${TIMEOUT_MINUTES}m. Session saved. Reply anytime — harness will resume." 2>/dev/null

    # Generate resume-on-reply.sh (runtime artifact, not build deliverable)
    {
      printf "#!/bin/bash\n"
      printf "# Auto-generated — runs when human-response.md appears\n"
      printf "bash \"\$HOME/.claude/scripts/run-harness.sh\"\n"
    } > "${STATE_DIR}/resume-on-reply.sh"
    chmod +x "${STATE_DIR}/resume-on-reply.sh" 2>/dev/null

    printf "wait-for-human: Timed out after %sm. State saved. resume-on-reply.sh generated.\n" "$TIMEOUT_MINUTES" >&2
    exit 1
  fi

  # Reminder every 10 minutes
  if [ $(( ELAPSED % 600 )) -eq 0 ] && [ "$ELAPSED" -gt 0 ]; then
    REMAINING=$(( (TIMEOUT_SECONDS - ELAPSED) / 60 ))
    bash "$HOME/.claude/scripts/notify.sh" "Still waiting. ${REMAINING}m until auto-save." 2>/dev/null
  fi
done

printf "wait-for-human: Human response received after %ss.\n" "$ELAPSED" >&2
exit 0
