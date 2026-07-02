#!/bin/bash
# pre-write-gate.sh — PreToolUse hook (Write|Edit|Agent)
# 2 free writes, LOCKED at 3rd unless BOTH watcher AND cron are active FOR THIS PROJECT.
# Exit 2 + stderr = BLOCKED
# Exit 0 = ALLOWED

source "$HOME/.claude/scripts/lib-helpers.sh" 2>/dev/null

STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
WRITE_COUNTER="${STATE_DIR}/write-count.txt"
WATCHER_REGISTRY="${HARNESS_REGISTRY:-$HOME/.openclaw/watchers/REGISTRY.json}"

# --- HARNESS KILL-SWITCH (Sprint 33/35): project OFF switch bypasses all enforcement ---
# Resolved by PROJECT ROOT (nearest .claude up from cwd), so `---` works from any subdir/nested root.
if harness_disabled_resolved "$(pwd -W 2>/dev/null || pwd)" "" 2>/dev/null || [ -f "${STATE_DIR}/harness-disabled.flag" ]; then
  exit 0
fi

# If no harness state, allow silently
if [ ! -f "${STATE_DIR}/current-phase.json" ]; then
  exit 0
fi

# Read stdin once for all gates (tool input JSON from Claude Code)
INPUT_DATA=$(cat)
export HARNESS_SESSION_ID="$(printf '%s' "$INPUT_DATA" | jq -r '.session_id // ""' 2>/dev/null | tr -d '\r')"  # per-session must-do fan-out (mustdo_file_for_dir)
# Heartbeat on EVERY Write/Edit attempt (even ones about to be blocked) so a busy agent never goes stale
# and gets its watcher/summary reaped mid-work. Any tool activity = alive.
[ -n "${HARNESS_SESSION_ID:-}" ] && type watcher_touch_session >/dev/null 2>&1 && watcher_touch_session "$HARNESS_SESSION_ID" 2>/dev/null

# Kill-switch by TARGET FILE: a write to a file inside an unlocked project is allowed regardless of cwd.
KS_TGT=$(printf '%s' "$INPUT_DATA" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null)
if [ -n "$KS_TGT" ] && harness_disabled_resolved "" "$KS_TGT" 2>/dev/null; then exit 0; fi

# HARD SESSION ISOLATION: refuse to write into ANOTHER, still-LIVE session's must-do property (its
# summary lane must-do-summary.<sid>.md, or its owned/stamped must-do file). Your OWN is always writable;
# a dead/reaped owner's property is reclaimable (NOT blocked) so no one is ever locked out; fail-open when
# this session has no id. Checked before any path exemption (summaries live in the always-writable state dir).
if [ -n "${HARNESS_SESSION_ID:-}" ] && [ -n "$KS_TGT" ] && type mustdo_peer_write_blocked >/dev/null 2>&1; then
  _ISO_PEER=$(mustdo_peer_write_blocked "$KS_TGT" "$HARNESS_SESSION_ID")
  if [ -n "$_ISO_PEER" ]; then
    printf "[SESSION ISOLATION] BLOCKED: %s belongs to a DIFFERENT, still-active session — you may not write it.\n\n" "$KS_TGT" >&2
    printf "Write ONLY your own must-do file / summary lane (the prompt packet names both). Another\n" >&2
    printf "session's property is off-limits while it is alive; it becomes reclaimable once that session ends.\n" >&2
    exit 2
  fi
fi

# Multilane lane resolution (Sprint 31a): override flat STATE_DIR with the lane's (lane 1 = flat,
# transparent for single instance). Skipped when HARNESS_STATE_DIR is an explicit test override.
if [ -z "${HARNESS_STATE_DIR:-}" ] && type resolve_instance >/dev/null 2>&1; then
  resolve_instance "$INPUT_DATA" "$(pwd -W 2>/dev/null || pwd)" "PreToolUse" >/dev/null 2>&1
  STATE_DIR="${STATE_DIR:-.claude/state}"
