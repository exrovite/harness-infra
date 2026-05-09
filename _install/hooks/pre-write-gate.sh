#!/bin/bash
# pre-write-gate.sh — PreToolUse hook (Write|Edit|Agent)
# 2 free writes, LOCKED at 3rd unless BOTH watcher AND cron are active FOR THIS PROJECT.
# Exit 2 + stderr = BLOCKED
# Exit 0 = ALLOWED

source "$HOME/.claude/scripts/lib-helpers.sh" 2>/dev/null

STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
WRITE_COUNTER="${STATE_DIR}/write-count.txt"
WATCHER_REGISTRY="$HOME/.openclaw/watchers/REGISTRY.json"

# If no harness state, allow silently
if [ ! -f "${STATE_DIR}/current-phase.json" ]; then
  exit 0
fi

# Read stdin once for all gates (tool input JSON from Claude Code)
INPUT_DATA=$(cat)

# PHASE GATE: Only BUILD phase allows source code writes.
# Agents in PLAN/NEGOTIATE/EVALUATE/COMPLETE can only write to infrastructure paths.
CURRENT_PHASE=$(jq -r '.phase // ""' "${STATE_DIR}/current-phase.json" 2>/dev/null)
CURRENT_SPRINT=$(jq -r '.sprint // 0' "${STATE_DIR}/current-phase.json" 2>/dev/null)
PHASE_CTX="[Phase: ${CURRENT_PHASE} | Sprint: ${CURRENT_SPRINT}]"


print_evidence_gate_note() {
  printf "This gate applies to ALL tasks regardless of complexity. Simple tasks drift too.\n" >&2
  printf "This cannot be shortcut.\n\n" >&2
}

print_gates_ahead() {
  if type compute_pending_gates >/dev/null 2>&1; then
    local PROJECT_PATH PENDING_GATES
    PROJECT_PATH=$(pwd -W 2>/dev/null || pwd)
    PENDING_GATES=$(compute_pending_gates "$CURRENT_PHASE" "$CURRENT_SPRINT" "$PROJECT_PATH")
    printf "\nGATES AHEAD (after you clear this):\n" >&2
    if [ -n "$PENDING_GATES" ]; then
      printf "%s" "$PENDING_GATES" >&2
    else
      printf " -> all clear - write freely\n" >&2
    fi
  fi
}


# RALPH STATE PROTECTION + COMPLETION GATE
RALPH_STATE_FILE="${STATE_DIR}/ralph-mode.json"
RALPH_TARGET=$(printf '%s' "$INPUT_DATA" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null)
RALPH_TARGET_NORM=$(printf '%s' "$RALPH_TARGET" | tr '\\' '/' | tr '[:upper:]' '[:lower:]')
RALPH_TOOL=$(printf '%s' "$INPUT_DATA" | jq -r '.tool_name // ""' 2>/dev/null)

iso_newer_than() {
  local NEW_TS="$1"
  local OLD_TS="$2"
  [ -n "$NEW_TS" ] || return 1
  if [ -z "$OLD_TS" ] || [ "$OLD_TS" = "null" ]; then return 0; fi
  local NEW_EPOCH OLD_EPOCH
  NEW_EPOCH=$(date -d "$NEW_TS" +%s 2>/dev/null) || NEW_EPOCH=""
  OLD_EPOCH=$(date -d "$OLD_TS" +%s 2>/dev/null) || OLD_EPOCH=""
  if [ -n "$NEW_EPOCH" ] && [ -n "$OLD_EPOCH" ]; then
    [ "$NEW_EPOCH" -gt "$OLD_EPOCH" ]
    return $?
  fi
  [[ "$NEW_TS" > "$OLD_TS" ]]
}

if printf '%s' "$RALPH_TARGET_NORM" | grep -qiF 'ralph-mode.json'; then
  printf "[ADMIN GATE] BLOCKED: ralph-mode.json is user-controlled. Only the user can activate/deactivate ralph mode.\n" >&2
  print_gates_ahead
  exit 2
fi

if [ -f "$RALPH_STATE_FILE" ] && jq -e '.active == true' "$RALPH_STATE_FILE" >/dev/null 2>&1; then
  RALPH_ITER=$(jq -r '.iteration // 1' "$RALPH_STATE_FILE" 2>/dev/null | tr -d '\r')
  RALPH_MAX=$(jq -r '.max_iterations // 5' "$RALPH_STATE_FILE" 2>/dev/null | tr -d '\r')
  RALPH_LAST=$(jq -r '.last_verdict // ""' "$RALPH_STATE_FILE" 2>/dev/null | tr -d '\r')
  RALPH_LAST_AT=$(jq -r '.last_verdict_at // ""' "$RALPH_STATE_FILE" 2>/dev/null | tr -d '\r')
  if ! printf '%s' "$RALPH_ITER" | grep -qE '^[0-9]+$'; then RALPH_ITER=1; fi
  if ! printf '%s' "$RALPH_MAX" | grep -qE '^[0-9]+$'; then RALPH_MAX=5; fi

  RALPH_EXEMPT=false
  if [ "$RALPH_TOOL" = "Agent" ]; then RALPH_EXEMPT=true; fi
  for RALPH_PAT in '.claude/state/' '.openclaw/watchers/' '.agent-memory/' '.claude/contracts/' '.claude/specs/' '.claude/pre-flight/' '.claude/evidence/' 'agentwiki/'; do
    if printf '%s' "$RALPH_TARGET_NORM" | grep -qiF "$RALPH_PAT"; then
      RALPH_EXEMPT=true
      break
    fi
  done

  if [ "$RALPH_ITER" -gt "$RALPH_MAX" ] && [ "$RALPH_LAST" != "PASS" ] && [ "$RALPH_EXEMPT" = false ]; then
    printf "[EVIDENCE GATE] BLOCKED: Ralph loop STUCK - %s iterations exhausted without PASS. Write .claude/state/stuck-report.md and wait for user.\n" "$RALPH_MAX" >&2
    print_evidence_gate_note
    print_gates_ahead
    exit 2
  fi

  if printf '%s' "$RALPH_TARGET_NORM" | grep -qiF 'phase-complete-marker.md'; then
    RALPH_VERDICT_FILE="${STATE_DIR}/evidence-verdict.json"
    RALPH_ALLOW_COMPLETE=false
    if [ -f "$RALPH_VERDICT_FILE" ] && jq '.' "$RALPH_VERDICT_FILE" >/dev/null 2>&1; then
      RALPH_V=$(jq -r '.verdict // ""' "$RALPH_VERDICT_FILE" 2>/dev/null | tr -d '\r')
      RALPH_TS=$(jq -r '.timestamp // .checked_at // .verdict_at // .created_at // .ts // ""' "$RALPH_VERDICT_FILE" 2>/dev/null | tr -d '\r')
      if [ "$RALPH_V" = "PASS" ] && iso_newer_than "$RALPH_TS" "$RALPH_LAST_AT"; then
        RALPH_ALLOW_COMPLETE=true
      fi
    fi
    if [ "$RALPH_ALLOW_COMPLETE" != true ]; then
      printf "[EVIDENCE GATE] BLOCKED: Ralph loop active - verifier must return PASS before completion. Spawn a verifier sub-agent, get PASS verdict in evidence-verdict.json, then retry.\n" >&2
      print_evidence_gate_note
      print_gates_ahead
      exit 2
    fi
  fi
