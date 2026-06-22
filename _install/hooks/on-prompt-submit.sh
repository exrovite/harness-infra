#!/bin/bash
# on-prompt-submit.sh — Claude Code UserPromptSubmit hook (Layer 1: harness outer loop)
#
# Fires once on every prompt the user submits, BEFORE the model sees it. Because it runs
# at prompt time (not on a tool write) it can never be blocked by a write gate, which is
# why the harness's control signals live here. Responsibilities, in order:
#   1. Kill-switch + signal tokens — exact-trimmed prompts toggle harness state:
#        '---' disables the harness for this project, '===' re-enables it,
#        '+++pack' builds the must-do grounding pack from the live transcript.
#   2. Instance/lane resolution — resolve_instance assigns this session its watcher
#      lane (drives which must-do file it owns: must-do.md vs must-do-N.md).
#   3. Context injection — prepends the "harness packet" to the user's prompt: current
#      phase/sprint, active must-do file list, evidence-checkpoint status, known-fix
#      injected-context, and a strategy nudge when work has drifted.
# Reads the prompt payload from stdin (JSON); emits the packet on stdout. Diagnostics go
# to stderr only. MSYS-safe throughout (tr for backslashes, \r stripping, trailing-newline
# read guards). See MEMORY.md "Harness Kill-Switch" and "Must-Do" sections for details.
PROMPT_INPUT=$(cat)
PROMPT_TEXT=$(printf '%s' "$PROMPT_INPUT" | jq -r '.prompt // ""' 2>/dev/null | tr -d '\r')

# on-prompt-submit.sh â€” Claude Code UserPromptSubmit hook
# Fires at the START of every Claude turn, injecting a turn packet.
# The packet tells the agent what to read, do, avoid, and finish before it discovers gates by failure.

STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
WATCHER_REGISTRY="$HOME/.openclaw/watchers/REGISTRY.json"
HELPERS="$HOME/.claude/scripts/lib-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS" 2>/dev/null

# Multilane lane resolution (Sprint 31a): UserPromptSubmit is where a lane is CLAIMED on the live
# registry (lane 1 = flat, transparent). Honor explicit HARNESS_STATE_DIR test override.
LANE=1
if [ -n "${HARNESS_STATE_DIR:-}" ]; then
  STATE_DIR="$HARNESS_STATE_DIR"
elif type resolve_instance >/dev/null 2>&1; then
  resolve_instance "$PROMPT_INPUT" "$(pwd -W 2>/dev/null || pwd)" "UserPromptSubmit" >/dev/null 2>&1
  STATE_DIR="${STATE_DIR:-.claude/state}"
fi

# --- HARNESS KILL-SWITCH TOGGLE (Sprint 33) ---
# Exact-match prompt tokens flip a project-scoped OFF switch. Nothing else toggles it.
#   '---' -> harness OFF (all gates bypassed)   '===' -> harness ON
# Project-scoped flag at <state>/harness-disabled.flag. The toggle messages and the
# OFF banner are injected here; they are never blocked by any write gate.
# Land the flag at the PROJECT ROOT (nearest .claude up from cwd) so it governs the whole project,
# regardless of which subdir --- was typed from. Honors HARNESS_STATE_DIR / lane overrides above.
if [ -z "${HARNESS_STATE_DIR:-}" ] && [ "${LANE:-1}" = "1" ] && type find_project_state_dir >/dev/null 2>&1; then
  _ks_root="$(find_project_state_dir "$(pwd -W 2>/dev/null || pwd)" 2>/dev/null)" && STATE_DIR="$_ks_root"