fi

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
  for RALPH_PAT in '.claude/state/' '.openclaw/watchers/' '.agent-memory/' '.claude/contracts/' '.claude/specs/' '.claude/pre-flight/' '.claude/evidence/' 'agentwiki/' '.lavish-axi/'; do
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
# --- MUST-DO PACK PLAN-ENTRY GATE (D-Trigger backstop, C12) ---
# OPT-IN ONLY (.claude/mustdo-pack.json {"require_pack": true}); default off = zero regression.
# When in PLAN and writing the product spec, block the first spec write until the caller's owned
# must-do file exists AND carries a captured raw conversation link (i.e. a pack was built).
if [ "$CURRENT_PHASE" = "PLAN" ] && [ -f "${STATE_DIR}/../mustdo-pack.json" ]; then
  PEG_REQ=$(jq -r '.require_pack // false' "${STATE_DIR}/../mustdo-pack.json" 2>/dev/null | tr -d '\r')
  if [ "$PEG_REQ" = "true" ]; then
    PEG_TARGET=$(printf '%s' "$INPUT_DATA" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null | tr '\\' '/')
    case "$PEG_TARGET" in
      */product-spec.md)
        PEG_DIR=""
        for PEG_C in "docs/must do" "docs/must-do" ".claude/must-do"; do
          [ -d "$PEG_C" ] && PEG_DIR="$PEG_C" && break
        done
        PEG_OWN=$(mustdo_file_for_dir "$PEG_DIR" 2>/dev/null); [ -n "$PEG_OWN" ] || PEG_OWN="${PEG_DIR}/must-do.md"
        if [ ! -f "$PEG_OWN" ] || ! grep -qiF "raw-conversation" "$PEG_OWN" 2>/dev/null; then
          printf "[PACK GATE] BLOCKED: %s — no claimed must-do pack for this session.\n\n" "$PHASE_CTX" >&2
          printf "Build your pack before writing the spec: send '+++pack' (captures the raw\n" >&2
          printf "conversation + clears/relinks your owned must-do file at %s),\n" "$PEG_OWN" >&2
          printf "then write your discussion-agreement and grounding links.\n" >&2
          exit 2
        fi
        ;;
    esac
  fi
fi
if [ "$CURRENT_PHASE" != "BUILD" ] && [ -n "$CURRENT_PHASE" ]; then
  # Agent tool spawns subagents, doesn't write files — exempt from phase gate
  PG_TOOL=$(printf '%s' "$INPUT_DATA" | jq -r '.tool_name // ""' 2>/dev/null)
  if [ "$PG_TOOL" != "Agent" ]; then
  PG_TARGET=$(printf '%s' "$INPUT_DATA" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null)
  PG_TARGET_NORM=$(printf '%s' "$PG_TARGET" | tr '\\' '/' | tr '[:upper:]' '[:lower:]')
  PG_EXEMPT=false
  for PG_PAT in '.claude/state/' '.claude/specs/' '.claude/contracts/' '.claude/pre-flight/' '.claude/evidence/' '.openclaw/watchers/' '.agent-memory/' 'agentwiki/' '.lavish-axi/' 'claude-progress' 'features.json' 'tests.json' 'claude.md'; do
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
  # Check for THIS sprint's contract file IN THIS LANE'S contracts dir (AC36: lane 2 must not be
  # gated against lane 1's contract — that would deadlock). CONTRACTS_DIR set by resolve_instance.
  CG_DIR="${CONTRACTS_DIR:-.claude/contracts}"
  if [ ! -f "${CG_DIR}/sprint-${CURRENT_SPRINT}-contract.md" ]; then
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
    if printf '%s' "$TARGET_NORM" | grep -qiE 'agentwiki/|\.lavish-axi/'; then exit 0; fi
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
    for SLB_PAT in '.claude/state/' '.openclaw/watchers/' '.agent-memory/' '.claude/contracts/' '.claude/specs/' '.claude/pre-flight/' '.claude/evidence/' 'agentwiki/' '.lavish-axi/'; do
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

          # Resolve THIS caller's OWNED must-do file (lane-aware), not the hardcoded must-do.md.
          SLB_MUST_DO_FILE=$(mustdo_file_for_dir "$SLB_MUST_DO_DIR" 2>/dev/null); [ -n "$SLB_MUST_DO_FILE" ] || SLB_MUST_DO_FILE="${SLB_MUST_DO_DIR}/must-do.md"
          if [ -n "$SLB_MUST_DO_DIR" ] && [ -f "$SLB_MUST_DO_FILE" ]; then
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
            done < "$SLB_MUST_DO_FILE"

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
        SLB_MD_FILE=$(mustdo_file_for_dir "$SLB_MD_DIR" 2>/dev/null); [ -n "$SLB_MD_FILE" ] || SLB_MD_FILE="${SLB_MD_DIR}/must-do.md"
        if [ -n "$SLB_MD_DIR" ] && [ -f "$SLB_MD_FILE" ]; then
          printf "  3. Reference at least one must-do file by name\n\n" >&2
          printf "Must-do files to review:\n" >&2
          while IFS= read -r SLB_L; do
            SLB_L=$(printf '%s' "$SLB_L" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            [ -z "$SLB_L" ] && continue
            case "$SLB_L" in "#"*|"---"*) continue ;; esac
            printf "  - %s\n" "$SLB_L" >&2
          done < "$SLB_MD_FILE"
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
    # Lane-aware: resolve THIS caller's OWNED must-do file, not just the first *.md.
    MUST_DO_MD=$(mustdo_file_for_dir "$CAND_DIR" 2>/dev/null)
    # Keep the resolved OWNED file even if it does not exist yet — a new session must author its own
    # (e.g. must-do-2.md). Only scan for an existing *.md when the resolver returned nothing; never
    # clobber a valid owned path with "the first file in the dir" (that was forcing every session onto
    # must-do.md and causing the multi-session ownership deadlock).
    [ -n "$MUST_DO_MD" ] || MUST_DO_MD=$(find "$CAND_DIR" -maxdepth 1 -name "*.md" -type f 2>/dev/null | head -1)
    [ -n "$MUST_DO_MD" ] && break
  fi
