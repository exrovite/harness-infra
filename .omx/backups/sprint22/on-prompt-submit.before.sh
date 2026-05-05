#!/bin/bash
# on-prompt-submit.sh â€” Claude Code UserPromptSubmit hook
# Fires at the START of every Claude turn, injecting a turn packet.
# The packet tells the agent what to read, do, avoid, and finish before it discovers gates by failure.

STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
WATCHER_REGISTRY="$HOME/.openclaw/watchers/REGISTRY.json"
HELPERS="$HOME/.claude/scripts/lib-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS" 2>/dev/null

one_line() {
  tr '\n' ' ' | tr -d '\r' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//'
}

add_read() {
  READS="${READS}- $1
"
}

add_action() {
  ACTION_COUNT=$((ACTION_COUNT + 1))
  ACTIONS="${ACTIONS}${ACTION_COUNT}. $1
"
}

add_block() {
  BLOCKS="${BLOCKS}- $1
"
}

# --- READ PHASE STATE ---
PHASE="UNKNOWN"
SPRINT="0"
ITERATION="0"
if [ -f "${STATE_DIR}/current-phase.json" ] && jq '.' "${STATE_DIR}/current-phase.json" >/dev/null 2>&1; then
  PHASE=$(jq -r '.phase // "UNKNOWN"' "${STATE_DIR}/current-phase.json" 2>/dev/null | tr -d '\r')
  SPRINT=$(jq -r '.sprint // 0' "${STATE_DIR}/current-phase.json" 2>/dev/null | tr -d '\r')
  ITERATION=$(jq -r '.iteration // 0' "${STATE_DIR}/current-phase.json" 2>/dev/null | tr -d '\r')
fi

# --- READ WRITE COUNT ---
WRITES=$(cat "${STATE_DIR}/write-count.txt" 2>/dev/null || printf "0")
WRITES=$(printf '%s' "$WRITES" | grep -o '[0-9]*' | head -1)
WRITES=${WRITES:-0}

# --- PROJECT + WATCHER STATE ---
CURRENT_PROJECT=$(pwd -W 2>/dev/null || pwd)
CURRENT_PROJECT=$(printf '%s' "$CURRENT_PROJECT" | tr '\\' '/' | sed 's|/$||')
CURRENT_PROJECT_NORM=$(printf '%s' "$CURRENT_PROJECT" | tr '[:upper:]' '[:lower:]')

WATCHER_SLOT=""
WATCHER_STATUS="no registry"
WATCHER_CLAIMED_BY=""
WATCHER_CRON_ID=""
WATCHER_CRON_INTERVAL=""
WATCHER_STEP=""
WATCHER_SCOPE=""
WATCHER_MISTAKES=""
WATCHER_DONE=""
TOOLS_LOCKED="false"

if [ -f "$WATCHER_REGISTRY" ]; then
  if type check_watcher_for_project >/dev/null 2>&1; then
    WATCHER_SLOT=$(check_watcher_for_project "$CURRENT_PROJECT" "$WATCHER_REGISTRY")
  else
    WATCHER_SLOT=$(jq -r --arg proj "$CURRENT_PROJECT_NORM" \
      '[.watchers[] | select(.status == "active" and .project != null and ((.project | gsub("\\\\";"/") | sub("/$";"") | ascii_downcase) == $proj))][0].slot // empty' \
      "$WATCHER_REGISTRY" 2>/dev/null | tr -d '\r' | head -1)
  fi

  if [ -n "$WATCHER_SLOT" ]; then
    WATCHER_CLAIMED_BY=$(jq -r --argjson slot "$WATCHER_SLOT" '.watchers[] | select(.slot == $slot) | .claimed_by // "unknown"' "$WATCHER_REGISTRY" 2>/dev/null | tr -d '\r' | head -1)
    WATCHER_CRON_ID=$(jq -r --argjson slot "$WATCHER_SLOT" '.watchers[] | select(.slot == $slot) | .cron_job_id // ""' "$WATCHER_REGISTRY" 2>/dev/null | tr -d '\r' | head -1)
    WATCHER_CRON_INTERVAL=$(jq -r --argjson slot "$WATCHER_SLOT" '.watchers[] | select(.slot == $slot) | .cron_interval // ""' "$WATCHER_REGISTRY" 2>/dev/null | tr -d '\r' | head -1)
    WATCHER_STATUS="slot ${WATCHER_SLOT} by ${WATCHER_CLAIMED_BY:-unknown}"

    SLOT_FILE="$HOME/.openclaw/watchers/slot-${WATCHER_SLOT}.md"
    if type read_watcher_step_scope >/dev/null 2>&1; then
      WATCHER_INFO=$(read_watcher_step_scope "$SLOT_FILE")
      WATCHER_STEP=$(printf '%s\n' "$WATCHER_INFO" | sed -n 's/^STEP=//p' | head -1)
      WATCHER_SCOPE=$(printf '%s\n' "$WATCHER_INFO" | sed -n 's/^SCOPE=//p' | head -1)
      WATCHER_MISTAKES=$(printf '%s\n' "$WATCHER_INFO" | sed -n 's/^MISTAKES=//p' | head -1)
      WATCHER_DONE=$(printf '%s\n' "$WATCHER_INFO" | sed -n 's/^DONE=//p' | head -1)
    fi
  else
    WATCHER_STATUS="not claimed for this project"
    if [ "$WRITES" -ge 2 ]; then
      TOOLS_LOCKED="true"
      WATCHER_STATUS="NOT CLAIMED â€” WRITE/EDIT LOCKED"
    fi
  fi
