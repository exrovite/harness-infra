#!/bin/bash
# generate-pre-flight-challenge.sh — Layer 2 Pre-Flight Challenge Generator
# Reads active watcher slot, generates 4 MCQ questions with rotating distractors.
# No answer key stored — validator re-derives correct answers at validation time.
#
# Usage: bash generate-pre-flight-challenge.sh <target_file_path>
# Output: Writes .claude/pre-flight/challenge.md

TARGET_FILE="${1:-(unknown)}"
# Per-session pre-flight subdir (Sprint 31a): concurrent agents must not share challenge/response files
# (sharing caused a regenerate/file-rotation thrash). Falls back to flat .claude/pre-flight when no session.
PF_SID=$(printf '%s' "${2:-}" | tr -cd 'a-zA-Z0-9-' | head -c 40)
STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
PREFLIGHT_DIR=".claude/pre-flight${PF_SID:+/$PF_SID}"
WATCHER_REGISTRY="$HOME/.openclaw/watchers/REGISTRY.json"
DISTRACTOR_POOL="$HOME/.openclaw/distractor-pool"

# --- Find active watcher slot for this project ---
CURRENT_PROJECT=$(pwd -W 2>/dev/null || pwd)
CURRENT_PROJECT=$(printf '%s' "$CURRENT_PROJECT" | tr '\\' '/' | sed 's|/$||' | tr '[:upper:]' '[:lower:]')

if [ ! -f "$WATCHER_REGISTRY" ]; then
  printf "generate-pre-flight-challenge: no watcher registry found\n" >&2
  exit 1
fi

# Find the slot number for this project
SLOT_NUM=$(jq --arg proj "$CURRENT_PROJECT" \
  '[.watchers[] | select(.status == "active" and .project != null and ((.project | gsub("\\\\";"/") | sub("/$";"") | ascii_downcase) == $proj))] | .[0].slot // empty' \
  "$WATCHER_REGISTRY" 2>/dev/null)

if [ -z "$SLOT_NUM" ]; then
  printf "generate-pre-flight-challenge: no active watcher for this project\n" >&2
  exit 1
fi

SLOT_FILE="$HOME/.openclaw/watchers/slot-${SLOT_NUM}.md"

if [ ! -f "$SLOT_FILE" ]; then
  printf "generate-pre-flight-challenge: watcher slot file not found: %s\n" "$SLOT_FILE" >&2
  exit 1
fi

# --- Extract content from watcher slot ---

# Task description (line starting with **Task**:)
TASK_DESC=$(grep -F '**Task**:' "$SLOT_FILE" | head -1 | sed 's/.*\*\*Task\*\*:[[:space:]]*//')
if [ -z "$TASK_DESC" ]; then
  TASK_DESC="(no task description found)"
fi

# Current step (first unchecked - [ ] item, header-agnostic)
CURRENT_STEP=$(sed -n '/## TO-DO/,/^## /{/^## /d;p;}' "$SLOT_FILE" | grep -F -- '- [ ]' | head -1 | sed 's/^[[:space:]]*- \[ \][[:space:]]*//')
if [ -z "$CURRENT_STEP" ]; then
  CURRENT_STEP="(no unchecked steps remain)"
fi

# Mistakes to avoid / out of scope (first non-empty line after the section header)
MISTAKES=""
if grep -qF '## MISTAKES TO AVOID' "$SLOT_FILE"; then
  MISTAKES=$(sed -n '/## MISTAKES TO AVOID/,/^##/{/^##/d;/^$/d;p;}' "$SLOT_FILE" | head -1 | sed 's/^[[:space:]]*-[[:space:]]*//')
fi
if [ -z "$MISTAKES" ] && grep -qF '## OUT OF SCOPE' "$SLOT_FILE"; then
  MISTAKES=$(sed -n '/## OUT OF SCOPE/,/^##/{/^##/d;/^$/d;p;}' "$SLOT_FILE" | head -1 | sed 's/^[[:space:]]*-[[:space:]]*//')
fi
if [ -z "$MISTAKES" ]; then
  MISTAKES="None identified for this task"
fi

# --- Ensure pre-flight directory exists ---
mkdir -p "$PREFLIGHT_DIR"

