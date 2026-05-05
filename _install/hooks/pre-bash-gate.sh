#!/bin/bash
# pre-bash-gate.sh — PreToolUse hook (Bash)
# Prevents agents from bypassing Write/Edit hooks via shell file-writing commands.
# Detects common file-write patterns and applies the same enforcement as Write/Edit gates.
# Exit 0 = allowed, Exit 2 = blocked
#
# WHY THIS EXISTS: Agents discovered they can bypass all Write/Edit hooks by using
# python3/echo/tee/sed-i via the Bash tool. This hook closes that gap.

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)

# If no harness state, allow everything
STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
if [ ! -f "${STATE_DIR}/current-phase.json" ]; then
  exit 0
fi

# --- Detect file-writing patterns in command ---
WRITES_FILES=false

# 1. Python/node/ruby file writes (primary bypass vector)
if printf '%s' "$COMMAND" | grep -qiE '\bpython'; then
  if printf '%s' "$COMMAND" | grep -qiE '\b(open|write|Path)\b'; then
    WRITES_FILES=true
  fi
fi
if printf '%s' "$COMMAND" | grep -qiE '\bnode\b.*\bfs\.'; then
  WRITES_FILES=true
fi

# 2. tee command (writes stdin to file)
if printf '%s' "$COMMAND" | grep -qE '\btee\s'; then
  WRITES_FILES=true
fi

# 3. sed in-place editing
if printf '%s' "$COMMAND" | grep -qE '\bsed\s.*-i'; then
  WRITES_FILES=true
fi

# 4. Shell redirects to project-relative paths
#    Catches: echo "x" > file.js, printf > file, cat > file, command > file
#    Allows:  command > /dev/null, command > /tmp/file, command 2> file
if printf '%s' "$COMMAND" | grep -qE '(echo|printf|cat)\s.*>\s*[a-zA-Z."$]'; then
  WRITES_FILES=true
fi

# 5. Heredoc writes: cat << 'EOF' > file
if printf '%s' "$COMMAND" | grep -qE '<<.+>' ; then
  WRITES_FILES=true
fi

# 6. cp/mv to project-relative destinations (2+ args, last arg doesn't start with /)
if printf '%s' "$COMMAND" | grep -qE '\b(cp|mv)\b\s+.+\s+[a-zA-Z."$]'; then
  WRITES_FILES=true
fi

# If no file-writing detected, allow
if [ "$WRITES_FILES" = false ]; then
  exit 0
fi

# Ralph state writes are never allowed from agent Bash, even though .claude/state is otherwise exempt.
if printf '%s' "$COMMAND" | grep -qiF 'ralph-mode.json'; then
  printf "BLOCKED: ralph-mode.json is user-controlled. Only the user can activate/deactivate ralph mode.\n" >&2
  exit 2
fi


# Ralph completion marker cannot be written via Bash unless a fresh PASS verdict exists.
if printf '%s' "$COMMAND" | grep -qiF 'phase-complete-marker.md'; then
  RALPH_STATE_FILE="${STATE_DIR}/ralph-mode.json"
  if [ -f "$RALPH_STATE_FILE" ] && jq -e '.active == true' "$RALPH_STATE_FILE" >/dev/null 2>&1; then
    RALPH_LAST_AT=$(jq -r '.last_verdict_at // ""' "$RALPH_STATE_FILE" 2>/dev/null | tr -d '\r')
    RALPH_VERDICT_FILE="${STATE_DIR}/evidence-verdict.json"
    RALPH_ALLOW_COMPLETE=false
    if [ -f "$RALPH_VERDICT_FILE" ] && jq '.' "$RALPH_VERDICT_FILE" >/dev/null 2>&1; then
      RALPH_V=$(jq -r '.verdict // ""' "$RALPH_VERDICT_FILE" 2>/dev/null | tr -d '\r')
      RALPH_TS=$(jq -r '.timestamp // .checked_at // .verdict_at // .created_at // .ts // ""' "$RALPH_VERDICT_FILE" 2>/dev/null | tr -d '\r')
      if [ "$RALPH_V" = "PASS" ] && [ -n "$RALPH_TS" ]; then
        if [ -z "$RALPH_LAST_AT" ] || [ "$RALPH_LAST_AT" = "null" ]; then
          RALPH_ALLOW_COMPLETE=true
        else
          RALPH_NEW_EPOCH=$(date -d "$RALPH_TS" +%s 2>/dev/null) || RALPH_NEW_EPOCH=""
          RALPH_OLD_EPOCH=$(date -d "$RALPH_LAST_AT" +%s 2>/dev/null) || RALPH_OLD_EPOCH=""
          if [ -n "$RALPH_NEW_EPOCH" ] && [ -n "$RALPH_OLD_EPOCH" ]; then
            [ "$RALPH_NEW_EPOCH" -gt "$RALPH_OLD_EPOCH" ] && RALPH_ALLOW_COMPLETE=true
          elif [[ "$RALPH_TS" > "$RALPH_LAST_AT" ]]; then
            RALPH_ALLOW_COMPLETE=true
          fi
        fi
      fi
    fi
    if [ "$RALPH_ALLOW_COMPLETE" != true ]; then
      printf "BLOCKED: Ralph loop active - verifier must return PASS before completion. Spawn a verifier sub-agent, get PASS verdict in evidence-verdict.json, then retry.\n" >&2
      exit 2
    fi
  fi