fi

# --- PACKET SECTIONS ---
READS=""
ACTION_COUNT=0
ACTIONS=""
BLOCKS=""
WARNINGS=""
PENDING_ITEMS=""
GUIDANCE_LINE=""
PROTOCOL_LINE=""
VERIFIER_RULES=""

case "$PHASE" in
  PLAN)
    GUIDANCE_LINE='GUIDANCE: Outcome-first — define result, criteria, constraints, stop condition BEFORE spec. Ambiguous request? Ask — do not assume.' ;;
  NEGOTIATE)
    GUIDANCE_LINE="GUIDANCE: Skeptical reviewer — challenge your proposal. What fails? What's vague? Binary pass/fail criteria. Max 3 self-revisions." ;;
  BUILD)
    GUIDANCE_LINE='GUIDANCE: Executor — proceed on clear, low-risk, reversible steps. ASK only for destructive/irreversible/scope-changing. No "should I continue?" — continue.' ;;
  EVALUATE)
    GUIDANCE_LINE='GUIDANCE: Adversarial verifier — default FAIL. Every criterion needs fresh evidence. Do not read progress-notes.md. No benefit of doubt.'
    VERIFIER_RULES='VERIFIER RULES: 1) Do NOT read .claude/state/progress-notes.md 2) Test from scratch using sprint contract criteria only 3) Default verdict is FAIL — pass requires positive evidence for every criterion 4) Report: criterion number, pass/fail, evidence snippet (file:line or command output)' ;;
  COMPLETE)
    GUIDANCE_LINE='GUIDANCE: Handoff — name outcome (finished/blocked/failed), list evidence, state what user verifies. No "would you like me to..." softeners.' ;;
esac

# --- TASK SIZE ADVISORY ---
# Advisory only: read from watcher SCOPE, never write state.
if [ -n "$WATCHER_SCOPE" ]; then
  WATCHER_SCOPE_LC=$(printf '%s' "$WATCHER_SCOPE" | tr '[:upper:]' '[:lower:]')
  case "$WATCHER_SCOPE_LC" in
    *"new system"*|*"cross-cutting"*|*"multi-feature"*|*"architecture"*|*"refactor all"*|*"migration"*)
      PROTOCOL_LINE='PROTOCOL: Full — PRD artifact (.claude/specs/prd-*.md) and test spec (.claude/specs/test-spec-*.md) required before BUILD.' ;;
    *config*|*typo*|*rename*|*"single file"*|*"one file"*|*"one-line"*|*"env var"*|*"bump version"*)
      PROTOCOL_LINE='PROTOCOL: Lightweight — implement, test, verify inline. No contract or sub-agent verifier required.' ;;
  esac
fi

# Section 2: read-first artifacts.
if [ "$SPRINT" != "0" ] && [ -f ".claude/contracts/sprint-${SPRINT}-contract.md" ]; then
  add_read ".claude/contracts/sprint-${SPRINT}-contract.md"
fi

MUST_DO_DIR=""
if type find_must_do_dir >/dev/null 2>&1; then
  MUST_DO_DIR=$(find_must_do_dir 2>/dev/null)