fi
if [ "$CURRENT_PHASE" != "BUILD" ] && [ -n "$CURRENT_PHASE" ]; then
  # Agent tool spawns subagents, doesn't write files — exempt from phase gate
  PG_TOOL=$(printf '%s' "$INPUT_DATA" | jq -r '.tool_name // ""' 2>/dev/null)
  if [ "$PG_TOOL" != "Agent" ]; then
  PG_TARGET=$(printf '%s' "$INPUT_DATA" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null)
  PG_TARGET_NORM=$(printf '%s' "$PG_TARGET" | tr '\\' '/' | tr '[:upper:]' '[:lower:]')
  PG_EXEMPT=false
  for PG_PAT in '.claude/state/' '.claude/specs/' '.claude/contracts/' '.claude/pre-flight/' '.openclaw/watchers/' '.agent-memory/' 'agentwiki/' 'claude-progress' 'features.json' 'tests.json' 'claude.md'; do
    if printf '%s' "$PG_TARGET_NORM" | grep -qiF "$PG_PAT"; then
      PG_EXEMPT=true
      break
    fi
  done
  # Markdown files are documentation, not source code — allow in all phases
  if [ "$PG_EXEMPT" = false ]; then
    case "$PG_TARGET_NORM" in
      *.md) PG_EXEMPT=true ;;
    esac
  fi
  if [ "$PG_EXEMPT" = false ]; then
    case "$CURRENT_PHASE" in
      PLAN)
        printf "[ADMIN GATE] BLOCKED: You are in PLAN phase. Source code writes are not allowed.\n\n" >&2
        printf "In PLAN, you may only write specs and harness state.\n" >&2
        printf "  1. Write your spec to .claude/specs/\n" >&2
        printf "  2. Advance to NEGOTIATE to write a sprint contract\n" >&2
        printf "  3. Advance to BUILD to unlock code writes\n" >&2
        ;;
      NEGOTIATE)
        printf "[ADMIN GATE] BLOCKED: You are in NEGOTIATE phase. Source code writes are not allowed.\n\n" >&2
        printf "In NEGOTIATE, you may only write contracts and specs.\n" >&2
        printf "  1. Write your sprint contract to .claude/contracts/\n" >&2
        printf "  2. Advance to BUILD to unlock code writes\n" >&2
        ;;
      EVALUATE)
        printf "[ADMIN GATE] BLOCKED: You are in EVALUATE phase. Source code writes are not allowed.\n\n" >&2
        printf "In EVALUATE, spawn an independent verifier — don't write code yourself.\n" >&2
        printf "If verification passes, advance to COMPLETE or next sprint.\n" >&2
        ;;
      COMPLETE)
        printf "[ADMIN GATE] BLOCKED: Task is COMPLETE. Source code writes are not allowed.\n\n" >&2
        printf "Start a new sprint if more work is needed.\n" >&2
        ;;
      *)
        printf "[ADMIN GATE] BLOCKED: Unknown phase '%s'. Source code writes are not allowed.\n" "$CURRENT_PHASE" >&2
        ;;
    esac
    print_gates_ahead
    exit 2
  fi
  fi
fi

