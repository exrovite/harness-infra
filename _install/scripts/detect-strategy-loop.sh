#!/bin/bash
# detect-strategy-loop.sh — Layer 2: Strategy loop detection (3-signal conjunction)
#
# Reads bash-failure-log.jsonl and checks for 3 conjunctive signals:
#   Signal 1: Same output fingerprint repeating (3+ consecutive failures)
#   Signal 2: Consecutive command failures without success (3+)
#   Signal 3: Same files edited between failures (file in 3+ entries)
#
# All 3 must fire simultaneously. Single signals are not loops.
#
# Exit codes:
#   0 = no loop detected (stdout: {"result":"none","reason":"..."})
#   1 = nudge recommended (stdout: {"result":"nudge",...})
#   2 = block recommended (stdout: {"result":"block",...})
#
# Usage: bash detect-strategy-loop.sh

set -euo pipefail

source "$HOME/.claude/scripts/lib-helpers.sh" 2>/dev/null
if ! type atomic_write >/dev/null 2>&1; then
  printf '{"result":"none","reason":"lib-helpers.sh missing"}\n'
  exit 0
fi

STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
FAILURE_LOG="${STATE_DIR}/bash-failure-log.jsonl"
STATE_FILE="${STATE_DIR}/strategy-loop-state.json"
BLOCKED_FILE="${STATE_DIR}/agent-blocked.md"

# --- Step 1: Check if failure log exists and has content ---
if [ ! -f "$FAILURE_LOG" ] || [ ! -s "$FAILURE_LOG" ]; then
  printf '{"result":"none","reason":"no failure log"}\n'
  exit 0
fi

# --- Step 2: Deconfliction — detect-loop.sh takes priority ---
if [ -f "$BLOCKED_FILE" ]; then
  # Reset nudge_count while agent-blocked.md exists so it's 0 when removed
  if [ -f "$STATE_FILE" ]; then
    atomic_write '{"nudge_count":0,"last_nudge_ts":null,"last_output_fingerprint":"","last_churn_files":[],"blocked":false}' "$STATE_FILE"
  fi
  printf '{"result":"none","reason":"agent-blocked.md exists (deconfliction)"}\n'
  exit 0
fi

# --- Step 3: Read last 10 entries ---
TAIL_FILE=$(mktemp 2>/dev/null || echo "/tmp/dsl_tail_$$")
tail -10 "$FAILURE_LOG" > "$TAIL_FILE"

if [ ! -s "$TAIL_FILE" ]; then
  rm -f "$TAIL_FILE" 2>/dev/null
  printf '{"result":"none","reason":"no entries"}\n'
  exit 0
fi

# --- Step 4: Find consecutive failures from the tail ---
# Walk backwards. Stop at first success entry.
CONSEC_REV=$(mktemp 2>/dev/null || echo "/tmp/dsl_cr_$$")
CONSEC_FILE=$(mktemp 2>/dev/null || echo "/tmp/dsl_cf_$$")
: > "$CONSEC_REV"

tac "$TAIL_FILE" 2>/dev/null | while IFS= read -r LINE; do
  [ -z "$LINE" ] && continue
  IS_SUCCESS=$(printf '%s' "$LINE" | jq -r '.success // false' 2>/dev/null | tr -d '\r')
  if [ "$IS_SUCCESS" = "true" ]; then
    break
  fi
  printf '%s\n' "$LINE"
done > "$CONSEC_REV"

# Reverse back to chronological order
tac "$CONSEC_REV" > "$CONSEC_FILE" 2>/dev/null
rm -f "$CONSEC_REV" "$TAIL_FILE" 2>/dev/null

CONSEC_COUNT=0
if [ -s "$CONSEC_FILE" ]; then
  CONSEC_COUNT=$(wc -l < "$CONSEC_FILE" | tr -d ' ')
fi

# --- Step 5: Check Signal 2 threshold (3+ consecutive failures) ---
if [ "$CONSEC_COUNT" -lt 3 ]; then
  rm -f "$CONSEC_FILE" 2>/dev/null
  printf '{"result":"none","reason":"fewer than 3 consecutive failures (%s)"}\n' "$CONSEC_COUNT"
  exit 0
fi

# --- Step 6-7: Extract output fingerprints, find most common ---
FP_FILE=$(mktemp 2>/dev/null || echo "/tmp/dsl_fp_$$")
jq -r '.output_fingerprint // empty' "$CONSEC_FILE" 2>/dev/null > "$FP_FILE"

DOMINANT_FP=""
DOMINANT_FP_COUNT=0