else
  for CANDIDATE in "docs/must do" "docs/must-do" ".claude/must-do"; do
    [ -d "$CANDIDATE" ] && MUST_DO_DIR="$CANDIDATE" && break
  done
fi
if [ -n "$MUST_DO_DIR" ] && [ ! -f "${STATE_DIR}/must-do-summary.md" ]; then
  if [ -f "${MUST_DO_DIR}/must-do.md" ]; then
    add_read "${MUST_DO_DIR}/must-do.md and referenced docs"
  else
    add_read "${MUST_DO_DIR}/"
  fi
fi

# Section 3: ordered soft action queue.
# Keep non-BUILD phase packets compact; watcher setup matters when code/edit work begins.
if [ "$PHASE" = "BUILD" ]; then
  if [ -z "$WATCHER_SLOT" ]; then
    add_action "Claim watcher: Bash — jq-update ~/.openclaw/watchers/REGISTRY.json and write ~/.openclaw/watchers/slot-N.md"
    add_action "Start reminder: CronCreate — */3 * * * * read your watcher slot"
  elif [ -z "$WATCHER_CRON_ID" ] || [ "$WATCHER_CRON_ID" = "null" ] || [ "$WATCHER_CRON_INTERVAL" = "manual" ]; then
    add_action "Start reminder: CronCreate — */3 * * * * read ~/.openclaw/watchers/slot-${WATCHER_SLOT}.md"
  fi
fi

if { [ "$PHASE" = "NEGOTIATE" ] || [ "$PHASE" = "BUILD" ]; } && [ "$SPRINT" != "0" ] && [ ! -f ".claude/contracts/sprint-${SPRINT}-contract.md" ]; then
  add_action "Write contract: Write â€” .claude/contracts/sprint-${SPRINT}-contract.md"
fi

if [ -n "$MUST_DO_DIR" ] && [ ! -f "${STATE_DIR}/must-do-summary.md" ]; then
  add_action "Write must-do summary: Write â€” .claude/state/must-do-summary.md after reading must-do docs"
fi

# MCQ due detection mirrors pre-flight-gate counter trigger without writing.
if [ -n "$WATCHER_SLOT" ] && [ "$PHASE" = "BUILD" ]; then
  PF_COUNTER=".claude/pre-flight/gate-counter.json"
  PF_WRITE_COUNT=0
  PF_LAST_STEP=""
  if [ -f "$PF_COUNTER" ] && jq '.' "$PF_COUNTER" >/dev/null 2>&1; then
    PF_WRITE_COUNT=$(jq -r '.write_count // 0' "$PF_COUNTER" 2>/dev/null | tr -d '\r')
    PF_LAST_STEP=$(jq -r '.last_step // ""' "$PF_COUNTER" 2>/dev/null | tr -d '\r')
  fi
  if ! printf '%s' "$PF_WRITE_COUNT" | grep -qE '^[0-9]+$'; then PF_WRITE_COUNT=0; fi
  if [ -n "$WATCHER_STEP" ] && { [ "$WATCHER_STEP" != "$PF_LAST_STEP" ] || [ $((PF_WRITE_COUNT % 4)) -eq 0 ]; }; then
    add_action "Note: MCQ gate fires on next gated write â€” read .claude/pre-flight/challenge.md if blocked"
  fi
fi

# Section 4: hard blocks.
case "$PHASE" in
  BUILD|UNKNOWN) ;;
  *) add_block "WRITES LOCKED: ${PHASE} — specs/contracts/state only" ;;
esac

if [ -f "${STATE_DIR}/phase-feedback.md" ] && grep -qF "FAIL" "${STATE_DIR}/phase-feedback.md" 2>/dev/null; then
  add_block "phase-feedback FAIL â€” read .claude/state/phase-feedback.md, fix issues, write .claude/state/phase-complete-marker.md"
fi
if [ -f "${STATE_DIR}/next-fix.md" ]; then
  PENDING_ITEMS="${PENDING_ITEMS}next-fix.md available; "
fi
if [ -f "${STATE_DIR}/watcher-self-check.md" ]; then
  PENDING_ITEMS="${PENDING_ITEMS}watcher self-check needed; "
fi