fi

# --- Exempt: watcher bootstrap and harness state paths ---
# These paths MUST be writable via Bash even when gated, otherwise agents
# can't claim watchers or update harness state (catch-22 deadlock).
if printf '%s' "$COMMAND" | grep -qiF '.openclaw/watchers/'; then exit 0; fi
if printf '%s' "$COMMAND" | grep -qiF '.claude/state/'; then exit 0; fi
if printf '%s' "$COMMAND" | grep -qiF '.claude/pre-flight/'; then exit 0; fi
if printf '%s' "$COMMAND" | grep -qiF '.claude/contracts/'; then exit 0; fi
if printf '%s' "$COMMAND" | grep -qiF '.claude/specs/'; then exit 0; fi
if printf '%s' "$COMMAND" | grep -qiF '.agent-memory/'; then exit 0; fi
if printf '%s' "$COMMAND" | grep -qiF 'agentwiki/'; then exit 0; fi

# --- File-writing detected — apply same enforcement as Write/Edit ---

# Check 0: Phase gate — only BUILD allows source code writes via Bash
CURRENT_PHASE=$(jq -r '.phase // ""' "${STATE_DIR}/current-phase.json" 2>/dev/null)
CURRENT_SPRINT=$(jq -r '.sprint // 0' "${STATE_DIR}/current-phase.json" 2>/dev/null)
PHASE_CTX="[Phase: ${CURRENT_PHASE} | Sprint: ${CURRENT_SPRINT}]"
if [ "$CURRENT_PHASE" != "BUILD" ] && [ -n "$CURRENT_PHASE" ]; then
  # Markdown files are documentation, not source code — allow in all phases
  if printf '%s' "$COMMAND" | grep -qiE '\.md(\s|"|'"'"'|$)'; then
    exit 0
  fi
  case "$CURRENT_PHASE" in
    PLAN)
      printf "BLOCKED: You are in PLAN phase. Source code writes (including via Bash) are not allowed.\n\n" >&2
      printf "Write your spec to .claude/specs/, then advance through NEGOTIATE to BUILD.\n" >&2
      ;;
    NEGOTIATE)
      printf "BLOCKED: You are in NEGOTIATE phase. Source code writes (including via Bash) are not allowed.\n\n" >&2
      printf "Write your sprint contract, then advance to BUILD.\n" >&2
      ;;
    EVALUATE)
      printf "BLOCKED: You are in EVALUATE phase. Source code writes (including via Bash) are not allowed.\n\n" >&2
      printf "Spawn an independent verifier — don't write code yourself.\n" >&2
      ;;
    *)
      printf "BLOCKED: Phase '%s' does not allow source code writes via Bash.\n" "$CURRENT_PHASE" >&2
      ;;
  esac
  exit 2
fi

# Ralph STUCK blocks source-code Bash writes while preserving harness-state exits above.
RALPH_STATE_FILE="${STATE_DIR}/ralph-mode.json"
if [ -f "$RALPH_STATE_FILE" ] && jq -e '.active == true' "$RALPH_STATE_FILE" >/dev/null 2>&1; then
  RALPH_ITER=$(jq -r '.iteration // 1' "$RALPH_STATE_FILE" 2>/dev/null | tr -d '\r')
  RALPH_MAX=$(jq -r '.max_iterations // 5' "$RALPH_STATE_FILE" 2>/dev/null | tr -d '\r')
  RALPH_LAST=$(jq -r '.last_verdict // ""' "$RALPH_STATE_FILE" 2>/dev/null | tr -d '\r')
  if ! printf '%s' "$RALPH_ITER" | grep -qE '^[0-9]+$'; then RALPH_ITER=1; fi
  if ! printf '%s' "$RALPH_MAX" | grep -qE '^[0-9]+$'; then RALPH_MAX=5; fi
  if [ "$RALPH_ITER" -gt "$RALPH_MAX" ] && [ "$RALPH_LAST" != "PASS" ]; then
    printf "BLOCKED: Ralph loop STUCK - %s iterations exhausted without PASS. Write .claude/state/stuck-report.md and wait for user.\n" "$RALPH_MAX" >&2
    exit 2
  fi
