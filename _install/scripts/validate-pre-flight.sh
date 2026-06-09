#!/bin/bash
# validate-pre-flight.sh — Layer 2 Pre-Flight Response Validator
# Re-derives correct answers from watcher slot + challenge.md. No stored key.
#
# Usage: bash validate-pre-flight.sh
# Exit: 0 = pass (files consumed), 1 = fail (stderr says which Q wrong)

# Per-session pre-flight subdir (Sprint 31a): read THIS session's challenge/response. Flat fallback.
PF_SID=$(printf '%s' "${1:-}" | tr -cd 'a-zA-Z0-9-' | head -c 40)
PREFLIGHT_DIR=".claude/pre-flight${PF_SID:+/$PF_SID}"
CHALLENGE_FILE="$PREFLIGHT_DIR/challenge.md"
RESPONSE_FILE="$PREFLIGHT_DIR/response.md"

# --- Check files exist ---
if [ ! -f "$CHALLENGE_FILE" ]; then
  printf "FAIL: No challenge file found at %s\n" "$CHALLENGE_FILE" >&2
  exit 1
fi

if [ ! -f "$RESPONSE_FILE" ]; then
  printf "FAIL: No response file found at %s — read challenge.md and write your answers\n" "$RESPONSE_FILE" >&2
  exit 1
fi

# --- Extract source slot from challenge metadata ---
SLOT_FILE=$(sed -n 's/.*<!-- source_slot: \([^>]*\) -->.*/\1/p' "$CHALLENGE_FILE" 2>/dev/null | head -1 | sed 's/[[:space:]]*$//')

if [ -z "$SLOT_FILE" ] || [ ! -f "$SLOT_FILE" ]; then
  printf "FAIL: Cannot find source watcher slot from challenge metadata\n" >&2
  exit 1
fi

# --- Extract Q5 Yes label from challenge metadata (BEFORE any file deletion) ---
Q5_YES_LABEL=$(sed -n 's/.*<!-- q5_yes_label: \([AB]\).*/\1/p' "$CHALLENGE_FILE" 2>/dev/null | head -1)

# --- Extract correct content from watcher slot (same logic as generator) ---

# Q1 correct: task description
CORRECT_Q1=$(grep -F '**Task**:' "$SLOT_FILE" | head -1 | sed 's/.*\*\*Task\*\*:[[:space:]]*//')
if [ -z "$CORRECT_Q1" ]; then
  CORRECT_Q1="(no task description found)"
fi

# Q2 correct: first unchecked step
CORRECT_Q2=$(sed -n '/## TO-DO/,/^## /{/^## /d;p;}' "$SLOT_FILE" | grep -F -- '- [ ]' | head -1 | sed 's/^[[:space:]]*- \[ \][[:space:]]*//')
if [ -z "$CORRECT_Q2" ]; then
  CORRECT_Q2="(no unchecked steps remain)"
fi

# Q3 correct: target file — extracted from Q3 options in challenge.md
# The generator put the actual target file as one of the options.
# We need to find it. The target file was passed as $1 to the generator.
# We can recover it from the challenge: it's the option that does NOT appear in the distractor pool.
# But simpler: we read stdin from the hook which has the target file.
# Actually simplest: Q3 answer is whichever option in Q3 matches the file the agent is trying to write.
# The hook passes the target file. But the validator doesn't know it at validation time.
# Solution: the challenge.md Q3 correct answer is the real target file.
# We find it by checking which Q3 option is NOT in the distractor pool files.txt.
CORRECT_Q3=""
IN_Q3=0
while IFS= read -r line; do
  if printf '%s' "$line" | grep -qF '## Q3:'; then
    IN_Q3=1
    continue
  fi
  if [ "$IN_Q3" -eq 1 ]; then
    if printf '%s' "$line" | grep -qE '^## Q[0-9]:'; then
      break
    fi
    if printf '%s' "$line" | grep -qE '^[A-D]\) '; then
      OPT_TEXT=$(printf '%s' "$line" | sed 's/^[A-D]) //')
      # Check if this option is NOT in the distractor pool
      if ! grep -qxF "$OPT_TEXT" "$HOME/.openclaw/distractor-pool/files.txt" 2>/dev/null; then
        CORRECT_Q3="$OPT_TEXT"
      fi
    fi
  fi
done < "$CHALLENGE_FILE"

if [ -z "$CORRECT_Q3" ]; then
  # Fallback: if we can't distinguish, accept any answer for Q3
  CORRECT_Q3="__ANY__"
fi

# Q4 correct: mistakes to avoid / out of scope
CORRECT_Q4=""
if grep -qF '## MISTAKES TO AVOID' "$SLOT_FILE"; then
  CORRECT_Q4=$(sed -n '/## MISTAKES TO AVOID/,/^##/{/^##/d;/^$/d;p;}' "$SLOT_FILE" | head -1 | sed 's/^[[:space:]]*-[[:space:]]*//')