# Evidence checkpoint: preserve all existing sub-state guidance.
EC_CHECKPOINT="${STATE_DIR}/evidence-checkpoint.json"
if [ -f "$EC_CHECKPOINT" ] && jq -r '.status' "$EC_CHECKPOINT" 2>/dev/null | tr -d '\r' | grep -q "pending"; then
  EC_VERDICT="${STATE_DIR}/evidence-verdict.json"
  if [ -f "$EC_VERDICT" ] && jq '.' "$EC_VERDICT" >/dev/null 2>&1; then
    EC_V=$(jq -r '.verdict // ""' "$EC_VERDICT" 2>/dev/null | tr -d '\r')
    if [ "$EC_V" = "FAIL" ]; then
      EC_RL=0
      if [ -f "${STATE_DIR}/evidence-remediation.md" ]; then
        EC_RL=$(wc -c < "${STATE_DIR}/evidence-remediation.md" 2>/dev/null | tr -d ' ')
      fi
      if [ "$EC_RL" -lt 200 ]; then
        add_block "evidence FAIL â€” read must-do docs and write .claude/state/evidence-remediation.md (200+ chars, failed phases/docs)"
      else
        add_block "evidence FAIL â€” produce evidence in .claude/evidence/, delete evidence-verdict.json, spawn a new verifier"
      fi
    fi
  else
    add_block "evidence checkpoint â€” spawn verifier sub-agent; brief is .claude/state/evidence-checkpoint.json; verdict goes to evidence-verdict.json"
  fi
fi

# Strategy loop fix-cycle accounting. Terminal STUCK can only be reset by user state edit/delete.
SLB_STATE_FILE="${STATE_DIR}/strategy-loop-state.json"
SLB_FIX_CYCLE_COUNT=0
SLB_MAX_FIX_CYCLES=3
SLB_LAST_SPRINT=""
SLB_BLOCKED_VALUE=false
SLB_STATE_WRITE_NEEDED=false
SLB_STATE_VALID=false
SLB_STUCK_ACTIVE=false

write_strategy_loop_state() {
  [ -n "$SLB_STATE_FILE" ] || return 1
  type atomic_write >/dev/null 2>&1 || return 1

  local SOURCE_FILE="$SLB_STATE_FILE"
  if [ ! -f "$SOURCE_FILE" ] || ! jq '.' "$SOURCE_FILE" >/dev/null 2>&1; then
    SOURCE_FILE="/dev/null"
  fi

  local UPDATED
  if [ "$SOURCE_FILE" = "/dev/null" ]; then
    UPDATED=$(jq -cn \
      --argjson fix "$SLB_FIX_CYCLE_COUNT" \
      --argjson max "$SLB_MAX_FIX_CYCLES" \
      --arg sprint "$SPRINT" \
      --argjson blocked "$SLB_BLOCKED_VALUE" \
      '{nudge_count:0,last_nudge_ts:null,last_output_fingerprint:"",last_churn_files:[],blocked:$blocked,fix_cycle_count:$fix,max_fix_cycles:$max,last_sprint:$sprint}' 2>/dev/null | tr -d '\r')
  else
    UPDATED=$(jq -c \
      --argjson fix "$SLB_FIX_CYCLE_COUNT" \
      --argjson max "$SLB_MAX_FIX_CYCLES" \
      --arg sprint "$SPRINT" \
      --argjson blocked "$SLB_BLOCKED_VALUE" \
      '.blocked=$blocked | .fix_cycle_count=$fix | .max_fix_cycles=$max | .last_sprint=$sprint' \
      "$SOURCE_FILE" 2>/dev/null | tr -d '\r')
  fi

  [ -n "$UPDATED" ] || return 1
  atomic_write "$UPDATED" "$SLB_STATE_FILE"
}

if [ -f "$SLB_STATE_FILE" ] && jq '.' "$SLB_STATE_FILE" >/dev/null 2>&1; then
  SLB_FIX_CYCLE_COUNT=$(jq -r '.fix_cycle_count // 0' "$SLB_STATE_FILE" 2>/dev/null | tr -d '\r')
  SLB_MAX_FIX_CYCLES=$(jq -r '.max_fix_cycles // 3' "$SLB_STATE_FILE" 2>/dev/null | tr -d '\r')
  SLB_LAST_SPRINT=$(jq -r '.last_sprint // ""' "$SLB_STATE_FILE" 2>/dev/null | tr -d '\r')
  SLB_BLOCKED_VALUE=$(jq -r '.blocked // false' "$SLB_STATE_FILE" 2>/dev/null | tr -d '\r')
  SLB_STATE_VALID=true