done

if [ -n "$MUST_DO_MD" ]; then
  TARGET_MD=$(printf '%s' "$INPUT_DATA" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null)
  TARGET_MD_NORM=$(printf '%s' "$TARGET_MD" | tr '\\' '/' | tr '[:upper:]' '[:lower:]')

  # --- Sprint 37: session-aware ownership of the must-do file ----------------------------------
  # A must-do file authored by a DIFFERENT session must not satisfy this gate. Three arms:
  #   no stamp (human seed) / stamp == me / no session  -> fall through to the summary gate (as before)
  #   stamp == another session + source write           -> BLOCK: author your own grounding (+++pack)
  #   (re)authoring the owned must-do file itself        -> snapshot foreign body to history/, then allow
  MD_OWNERSHIP_SKIP=false
  MD_CUR_SESSION=$(printf '%s' "$INPUT_DATA" | jq -r '.session_id // ""' 2>/dev/null | tr -d '\r')
  MD_STAMP=""; type mustdo_stamp_of >/dev/null 2>&1 && MD_STAMP=$(mustdo_stamp_of "$MUST_DO_MD")
  MD_OWNED_NORM=$(printf '%s' "$MUST_DO_MD" | tr '\\' '/' | tr '[:upper:]' '[:lower:]')
  # Is the write (re)authoring the owned must-do file? Match by basename + must-do dir so an
  # absolute target path still matches the relatively-resolved owned file (and vice-versa).
  MD_IS_OWNED=no
  if [ -n "$TARGET_MD_NORM" ] && [ "$(basename "$TARGET_MD_NORM")" = "$(basename "$MD_OWNED_NORM")" ] \
     && printf '%s' "$TARGET_MD_NORM" | grep -qiE '(^|/)(docs/must[ -]do|\.claude/must-do)/'; then
    MD_IS_OWNED=yes
  fi
  if [ "$MD_IS_OWNED" = yes ]; then
    # The write IS (re)authoring the owned must-do file: preserve any foreign/unstamped body first
    # (snapshot-then-write, COPY), then let the write through and skip the summary gate for it.
    if [ -s "$MUST_DO_MD" ] && [ -n "$MD_CUR_SESSION" ] && [ "$MD_STAMP" != "$MD_CUR_SESSION" ]; then
      type mustdo_snapshot >/dev/null 2>&1 && mustdo_snapshot "$MUST_DO_MD"
    fi
    MD_OWNERSHIP_SKIP=true
  elif { [ -n "$MD_CUR_SESSION" ] && [ -n "$MD_STAMP" ] && [ "$MD_STAMP" != "$MD_CUR_SESSION" ]; } \
       || { [ -n "$MD_CUR_SESSION" ] && [ -z "$MD_STAMP" ] && type mustdo_is_agentpack >/dev/null 2>&1 && mustdo_is_agentpack "$MUST_DO_MD"; }; then
    # Foreign-owned grounding: another session's stamp, OR a PRE-EXISTING/legacy agent pack with no
    # stamp (left in the folder before stamping existed). A plain unstamped human list is NOT caught
    # here -> it stays a shared seed. Grounding-building writes are exempt (mirror the create-branch list
    # verbatim, incl. docs/ and *.md); real source writes are blocked until the agent grounds itself.
    MD_FS_EXEMPT=false
    [ -z "$TARGET_MD_NORM" ] && MD_FS_EXEMPT=true
    if [ "$MD_FS_EXEMPT" = false ]; then
      for PAT in '.claude/state/' '.claude/contracts/' '.claude/specs/' '.openclaw/watchers/' '.agent-memory/' '.claude/pre-flight/' '.claude/evidence/' 'agentwiki/' '.lavish-axi/' 'docs/'; do
        if printf '%s' "$TARGET_MD_NORM" | grep -qiF "$PAT"; then MD_FS_EXEMPT=true; break; fi
      done
    fi
    case "$TARGET_MD_NORM" in *.md) MD_FS_EXEMPT=true ;; esac
    if [ "$MD_FS_EXEMPT" = true ]; then
      MD_OWNERSHIP_SKIP=true
    else
      printf "[MUST-DO OWNERSHIP] BLOCKED: %s This must-do file carries a DIFFERENT session's stamp — it is not yours.\n\n" "$PHASE_CTX" >&2
      printf "YOUR OWN must-do file is:  %s\n" "$MUST_DO_MD" >&2
      printf "Each session owns exactly ONE must-do file — never read, clear, or overwrite another\n" >&2
      printf "session's. Author/use only the file named above.\n" >&2
      printf "  - Send '+++pack' to (re)build YOUR file (%s) from this conversation\n" "$MUST_DO_MD" >&2
      printf "    (any prior body is preserved under docs/must do/history/), then write your summary.\n" >&2
      print_gates_ahead
      exit 2
    fi
  fi

  if [ "$MD_OWNERSHIP_SKIP" = false ]; then

  # Exempt harness/state files (agent must be able to write the summary itself)
  MD_EXEMPT=false
  # Sprint 50 (audit A3): the Agent tool / any empty-target call writes no file — a subagent spawn
  # must never be blocked on grounding, or the verifiers other gates demand cannot be spawned.
  MD_TOOL=$(printf '%s' "$INPUT_DATA" | jq -r '.tool_name // ""' 2>/dev/null)
  if [ "$MD_TOOL" = "Agent" ] || [ -z "$TARGET_MD_NORM" ]; then MD_EXEMPT=true; fi
  for PAT in '.claude/state/' '.claude/contracts/' '.claude/specs/' '.openclaw/watchers/' '.agent-memory/' '.claude/pre-flight/' '.claude/evidence/' 'agentwiki/' '.lavish-axi/'; do
    if printf '%s' "$TARGET_MD_NORM" | grep -qiF "$PAT"; then
      MD_EXEMPT=true
      break
    fi
  done

  if [ "$MD_EXEMPT" = false ]; then
    # PER-SESSION grounding: each distinct model/session validates against its OWN summary
    # file (must-do-summary.<session_id>.md), so parallel sessions in one project never clobber
    # each other's grounding. The per-session file IS the ownership proof. When no session_id is
    # present (tests / non-session callers) fall back to the shared file for back-compat.
    CUR_SESSION=$(printf '%s' "$INPUT_DATA" | jq -r '.session_id // ""' 2>/dev/null | tr -d '\r')
    if [ -n "$CUR_SESSION" ]; then
      SUMMARY_FILE="${STATE_DIR}/must-do-summary.${CUR_SESSION}.md"
      STEP_FILE="${STATE_DIR}/must-do-summary-step.${CUR_SESSION}.txt"
    else
      SUMMARY_FILE="${STATE_DIR}/must-do-summary.md"
      STEP_FILE="${STATE_DIR}/must-do-summary-step.txt"
    fi

    # Get current watcher step for staleness check
    CURRENT_STEP_MD=""
    if [ -f "$WATCHER_REGISTRY" ]; then
      CURRENT_PROJECT_MD=$(pwd -W 2>/dev/null || pwd)
      CURRENT_PROJECT_MD=$(printf '%s' "$CURRENT_PROJECT_MD" | tr '\\' '/' | sed 's|/$||' | tr '[:upper:]' '[:lower:]')
      # THIS session's own watcher slot (its own current step) — not the project's first/stale watcher.
      if [ -n "${CUR_SESSION:-}" ] && type watcher_slot_for_session >/dev/null 2>&1; then
        SLOT_NUM_MD=$(watcher_slot_for_session "$CUR_SESSION" "$WATCHER_REGISTRY")
      else
        SLOT_NUM_MD=$(jq -r --arg proj "$CURRENT_PROJECT_MD" \
          '[.watchers[] | select(.status == "active" and .project != null and ((.project | gsub("\\\\";"/") | sub("/$";"") | ascii_downcase) == $proj))] | .[0].slot // empty' \
          "$WATCHER_REGISTRY" 2>/dev/null)
      fi
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
        case "$mdl" in '<!--'*|'#'*|'---'*|*mustdo-session:*) continue ;; esac
        BN=$(basename "$(printf '%s' "$mdl" | tr '\\\\' '/')" 2>/dev/null)
        [ -z "$BN" ] && continue
        if grep -qiF "$BN" "$SUMMARY_FILE" 2>/dev/null; then
          MENTIONS=$((MENTIONS + 1))
        fi
      done < "$([ -f "$MUST_DO_MD" ] && printf '%s' "$MUST_DO_MD" || printf '/dev/null')"

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
      # YOUR own summary lane (per-session) — agents write THIS file directly, never the shared scratch.
      SUMMARY_REL=".claude/state/must-do-summary${CUR_SESSION:+.${CUR_SESSION}}.md"
      STEP_REL=".claude/state/must-do-summary-step${CUR_SESSION:+.${CUR_SESSION}}.txt"
      # Diagnostic header based on reason
      case "$NEED_REASON" in
        no_file)
          printf "[EVIDENCE GATE] BLOCKED: %s You have not authored your own must-do grounding yet.\n\n" "$PHASE_CTX" >&2
          printf "Each session keeps its OWN summary lane (so parallel sessions never clobber each other).\n" >&2
          printf "Write YOUR lane file:  %s\n" "$SUMMARY_REL" >&2
          printf "Write THAT exact file — never the shared must-do-summary.md or another session's summary.\n\n" >&2
          ;;
        stale_step)
          printf "[EVIDENCE GATE] BLOCKED: %s Must-do summary is stale — watcher step changed.\n\n" "$PHASE_CTX" >&2
          printf "  Watcher is on: %s\n" "$CURRENT_STEP_MD" >&2
          printf "  Summary was for: %s\n\n" "$SAVED_STEP" >&2
          printf "Rewrite YOUR summary (%s) AND update %s\n\n" "$SUMMARY_REL" "$STEP_REL" >&2
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
        case "$mdl" in '<!--'*|'#'*|'---'*|*mustdo-session:*) continue ;; esac
        printf "  - %s\n" "$mdl" >&2
      done < "$([ -f "$MUST_DO_MD" ] && printf '%s' "$MUST_DO_MD" || printf '/dev/null')"
      printf "\nYou MUST:\n" >&2
      printf "  1. READ every file listed above\n" >&2
      printf "  2. WRITE a summary to YOUR OWN lane: .claude/state/must-do-summary%s.md\n" "${CUR_SESSION:+.${CUR_SESSION}}" >&2
      printf "     (write THAT exact file — never the shared must-do-summary.md or another session's)\n" >&2
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
  fi   # end MD_OWNERSHIP_SKIP wrapper (Sprint 37)
