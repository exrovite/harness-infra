#!/bin/bash
# post-write-check.sh — Claude Code PostToolUse hook (Write/Edit only)
# Memory-hardened: uses append-only JSONL, atomic writes, hash-based change detection.
# NO jq WRITE operations. jq used only for READING.
# IMPORTANT: ALL diagnostic output goes to stderr (&2). ONLY the final JSON goes to stdout.

# Read tool context from stdin (Claude Code passes tool_input via stdin JSON)
HOOK_INPUT=$(cat)
TOOL_FILE_PATH=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null)

# Load helpers
source "$HOME/.claude/scripts/lib-helpers.sh" 2>/dev/null

STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
MARKER_FILE="${STATE_DIR}/phase-complete-marker.md"

# Auto-initialize if project has .claude/ but no harness state
if [ -d ".claude" ] && [ ! -f "${STATE_DIR}/current-phase.json" ]; then
  bash "$HOME/.claude/scripts/init-project.sh" 2>/dev/null
fi

# --- SESSION START DETECTION ---
# If write-count is 0 or missing, this is the first Write/Edit of a new session.
# Run startup-recovery to catch missed session-end and refresh memory.
CURRENT_WRITES=$(cat "${STATE_DIR}/write-count.txt" 2>/dev/null || printf "0")
if [ "$CURRENT_WRITES" = "0" ] && [ -f "${STATE_DIR}/current-phase.json" ]; then
  bash "$HOME/.claude/scripts/startup-recovery.sh" 2>/dev/null
fi

# --- WRITE COUNTER (atomic) ---
WRITE_COUNTER="${STATE_DIR}/write-count.txt"
WRITES=0
if [ -f "$WRITE_COUNTER" ]; then
  WRITES=$(cat "$WRITE_COUNTER" 2>/dev/null || printf "0")
fi
WRITES=$((WRITES + 1))
atomic_write "$WRITES" "$WRITE_COUNTER"

# --- WATCHER SELF-CHECK ---
WATCHER_REGISTRY="$HOME/.openclaw/watchers/REGISTRY.json"
WATCHER_PROMPT="${STATE_DIR}/watcher-self-check.md"
WATCHER_STATUS="no registry"

if [ -f "$WATCHER_REGISTRY" ]; then
  ACTIVE_WATCHERS=$(jq '[.watchers[] | select(.status == "active")] | length' "$WATCHER_REGISTRY" 2>/dev/null || printf "0")
  if [ "$ACTIVE_WATCHERS" -gt 0 ]; then
    WATCHER_STATUS="claimed (${ACTIVE_WATCHERS} active)"
  else
    WATCHER_STATUS="not claimed"
  fi
fi

if [ "$WRITES" -ge 5 ] && [ -f "$WATCHER_REGISTRY" ]; then
  if [ "$ACTIVE_WATCHERS" -eq 0 ]; then
    WATCHER_STATUS="NOT CLAIMED — claim one after 5+ writes!"
    if [ ! -f "$WATCHER_PROMPT" ]; then
      PROMPT_CONTENT="# WATCHER SELF-CHECK

You have made ${WRITES} file writes this session without a watcher.

Ask yourself:
1. Am I currently doing a multi-step task?
2. Does this task have 3 or more steps that I need to track?
3. Could I drift or forget where I am if context gets long?

If YES to any: claim a watcher at C:\\Users\\exrov\\.openclaw\\watchers\\
If NO (quick edit or simple question): continue without one.

Also check:
- Is there anything I should be doing BETWEEN steps that I have skipped?
- Have I updated progress-notes.md?
- Have I run tests after my last code change?
- Am I still following the state machine phase I am in?"
      atomic_write "$PROMPT_CONTENT" "$WATCHER_PROMPT"
    fi
  else
    # Watcher is active — remove the nag prompt (don't reset counter)
    rm -f "$WATCHER_PROMPT" 2>/dev/null
  fi
fi