fi
if ! printf '%s' "$SLB_FIX_CYCLE_COUNT" | grep -qE '^[0-9]+$' 2>/dev/null; then SLB_FIX_CYCLE_COUNT=0; fi
if ! printf '%s' "$SLB_MAX_FIX_CYCLES" | grep -qE '^[0-9]+$' 2>/dev/null; then SLB_MAX_FIX_CYCLES=3; fi
if [ "$SLB_MAX_FIX_CYCLES" -lt 1 ]; then SLB_MAX_FIX_CYCLES=3; fi
case "$SLB_BLOCKED_VALUE" in true|false) ;; *) SLB_BLOCKED_VALUE=false ;; esac

if [ "$SLB_STATE_VALID" = true ] && [ -n "$SLB_LAST_SPRINT" ] && [ "$SLB_LAST_SPRINT" != "null" ] && [ "$SLB_LAST_SPRINT" != "$SPRINT" ]; then
  SLB_FIX_CYCLE_COUNT=0
  SLB_BLOCKED_VALUE=false
  SLB_STATE_WRITE_NEEDED=true
fi
if [ "$SLB_STATE_VALID" = true ] && [ "$SLB_LAST_SPRINT" != "$SPRINT" ]; then
  SLB_STATE_WRITE_NEEDED=true
fi

if [ "$SLB_STATE_VALID" = true ] && [ "$SLB_FIX_CYCLE_COUNT" -lt "$SLB_MAX_FIX_CYCLES" ] && [ "$SLB_BLOCKED_VALUE" = "true" ] && [ -f "${STATE_DIR}/strategy-ack.md" ]; then
  SLB_FIX_CYCLE_COUNT=$((SLB_FIX_CYCLE_COUNT + 1))
  SLB_BLOCKED_VALUE=false
  SLB_STATE_WRITE_NEEDED=true
fi

if [ "$SLB_STATE_WRITE_NEEDED" = true ]; then
  write_strategy_loop_state
fi

if [ "$SLB_FIX_CYCLE_COUNT" -ge "$SLB_MAX_FIX_CYCLES" ]; then
  SLB_STUCK_ACTIVE=true
  add_block "STUCK — ${SLB_MAX_FIX_CYCLES} fix cycles exhausted. STOP. Write .claude/state/stuck-report.md (approaches tried, raw errors, what you need). WAIT for user."
fi

# Strategy loop breaker â€” preserve existing state updates, surface tier 1 as warning and tier 2 as block.
SLB_RESULT=""
SLB_EXIT=0
if [ -f "$HOME/.claude/scripts/detect-strategy-loop.sh" ]; then
  SLB_RESULT=$(bash "$HOME/.claude/scripts/detect-strategy-loop.sh" 2>/dev/null) || SLB_EXIT=$?
fi