fi
if [ -z "$CORRECT_Q4" ] && grep -qF '## OUT OF SCOPE' "$SLOT_FILE"; then
  CORRECT_Q4=$(sed -n '/## OUT OF SCOPE/,/^##/{/^##/d;/^$/d;p;}' "$SLOT_FILE" | head -1 | sed 's/^[[:space:]]*-[[:space:]]*//')
fi
if [ -z "$CORRECT_Q4" ]; then
  CORRECT_Q4="None identified for this task"
fi

# --- For each Q, find which letter (A/B/C/D) contains the correct content ---
find_correct_letter() {
  local q_num="$1"
  local correct_text="$2"
  local section_header="## Q${q_num}:"

  local in_section=0
  while IFS= read -r line; do
    if printf '%s' "$line" | grep -qF "$section_header"; then
      in_section=1
      continue
    fi
    if [ "$in_section" -eq 1 ]; then
      if printf '%s' "$line" | grep -qE '^## Q[0-9]:'; then
        break
      fi
      if printf '%s' "$line" | grep -qE '^[A-D]\) '; then
        local letter=$(printf '%s' "$line" | grep -oE '^[A-D]')
        local opt_text=$(printf '%s' "$line" | sed 's/^[A-D]) //')
        # Use fixed-string matching
        if [ "$opt_text" = "$correct_text" ]; then
          printf '%s' "$letter"
          return
        fi
      fi
    fi
  done < "$CHALLENGE_FILE"
  printf ""
}

CORRECT_LETTER_Q1=$(find_correct_letter 1 "$CORRECT_Q1")
CORRECT_LETTER_Q2=$(find_correct_letter 2 "$CORRECT_Q2")
if [ "$CORRECT_Q3" = "__ANY__" ]; then
  CORRECT_LETTER_Q3="__ANY__"
else
  CORRECT_LETTER_Q3=$(find_correct_letter 3 "$CORRECT_Q3")
fi
CORRECT_LETTER_Q4=$(find_correct_letter 4 "$CORRECT_Q4")

# --- Parse agent's response ---
parse_answer() {
  local q_num="$1"
  grep -iE "^[[:space:]]*Q${q_num}[[:space:]]*:[[:space:]]*[A-Da-d]" "$RESPONSE_FILE" | head -1 | grep -oE '[A-Da-d]' | head -1 | tr '[:lower:]' '[:upper:]'
}

AGENT_Q1=$(parse_answer 1)
AGENT_Q2=$(parse_answer 2)
AGENT_Q3=$(parse_answer 3)
AGENT_Q4=$(parse_answer 4)

# --- Compare ---
FAILURES=0
FAIL_MSG=""

if [ -z "$AGENT_Q1" ]; then
  FAILURES=$((FAILURES + 1))
  FAIL_MSG="${FAIL_MSG}FAIL: Q1 — no answer provided\n"
elif [ "$AGENT_Q1" != "$CORRECT_LETTER_Q1" ]; then
  FAILURES=$((FAILURES + 1))
  FAIL_MSG="${FAIL_MSG}FAIL: Q1 is wrong — re-read your watcher slot task description\n"
fi

if [ -z "$AGENT_Q2" ]; then
  FAILURES=$((FAILURES + 1))
  FAIL_MSG="${FAIL_MSG}FAIL: Q2 — no answer provided\n"
elif [ "$AGENT_Q2" != "$CORRECT_LETTER_Q2" ]; then
  FAILURES=$((FAILURES + 1))
  FAIL_MSG="${FAIL_MSG}FAIL: Q2 is wrong — re-read your watcher slot checklist for the current step\n"
fi

if [ "$CORRECT_LETTER_Q3" != "__ANY__" ]; then
  if [ -z "$AGENT_Q3" ]; then
    FAILURES=$((FAILURES + 1))
    FAIL_MSG="${FAIL_MSG}FAIL: Q3 — no answer provided\n"
  elif [ "$AGENT_Q3" != "$CORRECT_LETTER_Q3" ]; then
    FAILURES=$((FAILURES + 1))
    FAIL_MSG="${FAIL_MSG}FAIL: Q3 is wrong — check which file you are actually editing\n"
  fi
fi

if [ -z "$AGENT_Q4" ]; then
  FAILURES=$((FAILURES + 1))
  FAIL_MSG="${FAIL_MSG}FAIL: Q4 — no answer provided\n"
elif [ "$AGENT_Q4" != "$CORRECT_LETTER_Q4" ]; then
  FAILURES=$((FAILURES + 1))
  FAIL_MSG="${FAIL_MSG}FAIL: Q4 is wrong — re-read your watcher slot mistakes to avoid\n"
fi

# --- Q5: Verification self-report (no wrong answer, but tracks behavior) ---
AGENT_Q5=$(parse_answer 5)
VERIFY_COUNTER=".claude/pre-flight/verify-counter.json"

# Read current counter state
if [ -f "$VERIFY_COUNTER" ]; then
  NO_COUNT=$(jq -r '.no_verify_count // 0' "$VERIFY_COUNTER" 2>/dev/null) || NO_COUNT=0
  HARDENED=$(jq -r '.hardened // false' "$VERIFY_COUNTER" 2>/dev/null) || HARDENED="false"
  LAST_RESET=$(jq -r '.last_reset // ""' "$VERIFY_COUNTER" 2>/dev/null) || LAST_RESET=""
  if ! [[ "$NO_COUNT" =~ ^[0-9]+$ ]]; then NO_COUNT=0; fi