fi
KS_FLAG="${STATE_DIR}/harness-disabled.flag"
KS_PROJECT=$(pwd -W 2>/dev/null || pwd); KS_PROJECT=$(basename "$KS_PROJECT" 2>/dev/null)
KS_TRIMMED=$(printf '%s' "$PROMPT_TEXT" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
BEAST_FLAG="${STATE_DIR}/beast-mode.flag"
if [ "$KS_TRIMMED" = "---" ]; then
  if type harness_disable >/dev/null 2>&1; then
    harness_disable "$STATE_DIR"
  else
    mkdir -p "$STATE_DIR" 2>/dev/null
    KS_TS=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
    printf 'harness disabled at %s\n' "$KS_TS" > "${KS_FLAG}.tmp" 2>/dev/null && mv -f "${KS_FLAG}.tmp" "$KS_FLAG" 2>/dev/null
  fi
  # Beast-mode is a strict superset of harness-on: disabling the harness drops beast too.
  if type beast_disable >/dev/null 2>&1; then beast_disable "$STATE_DIR"; else rm -f "$BEAST_FLAG" 2>/dev/null; fi
  printf '[HARNESS UNLOCKED — %s] All enforcement gates bypassed for this project (phase lock, watcher, pre-flight MCQ, evidence, must-do, contract). Beast-mode off. Send === to lock.' "${KS_PROJECT:-project}"
  exit 0
elif [ "$KS_TRIMMED" = "===" ]; then
  if type harness_enable >/dev/null 2>&1; then
    harness_enable "$STATE_DIR"
  else
    rm -f "$KS_FLAG" 2>/dev/null
  fi
  printf '[HARNESS LOCKED] Enforcement re-enabled for this project. Send --- to unlock.'
  exit 0
elif [ "$KS_TRIMMED" = "beast-off" ]; then
  # Turn beast OFF only; leave the harness exactly as it is.
  if type beast_disable >/dev/null 2>&1; then beast_disable "$STATE_DIR"; else rm -f "$BEAST_FLAG" 2>/dev/null; fi
  printf '[BEAST MODE OFF] Intuition grounding disabled for this project. Harness unchanged. Send beast-on to re-arm.'
  exit 0
elif [ "$KS_TRIMMED" = "beast-on" ]; then
  # Superset rule: beast requires the harness ON. If it is disabled, enable it FIRST.
  BEAST_REENABLED=0
  if [ -f "$KS_FLAG" ]; then
    if type harness_enable >/dev/null 2>&1; then harness_enable "$STATE_DIR"; else rm -f "$KS_FLAG" 2>/dev/null; fi
    BEAST_REENABLED=1
  fi
  if type beast_enable >/dev/null 2>&1; then
    beast_enable "$STATE_DIR"
  else
    mkdir -p "$STATE_DIR" 2>/dev/null; printf 'beast mode on\n' > "$BEAST_FLAG" 2>/dev/null
  fi
  # One-time curated bulk pack into mempalace (best-effort, headless, no CMD window).
  if [ -x "${HOME}/.claude/scripts/beast-pack.sh" ] && [ ! -f "${STATE_DIR}/beast-packed.flag" ]; then
    ( "${HOME}/.claude/scripts/beast-pack.sh" >/dev/null 2>&1 && : > "${STATE_DIR}/beast-packed.flag" ) &
  fi
  if [ "$BEAST_REENABLED" = "1" ]; then
    printf '[HARNESS RE-ENABLED — beast mode requires active gates] [BEAST MODE ON — %s] Intuition grounding active.' "${KS_PROJECT:-project}"
  else
    printf '[BEAST MODE ON — %s] Intuition grounding active. Send beast-off to disable.' "${KS_PROJECT:-project}"
  fi
  exit 0
fi
# If OFF (flag present) and this is an ordinary prompt, inject only the persistent banner.
if [ -f "$KS_FLAG" ]; then
  printf '[HARNESS UNLOCKED — %s] Enforcement disabled for this project — all gates bypassed. Send === to lock.' "${KS_PROJECT:-project}"
  exit 0
fi

# --- MUST-DO PACK BUILD TRIGGER (D-Trigger, C12) ---
# Explicit signal '+++pack' (exact trimmed match) builds the caller's must-do PACK before PLAN:
# clears ONLY the caller's owned must-do file and relinks the raw conversation (transcript copy) +
# grounding. The PLAN-entry gate in pre-write-gate.sh is the independent backstop.
if [ "$KS_TRIMMED" = "+++pack" ]; then
  PK_DIR=""
  for PK_C in "docs/must do" "docs/must-do" ".claude/must-do"; do
    [ -d "$PK_C" ] && PK_DIR="$PK_C" && break
  done
  [ -z "$PK_DIR" ] && PK_DIR="docs/must do"
  if type mustdo_file_for_dir >/dev/null 2>&1; then
    PK_OWN=$(mustdo_file_for_dir "$PK_DIR" 2>/dev/null)
  fi
  [ -n "${PK_OWN:-}" ] || PK_OWN="${PK_DIR}/must-do.md"
  PK_TRANSCRIPT=$(printf '%s' "$PROMPT_INPUT" | jq -r '.transcript_path // ""' 2>/dev/null | tr -d '\r')
  # Sprint 37: thread session_id so the built pack carries this session's ownership stamp.
  PK_SID=$(printf '%s' "$PROMPT_INPUT" | jq -r '.session_id // ""' 2>/dev/null | tr -d '\r')
  PK_BUILDER="$HOME/.claude/scripts/build-mustdo-pack.sh"
  if [ -f "$PK_BUILDER" ]; then
    if [ -n "$PK_TRANSCRIPT" ] && [ -f "$PK_TRANSCRIPT" ]; then
      bash "$PK_BUILDER" --own "$PK_OWN" --transcript "$PK_TRANSCRIPT" --session "$PK_SID" >/dev/null 2>&1
    else
      bash "$PK_BUILDER" --own "$PK_OWN" --no-transcript --session "$PK_SID" >/dev/null 2>&1
    fi
    printf '[MUST-DO PACK BUILT] Owned file %s cleared + relinked (raw conversation captured). Now write your discussion-agreement / rough-plan, add grounding links, then proceed to PLAN.' "$PK_OWN"
  else
    printf '[MUST-DO PACK] build-mustdo-pack.sh not found at %s — cannot build pack.' "$PK_BUILDER"
  fi
  exit 0
fi

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

# --- RALPH LOOP HELPERS ---
iso_newer_than() {
  local NEW_TS="$1"
  local OLD_TS="$2"
  [ -n "$NEW_TS" ] || return 1
  if [ -z "$OLD_TS" ] || [ "$OLD_TS" = "null" ]; then
    return 0
  fi

  local NEW_EPOCH OLD_EPOCH
  NEW_EPOCH=$(date -d "$NEW_TS" +%s 2>/dev/null) || NEW_EPOCH=""
  OLD_EPOCH=$(date -d "$OLD_TS" +%s 2>/dev/null) || OLD_EPOCH=""
  if [ -n "$NEW_EPOCH" ] && [ -n "$OLD_EPOCH" ]; then
    [ "$NEW_EPOCH" -gt "$OLD_EPOCH" ]
    return $?
  fi

  # MSYS fallback: ISO8601 timestamps sort lexicographically.
  [[ "$NEW_TS" > "$OLD_TS" ]]
}

write_ralph_state_json() {
  [ -n "$1" ] || return 1
  mkdir -p "$STATE_DIR" 2>/dev/null
  if type atomic_write >/dev/null 2>&1; then
    atomic_write "$1" "${STATE_DIR}/ralph-mode.json"
  else
    printf '%s' "$1" > "${STATE_DIR}/ralph-mode.json"
  fi
}

write_ralph_state_from_file() {
  local UPDATED="$1"
  [ -n "$UPDATED" ] || return 1
  write_ralph_state_json "$UPDATED"
}

ralph_active_from_file() {
  [ -f "${STATE_DIR}/ralph-mode.json" ] && jq -e '.active == true' "${STATE_DIR}/ralph-mode.json" >/dev/null 2>&1
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

# --- RALPH LOOP STATE + KEYWORD ACTIVATION ---
RALPH_STATE_FILE="${STATE_DIR}/ralph-mode.json"
RALPH_LOOP_LINE=""
RALPH_WARNING_LINE=""
RALPH_AUTO_TRANSITIONED=false
RALPH_JUST_ACTIVATED=false
RALPH_PASSED_THIS_TURN=false
RALPH_ACTIVE=false
RALPH_ITERATION=1
RALPH_MAX_ITERATIONS=5
RALPH_LAST_VERDICT="null"
RALPH_LAST_VERDICT_AT=""
RALPH_FAILED_CRITERIA="[]"
RALPH_STATE_VALID=false
RALPH_SPRINT=""

if [ -f "$RALPH_STATE_FILE" ] && jq '.' "$RALPH_STATE_FILE" >/dev/null 2>&1; then
  RALPH_STATE_VALID=true
  RALPH_ACTIVE=$(jq -r '.active // false' "$RALPH_STATE_FILE" 2>/dev/null | tr -d '\r')
  RALPH_ITERATION=$(jq -r '.iteration // 1' "$RALPH_STATE_FILE" 2>/dev/null | tr -d '\r')
  RALPH_MAX_ITERATIONS=$(jq -r '.max_iterations // 5' "$RALPH_STATE_FILE" 2>/dev/null | tr -d '\r')
  RALPH_LAST_VERDICT=$(jq -r '.last_verdict // "null"' "$RALPH_STATE_FILE" 2>/dev/null | tr -d '\r')
  RALPH_LAST_VERDICT_AT=$(jq -r '.last_verdict_at // ""' "$RALPH_STATE_FILE" 2>/dev/null | tr -d '\r')
  RALPH_SPRINT=$(jq -r '.sprint // ""' "$RALPH_STATE_FILE" 2>/dev/null | tr -d '\r')
fi
if ! printf '%s' "$RALPH_ITERATION" | grep -qE '^[0-9]+$'; then RALPH_ITERATION=1; fi
if ! printf '%s' "$RALPH_MAX_ITERATIONS" | grep -qE '^[0-9]+$'; then RALPH_MAX_ITERATIONS=5; fi
if [ "$RALPH_MAX_ITERATIONS" -lt 1 ]; then RALPH_MAX_ITERATIONS=5; fi

# Existing active ralph belongs to one sprint; task/sprint changes auto-deactivate it.
if [ "$RALPH_ACTIVE" = "true" ] && [ -n "$RALPH_SPRINT" ] && [ "$RALPH_SPRINT" != "null" ] && [ "$RALPH_SPRINT" != "$SPRINT" ]; then
  RALPH_UPDATED=$(jq -c '.active=false' "$RALPH_STATE_FILE" 2>/dev/null | tr -d '\r')
  write_ralph_state_from_file "$RALPH_UPDATED"
  RALPH_ACTIVE=false
fi

if printf '%s' "$PROMPT_TEXT" | grep -qi '\$ralph'; then
  # Auto-transition: if not in BUILD but a sprint contract exists, advance to BUILD
  if [ "$PHASE" != "BUILD" ] && [ -f ".claude/contracts/sprint-${SPRINT}-contract.md" ]; then
    if [ "$PHASE" = "NEGOTIATE" ] || [ "$PHASE" = "COMPLETE" ] || [ "$PHASE" = "PLAN" ]; then
      mkdir -p "${STATE_DIR}" 2>/dev/null
      RALPH_TRANS_TS=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
      printf '# Phase Complete: %s (Sprint %s)\n\nAuto-transitioned to BUILD by $ralph at %s\n' "$PHASE" "$SPRINT" "$RALPH_TRANS_TS" > "${STATE_DIR}/phase-complete-marker.md"
      printf '{"phase":"BUILD","sprint":%s,"iteration":0}' "${SPRINT:-0}" > "${STATE_DIR}/current-phase.json"
      PHASE="BUILD"
      rm -f "${STATE_DIR}/phase-feedback.md" 2>/dev/null
      RALPH_AUTO_TRANSITIONED=true
    fi
  fi

  if [ "$PHASE" = "BUILD" ]; then
    if ! ralph_active_from_file; then
      RALPH_OVERRIDE=$(printf '%s' "$PROMPT_TEXT" | grep -oiE '\$ralph:[0-9]+' | head -1 | sed 's/.*://')
      if printf '%s' "$RALPH_OVERRIDE" | grep -qE '^[0-9]+$' && [ "$RALPH_OVERRIDE" -gt 0 ]; then
        RALPH_MAX_ITERATIONS="$RALPH_OVERRIDE"
      else
        RALPH_MAX_ITERATIONS=5
      fi
      RALPH_NOW=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
      RALPH_JSON=$(jq -cn \
        --arg activated_at "$RALPH_NOW" \
        --argjson max "$RALPH_MAX_ITERATIONS" \
        --argjson sprint "${SPRINT:-0}" \
        '{active:true,activated_by:"user_prompt",activated_at:$activated_at,iteration:1,max_iterations:$max,last_verdict:null,last_verdict_at:null,failed_criteria:[],sprint:$sprint}' 2>/dev/null | tr -d '\r')
      write_ralph_state_json "$RALPH_JSON"
      RALPH_JUST_ACTIVATED=true
      RALPH_ACTIVE=true
      RALPH_ITERATION=1
      RALPH_LAST_VERDICT="null"
      RALPH_LAST_VERDICT_AT=""
      RALPH_SPRINT="$SPRINT"
    fi
  else
    # No contract exists for this sprint — can't auto-transition
    RALPH_WARNING_LINE='[RALPH BLOCKED] $ralph requires a sprint contract. Write .claude/contracts/sprint-'${SPRINT}'-contract.md first.'
  fi
fi

# Process fresh verifier verdicts on each prompt when ralph remains active.
if [ "$RALPH_ACTIVE" = "true" ] && [ "$RALPH_JUST_ACTIVATED" != true ] && [ -f "${STATE_DIR}/evidence-verdict.json" ] && jq '.' "${STATE_DIR}/evidence-verdict.json" >/dev/null 2>&1; then
  RALPH_VERDICT=$(jq -r '.verdict // ""' "${STATE_DIR}/evidence-verdict.json" 2>/dev/null | tr -d '\r')
  RALPH_VERDICT_TS=$(jq -r '.timestamp // .checked_at // .verdict_at // .created_at // .ts // ""' "${STATE_DIR}/evidence-verdict.json" 2>/dev/null | tr -d '\r')
  if iso_newer_than "$RALPH_VERDICT_TS" "$RALPH_LAST_VERDICT_AT"; then
    if [ "$RALPH_VERDICT" = "PASS" ]; then
      RALPH_UPDATED=$(jq -c \
        --arg ts "$RALPH_VERDICT_TS" \
        '.last_verdict="PASS" | .active=false | .last_verdict_at=$ts | .failed_criteria=[]' \
        "$RALPH_STATE_FILE" 2>/dev/null | tr -d '\r')
      write_ralph_state_from_file "$RALPH_UPDATED"
      RALPH_ACTIVE=false
      RALPH_PASSED_THIS_TURN=true
      RALPH_LAST_VERDICT="PASS"
      RALPH_LAST_VERDICT_AT="$RALPH_VERDICT_TS"
    elif [ "$RALPH_VERDICT" = "FAIL" ]; then
      RALPH_ITERATION=$((RALPH_ITERATION + 1))
      RALPH_FAILED_CRITERIA=$(jq -c '[.failed_criteria[]?, .findings[]?.criterion?, .criteria[]?] | map(select(. != null))' "${STATE_DIR}/evidence-verdict.json" 2>/dev/null | tr -d '\r')
      if [ -z "$RALPH_FAILED_CRITERIA" ] || ! printf '%s' "$RALPH_FAILED_CRITERIA" | jq '.' >/dev/null 2>&1; then RALPH_FAILED_CRITERIA="[]"; fi
      RALPH_UPDATED=$(jq -c \
        --arg ts "$RALPH_VERDICT_TS" \
        --argjson iter "$RALPH_ITERATION" \
        --argjson failed "$RALPH_FAILED_CRITERIA" \
        '.iteration=$iter | .last_verdict="FAIL" | .last_verdict_at=$ts | .failed_criteria=$failed' \
        "$RALPH_STATE_FILE" 2>/dev/null | tr -d '\r')
      write_ralph_state_from_file "$RALPH_UPDATED"
      rm -f "${STATE_DIR}/evidence-verdict.json" 2>/dev/null
      RALPH_LAST_VERDICT="FAIL"
      RALPH_LAST_VERDICT_AT="$RALPH_VERDICT_TS"
    fi
  fi
fi

# Reload ralph after any activation/accounting writes.
if [ -f "$RALPH_STATE_FILE" ] && jq '.' "$RALPH_STATE_FILE" >/dev/null 2>&1; then
  RALPH_ACTIVE=$(jq -r '.active // false' "$RALPH_STATE_FILE" 2>/dev/null | tr -d '\r')
  RALPH_ITERATION=$(jq -r '.iteration // 1' "$RALPH_STATE_FILE" 2>/dev/null | tr -d '\r')
  RALPH_MAX_ITERATIONS=$(jq -r '.max_iterations // 5' "$RALPH_STATE_FILE" 2>/dev/null | tr -d '\r')
  RALPH_LAST_VERDICT=$(jq -r '.last_verdict // "null"' "$RALPH_STATE_FILE" 2>/dev/null | tr -d '\r')
  RALPH_LAST_VERDICT_AT=$(jq -r '.last_verdict_at // ""' "$RALPH_STATE_FILE" 2>/dev/null | tr -d '\r')
fi
if ! printf '%s' "$RALPH_ITERATION" | grep -qE '^[0-9]+$'; then RALPH_ITERATION=1; fi
if ! printf '%s' "$RALPH_MAX_ITERATIONS" | grep -qE '^[0-9]+$'; then RALPH_MAX_ITERATIONS=5; fi

# Ralph evidence bridge: if files changed since activation/last verdict, prepare a verifier brief.
if [ "$RALPH_ACTIVE" = "true" ] && [ "$RALPH_JUST_ACTIVATED" != true ]; then
  RALPH_BASE_TS="$RALPH_LAST_VERDICT_AT"
  if [ -z "$RALPH_BASE_TS" ] || [ "$RALPH_BASE_TS" = "null" ]; then
    RALPH_BASE_TS=$(jq -r '.activated_at // ""' "$RALPH_STATE_FILE" 2>/dev/null | tr -d '\r')
  fi
  RALPH_HAS_NEW_WRITES=false
  if [ -f "${STATE_DIR}/unverified-writes.jsonl" ] && [ -n "$RALPH_BASE_TS" ]; then
    while IFS= read -r RALPH_WRITE_LINE || [ -n "$RALPH_WRITE_LINE" ]; do
      [ -z "$RALPH_WRITE_LINE" ] && continue
      RALPH_WRITE_TS=$(printf '%s' "$RALPH_WRITE_LINE" | jq -r '.ts // ""' 2>/dev/null | tr -d '\r')
      if iso_newer_than "$RALPH_WRITE_TS" "$RALPH_BASE_TS"; then
        RALPH_HAS_NEW_WRITES=true
        break
      fi
    done < "${STATE_DIR}/unverified-writes.jsonl"
  elif [ "$WRITES" -gt 0 ] && [ -z "$RALPH_BASE_TS" ]; then
    RALPH_HAS_NEW_WRITES=true
  fi

  if [ "$RALPH_HAS_NEW_WRITES" = true ]; then
    if [ ! -f "${STATE_DIR}/evidence-checkpoint.json" ] && [ -f "$HOME/.claude/scripts/create-evidence-checkpoint.sh" ]; then
      bash "$HOME/.claude/scripts/create-evidence-checkpoint.sh" "ralph_iteration_${RALPH_ITERATION}" >/dev/null 2>&1 || true
    fi
    if [ -f "${STATE_DIR}/evidence-checkpoint.json" ] && jq '.' "${STATE_DIR}/evidence-checkpoint.json" >/dev/null 2>&1; then
      RALPH_TMP=$(mktemp)
      jq -c --arg contract ".claude/contracts/sprint-${SPRINT}-contract.md" --argjson iter "$RALPH_ITERATION" \
        '. + {ralph:{active:true,iteration:$iter,sprint_contract:$contract}}' \
        "${STATE_DIR}/evidence-checkpoint.json" > "$RALPH_TMP" 2>/dev/null && mv "$RALPH_TMP" "${STATE_DIR}/evidence-checkpoint.json"
      rm -f "$RALPH_TMP" 2>/dev/null
    else
      RALPH_NOW=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
      RALPH_MODIFIED='[]'
      if [ -f "${STATE_DIR}/unverified-writes.jsonl" ]; then
        RALPH_MODIFIED=$(jq -s '[.[].file] | unique' "${STATE_DIR}/unverified-writes.jsonl" 2>/dev/null | tr -d '\r')
        if [ -z "$RALPH_MODIFIED" ]; then RALPH_MODIFIED='[]'; fi
      fi
      RALPH_CHECKPOINT=$(jq -cn \
        --arg ts "$RALPH_NOW" \
        --arg contract ".claude/contracts/sprint-${SPRINT}-contract.md" \
        --argjson iter "$RALPH_ITERATION" \
        --argjson modified "$RALPH_MODIFIED" \
        '{status:"pending",triggered_at:$ts,trigger_reason:"ralph_write_since_verdict",ralph:{active:true,iteration:$iter,sprint_contract:$contract},modified_files_since_last:$modified,evidence_dir:".claude/evidence/",instruction:"Ralph verifier: independently verify Sprint contract criteria and changed files. Write evidence-verdict.json with verdict PASS or FAIL and a fresh timestamp."}' 2>/dev/null | tr -d '\r')
      if [ -n "$RALPH_CHECKPOINT" ]; then
        if type atomic_write >/dev/null 2>&1; then atomic_write "$RALPH_CHECKPOINT" "${STATE_DIR}/evidence-checkpoint.json"; else printf '%s' "$RALPH_CHECKPOINT" > "${STATE_DIR}/evidence-checkpoint.json"; fi
      fi
    fi
  fi
fi

if [ "$RALPH_PASSED_THIS_TURN" = true ]; then
  RALPH_LOOP_LINE="RALPH LOOP: PASSED at iteration ${RALPH_ITERATION}. Write phase-complete-marker.md to finish."
elif [ "$RALPH_ACTIVE" = "true" ]; then
  if [ "$RALPH_ITERATION" -gt "$RALPH_MAX_ITERATIONS" ] && [ "$RALPH_LAST_VERDICT" != "PASS" ]; then
    RALPH_LOOP_LINE="RALPH LOOP: STUCK - ${RALPH_MAX_ITERATIONS} iterations exhausted without PASS. STOP. Write stuck-report.md. WAIT for user."
  elif [ "$RALPH_LAST_VERDICT" = "PASS" ]; then
    RALPH_LOOP_LINE="RALPH LOOP: PASSED at iteration ${RALPH_ITERATION}. Write phase-complete-marker.md to finish."
  elif [ "$RALPH_LAST_VERDICT" = "FAIL" ]; then
    RALPH_LOOP_LINE="RALPH LOOP: Iteration ${RALPH_ITERATION}/${RALPH_MAX_ITERATIONS} | FAIL - fix failures in evidence-verdict.json, then spawn verifier. Cannot complete until PASS."
  else
    RALPH_LOOP_LINE="RALPH LOOP: Iteration ${RALPH_ITERATION}/${RALPH_MAX_ITERATIONS} | Implement, then spawn verifier sub-agent. You CANNOT complete until verifier returns PASS."
  fi
fi

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
  MUST_DO_OWN=$(mustdo_file_for_dir "$MUST_DO_DIR" 2>/dev/null); [ -n "$MUST_DO_OWN" ] || MUST_DO_OWN="${MUST_DO_DIR}/must-do.md"
  if [ -f "$MUST_DO_OWN" ]; then
    add_read "$MUST_DO_OWN and referenced docs"
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

if [ -n "$MUST_DO_DIR" ] && [ "$PHASE" = "BUILD" ]; then
  # Per-session grounding: each model keeps its OWN summary (must-do-summary.<session_id>.md) so
  # parallel sessions never clobber each other. Advise when THIS session hasn't authored one yet.
  OPS_SID=$(printf '%s' "$PROMPT_INPUT" | jq -r '.session_id // ""' 2>/dev/null | tr -d '\r')
  if [ -n "$OPS_SID" ]; then
    if [ ! -f "${STATE_DIR}/must-do-summary.${OPS_SID}.md" ]; then
      add_action "Author your OWN must-do summary: Write â€” .claude/state/must-do-summary.md. Each session keeps its own grounding; you haven't written yours yet (won't unlock source writes until you do)."
    fi
  elif [ ! -f "${STATE_DIR}/must-do-summary.md" ]; then
    add_action "Write must-do summary: Write â€” .claude/state/must-do-summary.md after reading must-do docs"
  fi
elif [ -n "$MUST_DO_DIR" ] && [ ! -f "${STATE_DIR}/must-do-summary.md" ]; then
  add_action "Write must-do summary: Write â€” .claude/state/must-do-summary.md after reading must-do docs"
elif [ -z "$MUST_DO_DIR" ] && [ "$PHASE" = "BUILD" ]; then
  # Must-do is ON by default: no grounding folder yet -> guide the model to create its own
  # before it hits the gate that blocks source writes (only '---' kill-switch turns this off).
  add_action "Create must-do grounding: Write â€” docs/must do/must-do.md (list files you MUST read for this task), then .claude/state/must-do-summary.md. Required before source writes in BUILD."
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
    add_action "Pre-flight MCQ fires on your next code write. When it does: do NOT guess - it loads your task context. READ challenge.md + your watcher slot + any 'MUST READ <file>' fresh; it reshuffles on wrong answers, so guessing loops."
  fi
fi

# Section 4: hard blocks.
case "$PHASE" in
  BUILD|UNKNOWN) ;;
  *) add_block "WRITES LOCKED: Phase is ${PHASE} - specs/contracts/state only" ;;
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
  SLB_MD_OWN=$(mustdo_file_for_dir "$MUST_DO_DIR" 2>/dev/null); [ -n "$SLB_MD_OWN" ] || SLB_MD_OWN="${MUST_DO_DIR}/must-do.md"
  if [ -n "$MUST_DO_DIR" ] && [ -f "$SLB_MD_OWN" ]; then
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
    done < "$SLB_MD_OWN"
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
if [ -n "$BLOCKS" ]; then
  TOOLS_LOCKED="true"
