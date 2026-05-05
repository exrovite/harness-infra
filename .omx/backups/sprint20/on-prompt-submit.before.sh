#!/bin/bash
# on-prompt-submit.sh — Claude Code UserPromptSubmit hook
# Fires at the START of every Claude turn, injecting state context.
# When tools are LOCKED, warns Claude before it even tries.

STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
WATCHER_REGISTRY="$HOME/.openclaw/watchers/REGISTRY.json"

# --- READ PHASE STATE ---
PHASE="UNKNOWN"
SPRINT="0"
ITERATION="0"
if [ -f "${STATE_DIR}/current-phase.json" ]; then
  PHASE=$(jq -r '.phase // "UNKNOWN"' "${STATE_DIR}/current-phase.json" 2>/dev/null)
  SPRINT=$(jq -r '.sprint // 0' "${STATE_DIR}/current-phase.json" 2>/dev/null)
  ITERATION=$(jq -r '.iteration // 0' "${STATE_DIR}/current-phase.json" 2>/dev/null)
fi

# --- READ WRITE COUNT ---
WRITES=$(cat "${STATE_DIR}/write-count.txt" 2>/dev/null || printf "0")
WRITES=$(printf '%s' "$WRITES" | grep -o '[0-9]*' | head -1)
WRITES=${WRITES:-0}

# --- CHECK WATCHER STATUS AND LOCK STATE (project-scoped) ---
WATCHER_STATUS="no registry"
TOOLS_LOCKED="false"

# Normalize current project path for comparison (lowercase, forward slashes, no trailing slash)
CURRENT_PROJECT=$(pwd -W 2>/dev/null || pwd)
CURRENT_PROJECT=$(printf '%s' "$CURRENT_PROJECT" | tr '\\\\' '/' | sed 's|/$||' | tr '[:upper:]' '[:lower:]')

if [ -f "$WATCHER_REGISTRY" ]; then
  # Check for watchers scoped to THIS project
  PROJECT_WATCHERS=$(jq --arg proj "$CURRENT_PROJECT" \
    '[.watchers[] | select(.status == "active" and .project != null and ((.project | gsub("\\\\";"/") | sub("/$";"") | ascii_downcase) == $proj))] | length' \
    "$WATCHER_REGISTRY" 2>/dev/null || printf "0")
  if [ "$PROJECT_WATCHERS" -gt 0 ]; then
    CLAIMED_BY=$(jq -r --arg proj "$CURRENT_PROJECT" \
      '[.watchers[] | select(.status == "active" and .project != null and ((.project | gsub("\\\\";"/") | sub("/$";"") | ascii_downcase) == $proj))][0].claimed_by // "unknown"' \
      "$WATCHER_REGISTRY" 2>/dev/null)
    WATCHER_STATUS="claimed by: ${CLAIMED_BY}"
  else
    WATCHER_STATUS="not claimed for this project"
    if [ "$WRITES" -ge 2 ]; then
      TOOLS_LOCKED="true"
      WATCHER_STATUS="NOT CLAIMED FOR THIS PROJECT — YOUR WRITE/EDIT TOOLS ARE LOCKED"
    fi
  fi
fi

# --- CHECK PENDING FILES ---
PENDING_ITEMS=""
if [ -f "${STATE_DIR}/phase-feedback.md" ]; then
  PENDING_ITEMS="${PENDING_ITEMS} | Phase feedback pending"
fi
if [ -f "${STATE_DIR}/next-fix.md" ]; then
  PENDING_ITEMS="${PENDING_ITEMS} | Fix available in next-fix.md"
fi
if [ -f "${STATE_DIR}/watcher-self-check.md" ]; then
  PENDING_ITEMS="${PENDING_ITEMS} | Watcher self-check needed"
fi
PENDING_ITEMS="${PENDING_ITEMS# | }"

# --- BUILD CONTEXT MESSAGE ---
CONTEXT_MSG="[HARNESS STATE] Phase: ${PHASE} | Sprint: ${SPRINT} | Iter: ${ITERATION} | Writes: ${WRITES} | Watcher: ${WATCHER_STATUS}"

