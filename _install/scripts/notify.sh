#!/bin/bash
# notify.sh — Telegram/WhatsApp bridge
# Sends messages via Telegram Bot API. Degrades gracefully if Telegram unavailable.
# Transport-agnostic: swap API endpoint for WhatsApp/Twilio.
#
# Usage: bash notify.sh "Your message here"
# Exit: 0 always (notification is best-effort, never blocks harness)

MESSAGE="$1"

if [ -z "$MESSAGE" ]; then
  printf "Usage: bash notify.sh \"message\"\n" >&2
  exit 0
fi

# Telegram Bot configuration — set these env vars or leave empty to skip
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

# Always log to file regardless of Telegram availability
NOTIFY_LOG="${HARNESS_STATE_DIR:-$HOME/.claude/state}/notifications.log"
mkdir -p "$(dirname "$NOTIFY_LOG")" 2>/dev/null
printf "[%s] %s\n" "$(date -Iseconds)" "$MESSAGE" >> "$NOTIFY_LOG" 2>/dev/null

# If Telegram not configured, degrade gracefully
if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
  printf "notify: Telegram not configured. Message logged to %s\n" "$NOTIFY_LOG" >&2
  exit 0
fi

# Send via Telegram Bot API (best-effort, 10s timeout)
RESPONSE=$(curl -s --max-time 10 -X POST \
  "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d chat_id="${TELEGRAM_CHAT_ID}" \
  -d text="${MESSAGE}" \
  -d parse_mode="Markdown" 2>/dev/null)

# Check if send succeeded (best-effort — don't block on failure)
if printf "%s" "$RESPONSE" | grep -q '"ok":true' 2>/dev/null; then
  printf "notify: Message sent via Telegram\n" >&2
else
  printf "notify: Telegram send failed (network or token issue). Message logged to %s\n" "$NOTIFY_LOG" >&2
fi

# Always exit 0 — notification failures never block the harness
exit 0