fi

# Check 1: Phase feedback FAIL — hard block
PHASE_FB="${STATE_DIR}/phase-feedback.md"
if [ -f "$PHASE_FB" ] && grep -qF "FAIL" "$PHASE_FB" 2>/dev/null; then
  printf "BLOCKED: %s Phase validation FAILED — file writes via Bash are also blocked.\n\n" "$PHASE_CTX" >&2
  printf "You cannot bypass Write/Edit hooks by writing files through shell commands.\n" >&2
  printf "Use the proper Write/Edit tools after fixing the failure.\n\n" >&2
  printf "READ: .claude/state/phase-feedback.md\n" >&2
  printf "FIX the failure, then use Write to create phase-complete-marker.md.\n" >&2
  exit 2
fi

# Check 2: Strategy loop block gate (mirrors pre-write-gate.sh)
SLB_STATE_FILE="${STATE_DIR}/strategy-loop-state.json"
SLB_ACK_FILE="${STATE_DIR}/strategy-ack.md"
SLB_FAILURE_LOG="${STATE_DIR}/bash-failure-log.jsonl"

if [ -f "$SLB_STATE_FILE" ] && jq '.' "$SLB_STATE_FILE" >/dev/null 2>&1; then
  SLB_BLOCKED=$(jq -r '.blocked // false' "$SLB_STATE_FILE" 2>/dev/null | tr -d '\r')

  if [ "$SLB_BLOCKED" = "true" ]; then
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
          [ -d "$SLB_CAND" ] && SLB_MUST_DO_DIR="$SLB_CAND" && break
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
          SLB_ACK_VALID=true
        fi
      fi
    fi

    if [ "$SLB_ACK_VALID" = true ]; then
      # Clear the block
      source "$HOME/.claude/scripts/lib-helpers.sh" 2>/dev/null
      if type atomic_write >/dev/null 2>&1; then
        atomic_write '{"nudge_count":0,"last_nudge_ts":null,"last_output_fingerprint":"","last_churn_files":[],"blocked":false}' "$SLB_STATE_FILE"
      fi
      rm -f "$SLB_ACK_FILE" 2>/dev/null
      : > "$SLB_FAILURE_LOG" 2>/dev/null
    else
      printf "BLOCKED: %s Strategy loop detected — file-writing Bash commands are locked (Tier 2).\n\n" "$PHASE_CTX" >&2
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
        printf "  3. Reference at least one must-do file by name\n" >&2
      else
        printf "\n(No must-do folder found — just describe your new approach.)\n" >&2
      fi
      exit 2
    fi
  fi
fi

# Check 3: Evidence checkpoint block (mirrors pre-write-gate.sh)
EC_CHECKPOINT="${STATE_DIR}/evidence-checkpoint.json"
EC_VERDICT="${STATE_DIR}/evidence-verdict.json"
EC_PATHS="${STATE_DIR}/evidence-paths.json"