else
  # --- MUST-DO DEFAULT-ON (no folder present) ---
  # The must-do discipline is ON by default, like the rest of the harness — it does NOT wait
  # for a hand-created docs/must do/ folder. When none exists and the session is about to write
  # SOURCE CODE in BUILD, block and require the model to create its own grounding first.
  # The --- kill-switch (harness-disabled.flag, checked at the top of this gate) is the only
  # off-switch. Exemptions keep this from deadlocking: the model must be free to write the
  # must-do file, its plan/specs/docs, and harness state in order to satisfy the requirement.
  if [ "$CURRENT_PHASE" = "BUILD" ]; then
    DON_TARGET=$(printf '%s' "$INPUT_DATA" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null)
    DON_NORM=$(printf '%s' "$DON_TARGET" | tr '\\' '/' | tr '[:upper:]' '[:lower:]')
    DON_EXEMPT=false
    # Empty target (e.g. Agent tool spawns a subagent, writes no file) — never block.
    [ -z "$DON_NORM" ] && DON_EXEMPT=true
    if [ "$DON_EXEMPT" = false ]; then
      for PAT in '.claude/state/' '.claude/contracts/' '.claude/specs/' '.openclaw/watchers/' '.agent-memory/' '.claude/pre-flight/' '.claude/evidence/' 'agentwiki/' '.lavish-axi/' 'docs/'; do
        if printf '%s' "$DON_NORM" | grep -qiF "$PAT"; then DON_EXEMPT=true; break; fi
      done
    fi
    # Markdown is grounding/plan/notes, never gated source — exempt.
    case "$DON_NORM" in *.md) DON_EXEMPT=true ;; esac
    if [ "$DON_EXEMPT" = false ]; then
      # Name the EXACT file this session owns (lane-aware), so multi-lane sessions get the
      # right filename (lane 1 -> must-do.md; lane N -> must-do-(N-1).md), not a hardcoded one.
      DON_MD_FILE=$(mustdo_file_for_dir "docs/must do" 2>/dev/null); [ -n "$DON_MD_FILE" ] || DON_MD_FILE="docs/must do/must-do.md"
      printf "[MUST-DO GATE] BLOCKED: %s This project has no must-do grounding yet.\n\n" "$PHASE_CTX" >&2
      printf "The must-do system is ON by default (only the '---' kill-switch turns it off).\n" >&2
      printf "Before writing source code you must ground yourself in what this task requires:\n" >&2
      printf "  1. Create '%s' listing the files you MUST read/respect for this task\n" "$DON_MD_FILE" >&2
      printf "  2. Read those files, then write a summary to YOUR lane: .claude/state/must-do-summary%s.md\n\n" "${HARNESS_SESSION_ID:+.${HARNESS_SESSION_ID}}" >&2
      printf "Then retry your write. (Tip: send '+++pack' to capture this conversation and relink grounding.)\n" >&2
      print_gates_ahead
      exit 2
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
  for EC_PAT in '.claude/state/' '.openclaw/watchers/' '.agent-memory/' '.claude/contracts/' '.claude/specs/' '.claude/pre-flight/' 'agentwiki/' '.lavish-axi/'; do
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
            EC_PRE_MDFILE=$(mustdo_file_for_dir "$EC_PRE_MD" 2>/dev/null); [ -n "$EC_PRE_MDFILE" ] || EC_PRE_MDFILE="${EC_PRE_MD}/must-do.md"
            if [ -n "$EC_PRE_MD" ] && [ -f "$EC_PRE_MDFILE" ]; then
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
              done < "$EC_PRE_MDFILE"
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
        # Clear checkpoint via shared helper (single source of truth, freshness-guarded)
        if type clear_evidence_checkpoint_if_pass >/dev/null 2>&1; then
          clear_evidence_checkpoint_if_pass "$STATE_DIR" "$CURRENT_PHASE" >/dev/null 2>&1
        else
          rm -f "$EC_CHECKPOINT" "$EC_VERDICT" "$EC_PATHS" 2>/dev/null
          rm -f "${STATE_DIR}/evidence-remediation.md" 2>/dev/null
          printf '{"writes":0,"last_step":""}' > "${STATE_DIR}/checkpoint-counter.json" 2>/dev/null
        fi
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
            EC_RMD_FILE=$(mustdo_file_for_dir "$EC_RMD_DIR" 2>/dev/null); [ -n "$EC_RMD_FILE" ] || EC_RMD_FILE="${EC_RMD_DIR}/must-do.md"
            if [ -n "$EC_RMD_DIR" ] && [ -f "$EC_RMD_FILE" ]; then
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
              done < "$EC_RMD_FILE"
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
          EC_RMD_FILE2=$(mustdo_file_for_dir "$EC_RMD_DIR" 2>/dev/null); [ -n "$EC_RMD_FILE2" ] || EC_RMD_FILE2="${EC_RMD_DIR}/must-do.md"
          if [ -n "$EC_RMD_DIR" ] && [ -f "$EC_RMD_FILE2" ]; then
            printf "\nMust-do files to read:\n" >&2
            while IFS= read -r EC_RML2 || [ -n "$EC_RML2" ]; do
              EC_RML2=$(printf '%s' "$EC_RML2" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
              [ -z "$EC_RML2" ] && continue
              case "$EC_RML2" in "#"*|"---"*) continue ;; esac
              printf "  - %s\n" "$EC_RML2" >&2
            done < "$EC_RMD_FILE2"
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