# --- Helper: shuffle and pick position ---
# Given correct answer and 3 distractors, output 4 lines in random order
# and print which position (A/B/C/D) the correct answer landed on
shuffle_options() {
  local correct="$1"
  local d1="$2"
  local d2="$3"
  local d3="$4"

  # Create temp file with all 4 options, mark correct with a prefix
  local tmpf
  tmpf=$(mktemp)
  printf "CORRECT_MARK|%s\n" "$correct" > "$tmpf"
  printf "DISTRACT|%s\n" "$d1" >> "$tmpf"
  printf "DISTRACT|%s\n" "$d2" >> "$tmpf"
  printf "DISTRACT|%s\n" "$d3" >> "$tmpf"

  # Shuffle
  local shuffled
  shuffled=$(shuf "$tmpf")

  local labels=("A" "B" "C" "D")
  local idx=0
  local correct_label=""

  while IFS= read -r line; do
    local marker="${line%%|*}"
    local text="${line#*|}"
    printf "%s) %s\n" "${labels[$idx]}" "$text"
    if [ "$marker" = "CORRECT_MARK" ]; then
      correct_label="${labels[$idx]}"
    fi
    idx=$((idx + 1))
  done <<< "$shuffled"

  rm -f "$tmpf"
  # Return correct label via fd 3
  printf "%s" "$correct_label" >&3
}

# --- Pick distractors from pool ---
pick_distractors() {
  local pool_file="$1"
  local exclude="$2"
  if [ -f "$pool_file" ]; then
    grep -vxF -- "$exclude" "$pool_file" 2>/dev/null | shuf -n 3
  else
    printf "Option alpha\nOption beta\nOption gamma\n"
  fi
}

# --- Helper: shuffle 2 binary options (Yes/No) ---
shuffle_binary() {
  local opt_yes="$1"
  local opt_no="$2"
  local tmpf
  tmpf=$(mktemp)
  printf "CORRECT_MARK|%s\n" "$opt_yes" > "$tmpf"
  printf "DISTRACT|%s\n" "$opt_no" >> "$tmpf"
  local shuffled
  shuffled=$(shuf "$tmpf")
  local labels=("A" "B")
  local idx=0
  local correct_label=""
  while IFS= read -r line; do
    local marker="${line%%|*}"
    local text="${line#*|}"
    printf "%s) %s\n" "${labels[$idx]}" "$text"
    if [ "$marker" = "CORRECT_MARK" ]; then
      correct_label="${labels[$idx]}"
    fi
    idx=$((idx + 1))
  done <<< "$shuffled"
  rm -f "$tmpf"
  printf "%s" "$correct_label" >&3
}

# --- Generate Q1: Ground Truth (task) ---
mapfile -t Q1_DIST < <(pick_distractors "$DISTRACTOR_POOL/tasks.txt" "$TASK_DESC")
Q1_CORRECT_LABEL=""
Q1_OPTIONS=$(shuffle_options "$TASK_DESC" "${Q1_DIST[0]}" "${Q1_DIST[1]}" "${Q1_DIST[2]}" 3>/tmp/pf_q1_label)
Q1_CORRECT_LABEL=$(cat /tmp/pf_q1_label 2>/dev/null)

# --- Generate Q2: Protocol (current step) ---
mapfile -t Q2_DIST < <(pick_distractors "$DISTRACTOR_POOL/steps.txt" "$CURRENT_STEP")
Q2_OPTIONS=$(shuffle_options "$CURRENT_STEP" "${Q2_DIST[0]}" "${Q2_DIST[1]}" "${Q2_DIST[2]}" 3>/tmp/pf_q2_label)
Q2_CORRECT_LABEL=$(cat /tmp/pf_q2_label 2>/dev/null)

# --- Generate Q3: Changes Planned (target file) ---
mapfile -t Q3_DIST < <(pick_distractors "$DISTRACTOR_POOL/files.txt" "$TARGET_FILE")
Q3_OPTIONS=$(shuffle_options "$TARGET_FILE" "${Q3_DIST[0]}" "${Q3_DIST[1]}" "${Q3_DIST[2]}" 3>/tmp/pf_q3_label)
Q3_CORRECT_LABEL=$(cat /tmp/pf_q3_label 2>/dev/null)