fi
# Keep bare PLAN packets compact; NEGOTIATE/other locked phases still show writable escape hatches.
if printf '%s' "$BLOCKS" | grep -q 'WRITES LOCKED: Phase is PLAN'; then
  TOOLS_LOCKED="false"
fi
# --- ORPHANED CHECKPOINT AUTO-RESOLVE (Sprint 29) ---
# At turn start, clear a pending checkpoint that already holds a fresh PASS verdict
# (covers the "agent stopped at PASS, user sends next prompt" case).
EC_RESOLVED_NOTE=""
if type clear_evidence_checkpoint_if_pass >/dev/null 2>&1; then
  if clear_evidence_checkpoint_if_pass "$STATE_DIR" "$PHASE" >/dev/null 2>&1; then
    EC_RESOLVED_NOTE="[CHECKPOINT RESOLVED] Pending evidence checkpoint auto-cleared on fresh PASS verdict — phase may now complete."
  fi
fi

# --- ASSEMBLE TURN PACKET ---
CONTEXT_MSG="[HARNESS] Lane: ${LANE:-1} | Phase: ${PHASE} | Sprint: ${SPRINT} | Iter: ${ITERATION} | Writes: ${WRITES} | Watcher: ${WATCHER_STATUS}"
if [ "${LANE:-1}" != "1" ]; then
  CONTEXT_MSG="${CONTEXT_MSG}