# Evidence checkpoint only applies during BUILD phase
if [ "$CURRENT_PHASE" = "BUILD" ] && [ -f "$EC_CHECKPOINT" ] && jq -r '.status' "$EC_CHECKPOINT" 2>/dev/null | tr -d '\r' | grep -q "pending"; then
  # Exempt if command targets harness paths
  EC_BASH_EXEMPT=false
  if printf '%s' "$COMMAND" | grep -qiF '.claude/state/'; then EC_BASH_EXEMPT=true; fi
  if printf '%s' "$COMMAND" | grep -qiF '.openclaw/watchers/'; then EC_BASH_EXEMPT=true; fi
  if printf '%s' "$COMMAND" | grep -qiF '.agent-memory/'; then EC_BASH_EXEMPT=true; fi
  if printf '%s' "$COMMAND" | grep -qiF '.claude/contracts/'; then EC_BASH_EXEMPT=true; fi
  if printf '%s' "$COMMAND" | grep -qiF '.claude/specs/'; then EC_BASH_EXEMPT=true; fi
  if printf '%s' "$COMMAND" | grep -qiF '.claude/pre-flight/'; then EC_BASH_EXEMPT=true; fi
  if printf '%s' "$COMMAND" | grep -qiF 'agentwiki/'; then EC_BASH_EXEMPT=true; fi

  # .claude/evidence/ — exempt UNLESS FAIL verdict without valid remediation plan
  if [ "$EC_BASH_EXEMPT" = false ] && printf '%s' "$COMMAND" | grep -qiF '.claude/evidence/'; then
    EC_B_ALLOW=true
    if [ -f "$EC_VERDICT" ] && jq '.' "$EC_VERDICT" >/dev/null 2>&1; then
      EC_B_PRE=$(jq -r '.verdict // ""' "$EC_VERDICT" 2>/dev/null | tr -d '\r')
      if [ "$EC_B_PRE" = "FAIL" ]; then
        EC_B_REMED="${STATE_DIR}/evidence-remediation.md"
        EC_B_RL=0
        if [ -f "$EC_B_REMED" ]; then
          EC_B_RL=$(wc -c < "$EC_B_REMED" 2>/dev/null | tr -d ' ')
        fi
        if [ "$EC_B_RL" -lt 200 ]; then
          EC_B_ALLOW=false
        fi
      fi
    fi
    if [ "$EC_B_ALLOW" = true ]; then
      EC_BASH_EXEMPT=true
    fi
  fi

  if [ "$EC_BASH_EXEMPT" = false ]; then
    if [ -f "$EC_VERDICT" ] && jq '.' "$EC_VERDICT" >/dev/null 2>&1; then
      EC_B_RESULT=$(jq -r '.verdict // ""' "$EC_VERDICT" 2>/dev/null | tr -d '\r')
      if [ "$EC_B_RESULT" = "PASS" ]; then
        rm -f "$EC_CHECKPOINT" "$EC_VERDICT" "$EC_PATHS" 2>/dev/null
        rm -f "${STATE_DIR}/evidence-remediation.md" 2>/dev/null
        printf '{"writes":0,"last_step":""}' > "${STATE_DIR}/checkpoint-counter.json" 2>/dev/null
      elif [ "$EC_B_RESULT" = "FAIL" ]; then
        EC_B_REMED2="${STATE_DIR}/evidence-remediation.md"
        if [ ! -f "$EC_B_REMED2" ] || [ "$(wc -c < "$EC_B_REMED2" 2>/dev/null | tr -d ' ')" -lt 200 ]; then
          printf "BLOCKED: %s Evidence checkpoint FAILED — remediation plan required.\n\n" "$PHASE_CTX" >&2
          printf "You cannot bypass the evidence checkpoint via shell commands.\n" >&2
          printf "Read the must-do docs and write a remediation plan to .claude/state/evidence-remediation.md first.\n" >&2
        else
          printf "BLOCKED: %s Evidence checkpoint FAILED — remediation plan accepted.\n\n" "$PHASE_CTX" >&2
          printf "Produce evidence in .claude/evidence/, then delete .claude/state/evidence-verdict.json to re-verify.\n" >&2
        fi
        exit 2
      fi
    else
      printf "BLOCKED: %s Evidence checkpoint active — file-writing Bash commands locked.\n\n" "$PHASE_CTX" >&2
      printf "Spawn a verifier sub-agent. Brief at .claude/state/evidence-checkpoint.json\n" >&2
      exit 2
    fi
  fi
fi

# Check 4: Watcher/cron enforcement (same logic as pre-write-gate.sh)
WRITES=$(cat "${STATE_DIR}/write-count.txt" 2>/dev/null || printf "0")
WRITES=$(printf '%s' "$WRITES" | grep -o '[0-9]*' | head -1)
WRITES=${WRITES:-0}

if [ "$WRITES" -ge 2 ]; then
  WATCHER_REGISTRY="$HOME/.openclaw/watchers/REGISTRY.json"
  if [ -f "$WATCHER_REGISTRY" ]; then
    CURRENT_PROJECT=$(pwd -W 2>/dev/null || pwd)
    CURRENT_PROJECT=$(printf '%s' "$CURRENT_PROJECT" | tr '\\\\' '/' | sed 's|/$||' | tr '[:upper:]' '[:lower:]')
    ACTIVE_WATCHERS=$(jq --arg proj "$CURRENT_PROJECT" \
      '[.watchers[] | select(.status == "active" and .project != null and ((.project | gsub("\\\\";"/") | sub("/$";"") | ascii_downcase) == $proj))] | length' \
      "$WATCHER_REGISTRY" 2>/dev/null || printf "0")

    if [ "$ACTIVE_WATCHERS" -eq 0 ]; then
      printf "BLOCKED: %s File-writing Bash command detected but no watcher is active for this project.\n\n" "$PHASE_CTX" >&2
      printf "You cannot bypass Write/Edit hooks by writing files through shell commands.\n" >&2
      printf "Claim a watcher and set up a cron first, then use the Write/Edit tools.\n" >&2
      exit 2
    fi
  fi
fi

# All checks passed — allow the file-writing bash command
exit 0
