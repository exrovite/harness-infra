#!/usr/bin/env bash
# lavish-review.sh — Harness wrapper around lavish-axi for HTML-artifact human feedback.
#
# Opens/ensures a lavish-axi session for an HTML file and BLOCKS for human feedback, pausing the
# 3-minute watcher cron during the (potentially long) poll so the harness does not mistake the wait
# for drift, then resuming. The human's feedback is printed to stdout for the calling agent.
#
# Usage: lavish-review.sh <file.html> [--agent-reply "what I changed"]
#
# Env:
#   LAVISH_POLL_PAUSE_MIN  minutes to pause the watcher cron during the poll (default 60)
#   HARNESS_SKIP_CRON=1    skip cron pause/resume (used by tests / non-harness contexts)
set -u

FILE="${1:-}"
[ -n "$FILE" ] && shift || true
if [ -z "$FILE" ]; then
  echo "usage: lavish-review.sh <file.html> [--agent-reply \"...\"]" >&2
  exit 2
fi

LH="$HOME/.claude/scripts/lib-helpers.sh"
PAUSE_MIN="${LAVISH_POLL_PAUSE_MIN:-60}"

_pause_cron() {
  [ "${HARNESS_SKIP_CRON:-0}" = "1" ] && return 0
  if [ -f "$LH" ]; then
    . "$LH" 2>/dev/null || return 0
    command -v cron_pause >/dev/null 2>&1 && cron_pause "$PAUSE_MIN" >/dev/null 2>&1
  fi
  return 0
}
_resume_cron() {
  [ "${HARNESS_SKIP_CRON:-0}" = "1" ] && return 0
  if [ -f "$LH" ]; then
    . "$LH" 2>/dev/null || return 0
    command -v cron_resume >/dev/null 2>&1 && cron_resume >/dev/null 2>&1
  fi
  return 0
}

if ! command -v lavish-axi >/dev/null 2>&1; then
  echo "lavish-review: lavish-axi is not installed. Run: npm install -g lavish-axi" >&2
  exit 127
fi

# 1. Ensure the session exists (lavish opens the browser UI for the human on first real interaction).
lavish-axi "$FILE" >/dev/null 2>&1 || true

# 2. Pause the watcher cron, long-poll for the human's feedback, then resume regardless of outcome.
_pause_cron
FEEDBACK=$(lavish-axi poll "$FILE" "$@" 2>/dev/null)
RC=$?
_resume_cron

# 3. Hand the feedback back to the agent.
printf '%s\n' "$FEEDBACK"
exit "$RC"
