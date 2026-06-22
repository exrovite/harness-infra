#!/bin/bash
# beast-recall-hook.sh — Sprint 36 G1: global recall wiring (PreToolUse adapter).
#
# Fires beast-surface.sh (the pure recall function) on the agent's CONSEQUENTIAL
# actions in ANY project, and injects what past-you already learned as
# hookSpecificOutput.additionalContext (NON-BLOCKING — inject only, per D5).
#
# Superset & silence rules (all fail-safe -> default to silence, never block):
#   - harness disabled (kill-switch)            -> emit nothing
#   - project has no beast-mode.flag            -> emit nothing
#   - no lessons / no match                     -> emit nothing
# Triggers: Write/Edit (file_path + content/new_string) AND file-writing Bash
# commands (mirroring pre-bash-gate.sh detection). Non-file Bash -> silence.
#
# This hook does INPUT NORMALISATION only; the match judgment lives in
# beast-surface.sh (frozen at capture). It must ALWAYS exit 0.
set -u
# Fail-safe by construction: no `set -e`, so non-zero returns (e.g. grep no-match)
# never abort; every exit path is `exit 0`. This hook must NEVER block a tool call.

INPUT="$(cat 2>/dev/null)"
[ -z "$INPUT" ] && exit 0

SURFACE="$HOME/.claude/hooks/../scripts/beast-surface.sh"
[ -f "$SURFACE" ] || SURFACE="$HOME/.claude/scripts/beast-surface.sh"
[ -f "$SURFACE" ] || exit 0

# lib-helpers for project-root resolution + kill-switch (best-effort).
# shellcheck disable=SC1091
source "$HOME/.claude/scripts/lib-helpers.sh" 2>/dev/null

CWD="$(pwd -W 2>/dev/null || pwd)"

# --- Resolve the project state dir (honour HARNESS_STATE_DIR for sandboxing) ---
if [ -n "${HARNESS_STATE_DIR:-}" ]; then
  STATE_DIR="$HARNESS_STATE_DIR"
elif type find_project_state_dir >/dev/null 2>&1; then
  STATE_DIR="$(find_project_state_dir "$CWD" 2>/dev/null)"
fi
[ -n "${STATE_DIR:-}" ] || STATE_DIR=".claude/state"

# --- Kill-switch superset: harness off => beast contributes nothing ---
if type harness_disabled_resolved >/dev/null 2>&1 && harness_disabled_resolved "$CWD" "" 2>/dev/null; then
  exit 0
fi
[ -f "${STATE_DIR}/harness-disabled.flag" ] && exit 0

# --- Beast gate: project must have beast-mode.flag ---
[ -f "${STATE_DIR}/beast-mode.flag" ] || exit 0

# --- Resolve lessons file (BEAST_LESSONS override, else <project-root>/.beast) ---
if [ -n "${BEAST_LESSONS:-}" ]; then
  LESSONS="$BEAST_LESSONS"
else
  ROOT="${STATE_DIR%/.claude/state}"
  [ "$ROOT" = "$STATE_DIR" ] && ROOT="$CWD"
  LESSONS="$ROOT/.beast/lessons.jsonl"
fi
[ -f "$LESSONS" ] || exit 0
export BEAST_LESSONS="$LESSONS"

TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null | tr -d '\r')"

# surface_for FILE CONTENT -> echoes beast-surface output (may be empty)
surface_for() {
  local fp="$1" content="$2" act
  act="$(jq -cn --arg f "$fp" --arg c "$content" '{file_path:$f,content:$c}' 2>/dev/null)"
  [ -n "$act" ] || return 0
  printf '%s' "$act" | bash "$SURFACE" 2>/dev/null
}

PACKET=""
case "$TOOL" in
  Write|Edit)
    FP="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)"
    CONTENT="$(printf '%s' "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // ""' 2>/dev/null)"
    PACKET="$(surface_for "$FP" "$CONTENT")"
    ;;
  Bash)
    COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)"
    # Only consider file-writing commands (mirror pre-bash-gate.sh detection).
    WRITES_FILES=false
    if printf '%s' "$COMMAND" | grep -qiE '\bpython' && printf '%s' "$COMMAND" | grep -qiE '\b(open|write|Path)\b'; then WRITES_FILES=true; fi
    printf '%s' "$COMMAND" | grep -qiE '\bnode\b.*\bfs\.'                 && WRITES_FILES=true
    printf '%s' "$COMMAND" | grep -qE  '\btee\s'                          && WRITES_FILES=true
    printf '%s' "$COMMAND" | grep -qE  '\bsed\s.*-i'                      && WRITES_FILES=true
    printf '%s' "$COMMAND" | grep -qE  '(echo|printf|cat)\s.*>\s*[a-zA-Z."$]' && WRITES_FILES=true
    printf '%s' "$COMMAND" | grep -qE  '<<.+>'                            && WRITES_FILES=true
    printf '%s' "$COMMAND" | grep -qE  '\b(cp|mv)\b\s+.+\s+[a-zA-Z."$]'   && WRITES_FILES=true
    if [ "$WRITES_FILES" = true ]; then
      # Extract filename-like target tokens; surface per candidate (scope match on
      # basename) plus one wildcard pass (file_path empty) for scope-agnostic lessons.
      CANDS="$(printf '%s' "$COMMAND" | grep -oE '[A-Za-z0-9_./-]+\.[A-Za-z0-9]+' 2>/dev/null | sort -u)"
      ACC=""
      ACC="${ACC}$(surface_for "" "$COMMAND")"
      while IFS= read -r cand || [ -n "$cand" ]; do
        [ -z "$cand" ] && continue
        ACC="${ACC}$(surface_for "$cand" "$COMMAND")"
      done <<EOF2
$CANDS
EOF2
      # De-duplicate repeated lesson lines while preserving a single packet header.
      PACKET="$ACC"
    fi
    ;;
  *)
    exit 0
    ;;
esac

# --- Emit (non-blocking) only if something surfaced ---
if [ -n "$(printf '%s' "$PACKET" | tr -d '[:space:]')" ]; then
  jq -cn --arg ctx "$PACKET" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$ctx}}' 2>/dev/null
fi
exit 0