# --- READ PHASE STATE (used by memory updates AND JSON output) ---
PHASE="UNKNOWN"
SPRINT="0"
ITERATION="0"
if [ -f "${STATE_DIR}/current-phase.json" ]; then
  PHASE=$(jq -r '.phase // "UNKNOWN"' "${STATE_DIR}/current-phase.json" 2>/dev/null)
  SPRINT=$(jq -r '.sprint // 0' "${STATE_DIR}/current-phase.json" 2>/dev/null)
  ITERATION=$(jq -r '.iteration // 0' "${STATE_DIR}/current-phase.json" 2>/dev/null)
fi

# --- AUTOMATIC MEMORY UPDATES (hardened) ---
MEMORY_DIR=".agent-memory"
if [ -d "$MEMORY_DIR" ] && [ -f "${STATE_DIR}/current-phase.json" ]; then

  TIMESTAMP=$(date -Iseconds)

  # 1. session-context.md — hash-based, only writes if changed
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    MODIFIED_FILES=$(git diff --name-only HEAD 2>/dev/null | head -10 | sed 's/^/  - /')
  elif [ -f "${STATE_DIR}/unverified-writes.jsonl" ]; then
    MODIFIED_FILES=$(jq -r '.file' "${STATE_DIR}/unverified-writes.jsonl" 2>/dev/null | sort -u | tail -10 | sed 's/^/  - /')
  else
    MODIFIED_FILES=""
  fi
  CONTEXT_CONTENT="# Session Context (auto-updated by hook)
Last updated: ${TIMESTAMP}
Phase: ${PHASE}
Sprint: ${SPRINT}
Iteration: ${ITERATION}
Write count: ${WRITES}
Working directory: $(pwd)
Last modified files:
${MODIFIED_FILES}"

  mkdir -p "${MEMORY_DIR}/working" 2>/dev/null
  write_if_changed "$CONTEXT_CONTENT" "${MEMORY_DIR}/working/session-context.md"

  # 2. recent-activity.jsonl — APPEND-ONLY (replaces fragile jq edit of JSON)
  ACTIVITY_FILE="${MEMORY_DIR}/working/recent-activity.jsonl"
  append_jsonl "{\"ts\":\"${TIMESTAMP}\",\"phase\":\"${PHASE}\",\"writes\":${WRITES}}" "$ACTIVITY_FILE"

fi