if [ "$SLB_STUCK_ACTIVE" != true ] && { [ "$SLB_EXIT" -eq 1 ] || [ "$SLB_EXIT" -eq 2 ]; }; then
  SLB_FILE_LIST=""
  if [ -n "$MUST_DO_DIR" ] && [ -f "${MUST_DO_DIR}/must-do.md" ]; then
    SLB_MISTAKE_FILES=""
    SLB_OTHER_FILES=""
    while IFS= read -r FPATH || [ -n "$FPATH" ]; do
      [ -z "$FPATH" ] && continue
      case "$FPATH" in "#"*|"---"*|" "*) continue ;; esac
      FBASE=$(basename "$FPATH")
      if printf '%s' "$FBASE" | grep -qi "mistake"; then
        SLB_MISTAKE_FILES="${SLB_MISTAKE_FILES} ${FPATH}(PRIORITY);"
      else
        SLB_OTHER_FILES="${SLB_OTHER_FILES} ${FPATH};"
      fi
    done < "${MUST_DO_DIR}/must-do.md"
    SLB_FILE_LIST="${SLB_MISTAKE_FILES}${SLB_OTHER_FILES}"
  fi

  if [ "$SLB_EXIT" -eq 1 ]; then
    SLB_NOW=$(date +%s 2>/dev/null)
    SLB_LAST_TS=""
    SLB_CURRENT_COUNT=0
    if [ -f "$SLB_STATE_FILE" ] && jq '.' "$SLB_STATE_FILE" >/dev/null 2>&1; then
      SLB_LAST_TS=$(jq -r '.last_nudge_ts // ""' "$SLB_STATE_FILE" 2>/dev/null | tr -d '\r')
      SLB_CURRENT_COUNT=$(jq -r '.nudge_count // 0' "$SLB_STATE_FILE" 2>/dev/null | tr -d '\r')
    fi
    if ! printf '%s' "$SLB_CURRENT_COUNT" | grep -qE '^[0-9]+$' 2>/dev/null; then SLB_CURRENT_COUNT=0; fi
    SLB_SHOULD_INCREMENT=true
    if [ -n "$SLB_LAST_TS" ] && [ "$SLB_LAST_TS" != "null" ]; then
      SLB_LAST_EPOCH=$(date -d "$SLB_LAST_TS" +%s 2>/dev/null || echo "0")
      SLB_ELAPSED=$((SLB_NOW - SLB_LAST_EPOCH))
      if [ "$SLB_ELAPSED" -lt 60 ]; then SLB_SHOULD_INCREMENT=false; fi
    fi
    if [ "$SLB_SHOULD_INCREMENT" = true ]; then
      SLB_NEW_COUNT=$((SLB_CURRENT_COUNT + 1))
      SLB_NOW_TS=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
      SLB_CUR_FP=$(jq -r '.last_output_fingerprint // ""' "$SLB_STATE_FILE" 2>/dev/null | tr -d '\r' | sed 's/\\/\\\\/g; s/"/\\"/g')
      SLB_CUR_CHURN=$(jq -c '.last_churn_files // []' "$SLB_STATE_FILE" 2>/dev/null | tr -d '\r')
      if ! printf '%s' "$SLB_CUR_CHURN" | jq '.' >/dev/null 2>&1; then SLB_CUR_CHURN="[]"; fi
      if type atomic_write >/dev/null 2>&1; then
        atomic_write "{\"nudge_count\":${SLB_NEW_COUNT},\"last_nudge_ts\":\"${SLB_NOW_TS}\",\"last_output_fingerprint\":\"${SLB_CUR_FP}\",\"last_churn_files\":${SLB_CUR_CHURN},\"blocked\":false,\"fix_cycle_count\":${SLB_FIX_CYCLE_COUNT},\"max_fix_cycles\":${SLB_MAX_FIX_CYCLES},\"last_sprint\":\"${SPRINT}\"}" "$SLB_STATE_FILE"
      fi
    fi
    WARNINGS="${WARNINGS}[STRATEGY NUDGE] Repeating pattern detected â€” re-read must-do files for alternatives. ${SLB_FILE_LIST}
"
  elif [ "$SLB_EXIT" -eq 2 ]; then
    if type atomic_write >/dev/null 2>&1 && [ -f "$SLB_STATE_FILE" ]; then
      SLB_CUR_COUNT=$(jq -r '.nudge_count // 0' "$SLB_STATE_FILE" 2>/dev/null | tr -d '\r')
      SLB_CUR_FP=$(jq -r '.last_output_fingerprint // ""' "$SLB_STATE_FILE" 2>/dev/null | tr -d '\r' | sed 's/\\/\\\\/g; s/"/\\"/g')
      SLB_CUR_CHURN=$(jq -c '.last_churn_files // []' "$SLB_STATE_FILE" 2>/dev/null | tr -d '\r')
      SLB_NOW_TS=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
      if ! printf '%s' "$SLB_CUR_CHURN" | jq '.' >/dev/null 2>&1; then SLB_CUR_CHURN="[]"; fi
      atomic_write "{\"nudge_count\":${SLB_CUR_COUNT:-0},\"last_nudge_ts\":\"${SLB_NOW_TS}\",\"last_output_fingerprint\":\"${SLB_CUR_FP}\",\"last_churn_files\":${SLB_CUR_CHURN},\"blocked\":true,\"fix_cycle_count\":${SLB_FIX_CYCLE_COUNT},\"max_fix_cycles\":${SLB_MAX_FIX_CYCLES},\"last_sprint\":\"${SPRINT}\"}" "$SLB_STATE_FILE"
    fi
    add_block "strategy loop â€” write .claude/state/strategy-ack.md with ## New Approach (150+ chars, reference must-do file). ${SLB_FILE_LIST}"
  fi
fi

