#!/bin/bash
# beast-watch-hook.sh — Sprint 38 B: in-work interjection (PostToolUse).
#
# THE IN-WORK HEARTBEAT. Stop fires only at the END of a turn (too late); a timer only
# fires BETWEEN turns. The thing that runs INSIDE a long working turn is the per-tool-call
# hook. So after each tool call we read the agent's RECENT REASONING (from the transcript)
# plus the action, feed that prose to the SAME pure matcher (beast-surface.sh), and surface
# matching lessons as additionalContext — catching drift mid-work, between the agent's steps.
#
# Pure-ish + fail-safe: never breaks a tool call (always exit 0). Flag-gated, kill-switch
# superset, silent by default. Each lesson surfaced AT MOST ONCE per session (anti-nag).
# Honest limit: a long pure-reasoning stretch with NO tool call cannot be interrupted.
set -u

INPUT="$(cat 2>/dev/null)"
[ -z "$INPUT" ] && exit 0

SURFACE="$HOME/.claude/scripts/beast-surface.sh"
[ -f "$SURFACE" ] || exit 0
# shellcheck disable=SC1091
source "$HOME/.claude/scripts/lib-helpers.sh" 2>/dev/null

CWD="$(pwd -W 2>/dev/null || pwd)"
if [ -n "${HARNESS_STATE_DIR:-}" ]; then
  STATE_DIR="$HARNESS_STATE_DIR"
elif type find_project_state_dir >/dev/null 2>&1; then
  STATE_DIR="$(find_project_state_dir "$CWD" 2>/dev/null)"
fi
[ -n "${STATE_DIR:-}" ] || STATE_DIR=".claude/state"

# Kill-switch superset: harness off => beast contributes nothing.
if type harness_disabled_resolved >/dev/null 2>&1 && harness_disabled_resolved "$CWD" "" 2>/dev/null; then exit 0; fi
[ -f "${STATE_DIR}/harness-disabled.flag" ] && exit 0
# Beast gate.
[ -f "${STATE_DIR}/beast-mode.flag" ] || exit 0

# Resolve lessons (BEAST_LESSONS override, else <project-root>/.beast/lessons.jsonl).
if [ -n "${BEAST_LESSONS:-}" ]; then
  LESSONS="$BEAST_LESSONS"
else
  ROOT="${STATE_DIR%/.claude/state}"; [ "$ROOT" = "$STATE_DIR" ] && ROOT="$CWD"
  LESSONS="$ROOT/.beast/lessons.jsonl"
fi
[ -f "$LESSONS" ] || exit 0
export BEAST_LESSONS="$LESSONS"

SID="$(printf '%s' "$INPUT" | jq -r '.session_id // "default"' 2>/dev/null | tr -d '\r/ \\')"
[ -n "$SID" ] || SID="default"
TPATH="$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null | tr -d '\r')"
TIN="$(printf '%s' "$INPUT" | jq -r '((.tool_input.command // .tool_input.content // .tool_input.new_string // "") + " " + (.tool_input.file_path // ""))' 2>/dev/null)"

# Recent reasoning = the last few assistant text blocks in the transcript tail.
REASON=""
if [ -n "$TPATH" ] && [ -f "$TPATH" ]; then
  REASON="$(tail -n 80 "$TPATH" 2>/dev/null \
    | jq -rc 'select(.type=="assistant") | (.message.content[]? | select(.type=="text") | .text)' 2>/dev/null \
    | tail -n 5 | tr '\n' ' ')"
fi
CONTENT="$REASON $TIN"
[ -n "$(printf '%s' "$CONTENT" | tr -d '[:space:]')" ] || exit 0

# Surface via the pure matcher (prose as content; wildcard file scope).
ACT="$(jq -cn --arg c "$CONTENT" '{file_path:"",content:$c}' 2>/dev/null)"
[ -n "$ACT" ] || exit 0
PACKET="$(printf '%s' "$ACT" | bash "$SURFACE" 2>/dev/null)"
[ -n "$(printf '%s' "$PACKET" | tr -d '[:space:]')" ] || exit 0

# Anti-nag: only surface lessons not already surfaced THIS session.
SURF="${STATE_DIR}/beast-surfaced.${SID}.txt"
touch "$SURF" 2>/dev/null
NEW=0
for id in $(printf '%s' "$PACKET" | grep -oE '\[M[A-Za-z0-9_]+\]' 2>/dev/null | tr -d '[]' | sort -u); do
  grep -qxF "$id" "$SURF" 2>/dev/null && continue
  NEW=1; printf '%s\n' "$id" >> "$SURF"
done
[ "$NEW" = 1 ] || exit 0

jq -cn --arg ctx "⚠️  IN-WORK CHECK (you're mid-task) — this came up in what you just did/said:"$'\n'"$PACKET" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}' 2>/dev/null
exit 0