# --- FILE WRITE TRACKER (for verification type enforcement) ---
# Accumulate file paths of agent work product for classifier
WRITTEN_FILE="${TOOL_FILE_PATH:-}"
if [ -n "$WRITTEN_FILE" ]; then
  NORM_FILE=$(printf '%s' "$WRITTEN_FILE" | tr '\\' '/')
  case "$NORM_FILE" in
    *.claude/state/*|*.claude/pre-flight/*|*.openclaw/watchers/*|*.agent-memory/*) ;;
    *)
      TS_W=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
      SAFE_W=$(printf '%s' "$NORM_FILE" | sed 's/\\/\\\\/g; s/"/\\"/g' | head -c 300)
      printf '{"ts":"%s","file":"%s"}\n' "$TS_W" "$SAFE_W" >> "${STATE_DIR}/unverified-writes.jsonl"
      ;;
  esac
fi

# --- SIGNAL 1: TDD TEST FILE WRITE DETECTION ---
# During BUILD phase with TDD enabled, detect when test files are written
# and log TEST_FILE_WRITTEN events to tdd-events.jsonl
TDD_DIR="${STATE_DIR}/tdd"
TDD_CONFIG="${TDD_DIR}/tdd-config.json"
if [ "$PHASE" = "BUILD" ] && [ -f "$TDD_CONFIG" ]; then
  TDD_REQUIRED=$(jq -r '.tdd_required // false' "$TDD_CONFIG" 2>/dev/null || echo "false")
  if [ "$TDD_REQUIRED" = "true" ]; then
    # Get the file that was just written from hook environment
    WRITTEN_FILE="${TOOL_FILE_PATH:-}"
    if [ -n "$WRITTEN_FILE" ]; then
      # Check if the written file matches test file naming patterns
      BASENAME=$(basename "$WRITTEN_FILE" 2>/dev/null || true)
      IS_TEST=false
      case "$BASENAME" in
        test_*.py|*_test.py|*_test.go|*_test.rs) IS_TEST=true ;;
        *.test.js|*.test.ts|*.test.jsx|*.test.tsx) IS_TEST=true ;;
        *.spec.js|*.spec.ts|*.spec.jsx|*.spec.tsx) IS_TEST=true ;;
        test_*.rb|*_spec.rb) IS_TEST=true ;;
        *Test.java|*Test.cs|*_test.dart) IS_TEST=true ;;
      esac
      # Also check if file is in a test directory
      if echo "$WRITTEN_FILE" | grep -qiE '(^|/)(tests?|__tests__|spec|specs)/'; then
        IS_TEST=true
      fi
      if [ "$IS_TEST" = true ]; then
        TS=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
        SAFE_FILE=$(printf '%s' "$WRITTEN_FILE" | sed 's|\\|\\\\|g; s|"|\\"|g' | head -c 200)
        EVENTS_FILE="${TDD_DIR}/tdd-events.jsonl"
        mkdir -p "$TDD_DIR" 2>/dev/null
        append_jsonl "{\"ts\":\"${TS}\",\"event\":\"TEST_FILE_WRITTEN\",\"file\":\"${SAFE_FILE}\"}" "$EVENTS_FILE"
        echo "TDD Signal 1: test file write detected: $WRITTEN_FILE" >&2
      fi
    fi
  fi
fi

# --- PHASE VALIDATION ---
PHASE_FEEDBACK=""
if [ -f "$MARKER_FILE" ]; then
  # jq READ only (safe)
  CURRENT_PHASE=$(jq -r '.phase // "UNKNOWN"' "${STATE_DIR}/current-phase.json" 2>/dev/null)

  if [ "$CURRENT_PHASE" != "UNKNOWN" ]; then
    case "$CURRENT_PHASE" in
      "PLAN") PHASE_NUM=1 ;;
      "NEGOTIATE") PHASE_NUM=2 ;;
      "BUILD") PHASE_NUM=3 ;;
      "EVALUATE") PHASE_NUM=4 ;;
      *) PHASE_NUM=0 ;;
    esac

    if [ "$PHASE_NUM" -gt 0 ]; then
      VALIDATION_OUTPUT=$(bash "$HOME/.claude/scripts/validate-phase.sh" "$PHASE_NUM" 2>&1)
      VALIDATION_EXIT=$?

      if [ $VALIDATION_EXIT -ne 0 ]; then
        FEEDBACK="# Phase Validation Failed

Phase: ${CURRENT_PHASE}
Timestamp: $(date -Iseconds)

## Feedback
${VALIDATION_OUTPUT}"
        atomic_write "$FEEDBACK" "${STATE_DIR}/phase-feedback.md"
        PHASE_FEEDBACK="VALIDATION FAILED — see phase-feedback.md"
      else
        # Log phase transition (append-only JSONL)
        if [ -d "$MEMORY_DIR" ]; then
          mkdir -p "${MEMORY_DIR}/episodic/decisions" 2>/dev/null
          append_jsonl "{\"event\":\"phase_complete\",\"phase\":\"${CURRENT_PHASE}\",\"ts\":\"$(date -Iseconds)\"}" \
            "${MEMORY_DIR}/episodic/decisions/transitions.jsonl"
        fi
      fi
    fi
    rm -f "$MARKER_FILE"
  fi
fi

# --- EVIDENCE CHECKPOINT COUNTER + TRIGGER ---
# After each write, increment the checkpoint counter.
# When threshold reached and must-do summary exists: trigger checkpoint.
EC_COUNTER_FILE="${STATE_DIR}/checkpoint-counter.json"
EC_CHECKPOINT_FILE="${STATE_DIR}/evidence-checkpoint.json"
EC_SUMMARY_FILE="${STATE_DIR}/must-do-summary.md"
EC_CONFIG_FILE="${STATE_DIR}/checkpoint-config.json"

# Only run during BUILD phase — evidence checkpoints verify code work compliance.
# In PLAN/NEGOTIATE/EVALUATE/COMPLETE there's no code to verify.
# Note: we run even when checkpoint exists — step-change detection needs to
# fire so stale checkpoints get replaced when the agent moves to new work.
if [ "$CURRENT_PHASE" = "BUILD" ] && [ -f "$EC_SUMMARY_FILE" ]; then
  # Read threshold (default 15)
  EC_THRESHOLD=15
  if [ -f "$EC_CONFIG_FILE" ] && jq '.' "$EC_CONFIG_FILE" >/dev/null 2>&1; then
    EC_CFG_VAL=$(jq -r '.interval // 15' "$EC_CONFIG_FILE" 2>/dev/null | tr -d '\r')
    if printf '%s' "$EC_CFG_VAL" | grep -qE '^[0-9]+$'; then
      EC_THRESHOLD="$EC_CFG_VAL"
    fi
  fi

  # Skip if threshold is 0 (disabled)
  if [ "$EC_THRESHOLD" -gt 0 ]; then
    # Read counter state
    EC_WRITES=0
    EC_LAST_STEP=""
    if [ -f "$EC_COUNTER_FILE" ] && jq '.' "$EC_COUNTER_FILE" >/dev/null 2>&1; then
      EC_WRITES=$(jq -r '.writes // 0' "$EC_COUNTER_FILE" 2>/dev/null | tr -d '\r')
      EC_LAST_STEP=$(jq -r '.last_step // ""' "$EC_COUNTER_FILE" 2>/dev/null | tr -d '\r')
      if ! printf '%s' "$EC_WRITES" | grep -qE '^[0-9]+$'; then EC_WRITES=0; fi
    fi

    # Get current watcher step (reuse from pre-flight gate-counter if available)
    EC_CURRENT_STEP=""
    EC_GATE_COUNTER=".claude/pre-flight/gate-counter.json"
    if [ -f "$EC_GATE_COUNTER" ] && jq '.' "$EC_GATE_COUNTER" >/dev/null 2>&1; then
      EC_CURRENT_STEP=$(jq -r '.last_step // ""' "$EC_GATE_COUNTER" 2>/dev/null | tr -d '\r')
    fi

    # Check for step change
    EC_STEP_CHANGED=false
    if [ -n "$EC_CURRENT_STEP" ] && [ -n "$EC_LAST_STEP" ] && [ "$EC_CURRENT_STEP" != "$EC_LAST_STEP" ]; then
      EC_STEP_CHANGED=true
      EC_WRITES=0
    fi

    # Increment
    EC_WRITES=$((EC_WRITES + 1))

    # Save counter
    EC_SAFE_STEP=$(printf '%s' "$EC_CURRENT_STEP" | sed 's/\\/\\\\/g; s/"/\\"/g' | head -c 200)
    printf '{"writes":%d,"last_step":"%s"}' "$EC_WRITES" "$EC_SAFE_STEP" > "$EC_COUNTER_FILE" 2>/dev/null

    # Trigger checkpoint if threshold reached or step changed
    EC_SHOULD_TRIGGER=false
    EC_TRIGGER_REASON="write_count"
    if [ "$EC_STEP_CHANGED" = true ]; then
      EC_SHOULD_TRIGGER=true
      EC_TRIGGER_REASON="step_change"
    elif [ ! -f "$EC_CHECKPOINT_FILE" ] && [ "$EC_WRITES" -ge "$EC_THRESHOLD" ]; then
      # write_count only triggers when no checkpoint exists (avoid repeated calls)
      EC_SHOULD_TRIGGER=true
      EC_TRIGGER_REASON="write_count"
    fi

    if [ "$EC_SHOULD_TRIGGER" = true ]; then
      bash "$HOME/.claude/scripts/create-evidence-checkpoint.sh" "$EC_TRIGGER_REASON" 2>/dev/null
      if [ $? -eq 0 ]; then
        # Reset counter after triggering
        printf '{"writes":0,"last_step":"%s"}' "$EC_SAFE_STEP" > "$EC_COUNTER_FILE" 2>/dev/null
        echo "evidence-checkpoint: triggered ($EC_TRIGGER_REASON)" >&2
      fi
    fi
  fi
fi

# --- CRON PAUSE AUTO-RESUME ON WRITE (F1: AC4, AC5) ---
# If cron is paused with resume_on_write:true, and the written file is NOT a state file,
# delete the pause file to resume the cron.
CRON_PAUSE_FILE="${STATE_DIR}/cron-paused.json"
if [ -f "$CRON_PAUSE_FILE" ]; then
  CP_RESUME_ON_WRITE=$(jq -r '.resume_on_write // false' "$CRON_PAUSE_FILE" 2>/dev/null | tr -d '\r')
  if [ "$CP_RESUME_ON_WRITE" = "true" ]; then
    # Check if this write is a state file (don't resume on harness self-writes)
    TOOL_PATH_NORM=$(printf '%s' "$TOOL_FILE_PATH" | tr '\\' '/')
    IS_STATE_FILE=false
    if printf '%s' "$TOOL_PATH_NORM" | grep -qF '/.claude/state/'; then
      IS_STATE_FILE=true
    fi
    if [ "$IS_STATE_FILE" = false ]; then
      rm -f "$CRON_PAUSE_FILE" 2>/dev/null
      echo "cron: auto-resumed on write to $(basename "$TOOL_FILE_PATH")" >&2
    fi
  fi
fi

# --- RALPH AUTO-DEACTIVATION ON VERIFIER PASS ---
# When evidence-verdict.json is written with PASS while ralph is active,
# update ralph state immediately (don't wait for next UserPromptSubmit).
RALPH_STATE_FILE="${STATE_DIR}/ralph-mode.json"
VERDICT_NORM=$(printf '%s' "$TOOL_FILE_PATH" | tr '\\' '/' | tr '[:upper:]' '[:lower:]')
if printf '%s' "$VERDICT_NORM" | grep -qF 'evidence-verdict.json'; then
  if [ -f "$RALPH_STATE_FILE" ] && jq -e '.active == true' "$RALPH_STATE_FILE" >/dev/null 2>&1; then
    RALPH_V=$(jq -r '.verdict // ""' "${STATE_DIR}/evidence-verdict.json" 2>/dev/null | tr -d '\r')
    if [ "$RALPH_V" = "PASS" ]; then
      RALPH_VTS=$(jq -r '.timestamp // .checked_at // .verdict_at // .created_at // .ts // ""' "${STATE_DIR}/evidence-verdict.json" 2>/dev/null | tr -d '\r')
      RALPH_LAST_AT=$(jq -r '.last_verdict_at // ""' "$RALPH_STATE_FILE" 2>/dev/null | tr -d '\r')
      # Timestamp freshness check (same logic as on-prompt-submit.sh)
      RALPH_IS_FRESH=false
      if [ -z "$RALPH_LAST_AT" ] || [ "$RALPH_LAST_AT" = "null" ]; then
        RALPH_IS_FRESH=true
      elif [ -n "$RALPH_VTS" ]; then
        R_NEW=$(date -d "$RALPH_VTS" +%s 2>/dev/null) || R_NEW=""
        R_OLD=$(date -d "$RALPH_LAST_AT" +%s 2>/dev/null) || R_OLD=""
        if [ -n "$R_NEW" ] && [ -n "$R_OLD" ]; then
          [ "$R_NEW" -gt "$R_OLD" ] && RALPH_IS_FRESH=true
        elif [[ "$RALPH_VTS" > "$RALPH_LAST_AT" ]]; then
          RALPH_IS_FRESH=true
        fi
      fi
      if [ "$RALPH_IS_FRESH" = true ]; then
        RALPH_UPDATED=$(jq -c --arg ts "$RALPH_VTS" \
          '.last_verdict="PASS" | .active=false | .last_verdict_at=$ts | .failed_criteria=[]' \
          "$RALPH_STATE_FILE" 2>/dev/null | tr -d '\r')
        if [ -n "$RALPH_UPDATED" ]; then
          if type atomic_write >/dev/null 2>&1; then
            atomic_write "$RALPH_UPDATED" "$RALPH_STATE_FILE"
          else
            printf '%s' "$RALPH_UPDATED" > "$RALPH_STATE_FILE"
          fi
          echo "ralph: auto-deactivated on verifier PASS" >&2
        fi
      fi
    fi
  fi
fi

# --- ORPHANED CHECKPOINT AUTO-RESOLVE (Sprint 29) ---
# A pending checkpoint with a FRESH PASS verdict must clear even when the
# triggering write was exempt (phase-complete-marker.md, progress notes, etc.) —
# the pre-write gate only clears on the next NON-exempt source write.
if type clear_evidence_checkpoint_if_pass >/dev/null 2>&1; then
  EC_AR_PHASE=$(jq -r '.phase // ""' "${STATE_DIR}/current-phase.json" 2>/dev/null | tr -d '\r')
  if clear_evidence_checkpoint_if_pass "$STATE_DIR" "$EC_AR_PHASE" >/dev/null 2>&1; then
    echo "evidence-checkpoint: auto-resolved on fresh PASS verdict" >&2
  fi
fi

# --- VERIFIER PASS COMPLETION REMINDER (F3: AC17, AC18) ---
VERDICT_REMINDER=""
if printf '%s' "$VERDICT_NORM" | grep -qF 'evidence-verdict.json'; then
  VR_VERDICT=$(jq -r '.verdict // ""' "${STATE_DIR}/evidence-verdict.json" 2>/dev/null | tr -d '\r')
  if [ "$VR_VERDICT" = "PASS" ]; then
    VERDICT_REMINDER="Verifier PASS — DO NOT release watcher or delete cron yet. Sequence: write phase-complete-marker.md, confirm COMPLETE, THEN release."
  fi
fi

# --- CHECK FOR PENDING ACTIONS ---
PENDING=""
if [ -f "${STATE_DIR}/phase-feedback.md" ]; then
  PENDING="${PENDING} | Phase feedback pending"
fi
if [ -f "${STATE_DIR}/next-fix.md" ]; then
  PENDING="${PENDING} | Fix available: next-fix.md"
fi
if [ -f "${STATE_DIR}/watcher-self-check.md" ]; then
  PENDING="${PENDING} | Watcher self-check needed"
fi
if [ -n "$PHASE_FEEDBACK" ]; then
  PENDING="${PENDING} | ${PHASE_FEEDBACK}"
fi
# Strip leading " | "
PENDING="${PENDING# | }"

# --- HARNESS TEST RESULT INJECTION (C3: AC10) ---
HARNESS_TEST_STATUS=""
HARNESS_RESULT_FILE="${STATE_DIR}/harness-test-result.json"
if [ -f "$HARNESS_RESULT_FILE" ] && jq '.' "$HARNESS_RESULT_FILE" >/dev/null 2>&1; then
  HT_PASSED=$(jq -r '.passed // false' "$HARNESS_RESULT_FILE" 2>/dev/null | tr -d '\r')
  HT_EXIT=$(jq -r '.exit_code // ""' "$HARNESS_RESULT_FILE" 2>/dev/null | tr -d '\r')
  if [ "$HT_PASSED" = "true" ]; then
    HARNESS_TEST_STATUS="HARNESS_TESTS: PASSED"
  else
    HARNESS_TEST_STATUS="HARNESS_TESTS: FAILED (exit ${HT_EXIT})"
  fi
fi

# --- BUILD THE additionalContext STRING ---
CONTEXT_MSG="[HARNESS] Phase: ${PHASE} | Sprint: ${SPRINT} | Iter: ${ITERATION} | Writes: ${WRITES} | Watcher: ${WATCHER_STATUS}"
if [ -n "$HARNESS_TEST_STATUS" ]; then
  CONTEXT_MSG="${CONTEXT_MSG} | ${HARNESS_TEST_STATUS}"
fi
if [ -n "$PENDING" ]; then
  CONTEXT_MSG="${CONTEXT_MSG} | PENDING: ${PENDING}"
fi
if [ -n "$VERDICT_REMINDER" ]; then
  CONTEXT_MSG="${CONTEXT_MSG} | ${VERDICT_REMINDER}"
fi

# --- OUTPUT JSON TO STDOUT (the ONLY stdout from this script) ---
# This is what makes Claude Code actually SEE the hook output.
# All other output in this script goes to files or stderr.
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}' \
  "$(printf '%s' "$CONTEXT_MSG" | sed 's|\\|\\\\|g; s|"|\\"|g')"

exit 0