# Read write count (sanitize to numeric). Sprint 50 (audit A5): the counter is PER-SESSION when a
# session id is present — a new session always starts with its own free writes; the old cumulative
# project counter (1000+) permanently pre-locked every fresh session. Shared file = test back-compat.
[ -n "${HARNESS_SESSION_ID:-}" ] && WRITE_COUNTER="${STATE_DIR}/write-count.${HARNESS_SESSION_ID}.txt"
WRITES=$(cat "$WRITE_COUNTER" 2>/dev/null || printf "0")
WRITES=$(printf '%s' "$WRITES" | grep -o '[0-9]*' | head -1)
WRITES=${WRITES:-0}

# 2 free writes, locked at 3rd
if [ "$WRITES" -lt 2 ]; then
  exit 0
fi

# Sprint 50 (audit A1): the admin lock gates SOURCE work only. The Agent tool and harness-state
# paths must stay reachable while locked, or the gate chain deadlocks on its own requirements
# (watcher claim instructions, summary lane, protocol-ack files, verifier spawns all live there).
WL_TOOL=$(printf '%s' "$INPUT_DATA" | jq -r '.tool_name // ""' 2>/dev/null)
if [ "$WL_TOOL" = "Agent" ]; then exit 0; fi
WL_NORM=$(printf '%s' "$INPUT_DATA" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null | tr '\\' '/' | tr '[:upper:]' '[:lower:]')
for WL_PAT in '.claude/state/' '.openclaw/watchers/' '.claude/pre-flight/' '.claude/contracts/' '.claude/specs/' '.agent-memory/' '.claude/evidence/' 'agentwiki/' '.lavish-axi/'; do
  if [ -n "$WL_NORM" ] && printf '%s' "$WL_NORM" | grep -qiF "$WL_PAT"; then exit 0; fi