if [ "$TOOLS_LOCKED" = "true" ]; then
  CONTEXT_MSG="${CONTEXT_MSG} — You MUST claim a watcher using Bash before you can Write/Edit any files. Use CronCreate for 3-min reminders."
fi

if [ -n "$PENDING_ITEMS" ]; then
  CONTEXT_MSG="${CONTEXT_MSG} | PENDING: ${PENDING_ITEMS}"
fi

# --- MUST-DO SUMMARY INJECTION ---
# If this project has required reading and the agent has written a summary,
# inject it into every prompt so the agent sees it while working — not just at a gate.
MUST_DO_SUMMARY="${STATE_DIR}/must-do-summary.md"
if [ -f "$MUST_DO_SUMMARY" ]; then
  # Truncate to first 800 chars to keep context lean
  SUMMARY_TEXT=$(head -c 800 "$MUST_DO_SUMMARY" 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g')
  if [ -n "$SUMMARY_TEXT" ]; then
    CONTEXT_MSG="${CONTEXT_MSG} | [MUST-DO ACTIVE] ${SUMMARY_TEXT}"
    # Log injection for debugging — append-only JSONL
    INJECT_LOG="${STATE_DIR}/must-do-injection-log.jsonl"
    INJECT_TS=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
    INJECT_STEP=$(cat "${STATE_DIR}/must-do-summary-step.txt" 2>/dev/null | tr -d '\r\n')
    printf '{"ts":"%s","step":"%s","chars":%d}\n' "$INJECT_TS" "$INJECT_STEP" "${#SUMMARY_TEXT}" >> "$INJECT_LOG" 2>/dev/null
  fi
fi

# --- EVIDENCE CHECKPOINT INJECTION ---
EC_CHECKPOINT="${STATE_DIR}/evidence-checkpoint.json"
if [ -f "$EC_CHECKPOINT" ] && jq -r '.status' "$EC_CHECKPOINT" 2>/dev/null | tr -d '\r' | grep -q "pending"; then
  EC_INJ_VERDICT="${STATE_DIR}/evidence-verdict.json"
  if [ -f "$EC_INJ_VERDICT" ] && jq '.' "$EC_INJ_VERDICT" >/dev/null 2>&1; then
    EC_INJ_V=$(jq -r '.verdict // ""' "$EC_INJ_VERDICT" 2>/dev/null | tr -d '\r')
    if [ "$EC_INJ_V" = "FAIL" ]; then
      EC_INJ_RL=0
      if [ -f "${STATE_DIR}/evidence-remediation.md" ]; then
        EC_INJ_RL=$(wc -c < "${STATE_DIR}/evidence-remediation.md" 2>/dev/null | tr -d ' ')
      fi
      if [ "$EC_INJ_RL" -lt 200 ]; then
        CONTEXT_MSG="${CONTEXT_MSG} | [EVIDENCE CHECKPOINT FAILED] Writes blocked. Read must-do docs and write remediation plan to .claude/state/evidence-remediation.md (200+ chars, reference failed phases and docs)."
      else
        CONTEXT_MSG="${CONTEXT_MSG} | [EVIDENCE CHECKPOINT FAILED] Remediation accepted. Produce evidence in .claude/evidence/, then delete .claude/state/evidence-verdict.json and spawn a new verifier. Verifier must write verdict to .claude/state/evidence-verdict.json as JSON: {\"verdict\":\"PASS or FAIL\",\"findings\":[...],\"summary\":\"text\"}"
      fi
    fi
  else
    CONTEXT_MSG="${CONTEXT_MSG} | [EVIDENCE CHECKPOINT] Writes blocked until verified. If you are the builder: spawn a verifier sub-agent (do NOT tell it what to check). If you are the verifier: read .claude/state/evidence-checkpoint.json — it contains the must-do source files, your instructions, and what to check. Write your verdict to .claude/state/evidence-verdict.json as JSON: {\"verdict\":\"PASS or FAIL\",\"findings\":[{\"phase\":\"X\",\"evidence_file\":\"path or null\",\"quality\":\"substantive or insufficient or null\",\"note\":\"details\"}],\"summary\":\"text\"}"
  fi
fi

# --- STRATEGY LOOP BREAKER — Nudge/Block injection ---
SLB_RESULT=""
SLB_EXIT=0
if [ -f "$HOME/.claude/scripts/detect-strategy-loop.sh" ]; then
  SLB_RESULT=$(bash "$HOME/.claude/scripts/detect-strategy-loop.sh" 2>/dev/null) || SLB_EXIT=$?
fi

if [ "$SLB_EXIT" -eq 1 ] || [ "$SLB_EXIT" -eq 2 ]; then
  SLB_STATE_FILE="${STATE_DIR}/strategy-loop-state.json"

  # --- Find must-do files for the message ---
  SLB_MUST_DO_DIR=""
  for CANDIDATE in "docs/must do" "docs/must-do" ".claude/must-do"; do
    if [ -d "$CANDIDATE" ]; then
      SLB_MUST_DO_DIR="$CANDIDATE"
      break
    fi
  done

  SLB_FILE_LIST=""
  if [ -n "$SLB_MUST_DO_DIR" ] && [ -f "${SLB_MUST_DO_DIR}/must-do.md" ]; then
    # Read file paths, sort with "mistake" files first
    SLB_MISTAKE_FILES=""
    SLB_OTHER_FILES=""
    while IFS= read -r FPATH || [ -n "$FPATH" ]; do
      [ -z "$FPATH" ] && continue
      # Skip lines that aren't file paths (headers, blank)
      case "$FPATH" in "#"*|"---"*|" "*) continue ;; esac
      FBASE=$(basename "$FPATH")
      if printf '%s' "$FBASE" | grep -qi "mistake"; then
        SLB_MISTAKE_FILES="${SLB_MISTAKE_FILES}  - ${FPATH} (PRIORITY)\n"
      else
        SLB_OTHER_FILES="${SLB_OTHER_FILES}  - ${FPATH}\n"
      fi
    done < "${SLB_MUST_DO_DIR}/must-do.md"
    SLB_FILE_LIST="${SLB_MISTAKE_FILES}${SLB_OTHER_FILES}"
  fi

  if [ "$SLB_EXIT" -eq 1 ]; then
    # --- Nudge (Tier 1) ---
    # Cooldown: only increment nudge_count if last_nudge_ts > 60s ago
    SLB_NOW=$(date +%s 2>/dev/null)
    SLB_LAST_TS=""
    SLB_CURRENT_COUNT=0
    if [ -f "$SLB_STATE_FILE" ] && jq '.' "$SLB_STATE_FILE" >/dev/null 2>&1; then
      SLB_LAST_TS=$(jq -r '.last_nudge_ts // ""' "$SLB_STATE_FILE" 2>/dev/null | tr -d '\r')
      SLB_CURRENT_COUNT=$(jq -r '.nudge_count // 0' "$SLB_STATE_FILE" 2>/dev/null | tr -d '\r')
    fi
    if ! printf '%s' "$SLB_CURRENT_COUNT" | grep -qE '^[0-9]+$' 2>/dev/null; then
      SLB_CURRENT_COUNT=0
    fi

    SLB_SHOULD_INCREMENT=true
    if [ -n "$SLB_LAST_TS" ] && [ "$SLB_LAST_TS" != "null" ]; then
      SLB_LAST_EPOCH=$(date -d "$SLB_LAST_TS" +%s 2>/dev/null || echo "0")
      SLB_ELAPSED=$((SLB_NOW - SLB_LAST_EPOCH))
      if [ "$SLB_ELAPSED" -lt 60 ]; then
        SLB_SHOULD_INCREMENT=false
      fi
    fi

    if [ "$SLB_SHOULD_INCREMENT" = true ]; then
      SLB_NEW_COUNT=$((SLB_CURRENT_COUNT + 1))
      SLB_NOW_TS=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
      # Read current state values to preserve them
      SLB_CUR_FP=$(jq -r '.last_output_fingerprint // ""' "$SLB_STATE_FILE" 2>/dev/null | tr -d '\r' | sed 's/\\/\\\\/g; s/"/\\"/g')
      SLB_CUR_CHURN=$(jq -c '.last_churn_files // []' "$SLB_STATE_FILE" 2>/dev/null | tr -d '\r')
      if ! printf '%s' "$SLB_CUR_CHURN" | jq '.' >/dev/null 2>&1; then SLB_CUR_CHURN="[]"; fi

      source "$HOME/.claude/scripts/lib-helpers.sh" 2>/dev/null
      if type atomic_write >/dev/null 2>&1; then
        atomic_write "{\"nudge_count\":${SLB_NEW_COUNT},\"last_nudge_ts\":\"${SLB_NOW_TS}\",\"last_output_fingerprint\":\"${SLB_CUR_FP}\",\"last_churn_files\":${SLB_CUR_CHURN},\"blocked\":false}" "$SLB_STATE_FILE"
      fi
    fi

    # Build nudge message
    SLB_NUDGE_MSG="[STRATEGY LOOP DETECTED — Tier 1 Nudge] You appear to be repeating the same failing approach."
    if [ -n "$SLB_FILE_LIST" ]; then
      SLB_NUDGE_MSG="${SLB_NUDGE_MSG} STOP and re-read your must-do files for alternative strategies:\n${SLB_FILE_LIST}"
    else
      SLB_NUDGE_MSG="${SLB_NUDGE_MSG} Review your knowledge base, AgentWiki, and any strategy documents for alternative approaches."
    fi
    CONTEXT_MSG="${CONTEXT_MSG} | ${SLB_NUDGE_MSG}"

  elif [ "$SLB_EXIT" -eq 2 ]; then
    # --- Block (Tier 2) ---
    source "$HOME/.claude/scripts/lib-helpers.sh" 2>/dev/null
    if type atomic_write >/dev/null 2>&1 && [ -f "$SLB_STATE_FILE" ]; then
      # Set blocked=true, preserve other fields
      SLB_CUR_COUNT=$(jq -r '.nudge_count // 0' "$SLB_STATE_FILE" 2>/dev/null | tr -d '\r')
      SLB_CUR_FP=$(jq -r '.last_output_fingerprint // ""' "$SLB_STATE_FILE" 2>/dev/null | tr -d '\r' | sed 's/\\/\\\\/g; s/"/\\"/g')
      SLB_CUR_CHURN=$(jq -c '.last_churn_files // []' "$SLB_STATE_FILE" 2>/dev/null | tr -d '\r')
      SLB_NOW_TS=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
      if ! printf '%s' "$SLB_CUR_CHURN" | jq '.' >/dev/null 2>&1; then SLB_CUR_CHURN="[]"; fi
      atomic_write "{\"nudge_count\":${SLB_CUR_COUNT},\"last_nudge_ts\":\"${SLB_NOW_TS}\",\"last_output_fingerprint\":\"${SLB_CUR_FP}\",\"last_churn_files\":${SLB_CUR_CHURN},\"blocked\":true}" "$SLB_STATE_FILE"
    fi

    SLB_BLOCK_MSG="[STRATEGY LOOP — Tier 2 BLOCK] Your writes are now BLOCKED. You have been nudged ${SLB_CUR_COUNT:-3}+ times but continue looping."
    SLB_BLOCK_MSG="${SLB_BLOCK_MSG} To unblock: 1) Read the must-do files listed below. 2) Write .claude/state/strategy-ack.md with a '## New Approach' section (150+ chars) referencing at least one must-do file by name."
    if [ -n "$SLB_FILE_LIST" ]; then
      SLB_BLOCK_MSG="${SLB_BLOCK_MSG}\nMust-do files:\n${SLB_FILE_LIST}"
    else
      SLB_BLOCK_MSG="${SLB_BLOCK_MSG} (No must-do folder found — write the ack with a '## New Approach' section describing your new strategy, 150+ chars.)"
    fi
    CONTEXT_MSG="${CONTEXT_MSG} | ${SLB_BLOCK_MSG}"
  fi
fi
# --- END STRATEGY LOOP BREAKER ---

# --- OUTPUT TO STDOUT (injected into Claude's context) ---
printf '%s' "$CONTEXT_MSG"

exit 0