if [ -s "$FP_FILE" ]; then
  TOP_FP_LINE=$(sort "$FP_FILE" | uniq -c | sort -rn | head -1)
  DOMINANT_FP_COUNT=$(printf '%s' "$TOP_FP_LINE" | awk '{print $1}' | tr -d ' ')
  DOMINANT_FP=$(printf '%s' "$TOP_FP_LINE" | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//')
fi
rm -f "$FP_FILE" 2>/dev/null

# Ensure numeric
if ! printf '%s' "$DOMINANT_FP_COUNT" | grep -qE '^[0-9]+$' 2>/dev/null; then
  DOMINANT_FP_COUNT=0
fi

# --- Step 8: Check Signal 1 threshold (most common fingerprint 3+ times) ---
if [ "$DOMINANT_FP_COUNT" -lt 3 ]; then
  rm -f "$CONSEC_FILE" 2>/dev/null
  printf '{"result":"none","reason":"dominant fingerprint count %s < 3"}\n' "$DOMINANT_FP_COUNT"
  exit 0
fi

# --- Step 9-10: Collect files from files_edited_since_last, count per-entry occurrences ---
FILES_FILE=$(mktemp 2>/dev/null || echo "/tmp/dsl_files_$$")
jq -r '.files_edited_since_last[]?' "$CONSEC_FILE" 2>/dev/null > "$FILES_FILE"

DOMINANT_CHURN_FILE=""
DOMINANT_CHURN_COUNT=0

if [ -s "$FILES_FILE" ]; then
  TOP_FILE_LINE=$(sort "$FILES_FILE" | uniq -c | sort -rn | head -1)
  DOMINANT_CHURN_COUNT=$(printf '%s' "$TOP_FILE_LINE" | awk '{print $1}' | tr -d ' ')
  DOMINANT_CHURN_FILE=$(printf '%s' "$TOP_FILE_LINE" | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//')
fi
rm -f "$FILES_FILE" "$CONSEC_FILE" 2>/dev/null

# Ensure numeric
if ! printf '%s' "$DOMINANT_CHURN_COUNT" | grep -qE '^[0-9]+$' 2>/dev/null; then
  DOMINANT_CHURN_COUNT=0
fi

# --- Step 10 check: Signal 3 threshold (file in 3+ entries) ---
if [ "$DOMINANT_CHURN_COUNT" -lt 3 ]; then
  printf '{"result":"none","reason":"no file in 3+ entries (max: %s)"}\n' "$DOMINANT_CHURN_COUNT"
  exit 0
fi

# ============================================================
# ALL 3 SIGNALS ACTIVE
# ============================================================

# --- Step 11-12: Read or initialise state ---
NUDGE_COUNT=0
BLOCKED=false
LAST_FP=""
LAST_CHURN="[]"
LAST_NUDGE_TS="null"

if [ -f "$STATE_FILE" ]; then
  # Validate JSON first — if corrupt, skip reading (defaults stay)
  if jq '.' "$STATE_FILE" >/dev/null 2>&1; then
    NUDGE_COUNT=$(jq -r '.nudge_count // 0' "$STATE_FILE" 2>/dev/null | tr -d '\r')
    BLOCKED=$(jq -r '.blocked // false' "$STATE_FILE" 2>/dev/null | tr -d '\r')
    LAST_FP=$(jq -r '.last_output_fingerprint // ""' "$STATE_FILE" 2>/dev/null | tr -d '\r')
    LAST_CHURN=$(jq -c '.last_churn_files // []' "$STATE_FILE" 2>/dev/null | tr -d '\r')
    LAST_NUDGE_TS=$(jq -r '.last_nudge_ts // "null"' "$STATE_FILE" 2>/dev/null | tr -d '\r')
  fi
fi

# Ensure NUDGE_COUNT is numeric
if ! printf '%s' "$NUDGE_COUNT" | grep -qE '^[0-9]+$' 2>/dev/null; then
  NUDGE_COUNT=0
fi

# --- Reset conditions ---
# Reset if dominant fingerprint changed from last detection
if [ -n "$LAST_FP" ] && [ "$LAST_FP" != "$DOMINANT_FP" ]; then
  NUDGE_COUNT=0
fi

# Reset if most-churned file changed from last detection
if [ "$LAST_CHURN" != "[]" ] && [ -n "$DOMINANT_CHURN_FILE" ]; then
  LAST_TOP_FILE=$(printf '%s' "$LAST_CHURN" | jq -r '.[0] // ""' 2>/dev/null | tr -d '\r')
  if [ -n "$LAST_TOP_FILE" ] && [ "$LAST_TOP_FILE" != "$DOMINANT_CHURN_FILE" ]; then
    NUDGE_COUNT=0
  fi
fi

# --- Build state values for writing ---
SAFE_FP=$(printf '%s' "$DOMINANT_FP" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r')
SAFE_CHURN_FILE=$(printf '%s' "$DOMINANT_CHURN_FILE" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r')
CHURN_JSON=$(printf '%s' "$DOMINANT_CHURN_FILE" | jq -Rs '[ . | rtrimstr("\n") ]' 2>/dev/null || echo "[]")

# Format last_nudge_ts for JSON (preserve value from state file)
if [ "$LAST_NUDGE_TS" = "null" ] || [ -z "$LAST_NUDGE_TS" ]; then
  NUDGE_TS_JSON="null"
else
  NUDGE_TS_JSON="\"${LAST_NUDGE_TS}\""
fi

# --- Step 13-14: Decide nudge vs block ---
if [ "$NUDGE_COUNT" -lt 3 ]; then
  # Nudge — don't increment nudge_count here (on-prompt-submit.sh does that with cooldown)
  atomic_write "{\"nudge_count\":${NUDGE_COUNT},\"last_nudge_ts\":${NUDGE_TS_JSON},\"last_output_fingerprint\":\"${SAFE_FP}\",\"last_churn_files\":${CHURN_JSON},\"blocked\":false}" "$STATE_FILE"
  printf '{"result":"nudge","consecutive_failures":%s,"dominant_fingerprint":"%s","dominant_churn_file":"%s","nudge_count":%s}\n' \
    "$CONSEC_COUNT" "$SAFE_FP" "$SAFE_CHURN_FILE" "$NUDGE_COUNT"
  exit 1
else
  # Block — set blocked=true
  atomic_write "{\"nudge_count\":${NUDGE_COUNT},\"last_nudge_ts\":${NUDGE_TS_JSON},\"last_output_fingerprint\":\"${SAFE_FP}\",\"last_churn_files\":${CHURN_JSON},\"blocked\":true}" "$STATE_FILE"
  printf '{"result":"block","consecutive_failures":%s,"dominant_fingerprint":"%s","dominant_churn_file":"%s","nudge_count":%s}\n' \
    "$CONSEC_COUNT" "$SAFE_FP" "$SAFE_CHURN_FILE" "$NUDGE_COUNT"
  exit 2
fi