done

# Normalize current project path for comparison (lowercase, forward slashes, no trailing slash)
CURRENT_PROJECT=$(pwd -W 2>/dev/null || pwd)
CURRENT_PROJECT=$(printf '%s' "$CURRENT_PROJECT" | tr '\\\\' '/' | sed 's|/$||' | tr '[:upper:]' '[:lower:]')

# 2+ writes — check that THIS SESSION has its OWN watcher AND cron (each concurrent session claims its
# own slot; a sibling's watcher must NOT satisfy this session, or the session rides another's task).
if [ -f "$WATCHER_REGISTRY" ]; then
  if [ -n "${HARNESS_SESSION_ID:-}" ] && type watcher_slot_for_session >/dev/null 2>&1; then
    if [ -n "$(watcher_slot_for_session "$HARNESS_SESSION_ID" "$WATCHER_REGISTRY")" ]; then ACTIVE_WATCHERS=1; else ACTIVE_WATCHERS=0; fi
    ACTIVE_CRON=$(jq -r --arg s "$HARNESS_SESSION_ID" \
      '[.watchers[]? | select(.session_id==$s and .status=="active" and .cron_job_id!=null and .cron_interval=="*/3 * * * *")] | length' \
      "$WATCHER_REGISTRY" 2>/dev/null | tr -d '\r'); [ -n "$ACTIVE_CRON" ] || ACTIVE_CRON=0
  else
    # Back-compat (session id unknown — tests): project-level count.
    ACTIVE_WATCHERS=$(jq --arg proj "$CURRENT_PROJECT" \
      '[.watchers[] | select(.status == "active" and .project != null and ((.project | gsub("\\\\";"/") | sub("/$";"") | ascii_downcase) == $proj))] | length' \
      "$WATCHER_REGISTRY" 2>/dev/null || printf "0")
    ACTIVE_CRON=$(jq --arg proj "$CURRENT_PROJECT" \
      '[.watchers[] | select(.status == "active" and .project != null and ((.project | gsub("\\\\";"/") | sub("/$";"") | ascii_downcase) == $proj) and .cron_job_id != null and .cron_interval == "*/3 * * * *")] | length' \
      "$WATCHER_REGISTRY" 2>/dev/null || printf "0")
  fi

  if [ "$ACTIVE_WATCHERS" -eq 0 ]; then
    # Per-project watcher pool: this project gets up to 5 of its OWN watchers — never blocked by others.
    CLAIM_SID=$(printf '%s' "$INPUT_DATA" | jq -r '.session_id // empty' 2>/dev/null | tr -d '\r')
    printf "[ADMIN GATE] BLOCKED: %s Write/Edit/Agent tools are LOCKED after %s writes.\n\n" "$PHASE_CTX" "$WRITES" >&2
    printf "You need a watcher AND a cron reminder FOR THIS PROJECT. Your project gets up to 5 of its OWN\n" >&2
    printf "watchers (not shared with other folders), so claiming never fails because other projects are busy.\n\n" >&2
    printf "STEP 1 - Claim a per-project watcher via Bash (prints your slot number):\n" >&2
    printf '  source "$HOME/.claude/scripts/lib-helpers.sh" && SLOT=$(watcher_claim_pp "%s" "$(pwd -W 2>/dev/null || pwd)") && echo "claimed watcher slot $SLOT"\n' "$CLAIM_SID" >&2
    printf "  (If it prints nothing: your project already has 5 active watchers — release one with watcher_release_pp.)\n\n" >&2
    printf "STEP 2 - Write your to-do to the slot file (use the printed \$SLOT):\n" >&2
    printf '  printf "# Watcher Slot $SLOT\\n\\n**Status**: active\\n**Task**: [describe]\\n## TO-DO\\n- [ ] Step 1\\n" > "$HOME/.openclaw/watchers/slot-$SLOT.md"\n\n' >&2
    printf "STEP 3 - Start the 3-minute cron (CronCreate tool):\n" >&2
    printf '  CronCreate with cron "*/3 * * * *" and prompt "WATCHER REMINDER - Read your watcher slot NOW. Which step am I on? On task?"\n\n' >&2
    printf "STEP 4 - Record the cron on your watcher via Bash:\n" >&2
    printf '  source "$HOME/.claude/scripts/lib-helpers.sh" && watcher_set_cron "%s" "<JOB_ID>"\n\n' "$CLAIM_SID" >&2
    printf "Tools stay locked until both watcher AND cron are active FOR THIS PROJECT.\n" >&2
    print_gates_ahead
    exit 2
  fi

  if [ "$ACTIVE_CRON" -eq 0 ]; then
    printf "[ADMIN GATE] BLOCKED: %s Watcher is claimed but NO CRON REMINDER is set up.\n\n" "$PHASE_CTX" >&2
    printf "Without the cron, you will forget your to-do list and drift.\n\n" >&2
    printf "Set up the 3-minute cron (use CronCreate tool):\n" >&2
    printf '  CronCreate with cron "*/3 * * * *" and prompt "WATCHER REMINDER - Read your watcher slot NOW. Which step am I on? Am I on task? Am I stuck?"\n\n' >&2
    CLAIM_SID=$(printf '%s' "$INPUT_DATA" | jq -r '.session_id // empty' 2>/dev/null | tr -d '\r')
    printf "Then record the cron on your watcher via Bash:\n" >&2
    printf '  source "$HOME/.claude/scripts/lib-helpers.sh" && watcher_set_cron "%s" "<JOB_ID>"\n\n' "$CLAIM_SID" >&2
    printf "Tools stay locked until cron is active.\n" >&2
    print_gates_ahead
    exit 2
  fi
fi

# Both watcher AND cron active for this project — allow
exit 0
