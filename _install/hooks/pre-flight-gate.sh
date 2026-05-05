#!/bin/bash
# pre-flight-gate.sh — PreToolUse hook (Write|Edit)
# Blocks writes until agent passes MCQ derived from watcher slot.
# Runs AFTER pre-write-gate.sh (watcher/cron enforcement).
# Exit 0 = allowed, Exit 2 = blocked
#
# Exemptions: .claude/pre-flight/, .openclaw/watchers/, .claude/state/

# --- Read tool input from stdin ---
INPUT=$(cat)
TARGET_FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null)

# --- Exemptions ---
# Normalize target for comparison
TARGET_NORM=$(printf '%s' "$TARGET_FILE" | tr '\\' '/' | tr '[:upper:]' '[:lower:]')

# Exempt: pre-flight directory (agent needs to write response.md)
if printf '%s' "$TARGET_NORM" | grep -qF '.claude/pre-flight/'; then
  exit 0
fi
if printf '%s' "$TARGET_NORM" | grep -qF 'pre-flight/'; then
  exit 0
fi

# --- HARD BLOCK: Phase validation failed — agent MUST address before continuing ---
STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
PHASE_FB="${STATE_DIR}/phase-feedback.md"
if [ -f "$PHASE_FB" ] && grep -qF "FAIL" "$PHASE_FB" 2>/dev/null; then
  # Allow writes to harness infrastructure paths (needed for phase transitions)
  for FB_PAT in '.claude/state/' '.openclaw/watchers/' '.claude/contracts/' '.claude/specs/' '.claude/pre-flight/' '.agent-memory/' 'agentwiki/'; do
    if printf '%s' "$TARGET_NORM" | grep -qiF "$FB_PAT"; then
      exit 0
    fi
  done
  # Block source code writes until feedback is addressed
  printf "BLOCKED: Phase validation FAILED. You MUST fix the issue before writing more code.\n\n" >&2
  printf "READ this file NOW:  .claude/state/phase-feedback.md\n\n" >&2
  cat "$PHASE_FB" >&2
  printf "\n\nTo unblock: fix the failure, then write phase-complete-marker.md to re-trigger validation.\n" >&2
  printf "The gate will re-validate. If it passes, phase-feedback.md is removed and writes resume.\n" >&2
  exit 2
fi

# Exempt: watcher slot files — UNLESS this is a step check-off (Edit with [x])
if printf '%s' "$TARGET_NORM" | grep -qF '.openclaw/watchers/'; then
  TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
  if [ "$TOOL_NAME" = "Edit" ]; then
    OLD_STR=$(printf '%s' "$INPUT" | jq -r '.tool_input.old_string // ""' 2>/dev/null)
    NEW_STR=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // ""' 2>/dev/null)
    if printf '%s' "$OLD_STR" | grep -qF '[ ]' && printf '%s' "$NEW_STR" | grep -qF '[x]'; then
      # Step check-off detected — fall through to step completion gate below
      :
    else
      exit 0  # Normal watcher edit — exempt
    fi
  else
    exit 0  # Write to watcher — exempt
  fi
fi

# Exempt: harness state files (phase markers, progress notes)
if printf '%s' "$TARGET_NORM" | grep -qF '.claude/state/'; then
  exit 0
fi

# Exempt: wiki files (AgentWiki vault pages)
if printf '%s' "$TARGET_NORM" | grep -qiF 'agentwiki/'; then
  exit 0
fi