# --- Generate Q4: Mistakes to Avoid ---
mapfile -t Q4_DIST < <(pick_distractors "$DISTRACTOR_POOL/constraints.txt" "$MISTAKES")
Q4_OPTIONS=$(shuffle_options "$MISTAKES" "${Q4_DIST[0]}" "${Q4_DIST[1]}" "${Q4_DIST[2]}" 3>/tmp/pf_q4_label)
Q4_CORRECT_LABEL=$(cat /tmp/pf_q4_label 2>/dev/null)

# --- Generate Q5: Verification self-report ---
Q5_YES="Yes — I completed work that an independent subagent should check"
Q5_NO="No — all work since the last gate was trivial or already verified"
Q5_OPTIONS=$(shuffle_binary "$Q5_YES" "$Q5_NO" 3>/tmp/pf_q5_label)
Q5_YES_LABEL=$(cat /tmp/pf_q5_label 2>/dev/null)

# --- Write challenge.md ---
cat > "$PREFLIGHT_DIR/challenge.md" << CHALLENGE
<!-- source_slot: $SLOT_FILE -->
<!-- q5_yes_label: $Q5_YES_LABEL -->

# Pre-Flight Challenge

>>> STOP. READ THIS FIRST — DO NOT GUESS. <<<
This is NOT an obstacle to bypass and NOT a quiz to pass. It is a checkpoint that exists to KEEP YOU
ON TASK and to catch where you may have drifted or misunderstood — a moment to confirm you are still
building the right thing, in the right file, within scope. Treat it as a useful self-check that is on
your side: answering it honestly by reading is how you discover, early, what you might be getting
wrong before you waste effort. Its job is to make you LOAD YOUR CONTEXT (your real task, current step,
target file, scope, and any reference files) before you write code.
Answer ONLY by reading, never from memory or from your previous answers:
  • READ THIS challenge.md FRESH every attempt. It is REGENERATED AND RESHUFFLED on each wrong
    answer, so option letters change and any previous answer you remember is now WRONG.
  • OPEN AND READ your watcher slot for Q1-Q4 (task / current step / target file / what to avoid).
  • For any "Qn: you MUST READ <file>" line, OPEN that exact file and read it before answering.
Guessing just reshuffles the challenge and burns tokens in a loop. Read once, answer once, proceed.

Answer all 5 questions. Write your answers to ${PREFLIGHT_DIR}/response.md in format:
Q1: A
Q2: B
Q3: C
Q4: D
Q5: A

---

## Q1: What is your current task?
$Q1_OPTIONS

## Q2: Which step are you currently on?
$Q2_OPTIONS

## Q3: What file should this edit target?
$Q3_OPTIONS

## Q4: What should you avoid or what is out of scope?
$Q4_OPTIONS

## Q5: Have you done work since the last gate that should be independently verified?
$Q5_OPTIONS
CHALLENGE

# --- Detect must-do reference files ---
MUST_DO_MD=""
for CAND_DIR in "docs/must do" "docs/must-do" ".claude/must-do"; do
  if [ -d "$CAND_DIR" ]; then
    MUST_DO_MD=$(find "$CAND_DIR" -maxdepth 1 -name "*.md" -type f 2>/dev/null | head -1)
    [ -n "$MUST_DO_MD" ] && break
  fi
done

MUST_DO_COUNT=0

