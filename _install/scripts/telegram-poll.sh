#!/bin/bash
# telegram-poll.sh — Notification daemon
# Long-polls Telegram Bot API for replies. Writes replies to human-response.md.
# Has heartbeat file so harness can detect if daemon dies.
# Triggers resume-on-reply.sh if agent was timed out.
#
# Usage: bash telegram-poll.sh &  (runs as background daemon)
# Exit: never (runs until killed)

TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
LAST_UPDATE_ID=0
HEARTBEAT_FILE="${STATE_DIR}/telegram-poll-heartbeat"

mkdir -p "$STATE_DIR" 2>/dev/null

# If Telegram not configured, exit gracefully
if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
  printf "telegram-poll: Telegram not configured. Daemon not starting.\n" >&2
  exit 0
fi

while true; do
  # Write heartbeat so harness knows we're alive
  printf "%s" "$(date +%s)" > "$HEARTBEAT_FILE"

  # Long-poll Telegram for updates (30s timeout on the API side)
  RESPONSE=$(curl -s --max-time 35 \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates?offset=$(( LAST_UPDATE_ID + 1 ))&timeout=30" 2>/dev/null)

  # Handle curl failure
  if [ $? -ne 0 ]; then
    printf "telegram-poll: Telegram API unreachable. Retrying in 30s...\n" >&2
    sleep 30
    continue
  fi

  # Extract messages from your chat
  MESSAGES=$(printf "%s" "$RESPONSE" | jq -r ".result[] | select(.message.chat.id == $TELEGRAM_CHAT_ID)" 2>/dev/null)

  if [ -n "$MESSAGES" ]; then
    LATEST_TEXT=$(printf "%s" "$MESSAGES" | jq -r '.message.text' | tail -1)
    LATEST_ID=$(printf "%s" "$MESSAGES" | jq -r '.update_id' | tail -1)
    LAST_UPDATE_ID="$LATEST_ID"

    # Write response to file (agent or harness reads this)
    printf "%s\n" "$LATEST_TEXT" > "${STATE_DIR}/human-response.md"

    # Acknowledge receipt
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d chat_id="${TELEGRAM_CHAT_ID}" \
      -d text="Received. Injecting into agent." > /dev/null 2>&1

    # If there's a resume script waiting, trigger it
    if [ -f "${STATE_DIR}/resume-on-reply.sh" ]; then
      bash "${STATE_DIR}/resume-on-reply.sh" &
      rm -f "${STATE_DIR}/resume-on-reply.sh"
    fi
  fi

  sleep 5
done
