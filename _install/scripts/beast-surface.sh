#!/bin/bash
# beast-surface.sh — Deterministic intuition surfacing (Sprint 35, beast-mode)
#
# THE RECALL HOT PATH. Pure function of observable inputs — NO LLM, NO network.
# Given a proposed action (a tool_input-shaped JSON on stdin: {file_path, content}),
# it scans the project's planted lessons by their STABLE ATOMS:
#   - scope  : a glob matched against the file basename ("" or "*" = any file)
#   - trigger: an extended-regex matched against the action content ("" = any)
# Every lesson whose scope AND trigger both match is surfaced. The output is an
# adversarial, self-relevant injection packet naming each matched lesson [M<id>]
# with its fix. If nothing matches, output is EMPTY (silence is the default).
#
# Same input -> identical output, every time. The "is this a mistake / what is the
# lesson / what is the trigger" judgment was frozen at CAPTURE; recall is mechanical.
#
# Lessons store (JSONL, one lesson per line):
#   {"id","scope","trigger","lesson","fix","dossier"}
# Resolved from $BEAST_LESSONS, else <project-root>/.beast/lessons.jsonl.
set -u

INPUT="$(cat)"
[ -z "$INPUT" ] && exit 0

FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.file_path // .tool_input.file_path // ""' 2>/dev/null | tr -d '\r')"
CONTENT="$(printf '%s' "$INPUT"  | jq -r '.content // .tool_input.content // .tool_input.command // ""' 2>/dev/null)"

# Resolve the lessons file.
resolve_lessons() {
  if [ -n "${BEAST_LESSONS:-}" ]; then printf '%s' "$BEAST_LESSONS"; return; fi
  local d; d="$(pwd 2>/dev/null)"
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -f "$d/.beast/lessons.jsonl" ] && { printf '%s' "$d/.beast/lessons.jsonl"; return; }
    d="$(dirname "$d")"
  done
  printf '.beast/lessons.jsonl'
}
LESSONS="$(resolve_lessons)"
[ -f "$LESSONS" ] || exit 0   # no lessons -> silence

BN="$(basename "$FILE_PATH" 2>/dev/null)"
HITS=""
while IFS= read -r line || [ -n "$line" ]; do
  [ -z "$line" ] && continue
  id="$(printf '%s' "$line" | jq -r '.id // ""' 2>/dev/null)"
  scope="$(printf '%s' "$line" | jq -r '.scope // ""' 2>/dev/null)"
  trigger="$(printf '%s' "$line" | jq -r '.trigger // ""' 2>/dev/null)"
  lesson="$(printf '%s' "$line" | jq -r '.lesson // ""' 2>/dev/null)"
  fix="$(printf '%s' "$line" | jq -r '.fix // ""' 2>/dev/null)"
  [ -z "$id" ] && continue

  # scope match (glob on basename); empty or * = any
  scope_ok=0
  if [ -z "$scope" ] || [ "$scope" = "*" ]; then
    scope_ok=1
  else
    case "$BN" in $scope) scope_ok=1 ;; esac
  fi
  [ "$scope_ok" = "1" ] || continue

  # trigger match (ERE on content); empty = any
  trig_ok=0
  if [ -z "$trigger" ]; then
    trig_ok=1
  elif printf '%s' "$CONTENT" | grep -qE -- "$trigger" 2>/dev/null; then
    trig_ok=1
  fi
  [ "$trig_ok" = "1" ] || continue

  HITS="${HITS}[M${id}] ${lesson}"$'\n'"        → DO: ${fix}"$'\n'
done < "$LESSONS"

[ -z "$HITS" ] && exit 0   # no matches -> silence

# Adversarial, self-relevant framing — provoke re-examination, not passive reading.
printf '⚠️  BEFORE YOU ACT — past-you has been here.\n'
printf 'You are about to work on: %s\n' "${FILE_PATH:-this action}"
printf 'On previous occasions doing this exact kind of work, you have ALREADY LEARNED — and already gotten wrong:\n\n'
printf '%s\n' "$HITS"
printf 'STOP. For each [M#] above: does it apply to what you are about to do RIGHT NOW?\n'
printf 'If it applies you MUST follow it — do not assume you remember. State which apply before proceeding.\n'
exit 0