if [ -n "$MUST_DO_MD" ]; then
  # Resolve each line to one file path (directories pick one random .md inside)
  MUST_DO_RESOLVED=()
  USED_PATHS=""
  while IFS= read -r mdline || [ -n "$mdline" ]; do
    mdline=$(printf '%s' "$mdline" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$mdline" ] && continue
    case "$mdline" in '<!--'*|'#'*|'---'*|*mustdo-session:*) continue ;; esac  # skip stamp/comment (Sprint 37)
    upath=$(printf '%s' "$mdline" | tr '\\\\' '/' | sed 's|^\([A-Za-z]\):|/\L\1|')
    if [ -f "$upath" ]; then
      if printf '%s' "$USED_PATHS" | grep -qxF "$upath" 2>/dev/null; then continue; fi
      MUST_DO_RESOLVED+=("$upath")
      USED_PATHS=$(printf '%s\n%s' "$USED_PATHS" "$upath")
    elif [ -d "$upath" ]; then
      DPICK=$(find "$upath" -maxdepth 2 -name "*.md" -type f 2>/dev/null | while IFS= read -r df; do
        if ! printf '%s' "$USED_PATHS" | grep -qxF "$df" 2>/dev/null; then printf '%s\n' "$df"; fi
      done | shuf -n 1)
      if [ -n "$DPICK" ]; then
        MUST_DO_RESOLVED+=("$DPICK")
        USED_PATHS=$(printf '%s\n%s' "$USED_PATHS" "$DPICK")
      fi
    fi
  done < "$MUST_DO_MD"

  # Build master distractor pool from ALL resolved files
  ALL_DIST_TMP=$(mktemp)
  for RFILE in "${MUST_DO_RESOLVED[@]}"; do
    grep -v '^[[:space:]]*$' "$RFILE" 2>/dev/null | grep -v '^[[:space:]]*#' | grep -v '^---' \
      | awk 'length > 30 && length < 200' \
      | sed 's/^[[:space:]]*//' | sed 's/\*\*//g' >> "$ALL_DIST_TMP"
  done

  # Generate one question per resolved file
  Q_NUM=6
  for RFILE in "${MUST_DO_RESOLVED[@]}"; do
    RBASENAME=$(basename "$RFILE")

    # Extract significant lines — prioritize directives, fall back to any content
    SIG_LINES=$(grep -iE '(NEVER|ALWAYS|MUST[^a-z]|Rule:|non-negotiable|REQUIRED)' "$RFILE" 2>/dev/null \
      | grep -v '^[[:space:]]*#' | grep -v '^---' | grep -v '^[[:space:]]*$' \
      | awk 'length > 30 && length < 200' \
      | sed 's/^[[:space:]]*//' | sed 's/\*\*//g')

    SIG_COUNT=$(printf '%s' "$SIG_LINES" | grep -c '.' 2>/dev/null || echo 0)
    if [ "$SIG_COUNT" -lt 1 ]; then
      SIG_LINES=$(grep -v '^[[:space:]]*$' "$RFILE" | grep -v '^[[:space:]]*#' | grep -v '^---' \
        | awk 'length > 30 && length < 200' \
        | sed 's/^[[:space:]]*//' | sed 's/\*\*//g')
    fi

    CORRECT_LINE=$(printf '%s\n' "$SIG_LINES" | shuf -n 1)
    [ -z "$CORRECT_LINE" ] && continue

    # Distractors: lines from OTHER files (exclude correct line)
    mapfile -t QN_DIST < <(grep -vxF "$CORRECT_LINE" "$ALL_DIST_TMP" 2>/dev/null | shuf -n 3)
    while [ ${#QN_DIST[@]} -lt 3 ]; do
      QN_DIST+=("This directive does not appear in any required reading file")
    done

    QN_OPTIONS=$(shuffle_options "$CORRECT_LINE" "${QN_DIST[0]}" "${QN_DIST[1]}" "${QN_DIST[2]}" 3>/tmp/pf_q${Q_NUM}_label)
    QN_CORRECT=$(cat /tmp/pf_q${Q_NUM}_label 2>/dev/null)

    if [ -n "$QN_CORRECT" ]; then
      sed -i "2a <!-- q${Q_NUM}_correct_label: ${QN_CORRECT} -->" "$PREFLIGHT_DIR/challenge.md"
      sed -i "3a <!-- q${Q_NUM}_source: ${RBASENAME} -->" "$PREFLIGHT_DIR/challenge.md"

      cat >> "$PREFLIGHT_DIR/challenge.md" << QBLOCK

## Q${Q_NUM}: Which of these statements can be found in ${RBASENAME}?
$QN_OPTIONS
QBLOCK

      MUST_DO_COUNT=$((MUST_DO_COUNT + 1))
      Q_NUM=$((Q_NUM + 1))
    fi
  done

  rm -f "$ALL_DIST_TMP"
fi

# --- Update challenge header for total question count ---
if [ "$MUST_DO_COUNT" -gt 0 ]; then
  TOTAL_Q=$((5 + MUST_DO_COUNT))
  sed -i "s/Answer all 5 questions/Answer all ${TOTAL_Q} questions/" "$PREFLIGHT_DIR/challenge.md"
  # Add Q6+ to the format example
  for i in $(seq 6 $((5 + MUST_DO_COUNT))); do
    sed -i "/^Q5: A$/a Q${i}: A" "$PREFLIGHT_DIR/challenge.md"
  done
fi

printf "Challenge generated at %s\n" "$PREFLIGHT_DIR/challenge.md" >&2
exit 0