# --- Step completion gate: block [x] check-off without verification ---
if printf '%s' "$TARGET_NORM" | grep -qF '.openclaw/watchers/slot-'; then
  # We reach here only for Edit check-offs ([ ] -> [x])
  STEP_TEXT=$(printf '%s' "$NEW_STR" | grep -F '[x]' | head -1 | sed 's/^[[:space:]]*- \[x\][[:space:]]*//')

  # Trivial steps don't need verification
  TRIVIAL_PATTERN='[Rr]ead|[Ss]earch|[Ee]xplore|[Ss]et up|[Cc]laim|[Ll]oad|[Ll]ist'
  if printf '%s' "$STEP_TEXT" | grep -qE "$TRIVIAL_PATTERN"; then
    exit 0  # Trivial step — allow without ledger check
  fi

  # Check verification ledger for matching entry
  LEDGER=".claude/state/verification-ledger.jsonl"
  STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
  if [ -f "$LEDGER" ]; then
    MATCH_PREFIX=$(printf '%s' "$STEP_TEXT" | head -c 30 | tr '[:upper:]' '[:lower:]')
    # Extract content words from step text (strip step numbering and short words)
    STEP_CONTENT=$(printf '%s' "$STEP_TEXT" | sed 's/^[Ss]tep [0-9a-z]*[:.[:space:]]*//' | tr '[:upper:]' '[:lower:]')
    # Match against step field OR prompt_snippet field (covers sub-steps like "Step 1a: Micro labels")
    LEDGER_MATCH="false"
    if grep -iF "$MATCH_PREFIX" "$LEDGER" >/dev/null 2>&1; then
      LEDGER_MATCH="true"
    else
      # Try matching each significant word (4+ chars) from the step — need 2+ hits on same line
      WORD_HITS=0
      for SWORD in $STEP_CONTENT; do
        [ ${#SWORD} -lt 4 ] && continue
        if grep -iF "$SWORD" "$LEDGER" >/dev/null 2>&1; then
          WORD_HITS=$((WORD_HITS + 1))
        fi
      done
      [ "$WORD_HITS" -ge 2 ] && LEDGER_MATCH="true"
    fi
    if [ "$LEDGER_MATCH" = "true" ]; then
      # Ledger match found — check verification type satisfaction
      LEDGER_VTYPE=$(grep -iF "$MATCH_PREFIX" "$LEDGER" | tail -1 | jq -r '.verification_type // "review"' 2>/dev/null)
      [ -z "$LEDGER_VTYPE" ] && LEDGER_VTYPE="review"
      TYPE_OK="true"
      if [ -f "${STATE_DIR}/unverified-writes.jsonl" ]; then
        STEP_CLS_TMP=$(mktemp)
        bash "$HOME/.claude/scripts/classify-verification-need.sh" > "$STEP_CLS_TMP" 2>/dev/null
        if [ -s "$STEP_CLS_TMP" ]; then
          for REQ in $(jq -r '.required[]' "$STEP_CLS_TMP" | tr -d '\r'); do
            case "$REQ" in
              vision)     case "$LEDGER_VTYPE" in vision|browser) ;; *) TYPE_OK="false" ;; esac ;;
              functional) case "$LEDGER_VTYPE" in functional|vision|browser) ;; *) TYPE_OK="false" ;; esac ;;
              browser)    [ "$LEDGER_VTYPE" = "browser" ] || TYPE_OK="false" ;;
              review)     ;;
            esac
          done
        fi
        rm -f "$STEP_CLS_TMP"
      fi
      if [ "$TYPE_OK" = "true" ]; then
        exit 0  # Matching ledger entry with sufficient verification type — allow
      fi
      # Type mismatch — fall through to block with prescription
    fi
  fi

  # No match or type mismatch — block with prescription
  printf "BLOCKED: You cannot mark this step complete without independent verification.\n" >&2
  printf "Step: %s\n\n" "$STEP_TEXT" >&2
  # Include prescriptive file list if available
  if [ -f "${STATE_DIR}/unverified-writes.jsonl" ]; then
    RX_TMP=$(mktemp)
    bash "$HOME/.claude/scripts/classify-verification-need.sh" > "$RX_TMP" 2>/dev/null
    if [ -s "$RX_TMP" ]; then
      printf "Files modified since last verification:\n" >&2
      jq -r '.files[] | "  - " + .file + "  -> requires " + (.type | ascii_upcase) + " validation"' "$RX_TMP" >&2
      printf "\n" >&2
      jq -r '"Required: " + .prescription' "$RX_TMP" >&2
      printf "\n\n" >&2
    fi
    rm -f "$RX_TMP"
  fi
  printf "Spawn a subagent with the appropriate verification type.\n" >&2
  printf "  Include 'verify' + specific method (test, screenshot, curl, etc.) in the prompt.\n" >&2
  exit 2
fi

# --- Check if watcher is active for this project ---
WATCHER_REGISTRY="$HOME/.openclaw/watchers/REGISTRY.json"
CURRENT_PROJECT=$(pwd -W 2>/dev/null || pwd)
CURRENT_PROJECT=$(printf '%s' "$CURRENT_PROJECT" | tr '\\' '/' | sed 's|/$||' | tr '[:upper:]' '[:lower:]')

if [ ! -f "$WATCHER_REGISTRY" ]; then
  # No registry — let pre-write-gate handle enforcement
  exit 0
fi

ACTIVE_WATCHERS=$(jq --arg proj "$CURRENT_PROJECT" \
  '[.watchers[] | select(.status == "active" and .project != null and ((.project | gsub("\\\\";"/") | sub("/$";"") | ascii_downcase) == $proj))] | length' \
  "$WATCHER_REGISTRY" 2>/dev/null || printf "0")

if [ "$ACTIVE_WATCHERS" -eq 0 ]; then
  # No active watcher — defer to pre-write-gate.sh
  exit 0
fi

# --- Counter logic: only fire gate every 4th write, or on step change ---
COUNTER_FILE=".claude/pre-flight/gate-counter.json"

# Step 1: Read counter file (initialize if missing or corrupt)
if [ -f "$COUNTER_FILE" ]; then
  WRITE_COUNT=$(jq -r '.write_count // 0' "$COUNTER_FILE" 2>/dev/null) || WRITE_COUNT=0
  LAST_STEP=$(jq -r '.last_step // ""' "$COUNTER_FILE" 2>/dev/null) || LAST_STEP=""
  if ! [[ "$WRITE_COUNT" =~ ^[0-9]+$ ]]; then
    WRITE_COUNT=0
    LAST_STEP=""
  fi
