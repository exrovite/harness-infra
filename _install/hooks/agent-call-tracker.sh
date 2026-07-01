#!/bin/bash
# agent-call-tracker.sh — PostToolUse hook (Agent)
# Tracks when Agent tool calls contain verification language.
# If verification detected: appends to verification ledger + resets verify counter.
# Output: JSON hookSpecificOutput to stdout. Diagnostics to stderr only.

source "$HOME/.claude/scripts/lib-helpers.sh" 2>/dev/null

STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
_pf_sd="$STATE_DIR"
if [ -z "${HARNESS_STATE_DIR:-}" ] && type find_project_state_dir >/dev/null 2>&1; then
  _pf_root="$(find_project_state_dir "$(pwd -W 2>/dev/null || pwd)" 2>/dev/null)" ; if [ -n "$_pf_root" ]; then _pf_sd="$_pf_root"; else exit 0; fi
fi
PF_BASE="${_pf_sd%/state}/pre-flight"
STATE_DIR="$_pf_sd"
LEDGER="${STATE_DIR}/verification-ledger.jsonl"
VERIFY_COUNTER="$PF_BASE/verify-counter.json"
WATCHER_REGISTRY="$HOME/.openclaw/watchers/REGISTRY.json"

# --- Read stdin (PostToolUse Agent provides full JSON on stdin) ---
INPUT=$(cat)
export HARNESS_SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null | tr -d '\r')"  # per-session watcher slot resolution
PROMPT=$(printf '%s' "$INPUT" | jq -r '.tool_input.prompt // ""' 2>/dev/null)

if [ -z "$PROMPT" ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":""}}' 
  exit 0
fi

# --- Check for verification language (compound pattern per contract) ---
IS_VERIFICATION="false"

# Tier 1: Strong keywords (always count)
if printf '%s' "$PROMPT" | grep -qiE 'verify|validate|audit|assess|evaluate independently|independent review'; then
  IS_VERIFICATION="true"
fi

# Tier 2: Moderate keyword + context (only if tier 1 didn't match)
if [ "$IS_VERIFICATION" = "false" ]; then
  if printf '%s' "$PROMPT" | grep -qiE '(review|check|test|evaluate).*(work|output|result|implementation|changes|code|document|step|criteria)'; then
    IS_VERIFICATION="true"
  fi
fi

if [ "$IS_VERIFICATION" = "false" ]; then
  # Not a verification call — silent pass
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":""}}'
  exit 0
fi

# --- Verification call detected — update ledger and counter ---

# Classify verification type from prompt keywords
VTYPE="review"
if printf '%s' "$PROMPT" | grep -qiE 'screenshot|vision|visual|look at|render|\bUI\b|inspect.*layout'; then
  VTYPE="vision"
elif printf '%s' "$PROMPT" | grep -qiE 'browser|navigate|page|open.*url|website|localhost'; then
  VTYPE="browser"
elif printf '%s' "$PROMPT" | grep -qiE 'run|execute|test|curl|output|functional|invoke|call.*endpoint'; then
  VTYPE="functional"
fi

TS=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')

# Extract current step from watcher slot
CURRENT_PROJECT=$(pwd -W 2>/dev/null || pwd)
CURRENT_PROJECT=$(printf '%s' "$CURRENT_PROJECT" | tr '\\' '/' | sed 's|/$||' | tr '[:upper:]' '[:lower:]')

CURRENT_STEP=""
if [ -f "$WATCHER_REGISTRY" ]; then
  # THIS session's own watcher slot (its own current step), not the project's first/stale watcher.
  if [ -n "${HARNESS_SESSION_ID:-}" ] && type watcher_slot_for_session >/dev/null 2>&1; then
    SLOT_NUM=$(watcher_slot_for_session "$HARNESS_SESSION_ID" "$WATCHER_REGISTRY")
  else
    SLOT_NUM=$(jq -r --arg proj "$CURRENT_PROJECT" \
      '[.watchers[] | select(.status == "active" and .project != null and ((.project | gsub("\\\\";"/") | sub("/$";"") | ascii_downcase) == $proj))] | .[0].slot // empty' \
      "$WATCHER_REGISTRY" 2>/dev/null)
  fi
  if [ -n "$SLOT_NUM" ]; then
    SLOT_FILE="$HOME/.openclaw/watchers/slot-${SLOT_NUM}.md"
    if [ -f "$SLOT_FILE" ]; then
      CURRENT_STEP=$(sed -n '/## TO-DO/,/^## /{/^## /d;p;}' "$SLOT_FILE" | grep -F -- '- [ ]' | head -1 | sed 's/^[[:space:]]*- \[ \][[:space:]]*//')
    fi
  fi
fi
if [ -z "$CURRENT_STEP" ]; then
  CURRENT_STEP="(no unchecked steps remain)"
fi

# Read phase+sprint
PHASE="UNKNOWN"
SPRINT=0
if [ -f "${STATE_DIR}/current-phase.json" ]; then
  PHASE=$(jq -r '.phase // "UNKNOWN"' "${STATE_DIR}/current-phase.json" 2>/dev/null)
  SPRINT=$(jq -r '.sprint // 0' "${STATE_DIR}/current-phase.json" 2>/dev/null)
fi

# Prompt snippet (first 100 chars, sanitized for JSON)
SNIPPET=$(printf '%s' "$PROMPT" | head -c 100 | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')

# Append to verification ledger
mkdir -p "$STATE_DIR" 2>/dev/null
SAFE_STEP=$(printf '%s' "$CURRENT_STEP" | sed 's/\\/\\\\/g; s/"/\\"/g' | head -c 200)
ENTRY=$(printf '{"ts":"%s","step":"%s","phase":"%s","sprint":"%s","prompt_snippet":"%s","verification_type":"%s"}' \
  "$TS" "$SAFE_STEP" "$PHASE" "$SPRINT" "$SNIPPET" "$VTYPE")

if type append_jsonl >/dev/null 2>&1; then
  append_jsonl "$ENTRY" "$LEDGER"
else
  printf '%s\n' "$ENTRY" >> "$LEDGER"
fi

echo "agent-call-tracker: verification call logged to ledger (type: $VTYPE)" >&2

# Consume unverified-writes (archive then clear)
UNVERIFIED="${STATE_DIR}/unverified-writes.jsonl"
if [ -f "$UNVERIFIED" ]; then
  cat "$UNVERIFIED" >> "${STATE_DIR}/unverified-writes-archive.jsonl" 2>/dev/null
  rm -f "$UNVERIFIED"
  echo "agent-call-tracker: unverified-writes consumed" >&2
fi

# Reset verify counter
mkdir -p "$PF_BASE" 2>/dev/null
jq -n --arg lr "$TS" '{"no_verify_count":0,"hardened":false,"last_reset":$lr}' > "$VERIFY_COUNTER"

echo "agent-call-tracker: verify counter reset" >&2

# --- Output ---
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"Verification subagent tracked. Ledger updated, verify counter reset."}}'
exit 0