# Any non-phase hard block means normal writes are constrained; show exempt paths for the cockpit.
if [ -n "$BLOCKS" ] && printf '%s' "$BLOCKS" | grep -vq '^- WRITES LOCKED:'; then
  TOOLS_LOCKED="true"
fi
# --- ASSEMBLE TURN PACKET ---
CONTEXT_MSG="[HARNESS] Phase: ${PHASE} | Sprint: ${SPRINT} | Iter: ${ITERATION} | Writes: ${WRITES} | Watcher: ${WATCHER_STATUS}"
if [ -n "$GUIDANCE_LINE" ]; then
  CONTEXT_MSG="${CONTEXT_MSG}
${GUIDANCE_LINE}"
fi
if [ -n "$PROTOCOL_LINE" ]; then
  CONTEXT_MSG="${CONTEXT_MSG}
${PROTOCOL_LINE}"
fi
if [ -n "$VERIFIER_RULES" ]; then
  CONTEXT_MSG="${CONTEXT_MSG}
${VERIFIER_RULES}"
fi

if [ -n "$READS" ]; then
  CONTEXT_MSG="${CONTEXT_MSG}
READ FIRST:
${READS}"
fi
if [ -n "$WARNINGS" ]; then
  CONTEXT_MSG="${CONTEXT_MSG}
${WARNINGS}"
fi
if [ -n "$ACTIONS" ]; then
  CONTEXT_MSG="${CONTEXT_MSG}
ACTIONS BEFORE CODE:
${ACTIONS}"
fi
if [ -n "$BLOCKS" ]; then
  CONTEXT_MSG="${CONTEXT_MSG}
BLOCKED BY:
${BLOCKS}"
fi
if [ "$TOOLS_LOCKED" = "true" ]; then
  CONTEXT_MSG="${CONTEXT_MSG}
ALWAYS WRITABLE: .claude/state/, contracts/specs, watchers, evidence."
fi
if [ -n "$WATCHER_SLOT" ]; then
  if [ -n "$WATCHER_STEP" ]; then CONTEXT_MSG="${CONTEXT_MSG}
CURRENT STEP: ${WATCHER_STEP}"; fi
  if [ -n "$WATCHER_SCOPE" ]; then CONTEXT_MSG="${CONTEXT_MSG}
SCOPE: ${WATCHER_SCOPE}"; fi
  if [ -n "$WATCHER_MISTAKES" ]; then CONTEXT_MSG="${CONTEXT_MSG}
MISTAKES TO AVOID: ${WATCHER_MISTAKES}"; fi
  if [ -n "$WATCHER_DONE" ]; then CONTEXT_MSG="${CONTEXT_MSG}
DONE WHEN: ${WATCHER_DONE}"; fi
fi
if [ -n "$PENDING_ITEMS" ]; then
  CONTEXT_MSG="${CONTEXT_MSG}
PENDING: ${PENDING_ITEMS}"
fi

# --- MUST-DO SUMMARY INJECTION ---
# Preserve existing injection and append-only log behavior.
MUST_DO_SUMMARY="${STATE_DIR}/must-do-summary.md"
if [ -f "$MUST_DO_SUMMARY" ]; then
  SUMMARY_TEXT=$(head -c 800 "$MUST_DO_SUMMARY" 2>/dev/null | one_line)
  if [ -n "$SUMMARY_TEXT" ]; then
    CONTEXT_MSG="${CONTEXT_MSG}
[MUST-DO ACTIVE] ${SUMMARY_TEXT}"
    INJECT_LOG="${STATE_DIR}/must-do-injection-log.jsonl"
    INJECT_TS=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
    INJECT_STEP=$(cat "${STATE_DIR}/must-do-summary-step.txt" 2>/dev/null | tr -d '\r\n')
    printf '{"ts":"%s","step":"%s","chars":%d}\n' "$INJECT_TS" "$INJECT_STEP" "${#SUMMARY_TEXT}" >> "$INJECT_LOG" 2>/dev/null
  fi
fi

# Contract budget: Sprint 21 raises the hard safety cap to 2000 chars.
if [ "${#CONTEXT_MSG}" -gt 2000 ]; then
  CONTEXT_MSG=$(printf '%s' "$CONTEXT_MSG" | head -c 1990)
  CONTEXT_MSG="${CONTEXT_MSG}â€¦"
fi

printf '%s' "$CONTEXT_MSG"
exit 0