[LANE ${LANE}] Your state is under .claude/state/lane-${LANE}/ and contracts under .claude/contracts/lane-${LANE}/ — use these, not the bare CLAUDE.md defaults. Other lanes are separate instances; do not touch their dirs."
fi
if [ -n "$EC_RESOLVED_NOTE" ]; then
  CONTEXT_MSG="${CONTEXT_MSG}
${EC_RESOLVED_NOTE}"
fi
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
if [ "$RALPH_AUTO_TRANSITIONED" = "true" ]; then
  CONTEXT_MSG="${CONTEXT_MSG}
[RALPH] Auto-transitioned to BUILD phase. Contract: .claude/contracts/sprint-${SPRINT}-contract.md"
fi
if [ -n "$RALPH_WARNING_LINE" ]; then
  CONTEXT_MSG="${CONTEXT_MSG}
${RALPH_WARNING_LINE}"
fi
if [ -n "$RALPH_LOOP_LINE" ]; then
  CONTEXT_MSG="${CONTEXT_MSG}
${RALPH_LOOP_LINE}"
fi

# --- CRON PAUSE STATUS INJECTION (F1: AC6, AC7) ---
CRON_PAUSE_FILE="${STATE_DIR}/cron-paused.json"
if [ -f "$CRON_PAUSE_FILE" ] && jq '.' "$CRON_PAUSE_FILE" >/dev/null 2>&1; then
  CP_RESUME_AT=$(jq -r '.resume_at // ""' "$CRON_PAUSE_FILE" 2>/dev/null | tr -d '\r')
  CP_EXPIRED=false
  if [ -n "$CP_RESUME_AT" ] && [ "$CP_RESUME_AT" != "null" ]; then
    CP_RESUME_EPOCH=$(date -d "$CP_RESUME_AT" +%s 2>/dev/null) || CP_RESUME_EPOCH=""
    CP_NOW_EPOCH=$(date +%s 2>/dev/null) || CP_NOW_EPOCH=""
    if [ -n "$CP_RESUME_EPOCH" ] && [ -n "$CP_NOW_EPOCH" ] && [ "$CP_NOW_EPOCH" -ge "$CP_RESUME_EPOCH" ]; then
      CP_EXPIRED=true
    fi
  fi
  if [ "$CP_EXPIRED" = false ]; then
    CP_TIME=$(printf '%s' "$CP_RESUME_AT" | grep -oE '[0-9]{2}:[0-9]{2}' | head -1)
    CONTEXT_MSG="${CONTEXT_MSG}