# CONTRACT GATE: BUILD phase requires a sprint contract
# Without a contract, there's no scope boundary — agent can drift indefinitely.
if [ "$CURRENT_PHASE" = "BUILD" ]; then
  # Check for THIS sprint's contract file (not just any contract)
  if [ ! -f ".claude/contracts/sprint-${CURRENT_SPRINT}-contract.md" ]; then
    # Agent tool spawns subagents — they get their own Write/Edit gating independently.
    # Blocking Agent here creates deadlocks (can't spawn verifier without contract).
    CG_TOOL=$(printf '%s' "$INPUT_DATA" | jq -r '.tool_name // ""' 2>/dev/null)
    if [ "$CG_TOOL" = "Agent" ]; then exit 0; fi
    # Allow writes to harness state, watcher slots, and contract files themselves
    TARGET=$(printf '%s' "$INPUT_DATA" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null)
    TARGET_NORM=$(printf '%s' "$TARGET" | tr '\\\\' '/' | tr '[:upper:]' '[:lower:]')
    if printf '%s' "$TARGET_NORM" | grep -qiF '.claude/state/'; then exit 0; fi
    if printf '%s' "$TARGET_NORM" | grep -qiF '.claude/contracts/'; then exit 0; fi
    if printf '%s' "$TARGET_NORM" | grep -qiF '.claude/specs/'; then exit 0; fi
    if printf '%s' "$TARGET_NORM" | grep -qiF '.openclaw/watchers/'; then exit 0; fi
    if printf '%s' "$TARGET_NORM" | grep -qiF '.agent-memory/'; then exit 0; fi
    if printf '%s' "$TARGET_NORM" | grep -qiF '.claude/pre-flight/'; then exit 0; fi
    if printf '%s' "$TARGET_NORM" | grep -qiF '.claude/evidence/'; then exit 0; fi
    if printf '%s' "$TARGET_NORM" | grep -qiF 'agentwiki/'; then exit 0; fi
    printf "[ADMIN GATE] BLOCKED: BUILD phase requires a contract for sprint %s.\n\n" "$CURRENT_SPRINT" >&2
    printf "No contract found at .claude/contracts/sprint-%s-contract.md\n\n" "$CURRENT_SPRINT" >&2
    printf "You MUST complete the NEGOTIATE phase first:\n" >&2
    printf "  1. Write a sprint proposal to .claude/contracts/sprint-%s-proposal.md\n" "$CURRENT_SPRINT" >&2
    printf "  2. Review it critically\n" >&2
    printf "  3. Write the final contract to .claude/contracts/sprint-%s-contract.md\n" "$CURRENT_SPRINT" >&2
    printf "  4. Then BUILD is unlocked.\n\n" >&2
    printf "Without a contract, there is no scope boundary and work will drift.\n" >&2
    print_gates_ahead
    exit 2
  fi
fi

# --- STRATEGY LOOP BLOCK GATE ---
# If strategy loop breaker has set blocked=true, block source code writes
# until agent writes a valid strategy-ack.md
SLB_STATE_FILE="${STATE_DIR}/strategy-loop-state.json"
SLB_ACK_FILE="${STATE_DIR}/strategy-ack.md"
SLB_FAILURE_LOG="${STATE_DIR}/bash-failure-log.jsonl"

if [ -f "$SLB_STATE_FILE" ] && jq '.' "$SLB_STATE_FILE" >/dev/null 2>&1; then
  SLB_BLOCKED=$(jq -r '.blocked // false' "$SLB_STATE_FILE" 2>/dev/null | tr -d '\r')

  if [ "$SLB_BLOCKED" = "true" ]; then
    # Check if target is an exempt harness path
    SLB_TARGET=$(printf '%s' "$INPUT_DATA" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null)
    SLB_TARGET_NORM=$(printf '%s' "$SLB_TARGET" | tr '\\' '/' | tr '[:upper:]' '[:lower:]')

    SLB_EXEMPT=false
    for SLB_PAT in '.claude/state/' '.openclaw/watchers/' '.agent-memory/' '.claude/contracts/' '.claude/specs/' '.claude/pre-flight/' 'agentwiki/'; do
      if printf '%s' "$SLB_TARGET_NORM" | grep -qiF "$SLB_PAT"; then
        SLB_EXEMPT=true
        break
      fi
    done

    # Agent tool exempt (spawns subagents, doesn't write files)
    SLB_TOOL=$(printf '%s' "$INPUT_DATA" | jq -r '.tool_name // ""' 2>/dev/null)
    if [ "$SLB_TOOL" = "Agent" ]; then SLB_EXEMPT=true; fi

    if [ "$SLB_EXEMPT" = false ]; then
      # Check for valid strategy-ack.md
      SLB_ACK_VALID=false
      SLB_ACK_REASON=""

      if [ -f "$SLB_ACK_FILE" ]; then
        SLB_ACK_LEN=$(wc -c < "$SLB_ACK_FILE" 2>/dev/null | tr -d ' ')
        SLB_HAS_HEADER=$(grep -c '## New Approach' "$SLB_ACK_FILE" 2>/dev/null)
        SLB_HAS_HEADER=${SLB_HAS_HEADER:-0}

        if [ "$SLB_ACK_LEN" -lt 150 ]; then
          SLB_ACK_REASON="too short (${SLB_ACK_LEN} chars, need 150+)"
        elif [ "$SLB_HAS_HEADER" -eq 0 ]; then
          SLB_ACK_REASON="missing '## New Approach' section header"
        else
          # Check must-do file reference (only if must-do folder exists)
          SLB_MUST_DO_DIR=""
          for SLB_CAND in "docs/must do" "docs/must-do" ".claude/must-do"; do
            if [ -d "$SLB_CAND" ]; then
              SLB_MUST_DO_DIR="$SLB_CAND"
              break
            fi
          done

          if [ -n "$SLB_MUST_DO_DIR" ] && [ -f "${SLB_MUST_DO_DIR}/must-do.md" ]; then
            SLB_HAS_REF=false
            while IFS= read -r SLB_LINE || [ -n "$SLB_LINE" ]; do
              SLB_LINE=$(printf '%s' "$SLB_LINE" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
              [ -z "$SLB_LINE" ] && continue
              case "$SLB_LINE" in "#"*|"---"*) continue ;; esac
              SLB_BN=$(basename "$SLB_LINE" 2>/dev/null)
              [ -z "$SLB_BN" ] && continue
              if grep -qiF "$SLB_BN" "$SLB_ACK_FILE" 2>/dev/null; then
                SLB_HAS_REF=true
                break
              fi
            done < "${SLB_MUST_DO_DIR}/must-do.md"

            if [ "$SLB_HAS_REF" = false ]; then
              SLB_ACK_REASON="does not reference any must-do file basename"
            else
              SLB_ACK_VALID=true
            fi
          else
            # No must-do folder — skip basename check
            SLB_ACK_VALID=true
          fi
        fi
      fi

      if [ "$SLB_ACK_VALID" = true ]; then
        # Ack is valid — clear the block
        if type atomic_write >/dev/null 2>&1; then
          atomic_write '{"nudge_count":0,"last_nudge_ts":null,"last_output_fingerprint":"","last_churn_files":[],"blocked":false}' "$SLB_STATE_FILE"
        fi
        rm -f "$SLB_ACK_FILE" 2>/dev/null
        : > "$SLB_FAILURE_LOG" 2>/dev/null
        # Block cleared — fall through to remaining gates
      else
        # Block the write
        printf "[EVIDENCE GATE] BLOCKED: %s Strategy loop detected — writes are locked (Tier 2).\n\n" "$PHASE_CTX" >&2
        print_evidence_gate_note
        if [ -f "$SLB_ACK_FILE" ] && [ -n "$SLB_ACK_REASON" ]; then
          printf "Your strategy-ack.md is INVALID: %s\n\n" "$SLB_ACK_REASON" >&2
        fi
        printf "To unblock, write .claude/state/strategy-ack.md with:\n" >&2
        printf "  1. A '## New Approach' section header\n" >&2
        printf "  2. At least 150 characters describing your new strategy\n" >&2

        SLB_MD_DIR=""
        for SLB_C in "docs/must do" "docs/must-do" ".claude/must-do"; do
          [ -d "$SLB_C" ] && SLB_MD_DIR="$SLB_C" && break
        done
        if [ -n "$SLB_MD_DIR" ] && [ -f "${SLB_MD_DIR}/must-do.md" ]; then
          printf "  3. Reference at least one must-do file by name\n\n" >&2
          printf "Must-do files to review:\n" >&2
          while IFS= read -r SLB_L; do
            SLB_L=$(printf '%s' "$SLB_L" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            [ -z "$SLB_L" ] && continue
            case "$SLB_L" in "#"*|"---"*) continue ;; esac
            printf "  - %s\n" "$SLB_L" >&2
          done < "${SLB_MD_DIR}/must-do.md"
        else
          printf "\n(No must-do folder found — just describe your new approach.)\n" >&2
        fi
        print_gates_ahead
        exit 2
      fi
    fi
  fi