else
  NO_COUNT=0
  HARDENED="false"
  LAST_RESET=""
fi

# Check hardened state BEFORE processing Q5
if [ "$HARDENED" = "true" ]; then
  LEDGER=".claude/state/verification-ledger.jsonl"
  HAS_NEW_ENTRY="false"
  if [ -f "$LEDGER" ] && [ -n "$LAST_RESET" ]; then
    LATEST_TS=$(tail -1 "$LEDGER" | jq -r '.ts // ""' 2>/dev/null)
    if [ -n "$LATEST_TS" ] && [[ "$LATEST_TS" > "$LAST_RESET" ]]; then
      HAS_NEW_ENTRY="true"
    fi
  fi
  if [ "$HAS_NEW_ENTRY" = "false" ]; then
    FAILURES=$((FAILURES + 1))
    FAIL_MSG="${FAIL_MSG}BLOCKED: You have answered 'no verification needed' 5 times without spawning a verification subagent. You MUST use the Agent tool to spawn an independent verifier before continuing. The Agent prompt must include verification language (verify, review, evaluate, validate, audit, assess).\n"
    # Add prescriptive guidance based on modified files
    HSTATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
    if [ -f "${HSTATE_DIR}/unverified-writes.jsonl" ]; then
      H_RX_TMP=$(mktemp)
      bash "$HOME/.claude/scripts/classify-verification-need.sh" > "$H_RX_TMP" 2>/dev/null
      if [ -s "$H_RX_TMP" ]; then
        HFILES=$(jq -r '.files[] | "  - " + .file + "  -> requires " + (.type | ascii_upcase) + " validation"' "$H_RX_TMP")
        HREQ=$(jq -r '.prescription' "$H_RX_TMP")
        FAIL_MSG="${FAIL_MSG}Files modified since last verification:\n${HFILES}\n${HREQ}\n"
      fi
      rm -f "$H_RX_TMP"
    fi
  fi
fi

# Process Q5 answer (only if Q1-Q4 passed and not hardened-blocked)
if [ "$FAILURES" -eq 0 ] && [ -n "$AGENT_Q5" ] && [ -n "$Q5_YES_LABEL" ]; then
  if [ "$AGENT_Q5" = "$Q5_YES_LABEL" ]; then
    # Agent said "Yes" — needs verification
    printf "NUDGE: You acknowledged unverified work. Spawn an independent subagent (Agent tool) to verify before continuing.\n" >&2
  else
    # Agent said "No" — increment counter
    NO_COUNT=$((NO_COUNT + 1))
    if [ "$NO_COUNT" -ge 5 ]; then
      HARDENED="true"
    fi
  fi
  # Save counter (ISO 8601 for lexicographic comparison)
  mkdir -p .claude/pre-flight
  jq -n --argjson nc "$NO_COUNT" --arg h "$HARDENED" --arg lr "$LAST_RESET" \
    '{"no_verify_count": $nc, "hardened": ($h == "true"), "last_reset": $lr}' > "$VERIFY_COUNTER"
fi

# --- Q6+: Must-do reference questions (variable count, only when project has must-do files) ---
MD_Q=6
while true; do
  MDQ_CORRECT=$(sed -n "s/.*<!-- q${MD_Q}_correct_label: \([A-D]\).*/\1/p" "$CHALLENGE_FILE" 2>/dev/null | head -1)
  [ -z "$MDQ_CORRECT" ] && break
  MDQ_SOURCE=$(sed -n "s/.*<!-- q${MD_Q}_source: \([^>]*\) -->.*/\1/p" "$CHALLENGE_FILE" 2>/dev/null | head -1 | sed 's/[[:space:]]*$//')
  AGENT_MDQ=$(parse_answer "$MD_Q")
  if [ -z "$AGENT_MDQ" ]; then
    FAILURES=$((FAILURES + 1))
    FAIL_MSG="${FAIL_MSG}FAIL: Q${MD_Q} — no answer provided. This project has REQUIRED READING. Read ${MDQ_SOURCE:-the must-do reference files} and answer.\n"
  elif [ "$AGENT_MDQ" != "$MDQ_CORRECT" ]; then
    FAILURES=$((FAILURES + 1))
    FAIL_MSG="${FAIL_MSG}FAIL: Q${MD_Q} is wrong — you MUST READ ${MDQ_SOURCE:-the must-do reference files}. Open the file and read it before continuing.\n"
  fi
  MD_Q=$((MD_Q + 1))
done

if [ "$FAILURES" -gt 0 ]; then
  printf "%b" "$FAIL_MSG" >&2
  exit 1
fi

# --- PASS: consume the challenge and response ---
rm -f "$CHALLENGE_FILE" "$RESPONSE_FILE"
printf "PASS: Pre-flight validated. Challenge consumed.\n" >&2
exit 0