[CRON PAUSED until ${CP_TIME:-unknown}]"
  fi
fi

# --- BUILD PIPELINE STATUS ---
# Sprint 23: show pending gates proactively during BUILD only.
if [ "$PHASE" = "BUILD" ] && type compute_pending_gates >/dev/null 2>&1; then
  GATE_PENDING=$(compute_pending_gates "$PHASE" "$SPRINT" "$CURRENT_PROJECT")
  if [ -n "$GATE_PENDING" ]; then
    GATE_PENDING_ONE_LINE=$(printf '%s' "$GATE_PENDING" | tr '\012' ' ' | sed 's/^[[:space:]]*->[[:space:]]*//; s/[[:space:]][[:space:]]*/ /g; s/[[:space:]]*$//')
    CONTEXT_MSG="${CONTEXT_MSG}
PENDING: ${GATE_PENDING_ONE_LINE}"
  else
    CONTEXT_MSG="${CONTEXT_MSG}
GATES: all clear - write freely"
  fi
  CONTEXT_MSG="${CONTEXT_MSG}
PROCESS NOTE: Every task follows the full gate sequence - no exceptions for \"simple\" edits. The process IS the work; gates catch drift in simple tasks too."
fi

# --- HARNESS TEST RESULT INJECTION (C3: AC11) + DEDUP GUIDANCE (C4: AC13) ---
if [ "$PHASE" = "BUILD" ]; then
  HARNESS_RESULT_FILE="${STATE_DIR}/harness-test-result.json"
  if [ -f "$HARNESS_RESULT_FILE" ] && jq '.' "$HARNESS_RESULT_FILE" >/dev/null 2>&1; then
    HT_PASSED=$(jq -r '.passed // false' "$HARNESS_RESULT_FILE" 2>/dev/null | tr -d '\r')
    HT_EXIT=$(jq -r '.exit_code // ""' "$HARNESS_RESULT_FILE" 2>/dev/null | tr -d '\r')
    HT_RAN_AT=$(jq -r '.ran_at // ""' "$HARNESS_RESULT_FILE" 2>/dev/null | tr -d '\r')
    HT_COUNT=$(jq -r '.test_count // 0' "$HARNESS_RESULT_FILE" 2>/dev/null | tr -d '\r')
    if [ "$HT_PASSED" = "true" ]; then
      CONTEXT_MSG="${CONTEXT_MSG}