fi

# --- MUST-DO SUMMARY GATE ---
# If project has a docs/must do/ folder with required reading, block code writes
# until the agent has read those files and written a summary.
MUST_DO_MD=""
for CAND_DIR in "docs/must do" "docs/must-do" ".claude/must-do"; do
  if [ -d "$CAND_DIR" ]; then
    MUST_DO_MD=$(find "$CAND_DIR" -maxdepth 1 -name "*.md" -type f 2>/dev/null | head -1)
    [ -n "$MUST_DO_MD" ] && break
  fi
done

if [ -n "$MUST_DO_MD" ]; then
  TARGET_MD=$(printf '%s' "$INPUT_DATA" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null)
  TARGET_MD_NORM=$(printf '%s' "$TARGET_MD" | tr '\\' '/' | tr '[:upper:]' '[:lower:]')

  # Exempt harness/state files (agent must be able to write the summary itself)
  MD_EXEMPT=false
  for PAT in '.claude/state/' '.claude/contracts/' '.claude/specs/' '.openclaw/watchers/' '.agent-memory/' '.claude/pre-flight/' 'agentwiki/'; do
    if printf '%s' "$TARGET_MD_NORM" | grep -qiF "$PAT"; then
      MD_EXEMPT=true
      break
    fi
  done

  if [ "$MD_EXEMPT" = false ]; then
    SUMMARY_FILE="${STATE_DIR}/must-do-summary.md"
    STEP_FILE="${STATE_DIR}/must-do-summary-step.txt"

    # Get current watcher step for staleness check
    CURRENT_STEP_MD=""
    if [ -f "$WATCHER_REGISTRY" ]; then
      CURRENT_PROJECT_MD=$(pwd -W 2>/dev/null || pwd)
      CURRENT_PROJECT_MD=$(printf '%s' "$CURRENT_PROJECT_MD" | tr '\\' '/' | sed 's|/$||' | tr '[:upper:]' '[:lower:]')
      SLOT_NUM_MD=$(jq -r --arg proj "$CURRENT_PROJECT_MD" \
        '[.watchers[] | select(.status == "active" and .project != null and ((.project | gsub("\\\\";"/") | sub("/$";"") | ascii_downcase) == $proj))] | .[0].slot // empty' \
        "$WATCHER_REGISTRY" 2>/dev/null)
      if [ -n "$SLOT_NUM_MD" ]; then
        SLOT_FILE_MD="$HOME/.openclaw/watchers/slot-${SLOT_NUM_MD}.md"
        if [ -f "$SLOT_FILE_MD" ]; then
          CURRENT_STEP_MD=$(sed -n '/## TO-DO/,/^## /{/^## /d;p;}' "$SLOT_FILE_MD" | grep -F -- '- [ ]' | head -1 | sed 's/^[[:space:]]*- \[ \][[:space:]]*//')
        fi
      fi
    fi

    NEED_SUMMARY=false
    NEED_REASON=""
    SUMMARY_LEN=0
    MENTIONS=0
    SAVED_STEP=""

    if [ ! -f "$SUMMARY_FILE" ]; then
      NEED_SUMMARY=true
      NEED_REASON="no_file"
    else
      SUMMARY_LEN=$(wc -c < "$SUMMARY_FILE" 2>/dev/null || echo 0)
      # Count basename mentions
      while IFS= read -r mdl || [ -n "$mdl" ]; do
        mdl=$(printf '%s' "$mdl" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$mdl" ] && continue
        BN=$(basename "$(printf '%s' "$mdl" | tr '\\\\' '/')" 2>/dev/null)
        [ -z "$BN" ] && continue
        if grep -qiF "$BN" "$SUMMARY_FILE" 2>/dev/null; then
          MENTIONS=$((MENTIONS + 1))
        fi
      done < "$MUST_DO_MD"

      # Check if summary is for the current step (stale if step changed)
      if [ -f "$STEP_FILE" ] && [ -n "$CURRENT_STEP_MD" ]; then
        SAVED_STEP=$(cat "$STEP_FILE" 2>/dev/null | tr -d '\r')
        if [ "$SAVED_STEP" != "$CURRENT_STEP_MD" ]; then
          # Fresh summary bypass: if modified < 5 min ago AND length + mentions OK, accept
          SUMMARY_AGE_OK=false
          if [ "$SUMMARY_LEN" -ge 200 ] && [ "$MENTIONS" -gt 0 ]; then
            FRESH_CHECK=$(find "$SUMMARY_FILE" -mmin -5 2>/dev/null)
            if [ -n "$FRESH_CHECK" ]; then
              SUMMARY_AGE_OK=true
            fi
          fi
          if [ "$SUMMARY_AGE_OK" = true ]; then
            # Fresh bypass — auto-update step file and allow
            printf '%s' "$CURRENT_STEP_MD" > "$STEP_FILE" 2>/dev/null
          else
            NEED_SUMMARY=true
            NEED_REASON="stale_step"
          fi
        fi
      fi
      # Check minimum length
      if [ "$NEED_SUMMARY" = false ] && [ "$SUMMARY_LEN" -lt 200 ]; then
        NEED_SUMMARY=true
        NEED_REASON="too_short"
      fi
      # Check that summary mentions at least one must-do file basename
      if [ "$NEED_SUMMARY" = false ] && [ "$MENTIONS" -eq 0 ]; then
        NEED_SUMMARY=true
        NEED_REASON="no_mentions"
      fi
    fi

    if [ "$NEED_SUMMARY" = true ]; then
      # Diagnostic header based on reason
      case "$NEED_REASON" in
        no_file)
          printf "[EVIDENCE GATE] BLOCKED: %s No must-do summary found at .claude/state/must-do-summary.md\n\n" "$PHASE_CTX" >&2
          ;;
        stale_step)
          printf "[EVIDENCE GATE] BLOCKED: %s Must-do summary is stale — watcher step changed.\n\n" "$PHASE_CTX" >&2
          printf "  Watcher is on: %s\n" "$CURRENT_STEP_MD" >&2
          printf "  Summary was for: %s\n\n" "$SAVED_STEP" >&2
          printf "Rewrite your summary AND update .claude/state/must-do-summary-step.txt\n\n" >&2
          ;;
        too_short)
          printf "[EVIDENCE GATE] BLOCKED: %s Must-do summary is too short (%d chars, minimum 200).\n\n" "$PHASE_CTX" "$SUMMARY_LEN" >&2
          ;;
        no_mentions)
          printf "[EVIDENCE GATE] BLOCKED: %s Must-do summary doesn't reference any required file basenames.\n\n" "$PHASE_CTX" >&2
          ;;
      esac
      print_evidence_gate_note
      printf "Files listed in %s:\n\n" "$MUST_DO_MD" >&2
      while IFS= read -r mdl || [ -n "$mdl" ]; do
        mdl=$(printf '%s' "$mdl" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$mdl" ] && continue
        printf "  - %s\n" "$mdl" >&2
      done < "$MUST_DO_MD"
      printf "\nYou MUST:\n" >&2
      printf "  1. READ every file listed above\n" >&2
      printf "  2. WRITE a summary to .claude/state/must-do-summary.md\n" >&2
      printf "     explaining what you learned that is relevant to your CURRENT TASK\n" >&2
      printf "  3. The summary must be at least 200 characters\n" >&2
      printf "  4. The summary must reference the files you read (use their filenames)\n" >&2
      printf "\nOnly then will code writes be unlocked.\n" >&2
      print_gates_ahead
      exit 2
    fi

    # Summary valid — save current step for staleness tracking
    if [ -n "$CURRENT_STEP_MD" ]; then
      printf '%s' "$CURRENT_STEP_MD" > "$STEP_FILE" 2>/dev/null
    fi
  fi
fi

# --- EVIDENCE CHECKPOINT BLOCK ---
# If an evidence checkpoint is active (pending), block source code writes
# until a verifier sub-agent writes a PASS verdict.
EC_CHECKPOINT="${STATE_DIR}/evidence-checkpoint.json"
EC_VERDICT="${STATE_DIR}/evidence-verdict.json"
EC_PATHS="${STATE_DIR}/evidence-paths.json"

# Evidence checkpoint only applies during BUILD phase — no code evidence to verify in PLAN/NEGOTIATE/EVALUATE/COMPLETE
if [ "$CURRENT_PHASE" = "BUILD" ] && [ -f "$EC_CHECKPOINT" ] && jq -r '.status' "$EC_CHECKPOINT" 2>/dev/null | tr -d '\r' | grep -q "pending"; then
  EC_TARGET=$(printf '%s' "$INPUT_DATA" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null)
  EC_TARGET_NORM=$(printf '%s' "$EC_TARGET" | tr '\\' '/' | tr '[:upper:]' '[:lower:]')
  EC_TOOL=$(printf '%s' "$INPUT_DATA" | jq -r '.tool_name // ""' 2>/dev/null)

  # Exempt: harness state, infrastructure, Agent tool
  EC_EXEMPT=false
  if [ "$EC_TOOL" = "Agent" ]; then EC_EXEMPT=true; fi
  for EC_PAT in '.claude/state/' '.openclaw/watchers/' '.agent-memory/' '.claude/contracts/' '.claude/specs/' '.claude/pre-flight/' 'agentwiki/'; do
    if printf '%s' "$EC_TARGET_NORM" | grep -qiF "$EC_PAT"; then
      EC_EXEMPT=true
      break
    fi
  done

  # .claude/evidence/ — exempt UNLESS FAIL verdict exists without FULLY valid remediation plan
  if [ "$EC_EXEMPT" = false ] && printf '%s' "$EC_TARGET_NORM" | grep -qiF '.claude/evidence/'; then
    EC_ALLOW_EVIDENCE=true
    if [ -f "$EC_VERDICT" ] && jq '.' "$EC_VERDICT" >/dev/null 2>&1; then
      EC_PRE_V=$(jq -r '.verdict // ""' "$EC_VERDICT" 2>/dev/null | tr -d '\r')
      if [ "$EC_PRE_V" = "FAIL" ]; then
        EC_ALLOW_EVIDENCE=false
        EC_REMED_FILE="${STATE_DIR}/evidence-remediation.md"
        if [ -f "$EC_REMED_FILE" ]; then
          EC_PRE_RL=$(wc -c < "$EC_REMED_FILE" 2>/dev/null | tr -d ' ')
          if [ "$EC_PRE_RL" -ge 200 ]; then
            # Check phase ref
            EC_PRE_HAS_PHASE=false
            EC_PRE_FP=$(jq -r '.findings[]? | select(.evidence_file == null or .quality == "insufficient") | .phase' "$EC_VERDICT" 2>/dev/null | tr -d '\r')
            if [ -n "$EC_PRE_FP" ]; then
              while IFS= read -r EC_PRE_P; do
                [ -z "$EC_PRE_P" ] && continue
                if grep -qiF "$EC_PRE_P" "$EC_REMED_FILE" 2>/dev/null; then
                  EC_PRE_HAS_PHASE=true
                  break
                fi
              done < <(printf '%s\n' "$EC_PRE_FP")
            else
              EC_PRE_HAS_PHASE=true
            fi
            # Check doc ref
            EC_PRE_HAS_DOC=false
            EC_PRE_MD=""
            for EC_PRE_C in "docs/must do" "docs/must-do" ".claude/must-do"; do
              [ -d "$EC_PRE_C" ] && EC_PRE_MD="$EC_PRE_C" && break
            done
            if [ -n "$EC_PRE_MD" ] && [ -f "${EC_PRE_MD}/must-do.md" ]; then
              while IFS= read -r EC_PRE_L || [ -n "$EC_PRE_L" ]; do
                EC_PRE_L=$(printf '%s' "$EC_PRE_L" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                [ -z "$EC_PRE_L" ] && continue
                case "$EC_PRE_L" in "#"*|"---"*) continue ;; esac
                EC_PRE_BN=$(basename "$EC_PRE_L" 2>/dev/null)
                [ -z "$EC_PRE_BN" ] && continue
                if grep -qiF "$EC_PRE_BN" "$EC_REMED_FILE" 2>/dev/null; then
                  EC_PRE_HAS_DOC=true
                  break
                fi
              done < "${EC_PRE_MD}/must-do.md"
            else
              EC_PRE_HAS_DOC=true
            fi
            if [ "$EC_PRE_HAS_PHASE" = true ] && [ "$EC_PRE_HAS_DOC" = true ]; then
              EC_ALLOW_EVIDENCE=true
            fi
          fi
        fi
      fi
    fi
    if [ "$EC_ALLOW_EVIDENCE" = true ]; then
      EC_EXEMPT=true
    fi
  fi

  if [ "$EC_EXEMPT" = false ]; then
    # Check for verdict file
    if [ -f "$EC_VERDICT" ] && jq '.' "$EC_VERDICT" >/dev/null 2>&1; then
      EC_RESULT=$(jq -r '.verdict // ""' "$EC_VERDICT" 2>/dev/null | tr -d '\r')

      if [ "$EC_RESULT" = "PASS" ]; then
        # Clear checkpoint — all phases verified
        rm -f "$EC_CHECKPOINT" "$EC_VERDICT" "$EC_PATHS" 2>/dev/null
        rm -f "${STATE_DIR}/evidence-remediation.md" 2>/dev/null
        # Reset checkpoint counter
        printf '{"writes":0,"last_step":""}' > "${STATE_DIR}/checkpoint-counter.json" 2>/dev/null
        # Fall through to remaining gates
      elif [ "$EC_RESULT" = "FAIL" ]; then
        # --- Remediation plan validation ---
        EC_REMED="${STATE_DIR}/evidence-remediation.md"
        EC_REMED_VALID=false
        EC_REMED_REASON=""

        if [ -f "$EC_REMED" ]; then
          EC_RL=$(wc -c < "$EC_REMED" 2>/dev/null | tr -d ' ')
          if [ "$EC_RL" -lt 200 ]; then
            EC_REMED_REASON="too short (${EC_RL} chars, need 200+)"
          else
            # Check references to failed phases
            EC_HAS_PHASE=false
            EC_FP_LIST=$(jq -r '.findings[]? | select(.evidence_file == null or .quality == "insufficient") | .phase' "$EC_VERDICT" 2>/dev/null | tr -d '\r')
            if [ -n "$EC_FP_LIST" ]; then
              while IFS= read -r EC_FP; do
                [ -z "$EC_FP" ] && continue
                if grep -qiF "$EC_FP" "$EC_REMED" 2>/dev/null; then
                  EC_HAS_PHASE=true
                  break
                fi
              done < <(printf '%s\n' "$EC_FP_LIST")
            else
              EC_HAS_PHASE=true
            fi

            # Check must-do doc references
            EC_HAS_DOC=false
            EC_RMD_DIR=""
            for EC_RMD_CAND in "docs/must do" "docs/must-do" ".claude/must-do"; do
              [ -d "$EC_RMD_CAND" ] && EC_RMD_DIR="$EC_RMD_CAND" && break
            done
            if [ -n "$EC_RMD_DIR" ] && [ -f "${EC_RMD_DIR}/must-do.md" ]; then
              while IFS= read -r EC_RML || [ -n "$EC_RML" ]; do
                EC_RML=$(printf '%s' "$EC_RML" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                [ -z "$EC_RML" ] && continue
                case "$EC_RML" in "#"*|"---"*) continue ;; esac
                EC_RBN=$(basename "$EC_RML" 2>/dev/null)
                [ -z "$EC_RBN" ] && continue
                if grep -qiF "$EC_RBN" "$EC_REMED" 2>/dev/null; then
                  EC_HAS_DOC=true
                  break
                fi
              done < "${EC_RMD_DIR}/must-do.md"
            else
              EC_HAS_DOC=true
            fi

            if [ "$EC_HAS_PHASE" = false ]; then
              EC_REMED_REASON="does not reference any failed phase"
            elif [ "$EC_HAS_DOC" = false ]; then
              EC_REMED_REASON="does not reference any must-do document"
            else
              EC_REMED_VALID=true
            fi
          fi
        fi

        # --- Show verdict details ---
        EC_SUMMARY=$(jq -r '.summary // "No details"' "$EC_VERDICT" 2>/dev/null | tr -d '\r')
        EC_FINDINGS=$(jq -r '.findings[]? | select(.evidence_file == null or .quality == "insufficient") | "  - " + .phase + ": " + (.note // "missing")' "$EC_VERDICT" 2>/dev/null | tr -d '\r')

        if [ "$EC_REMED_VALID" = true ]; then
          printf "[EVIDENCE GATE] BLOCKED: %s Evidence checkpoint FAILED — remediation plan accepted.\n\n" "$PHASE_CTX" >&2
          print_evidence_gate_note
          printf "Verifier summary: %s\n\n" "$EC_SUMMARY" >&2
          if [ -n "$EC_FINDINGS" ]; then
            printf "Missing/insufficient evidence:\n%s\n\n" "$EC_FINDINGS" >&2
          fi
          printf "Now produce the missing evidence in .claude/evidence/, then:\n" >&2
          printf "  - Delete .claude/state/evidence-verdict.json to re-verify\n" >&2
          printf "  - Or write paths to .claude/state/evidence-paths.json, then delete verdict\n" >&2
        else
          printf "[EVIDENCE GATE] BLOCKED: %s Evidence checkpoint FAILED — remediation plan required.\n\n" "$PHASE_CTX" >&2
          print_evidence_gate_note
          printf "Verifier summary: %s\n\n" "$EC_SUMMARY" >&2
          if [ -n "$EC_FINDINGS" ]; then
            printf "Missing/insufficient evidence:\n%s\n\n" "$EC_FINDINGS" >&2
          fi
          if [ -f "$EC_REMED" ] && [ -n "$EC_REMED_REASON" ]; then
            printf "Your remediation plan is INVALID: %s\n\n" "$EC_REMED_REASON" >&2
          fi
          printf "Before you can fix this, you MUST:\n" >&2
          printf "  1. READ the must-do documentation files\n" >&2
          printf "  2. WRITE a remediation plan to .claude/state/evidence-remediation.md\n" >&2
          printf "     The plan must:\n" >&2
          printf "     - Be at least 200 characters\n" >&2
          printf "     - Reference the specific failed phases listed above\n" >&2
          printf "     - Reference the must-do documents you consulted\n" >&2
          printf "     - Describe HOW you will produce the missing evidence\n" >&2
          if [ -n "$EC_RMD_DIR" ] && [ -f "${EC_RMD_DIR}/must-do.md" ]; then
            printf "\nMust-do files to read:\n" >&2
            while IFS= read -r EC_RML2 || [ -n "$EC_RML2" ]; do
              EC_RML2=$(printf '%s' "$EC_RML2" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
              [ -z "$EC_RML2" ] && continue
              case "$EC_RML2" in "#"*|"---"*) continue ;; esac
              printf "  - %s\n" "$EC_RML2" >&2
            done < "${EC_RMD_DIR}/must-do.md"
          fi
        fi
        print_gates_ahead
        exit 2
      fi
    else
      # No verdict yet — block and tell agent to spawn verifier
      printf "[EVIDENCE GATE] BLOCKED: %s Evidence checkpoint active — writes locked until verifier completes.\n\n" "$PHASE_CTX" >&2
      print_evidence_gate_note
      printf "A checkpoint was triggered after sustained work. You must verify process compliance.\n\n" >&2
      printf "Spawn a verifier sub-agent. Do NOT tell it what to check — the brief is already\n" >&2
      printf "in its environment at .claude/state/evidence-checkpoint.json\n\n" >&2
      printf "IMPORTANT: Tell the verifier to write its verdict to .claude/state/evidence-verdict.json\n" >&2
      printf "Verdict format: {\"verdict\":\"PASS|FAIL\",\"findings\":[{\"phase\":\"X\",\"evidence_file\":\"path|null\",\n" >&2
      printf "\"quality\":\"substantive|insufficient|null\",\"note\":\"details\"}],\"summary\":\"text\"}\n" >&2
      print_gates_ahead
      exit 2
    fi
  fi
fi

# Read write count (sanitize to numeric)
WRITES=$(cat "$WRITE_COUNTER" 2>/dev/null || printf "0")
WRITES=$(printf '%s' "$WRITES" | grep -o '[0-9]*' | head -1)
WRITES=${WRITES:-0}

# 2 free writes, locked at 3rd
if [ "$WRITES" -lt 2 ]; then
  exit 0
fi

# Normalize current project path for comparison (lowercase, forward slashes, no trailing slash)
CURRENT_PROJECT=$(pwd -W 2>/dev/null || pwd)
CURRENT_PROJECT=$(printf '%s' "$CURRENT_PROJECT" | tr '\\\\' '/' | sed 's|/$||' | tr '[:upper:]' '[:lower:]')

# 2+ writes — check if watcher AND cron are active FOR THIS PROJECT
if [ -f "$WATCHER_REGISTRY" ]; then
  # Count watchers that match this project (case-insensitive, slash-normalized)
  ACTIVE_WATCHERS=$(jq --arg proj "$CURRENT_PROJECT" \
    '[.watchers[] | select(.status == "active" and .project != null and ((.project | gsub("\\\\";"/") | sub("/$";"") | ascii_downcase) == $proj))] | length' \
    "$WATCHER_REGISTRY" 2>/dev/null || printf "0")
  ACTIVE_CRON=$(jq --arg proj "$CURRENT_PROJECT" \
    '[.watchers[] | select(.status == "active" and .project != null and ((.project | gsub("\\\\";"/") | sub("/$";"") | ascii_downcase) == $proj) and .cron_job_id != null and .cron_interval == "*/3 * * * *")] | length' \
    "$WATCHER_REGISTRY" 2>/dev/null || printf "0")

  if [ "$ACTIVE_WATCHERS" -eq 0 ]; then
    # Show available slots so agent knows which to claim
    AVAIL_SLOTS=$(jq -r '[.watchers[] | select(.status == "available") | .slot] | join(", ")' "$WATCHER_REGISTRY" 2>/dev/null)
    printf "[ADMIN GATE] BLOCKED: %s Write/Edit/Agent tools are LOCKED after %s writes.\n\n" "$PHASE_CTX" "$WRITES" >&2
    if [ -n "$AVAIL_SLOTS" ]; then
      printf "Available watcher slots: %s\n\n" "$AVAIL_SLOTS" >&2
    fi
    printf "You need BOTH a watcher AND a cron reminder FOR THIS PROJECT. Neither is set up.\n\n" >&2
    printf "STEP 1 - Claim a watcher via Bash. IMPORTANT: use a CURRENT timestamp or it will be auto-cleaned as stale.\n" >&2
    printf "  Find an available slot in REGISTRY.json, then run (replace [N] with slot number):\n\n" >&2
    printf '  source "$HOME/.claude/scripts/lib-helpers.sh" && registry_lock && \\\n' >&2
    printf '  TSTAMP=$(date -Iseconds) && PROJ=$(pwd -W 2>/dev/null || pwd) && \\\n' >&2
    printf '  jq --arg ts "$TSTAMP" --arg pr "$PROJ" '"'"'.watchers[[N]-1].status = "active" | .watchers[[N]-1].claimed_by = "Claude" | .watchers[[N]-1].claimed_at = $ts | .watchers[[N]-1].project = $pr'"'"' \\\n' >&2
    printf '  "$HOME/.openclaw/watchers/REGISTRY.json" > /tmp/reg.tmp && mv /tmp/reg.tmp "$HOME/.openclaw/watchers/REGISTRY.json" && \\\n' >&2
    printf '  registry_unlock\n\n' >&2
    printf "STEP 2 - Write your to-do list to the slot file via Bash:\n" >&2
    printf '  printf "# Watcher Slot [N]\\n\\n**Status**: active\\n**Task**: [describe]\\n## TO-DO\\n- [ ] Step 1\\n" > "$HOME/.openclaw/watchers/slot-[N].md"\n\n' >&2
    printf "STEP 3 - Start 3-minute cron (use CronCreate tool):\n" >&2
    printf '  CronCreate with cron "*/3 * * * *" and prompt "WATCHER REMINDER - Read your watcher slot NOW. Which step am I on? Am I on task?"\n\n' >&2
    printf "STEP 4 - Record cron job ID in registry via Bash (use the lock):\n" >&2
    printf '  source "$HOME/.claude/scripts/lib-helpers.sh" && registry_lock && \\\n' >&2
    printf '  jq '"'"'.watchers[[N]-1].cron_job_id = "<JOB_ID>" | .watchers[[N]-1].cron_interval = "*/3 * * * *"'"'"' \\\n' >&2
    printf '  "$HOME/.openclaw/watchers/REGISTRY.json" > /tmp/reg.tmp && mv /tmp/reg.tmp "$HOME/.openclaw/watchers/REGISTRY.json" && \\\n' >&2
    printf '  registry_unlock\n\n' >&2
    printf "All 4 steps required. Tools stay locked until both watcher AND cron are active FOR THIS PROJECT.\n" >&2
    printf "CRITICAL: claimed_at MUST be a current timestamp. Stale watchers (>4h old) are auto-cleaned.\n" >&2
    print_gates_ahead
    exit 2
  fi

  if [ "$ACTIVE_CRON" -eq 0 ]; then
    printf "[ADMIN GATE] BLOCKED: %s Watcher is claimed but NO CRON REMINDER is set up.\n\n" "$PHASE_CTX" >&2
    printf "Without the cron, you will forget your to-do list and drift.\n\n" >&2
    printf "Set up the 3-minute cron (use CronCreate tool):\n" >&2
    printf '  CronCreate with cron "*/3 * * * *" and prompt "WATCHER REMINDER - Read your watcher slot NOW. Which step am I on? Am I on task? Am I stuck?"\n\n' >&2
    printf "Then record the cron job ID in the registry via Bash (replace [N] with your slot number):\n" >&2
    printf '  source "$HOME/.claude/scripts/lib-helpers.sh" && registry_lock && \\\n' >&2
    printf '  jq '"'"'.watchers[[N]-1].cron_job_id = "<JOB_ID>" | .watchers[[N]-1].cron_interval = "*/3 * * * *"'"'"' \\\n' >&2
    printf '  "$HOME/.openclaw/watchers/REGISTRY.json" > /tmp/reg.tmp && mv /tmp/reg.tmp "$HOME/.openclaw/watchers/REGISTRY.json" && \\\n' >&2
    printf '  registry_unlock\n\n' >&2
    printf "Tools stay locked until cron is active.\n" >&2
    print_gates_ahead
    exit 2
  fi
fi

# Both watcher AND cron active for this project — allow
exit 0