else
  WRITE_COUNT=0
  LAST_STEP=""
fi

# Step 2: Look up active slot file
SLOT_NUM=$(jq -r --arg proj "$CURRENT_PROJECT" \
  '[.watchers[] | select(.status == "active" and .project != null and ((.project | gsub("\\\\";"/") | sub("/$";"") | ascii_downcase) == $proj))] | .[0].slot' \
  "$WATCHER_REGISTRY" 2>/dev/null)
SLOT_FILE="$HOME/.openclaw/watchers/slot-${SLOT_NUM}.md"

# Step 3: Extract current step (first unchecked TO-DO item)
CURRENT_STEP=""
if [ -f "$SLOT_FILE" ]; then
  CURRENT_STEP=$(sed -n '/## TO-DO/,/^## /{/^## /d;p;}' "$SLOT_FILE" | grep -F -- '- [ ]' | head -1 | sed 's/^[[:space:]]*- \[ \][[:space:]]*//')
fi

# Step 4: If no unchecked items, use sentinel
if [ -z "$CURRENT_STEP" ]; then
  CURRENT_STEP="(no unchecked steps remain)"
fi

# Step 5: If step changed, reset counter and fire gate
if [ "$CURRENT_STEP" != "$LAST_STEP" ]; then
  WRITE_COUNT=0
  LAST_STEP="$CURRENT_STEP"
  # Fall through to MCQ check (gate fires)
# Step 6: If write_count % 4 == 0, fire gate
elif [ $((WRITE_COUNT % 4)) -eq 0 ]; then
  :
  # Fall through to MCQ check (gate fires)
# Step 7: Otherwise, allow without MCQ
else
  WRITE_COUNT=$((WRITE_COUNT + 1))
  mkdir -p .claude/pre-flight
  jq -n --argjson wc "$WRITE_COUNT" --arg ls "$LAST_STEP" \
    '{"write_count": $wc, "last_step": $ls}' > "$COUNTER_FILE"
  exit 0
fi

# Save counter state before MCQ check (ensures corrupt/missing files are re-created)
mkdir -p .claude/pre-flight
jq -n --argjson wc "$WRITE_COUNT" --arg ls "$LAST_STEP" \
  '{"write_count": $wc, "last_step": $ls}' > "$COUNTER_FILE"

# --- Check for valid pre-flight response ---
PREFLIGHT_DIR=".claude/pre-flight"
RESPONSE_FILE="$PREFLIGHT_DIR/response.md"
CHALLENGE_FILE="$PREFLIGHT_DIR/challenge.md"

# If response exists, try to validate it
if [ -f "$RESPONSE_FILE" ] && [ -f "$CHALLENGE_FILE" ]; then
  VALIDATE_OUTPUT=$(bash "$HOME/.claude/scripts/validate-pre-flight.sh" 2>&1)
  VALIDATE_EXIT=$?
  if [ $VALIDATE_EXIT -eq 0 ]; then
    # Validation passed — files consumed, allow write
    # Step 8: Increment counter and save after MCQ pass
    WRITE_COUNT=$((WRITE_COUNT + 1))
    mkdir -p .claude/pre-flight
    jq -n --argjson wc "$WRITE_COUNT" --arg ls "$LAST_STEP" \
      '{"write_count": $wc, "last_step": $ls}' > "$COUNTER_FILE"
    exit 0
  else
    # Validation failed — show feedback, regenerate challenge, block
    printf "PRE-FLIGHT CHECK FAILED:\n%s\n\n" "$VALIDATE_OUTPUT" >&2
    # Remove the bad response so agent must re-answer
    rm -f "$RESPONSE_FILE"
  fi
fi

# --- Generate fresh challenge and block ---
bash "$HOME/.claude/scripts/generate-pre-flight-challenge.sh" "$TARGET_FILE" 2>/dev/null

if [ -f "$CHALLENGE_FILE" ]; then
  printf "BLOCKED: Pre-flight check required before writing.\n\n" >&2
  printf "Before you can write to: %s\n\n" "$TARGET_FILE" >&2
  printf "1. READ your challenge: .claude/pre-flight/challenge.md\n" >&2
  printf "2. WRITE your answers to: .claude/pre-flight/response.md\n" >&2
  printf "   Format:\n" >&2
  printf "   Q1: A\n" >&2
  printf "   Q2: B\n" >&2
  printf "   Q3: C\n" >&2
  printf "   Q4: D\n\n" >&2
  printf "3. Then retry your Write/Edit — the gate will validate and allow if correct.\n" >&2
else
  printf "BLOCKED: Pre-flight challenge generation failed. Check watcher slot.\n" >&2
fi

exit 2