[HARNESS TESTS: PASSED] ${HT_COUNT} tests passed (ran at ${HT_RAN_AT}). Tests verified by harness — skip re-run unless you changed code since."
    else
      HT_OUTPUT=""
      HT_OUTPUT_FILE="${STATE_DIR}/test-output.txt"
      if [ -f "$HT_OUTPUT_FILE" ]; then
        HT_OUTPUT=$(tail -20 "$HT_OUTPUT_FILE" 2>/dev/null | head -c 500)
      fi
      if [ -n "$HT_OUTPUT" ]; then
        CONTEXT_MSG="${CONTEXT_MSG}
[HARNESS TESTS: FAILED] exit ${HT_EXIT} (ran at ${HT_RAN_AT}). Fix these failures:
${HT_OUTPUT}"
      else
        CONTEXT_MSG="${CONTEXT_MSG}
[HARNESS TESTS: FAILED] exit ${HT_EXIT} (ran at ${HT_RAN_AT}). Run tests to see errors."
      fi
    fi
  fi
fi

# --- BUILD ITERATION GUIDANCE ---
# Injects compound reliability guidance during BUILD phase.
if [ "$PHASE" = "BUILD" ]; then
  BUILD_ITER_FILE="${STATE_DIR}/build-iteration.json"
  BUILD_ITER_GUIDANCE=""

  if [ -f "$BUILD_ITER_FILE" ] && jq '.' "$BUILD_ITER_FILE" >/dev/null 2>&1; then
    BI_STATUS=$(jq -r '.status // "running"' "$BUILD_ITER_FILE" 2>/dev/null | tr -d '\r')
    BI_ITERATION=$(jq -r '.iteration // 0' "$BUILD_ITER_FILE" 2>/dev/null | tr -d '\r')
    BI_MAX=$(jq -r '.max_iterations // 5' "$BUILD_ITER_FILE" 2>/dev/null | tr -d '\r')
    BI_FEATURE=$(jq -r '.feature // ""' "$BUILD_ITER_FILE" 2>/dev/null | tr -d '\r')
    BI_EXIT_CODE=$(jq -r '.last_test_exit_code // ""' "$BUILD_ITER_FILE" 2>/dev/null | tr -d '\r')
    BI_TEST_OUT=$(jq -r '.last_test_output // ""' "$BUILD_ITER_FILE" 2>/dev/null | tr -d '\r')
    BI_FEATURE_TAG=""
    [ -n "$BI_FEATURE" ] && [ "$BI_FEATURE" != "null" ] && BI_FEATURE_TAG=" [${BI_FEATURE}]"

    # Threshold check: iteration >= max triggers STUCK regardless of status field
    if ! printf '%s' "$BI_ITERATION" | grep -qE '^[0-9]+$'; then BI_ITERATION=0; fi
    if ! printf '%s' "$BI_MAX" | grep -qE '^[0-9]+$'; then BI_MAX=5; fi
    if [ "$BI_ITERATION" -ge "$BI_MAX" ] && [ "$BI_STATUS" != "passed" ]; then
      BUILD_ITER_GUIDANCE="BUILD LOOP: STUCK${BI_FEATURE_TAG} — ${BI_ITERATION}/${BI_MAX} iterations exhausted without passing. STOP and escalate to user with exact errors."
    elif [ "$BI_STATUS" = "stuck" ]; then
      BUILD_ITER_GUIDANCE="BUILD LOOP: STUCK${BI_FEATURE_TAG} at iteration ${BI_ITERATION}/${BI_MAX}. STOP and escalate to user with exact errors."
    elif [ "$BI_STATUS" = "passed" ]; then
      BUILD_ITER_GUIDANCE="BUILD LOOP: Tests PASSED${BI_FEATURE_TAG} at iteration ${BI_ITERATION}. Proceed to next feature or spawn verifier."
    elif [ -n "$BI_EXIT_CODE" ] && [ "$BI_EXIT_CODE" != "0" ] && [ "$BI_EXIT_CODE" != "null" ]; then
      # Test failed — inject error feedback (truncated to 500 chars to stay in budget)
      BI_TRUNCATED=$(printf '%s' "$BI_TEST_OUT" | head -c 500)
      if [ -n "$BI_TRUNCATED" ]; then
        BUILD_ITER_GUIDANCE="BUILD LOOP: Iteration ${BI_ITERATION}/${BI_MAX}${BI_FEATURE_TAG} — tests FAILED (exit ${BI_EXIT_CODE}). Fix this error then rerun:
${BI_TRUNCATED}"
      else
        BUILD_ITER_GUIDANCE="BUILD LOOP: Iteration ${BI_ITERATION}/${BI_MAX}${BI_FEATURE_TAG} — tests FAILED (exit ${BI_EXIT_CODE}). Run tests, read output, fix."
      fi
    fi
  fi

  # First BUILD entry or no iteration file — show setup guidance
  if [ -z "$BUILD_ITER_GUIDANCE" ]; then
    BUILD_ITER_GUIDANCE="BUILD LOOP: After each code change — run tests, capture output to .claude/state/build-iteration.json, fix failures. Roles: .claude/roles/executor.md (implement), .claude/roles/verifier.md (verify)."
    if [ ! -f "${STATE_DIR}/context-snapshot.md" ]; then
      BUILD_ITER_GUIDANCE="${BUILD_ITER_GUIDANCE}
CONTEXT: Before implementing, explore the target codebase and write a ~100 line snapshot to .claude/state/context-snapshot.md (files, patterns, test structure, dependencies)."
    fi
  fi

  if [ -n "$BUILD_ITER_GUIDANCE" ]; then
    CONTEXT_MSG="${CONTEXT_MSG}
${BUILD_ITER_GUIDANCE}"
  fi
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
if [ "$PHASE" = "BUILD" ] && [ -n "$PENDING_ITEMS" ]; then
  CONTEXT_MSG="${CONTEXT_MSG}
PENDING ITEMS: ${PENDING_ITEMS}"
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