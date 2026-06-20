#!/bin/bash
# lib-helpers.sh Ã¢â‚¬â€ Shared helper functions for harness scripts
# Source this file: source "$HOME/.claude/scripts/lib-helpers.sh"

# atomic_write Ã¢â‚¬â€ Write content to file via temp+mv (prevents partial writes)
# Usage: atomic_write "content" "/path/to/file"
atomic_write() {
  local CONTENT="$1"
  local TARGET="$2"
  local TMPFILE="${TARGET}.tmp.$$"

  mkdir -p "$(dirname "$TARGET")" 2>/dev/null
  printf "%s" "$CONTENT" > "$TMPFILE"

  # mv with retry (Windows may hold file handles briefly)
  if ! mv "$TMPFILE" "$TARGET" 2>/dev/null; then
    sleep 1
    mv "$TMPFILE" "$TARGET" 2>/dev/null || {
      rm -f "$TMPFILE" 2>/dev/null
      return 1
    }
  fi
  return 0
}

# append_jsonl Ã¢â‚¬â€ Append one JSON line to a JSONL file (append-only, can't corrupt previous entries)
# Usage: append_jsonl '{"key":"value"}' "/path/to/file.jsonl"
harness_is_disabled() {
  local sd="${1:-${HARNESS_STATE_DIR:-.claude/state}}"
  [ -f "$sd/harness-disabled.flag" ]
}
harness_disable() {
  local sd="${1:-${HARNESS_STATE_DIR:-.claude/state}}"
  mkdir -p "$sd" 2>/dev/null
  local ts
  ts=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
  if type atomic_write >/dev/null 2>&1; then
    atomic_write "harness disabled at ${ts}"$'\n' "$sd/harness-disabled.flag"
  else
    printf 'harness disabled at %s\n' "$ts" > "$sd/harness-disabled.flag.tmp" 2>/dev/null \
      && mv -f "$sd/harness-disabled.flag.tmp" "$sd/harness-disabled.flag" 2>/dev/null
  fi
}
harness_enable() {
  local sd="${1:-${HARNESS_STATE_DIR:-.claude/state}}"
  rm -f "$sd/harness-disabled.flag" 2>/dev/null
}

# --- Kill-switch path resolution (Sprint 35): make the OFF switch cwd-independent. ---
# The flag used to be looked up at a cwd-relative .claude/state, so an agent whose hook ran from a
# different working dir (a subfolder, or a NESTED project root) never saw a flag set elsewhere and
# stayed locked. These helpers resolve the flag by the PROJECT ROOT instead (nearest ancestor that
# contains a .claude dir), so `---` is honored regardless of which dir the hook runs from.

# Walk up from a starting dir to the FIRST ancestor containing .claude; echo its .claude/state.
# Returns 1 (no output) if none found. HARNESS_STATE_DIR (tests/sandboxes) always wins.
find_project_state_dir() {
  if [ -n "${HARNESS_STATE_DIR:-}" ]; then printf '%s\n' "$HARNESS_STATE_DIR"; return 0; fi
  local d; d="$(printf '%s' "${1:-.}" | tr '\\' '/')"
  [ -n "$d" ] || d="."
  case "$d" in /*|[A-Za-z]:/*) ;; *) d="$(pwd -W 2>/dev/null || pwd)/$d" ;; esac
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    if [ -d "$d/.claude" ]; then printf '%s/.claude/state\n' "$d"; return 0; fi
    case "$d" in */*) d="${d%/*}" ;; *) break ;; esac
  done
  return 1
}

# Is the kill-switch flag set for the project owning the cwd OR the target file?
# $1 = cwd (optional), $2 = target file path (optional). Returns 0 (disabled) if EITHER project root
# carries the flag — so a write to a file inside an unlocked tree is allowed no matter the hook's cwd.
# A nested project stays governed by its OWN nearest .claude (walk-up stops at the first one found),
# so an unlocked parent does not silently unlock a locked child via the file path.
harness_disabled_resolved() {
  if [ -n "${HARNESS_STATE_DIR:-}" ]; then
    [ -f "${HARNESS_STATE_DIR}/harness-disabled.flag" ] && return 0
    return 1
  fi
  local cwd="${1:-}" tgt="${2:-}" sd
  if [ -n "$cwd" ]; then
    sd="$(find_project_state_dir "$cwd")" && [ -f "$sd/harness-disabled.flag" ] && return 0
  fi
  if [ -n "$tgt" ]; then
    tgt="$(printf '%s' "$tgt" | tr '\\' '/')"
    sd="$(find_project_state_dir "$(dirname "$tgt")")" && [ -f "$sd/harness-disabled.flag" ] && return 0
  fi
  return 1
}

# HARNESS KILL-SWITCH (Sprint 33): per-project on/off switch via <state>/harness-disabled.flag.
# Honors HARNESS_STATE_DIR. Used by on-prompt-submit toggle + all enforcement gates.

append_jsonl() {
  local LINE="$1"
  local TARGET="$2"

  mkdir -p "$(dirname "$TARGET")" 2>/dev/null
  printf "%s\n" "$LINE" >> "$TARGET"
}

# trim_jsonl Ã¢â‚¬â€ Keep only the last N lines of a JSONL file (atomic trim)
# Usage: trim_jsonl "/path/to/file.jsonl" 50
trim_jsonl() {
  local TARGET="$1"
  local KEEP="${2:-50}"

  if [ -f "$TARGET" ]; then
    local LINE_COUNT
    LINE_COUNT=$(wc -l < "$TARGET")
    if [ "$LINE_COUNT" -gt "$KEEP" ]; then
      tail -n "$KEEP" "$TARGET" > "${TARGET}.tmp.$$"
      mv "${TARGET}.tmp.$$" "$TARGET" 2>/dev/null
    fi
  fi
}

# write_if_changed Ã¢â‚¬â€ Only write if content differs from current file (hash-based)
# Usage: write_if_changed "content" "/path/to/file"
# Returns: 0 if written (changed), 1 if skipped (unchanged)
write_if_changed() {
  local CONTENT="$1"
  local TARGET="$2"
  local HASH_FILE="${TARGET}.hash"

  local NEW_HASH
  NEW_HASH=$(printf "%s" "$CONTENT" | sha256sum 2>/dev/null | cut -d' ' -f1)

  local OLD_HASH=""
  if [ -f "$HASH_FILE" ]; then
    OLD_HASH=$(cat "$HASH_FILE" 2>/dev/null)
  fi

  if [ "$NEW_HASH" != "$OLD_HASH" ]; then
    atomic_write "$CONTENT" "$TARGET"
    atomic_write "$NEW_HASH" "$HASH_FILE"
    return 0
  fi
  return 1
}

# registry_lock Ã¢â‚¬â€ Acquire exclusive lock on REGISTRY.json via lockdir (mkdir is atomic)
# Usage: registry_lock [timeout_seconds]
# Returns: 0 on success, 1 on timeout
registry_lock() {
  local LOCKDIR="$HOME/.openclaw/watchers/.registry-lock"
  local MAX_WAIT="${1:-10}"
  local WAITED=0

  while ! mkdir "$LOCKDIR" 2>/dev/null; do
    sleep 0.2
    WAITED=$((WAITED + 1))
    if [ "$WAITED" -ge $((MAX_WAIT * 5)) ]; then
      # Stale lock (crashed process) Ã¢â‚¬â€ force clean and retry once
      rm -rf "$LOCKDIR" 2>/dev/null
      if ! mkdir "$LOCKDIR" 2>/dev/null; then
        return 1
      fi
      break
    fi
  done
  # Write PID so stale locks can be identified
  printf '%s' "$$" > "$LOCKDIR/pid" 2>/dev/null
  return 0
}

# registry_unlock Ã¢â‚¬â€ Release REGISTRY.json lock
# Usage: registry_unlock
registry_unlock() {
  rm -rf "$HOME/.openclaw/watchers/.registry-lock" 2>/dev/null
}

# registry_modify Ã¢â‚¬â€ Safely modify REGISTRY.json with locking
# Usage: registry_modify 'jq_filter' [--arg name value ...]
# Acquires lock, reads file, applies jq filter, writes back, releases lock
registry_modify() {
  local JQ_FILTER="$1"
  shift
  local REGISTRY="$HOME/.openclaw/watchers/REGISTRY.json"

  registry_lock || return 1

  local UPDATED
  UPDATED=$(jq "$JQ_FILTER" "$@" "$REGISTRY" 2>/dev/null)

  if [ -n "$UPDATED" ]; then
    printf '%s\n' "$UPDATED" > "${REGISTRY}.tmp.$$"
    mv "${REGISTRY}.tmp.$$" "$REGISTRY" 2>/dev/null || {
      rm -f "${REGISTRY}.tmp.$$" 2>/dev/null
      registry_unlock
      return 1
    }
  fi

  registry_unlock
  return 0
}

# write_phase Ã¢â‚¬â€ Atomically write current-phase.json (most critical state file)
# Usage: write_phase "BUILD" 1 5
write_phase() {
  local PHASE="$1"
  local SPRINT="${2:-0}"
  local ITERATION="${3:-0}"
  local STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"

  local CONTENT
  CONTENT=$(printf '{"phase":"%s","sprint":%s,"iteration":%s}\n' "$PHASE" "$SPRINT" "$ITERATION")
  atomic_write "$CONTENT" "${STATE_DIR}/current-phase.json"
}

# find_must_do_dir Ã¢â‚¬â€ Return first project must-do directory, or empty string
# Usage: find_must_do_dir
find_must_do_dir() {
  for CANDIDATE in "docs/must do" "docs/must-do" ".claude/must-do"; do
    if [ -d "$CANDIDATE" ]; then
      printf '%s' "$CANDIDATE"
      return 0
    fi
  done
  return 1
}


# compute_pending_gates - Return context-aware pending harness gates.
# Usage: compute_pending_gates "BUILD" 23 "G:/project/path"
# Output: one pending gate per line, formatted for user-facing block messages.
compute_pending_gates() {
  local CURRENT_PHASE="${1:-}"
  local SPRINT="${2:-0}"
  local PROJECT_PATH="${3:-}"
  local STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
  local WATCHER_REGISTRY="${WATCHER_REGISTRY:-${HARNESS_REGISTRY:-$HOME/.openclaw/watchers/REGISTRY.json}}"
  local PENDING=""

  if [ -z "$PROJECT_PATH" ]; then
    PROJECT_PATH=$(pwd -W 2>/dev/null || pwd)
  fi

  add_pending_gate() {
    local TYPE="$1"
    local LABEL="$2"
    local DETAIL="$3"
    PENDING="${PENDING} -> [${TYPE}] ${LABEL} - ${DETAIL}
"
  }

  if [ -n "$CURRENT_PHASE" ] && [ "$CURRENT_PHASE" != "BUILD" ]; then
    add_pending_gate "ADMIN" "phase gate" "advance to BUILD before source writes"
  fi

  if [ -n "$SPRINT" ] && [ "$SPRINT" != "0" ] && [ "$SPRINT" != "null" ]; then
    if [ ! -f ".claude/contracts/sprint-${SPRINT}-contract.md" ]; then
      add_pending_gate "ADMIN" "contract" "need .claude/contracts/sprint-${SPRINT}-contract.md"
    fi
  fi

  local PROJECT_NORM
  PROJECT_NORM=$(printf '%s' "$PROJECT_PATH" | tr '\\' '/' | sed 's|/$||' | tr '[:upper:]' '[:lower:]')

  local ACTIVE_WATCHERS=0
  local ACTIVE_CRON=0
  local ACTIVE_SLOT=""
  if [ "$CURRENT_PHASE" = "BUILD" ] && [ -f "$WATCHER_REGISTRY" ]; then
    ACTIVE_WATCHERS=$(jq --arg proj "$PROJECT_NORM" \
      '[.watchers[] | select(.status == "active" and .project != null and ((.project | gsub("\\\\";"/") | sub("/$";"") | ascii_downcase) == $proj))] | length' \
      "$WATCHER_REGISTRY" 2>/dev/null || printf "0")
    ACTIVE_CRON=$(jq --arg proj "$PROJECT_NORM" \
      '[.watchers[] | select(.status == "active" and .project != null and ((.project | gsub("\\\\";"/") | sub("/$";"") | ascii_downcase) == $proj) and .cron_job_id != null and .cron_interval == "*/3 * * * *")] | length' \
      "$WATCHER_REGISTRY" 2>/dev/null || printf "0")
    ACTIVE_SLOT=$(jq -r --arg proj "$PROJECT_NORM" \
      '[.watchers[] | select(.status == "active" and .project != null and ((.project | gsub("\\\\";"/") | sub("/$";"") | ascii_downcase) == $proj))][0].slot // empty' \
      "$WATCHER_REGISTRY" 2>/dev/null | tr -d '\r' | head -1)

    if [ "${ACTIVE_WATCHERS:-0}" -eq 0 ] 2>/dev/null; then
      add_pending_gate "ADMIN" "watcher claim" "claim an active watcher for this project"
    elif [ "${ACTIVE_CRON:-0}" -eq 0 ] 2>/dev/null; then
      add_pending_gate "ADMIN" "cron reminder" "set */3 * * * * reminder on the watcher"
    fi
  elif [ "$CURRENT_PHASE" = "BUILD" ]; then
    add_pending_gate "ADMIN" "watcher claim" "watcher registry is missing or no project watcher is active"
  fi

  local MUST_DO_DIR
  MUST_DO_DIR=$(find_must_do_dir 2>/dev/null || printf '')
  if [ -n "$MUST_DO_DIR" ] && [ -f "${MUST_DO_DIR}/must-do.md" ] && [ ! -f "${STATE_DIR}/must-do-summary.md" ]; then
    add_pending_gate "EVIDENCE" "must-do summary" "read required docs and write .claude/state/must-do-summary.md"
  fi

  if [ "$CURRENT_PHASE" = "BUILD" ] && [ -n "$ACTIVE_SLOT" ]; then
    local COUNTER_FILE=".claude/pre-flight/gate-counter.json"
    local WRITE_COUNT=0
    local LAST_STEP=""
    if [ -f "$COUNTER_FILE" ]; then
      WRITE_COUNT=$(jq -r '.write_count // 0' "$COUNTER_FILE" 2>/dev/null || printf "0")
      LAST_STEP=$(jq -r '.last_step // ""' "$COUNTER_FILE" 2>/dev/null | tr -d '\r')
      if ! printf '%s' "$WRITE_COUNT" | grep -qE '^[0-9]+$'; then
        WRITE_COUNT=0
        LAST_STEP=""
      fi
    fi

    local SLOT_FILE="$HOME/.openclaw/watchers/slot-${ACTIVE_SLOT}.md"
    local CURRENT_STEP=""
    if [ -f "$SLOT_FILE" ]; then
      CURRENT_STEP=$(sed -n '/## TO-DO/,/^## /{/^## /d;p;}' "$SLOT_FILE" 2>/dev/null | grep -F -- '- [ ]' | head -1 | sed 's/^[[:space:]]*- \[ \][[:space:]]*//' | tr -d '\r')
    fi
    [ -z "$CURRENT_STEP" ] && CURRENT_STEP="(no unchecked steps remain)"

    if [ -f ".claude/pre-flight/challenge.md" ] || [ "$CURRENT_STEP" != "$LAST_STEP" ] || [ $((WRITE_COUNT % 4)) -eq 0 ]; then
      add_pending_gate "EVIDENCE" "pre-flight MCQ" "next gated write verifies task, step, target file, and scope"
    fi
  fi

  if [ -f "${STATE_DIR}/evidence-checkpoint.json" ] && jq -r '.status' "${STATE_DIR}/evidence-checkpoint.json" 2>/dev/null | tr -d '\r' | grep -q "pending"; then
    add_pending_gate "EVIDENCE" "evidence checkpoint" "spawn verifier and resolve .claude/state/evidence-checkpoint.json"
  fi

  printf '%s' "$PENDING"
}

# test_lock_acquire — Acquire exclusive test execution lock (GPU mutex)
# Usage: test_lock_acquire "harness|agent" "python -m pytest"
# Returns: 0 on success, 1 if already locked
test_lock_acquire() {
  local SOURCE="${1:-harness}"
  local COMMAND="${2:-unknown}"
  local STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
  local LOCKDIR="${STATE_DIR}/.test-lock"
  local LOCKFILE="${STATE_DIR}/test-lock.json"

  # Attempt atomic mkdir
  if ! mkdir "$LOCKDIR" 2>/dev/null; then
    # Lock exists — check if stale
    if test_lock_check 2>/dev/null; then
      # Lock is valid (PID alive + fresh) — cannot acquire
      return 1
    fi
    # Stale lock was auto-released by test_lock_check — retry once
    if ! mkdir "$LOCKDIR" 2>/dev/null; then
      return 1
    fi
  fi

  # Write lock metadata
  local TS
  TS=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
  local SAFE_CMD
  SAFE_CMD=$(printf '%s' "$COMMAND" | sed 's/\\/\\\\/g; s/"/\\"/g' | head -c 200)
  printf '{"pid":%d,"started_at":"%s","command":"%s","source":"%s"}' \
    "$$" "$TS" "$SAFE_CMD" "$SOURCE" > "$LOCKFILE" 2>/dev/null
  return 0
}

# test_lock_release — Release test execution lock
# Usage: test_lock_release
test_lock_release() {
  local STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
  rm -f "${STATE_DIR}/test-lock.json" 2>/dev/null
  rm -rf "${STATE_DIR}/.test-lock" 2>/dev/null
  return 0
}

# test_lock_check — Check if test lock is currently held and valid
# Usage: test_lock_check
# Returns: 0 if locked (PID alive + not stale), 1 if unlocked or stale
# Side effect: auto-releases stale locks
test_lock_check() {
  local STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
  local LOCKDIR="${STATE_DIR}/.test-lock"
  local LOCKFILE="${STATE_DIR}/test-lock.json"

  # No lock dir or no lock file = unlocked
  if [ ! -d "$LOCKDIR" ] || [ ! -f "$LOCKFILE" ]; then
    return 1
  fi

  # Read lock metadata
  local LOCK_PID LOCK_TS
  LOCK_PID=$(jq -r '.pid // 0' "$LOCKFILE" 2>/dev/null | tr -d '\r')
  LOCK_TS=$(jq -r '.started_at // ""' "$LOCKFILE" 2>/dev/null | tr -d '\r')

  if ! printf '%s' "$LOCK_PID" | grep -qE '^[0-9]+$'; then
    LOCK_PID=0
  fi

  # Check 1: PID alive?
  if [ "$LOCK_PID" -gt 0 ]; then
    if ! kill -0 "$LOCK_PID" 2>/dev/null; then
      # PID dead — stale lock, auto-release
      test_lock_release
      return 1
    fi
  else
    # No valid PID — stale
    test_lock_release
    return 1
  fi

  # Check 2: Timestamp freshness (default 120s max)
  if [ -n "$LOCK_TS" ] && [ "$LOCK_TS" != "null" ]; then
    local LOCK_EPOCH NOW_EPOCH
    LOCK_EPOCH=$(date -d "$LOCK_TS" +%s 2>/dev/null) || LOCK_EPOCH=""
    NOW_EPOCH=$(date +%s 2>/dev/null) || NOW_EPOCH=""
    if [ -n "$LOCK_EPOCH" ] && [ -n "$NOW_EPOCH" ]; then
      local AGE=$((NOW_EPOCH - LOCK_EPOCH))
      local MAX_AGE="${TEST_LOCK_MAX_AGE:-120}"
      if [ "$AGE" -gt "$MAX_AGE" ]; then
        # Too old — stale, auto-release
        test_lock_release
        return 1
      fi
    fi
  fi

  # Lock is valid
  return 0
}

# cron_pause — Pause the watcher cron for N minutes (default 30)
# Creates .claude/state/cron-paused.json with resume triggers
# Usage: cron_pause [minutes]
cron_pause() {
  local MINUTES="${1:-30}"
  local STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
  local PAUSE_FILE="${STATE_DIR}/cron-paused.json"
  local NOW_ISO
  NOW_ISO=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
  local NOW_EPOCH
  NOW_EPOCH=$(date +%s 2>/dev/null || echo "0")
  local RESUME_EPOCH=$((NOW_EPOCH + MINUTES * 60))
  local RESUME_ISO
  RESUME_ISO=$(date -d "@${RESUME_EPOCH}" -Iseconds 2>/dev/null || date -Iseconds 2>/dev/null)
  printf '{"paused":true,"paused_at":"%s","resume_at":"%s","resume_on_write":true}' \
    "$NOW_ISO" "$RESUME_ISO" > "$PAUSE_FILE" 2>/dev/null
  return 0
}

# cron_resume — Resume the watcher cron (delete the pause file)
# Usage: cron_resume
cron_resume() {
  local STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
  rm -f "${STATE_DIR}/cron-paused.json" 2>/dev/null
  return 0
}

# check_watcher_for_project Ã¢â‚¬â€ Return active watcher slot for a project, or empty string
# Usage: check_watcher_for_project "G:/path" [registry_path]
check_watcher_for_project() {
  local PROJECT_PATH="$1"
  local REGISTRY="${2:-${HARNESS_REGISTRY:-$HOME/.openclaw/watchers/REGISTRY.json}}"

  if [ -z "$PROJECT_PATH" ] || [ ! -f "$REGISTRY" ]; then
    return 1
  fi

  local PROJECT_NORM
  PROJECT_NORM=$(printf '%s' "$PROJECT_PATH" | tr '\\' '/' | sed 's|/$||' | tr '[:upper:]' '[:lower:]')

  jq -r --arg proj "$PROJECT_NORM" \
    '[.watchers[] | select(.status == "active" and .project != null and ((.project | gsub("\\\\";"/") | sub("/$";"") | ascii_downcase) == $proj))][0].slot // empty' \
    "$REGISTRY" 2>/dev/null | tr -d '\r' | head -1
}

# read_watcher_step_scope Ã¢â‚¬â€ Extract current step, SCOPE, MISTAKES TO AVOID, and completion criteria
# Usage: read_watcher_step_scope "$HOME/.openclaw/watchers/slot-N.md"
# Output: STEP=...\nSCOPE=...\nMISTAKES=...\nDONE=...
read_watcher_step_scope() {
  local SLOT_FILE="$1"
  if [ ! -f "$SLOT_FILE" ]; then
    printf 'STEP=\nSCOPE=\nMISTAKES=\nDONE=\n'
    return 1
  fi

  local STEP SCOPE MISTAKES DONE
  STEP=$(sed -n '/^## TO-DO/,/^## /{/^## /d;p;}' "$SLOT_FILE" 2>/dev/null | grep -F -- '- [ ]' | head -1 | sed 's/^[[:space:]]*- \[ \][[:space:]]*//' | tr -d '\r')
  SCOPE=$(awk '/^## SCOPE/{flag=1;next}/^## /{if(flag) exit}flag{print}' "$SLOT_FILE" 2>/dev/null | tr '\n' ' ' | tr -d '\r' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//' | head -c 90)
  MISTAKES=$(awk '/^## MISTAKES TO AVOID/{flag=1;next}/^## /{if(flag) exit}flag{print}' "$SLOT_FILE" 2>/dev/null | tr '\n' ' ' | tr -d '\r' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//' | head -c 90)
  DONE=$(awk '/^## (COMPLETION CRITERIA|DONE WHEN|DONE)/{flag=1;next}/^## /{if(flag) exit}flag{print}' "$SLOT_FILE" 2>/dev/null | tr '\n' ' ' | tr -d '\r' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//' | head -c 90)

  printf 'STEP=%s\nSCOPE=%s\nMISTAKES=%s\nDONE=%s\n' "$STEP" "$SCOPE" "$MISTAKES" "$DONE"
}

# clear_evidence_checkpoint_if_pass — auto-resolve a pending evidence checkpoint
# when a FRESH PASS verdict exists, independent of any later source write.
# Freshness = verdict FILE mtime >= checkpoint FILE mtime (verdict JSON frequently
# omits checked_at). If BOTH an explicit verdict timestamp and the checkpoint
# triggered_at parse, that comparison is applied as an additional gate.
# Usage: clear_evidence_checkpoint_if_pass [state_dir] [current_phase]
# Prints 'cleared' and returns 0 when it clears; returns 1 (no output) otherwise.
clear_evidence_checkpoint_if_pass() {
  local STATE_DIR="${1:-${HARNESS_STATE_DIR:-.claude/state}}"
  local CURRENT_PHASE="$2"
  local CHK="${STATE_DIR}/evidence-checkpoint.json"
  local VRD="${STATE_DIR}/evidence-verdict.json"
  local PTH="${STATE_DIR}/evidence-paths.json"

  if [ -z "$CURRENT_PHASE" ]; then
    CURRENT_PHASE=$(jq -r '.phase // ""' "${STATE_DIR}/current-phase.json" 2>/dev/null | tr -d '\r')
  fi
  # BUILD-only scoping — matches the evidence gate
  [ "$CURRENT_PHASE" = "BUILD" ] || return 1

  # Must be a pending checkpoint
  [ -f "$CHK" ] || return 1
  local STATUS
  STATUS=$(jq -r '.status // ""' "$CHK" 2>/dev/null | tr -d '\r')
  [ "$STATUS" = "pending" ] || return 1

  # Must be a valid PASS verdict
  [ -f "$VRD" ] && jq '.' "$VRD" >/dev/null 2>&1 || return 1
  local VERDICT
  VERDICT=$(jq -r '.verdict // ""' "$VRD" 2>/dev/null | tr -d '\r')
  [ "$VERDICT" = "PASS" ] || return 1

  # Freshness — primary signal: verdict file mtime >= checkpoint file mtime
  local V_MT C_MT
  V_MT=$(stat --format='%Y' "$VRD" 2>/dev/null)
  C_MT=$(stat --format='%Y' "$CHK" 2>/dev/null)
  if [ -n "$V_MT" ] && [ -n "$C_MT" ]; then
    [ "$V_MT" -ge "$C_MT" ] || return 1
  fi

  # Freshness — additional gate only when BOTH explicit timestamps parse
  local VTS TRIG
  VTS=$(jq -r '.timestamp // .checked_at // .verdict_at // .created_at // .ts // ""' "$VRD" 2>/dev/null | tr -d '\r')
  TRIG=$(jq -r '.triggered_at // ""' "$CHK" 2>/dev/null | tr -d '\r')
  if [ -n "$VTS" ] && [ "$VTS" != "null" ] && [ -n "$TRIG" ] && [ "$TRIG" != "null" ]; then
    local VE TE
    VE=$(date -d "$VTS" +%s 2>/dev/null) || VE=""
    TE=$(date -d "$TRIG" +%s 2>/dev/null) || TE=""
    if [ -n "$VE" ] && [ -n "$TE" ]; then
      [ "$VE" -ge "$TE" ] || return 1
    fi
  fi

  # Conditions met — clear (idempotent rm -f) and reset counter
  rm -f "$CHK" "$VRD" "$PTH" 2>/dev/null
  rm -f "${STATE_DIR}/evidence-remediation.md" 2>/dev/null
  printf '{"writes":0,"last_step":""}' > "${STATE_DIR}/checkpoint-counter.json" 2>/dev/null
  printf 'cleared'
  return 0
}

# ===== Multilane instances (Sprint 31a) =====
# Registry v2: {version, max_lanes_per_project, instances:[{session_id,project,lane,status,...}]}
# Identity = session_id. Lane 1 = flat layout (today); lanes 2-5 = subdirs. Per-project cap.

# _reg_lock_for REG [maxwait] — mkdir-lock keyed to a SPECIFIC registry path (hermetic for sandboxes)
_reg_lock_for() {
  local LOCK="${1}.lock" MAX="${2:-10}" W=0
  while ! mkdir "$LOCK" 2>/dev/null; do
    sleep 0.2; W=$((W + 1))
    if [ "$W" -ge $((MAX * 5)) ]; then rm -rf "$LOCK" 2>/dev/null; mkdir "$LOCK" 2>/dev/null || return 1; break; fi
  done
  return 0
}
_reg_unlock_for() { rm -rf "${1}.lock" 2>/dev/null; }

_proj_norm() { printf '%s' "$1" | tr '\\' '/' | sed 's:/*$::' | tr '[:upper:]' '[:lower:]'; }

_ensure_reg_v2() {
  local REG="$1" M
  if [ ! -f "$REG" ]; then
    printf '{"version":"2.0.0","max_lanes_per_project":5,"instances":[]}' > "$REG"
    return 0
  fi
  if ! jq -e '.instances' "$REG" >/dev/null 2>&1; then
    # Migrate-in-place: ADD version/max/instances, PRESERVE all existing keys (.watchers etc.).
    # NEVER clobber a live v1 watcher registry.
    M=$(jq -c '. + {version:"2.0.0", max_lanes_per_project:(.max_lanes_per_project // 5), instances:(.instances // [])}' "$REG" 2>/dev/null)
    if [ -n "$M" ]; then
      printf '%s' "$M" > "$REG"
    else
      # Unparseable/corrupt — fresh v2 (nothing recoverable to lose)
      printf '{"version":"2.0.0","max_lanes_per_project":5,"instances":[]}' > "$REG"
    fi
  fi
}

# instance_find_by_session SESSION [REG] -> echo lane; rc 0 if found, 1 if not
instance_find_by_session() {
  local SID="$1" REG="${2:-${HARNESS_REGISTRY:-$HOME/.openclaw/watchers/REGISTRY.json}}" L
  [ -f "$REG" ] || return 1
  L=$(jq -r --arg s "$SID" '[.instances[]? | select(.session_id==$s)][0].lane // empty' "$REG" 2>/dev/null | tr -d '\r')
  [ -n "$L" ] || return 1
  printf '%s' "$L"; return 0
}

# instance_claim_lane SESSION PROJECT [REG] -> echo lane(1-5) rc0; refuse (cap full) -> empty rc1
# Idempotent: an existing session keeps its lane. Lowest free lane per project, under per-registry lock.
instance_claim_lane() {
  local SID="$1" PROJ="$2" REG="${3:-${HARNESS_REGISTRY:-$HOME/.openclaw/watchers/REGISTRY.json}}"
  local NOW PN MAX USED LANE i NEW
  NOW=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
  PN=$(_proj_norm "$PROJ")
  _reg_lock_for "$REG" || return 1
  _ensure_reg_v2 "$REG"
  MAX=$(jq -r '.max_lanes_per_project // 5' "$REG" 2>/dev/null | tr -d '\r'); [ -n "$MAX" ] || MAX=5
  LANE=$(jq -r --arg s "$SID" '[.instances[]? | select(.session_id==$s)][0].lane // empty' "$REG" 2>/dev/null | tr -d '\r')
  if [ -n "$LANE" ]; then _reg_unlock_for "$REG"; printf '%s' "$LANE"; return 0; fi
  USED=$(jq -r --arg p "$PN" '.instances[]? | select((.project|gsub("\\\\";"/")|sub("/+$";"")|ascii_downcase)==$p and .status=="active") | .lane' "$REG" 2>/dev/null | tr -d '\r' | tr '\n' ' ')
  LANE=""
  for i in $(seq 1 "$MAX"); do
    case " $USED " in *" $i "*) ;; *) LANE="$i"; break ;; esac
  done
  if [ -z "$LANE" ]; then _reg_unlock_for "$REG"; return 1; fi
  NEW=$(jq -c --arg s "$SID" --arg p "$PROJ" --argjson l "$LANE" --arg t "$NOW" \
    '.instances += [{"session_id":$s,"project":$p,"lane":$l,"status":"active","claimed_at":$t,"last_seen":$t,"cron_job_id":null,"cron_interval":null}]' \
    "$REG" 2>/dev/null)
  [ -n "$NEW" ] && printf '%s' "$NEW" > "$REG"
  _reg_unlock_for "$REG"
  printf '%s' "$LANE"; return 0
}

# instance_release SESSION [REG] — remove ONLY this session's entry (under lock)
instance_release() {
  local SID="$1" REG="${2:-${HARNESS_REGISTRY:-$HOME/.openclaw/watchers/REGISTRY.json}}" NEW
  [ -f "$REG" ] || return 0
  _reg_lock_for "$REG" || return 1
  NEW=$(jq -c --arg s "$SID" '.instances |= map(select(.session_id != $s))' "$REG" 2>/dev/null)
  [ -n "$NEW" ] && printf '%s' "$NEW" > "$REG"
  _reg_unlock_for "$REG"
  return 0
}

# lane_paths LANE — set STATE_DIR/CONTRACTS_DIR/PREFLIGHT_DIR/EVIDENCE_DIR/WORKING_DIR/MUSTDO_FILE/LANE
# Lane 1 (or empty) = today's FLAT layout (zero migration). Lanes 2-5 = lane-N subdirs.
lane_paths() {
  local L="$1"
  if [ "$L" = "1" ] || [ -z "$L" ]; then
    STATE_DIR=".claude/state"; CONTRACTS_DIR=".claude/contracts"; PREFLIGHT_DIR=".claude/pre-flight"
    EVIDENCE_DIR=".claude/evidence"; WORKING_DIR=".agent-memory/working"; MUSTDO_FILE="docs/must do/must-do.md"
    LANE=1
  else
    STATE_DIR=".claude/state/lane-${L}"; CONTRACTS_DIR=".claude/contracts/lane-${L}"
    PREFLIGHT_DIR=".claude/pre-flight/lane-${L}"; EVIDENCE_DIR=".claude/evidence/lane-${L}"
    WORKING_DIR=".agent-memory/working/lane-${L}"; MUSTDO_FILE="docs/must do/must-do-$((L - 1)).md"
    LANE="$L"
  fi
}

# mustdo_file_for_dir DIR — resolve THIS caller's owned must-do file inside a candidate dir,
# honoring lane ownership (slot-N <-> must-do-(N-1).md). Uses the global LANE set by resolve_instance.
# Lane 1 / unset -> "DIR/must-do.md". Lane N>=2 -> "DIR/must-do-(N-1).md" IF it exists, else falls
# back to "DIR/must-do.md" (back-compat: a lane with no numbered file uses the shared default).
# Replaces hardcoded "DIR/must-do.md" and "find DIR | head -1" so every gate reads the OWNED file.
mustdo_file_for_dir() {
  local DIR="$1" L="${LANE:-1}" F
  if [ "$L" = "1" ] || [ -z "$L" ]; then
    printf '%s/must-do.md' "$DIR"; return 0
  fi
  F="${DIR}/must-do-$((L - 1)).md"
  if [ -f "$F" ]; then printf '%s' "$F"; else printf '%s/must-do.md' "$DIR"; fi
}

# resolve_instance PAYLOAD PROJECT EVENT [REG] — the chokepoint. Reads session_id from the PASSED
# payload (never stdin). Finds the session's lane; claims ONLY at UserPromptSubmit; otherwise a new
# session defaults to read-only flat (lane 1) WITHOUT claiming. Sets LANE + all *_DIR/MUSTDO_FILE.
resolve_instance() {
  local PAYLOAD="$1" PROJ="$2" EVENT="$3" REG="${4:-${HARNESS_REGISTRY:-$HOME/.openclaw/watchers/REGISTRY.json}}"
  local SID L
  SID=$(printf '%s' "$PAYLOAD" | jq -r '.session_id // empty' 2>/dev/null | tr -d '\r')
  if [ -z "$SID" ]; then lane_paths 1; return 0; fi
  # OPT-IN GATE: multilane is ONLY active when the project has .claude/multi-lane.json. Otherwise every
  # instance resolves to lane 1 = flat = exact pre-multilane behavior (zero regression). This prevents
  # auto-lane-assignment from breaking projects whose per-lane state (phase/contracts) isn't seeded.
  if [ ! -f ".claude/multi-lane.json" ]; then lane_paths 1; return 0; fi
  L=$(instance_find_by_session "$SID" "$REG" 2>/dev/null)
  if [ -z "$L" ]; then
    if [ "$EVENT" = "UserPromptSubmit" ]; then
      L=$(instance_claim_lane "$SID" "$PROJ" "$REG" 2>/dev/null)
    fi
    [ -z "$L" ] && L=1
  fi
  lane_paths "$L"
  return 0
}

# ===== Per-project watcher POOL (AC13) — unlimited total watchers, capped max_per_project PER PROJECT =====
# Replaces the old fixed global 5-slot pool. .watchers[] is now a DYNAMIC list; each project independently
# gets up to max_per_project (5) active watchers. Slot numbers are global-unique (reused when freed).

# watcher_count_pp PROJECT [REG] -> echo count of ACTIVE watchers for that project
watcher_count_pp() {
  local PROJ="$1" REG="${2:-${HARNESS_REGISTRY:-$HOME/.openclaw/watchers/REGISTRY.json}}" PN C
  PN=$(_proj_norm "$PROJ")
  [ -f "$REG" ] || { printf '0'; return 0; }
  C=$(jq -r --arg p "$PN" '[.watchers[]? | select(.status=="active" and .project!=null and ((.project|gsub("\\\\";"/")|sub("/+$";"")|ascii_downcase)==$p))] | length' "$REG" 2>/dev/null | tr -d '\r')
  [ -n "$C" ] || C=0
  printf '%s' "$C"
}

# watcher_claim_pp SESSION PROJECT [REG] -> echo slot (global-unique) rc0; refuse (empty rc1) if project full.
# Idempotent: an existing active session keeps its slot.
watcher_claim_pp() {
  local SID="$1" PROJ="$2" REG="${3:-${HARNESS_REGISTRY:-$HOME/.openclaw/watchers/REGISTRY.json}}"
  local NOW PN MAX EXIST CNT USED SLOT NEW
  NOW=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
  PN=$(_proj_norm "$PROJ")
  _reg_lock_for "$REG" || return 1
  if [ ! -f "$REG" ] || ! jq -e '.watchers' "$REG" >/dev/null 2>&1; then
    printf '{"version":"3.0.0","max_per_project":5,"watchers":[]}' > "$REG"
  fi
  MAX=$(jq -r '.max_per_project // 5' "$REG" 2>/dev/null | tr -d '\r'); [ -n "$MAX" ] || MAX=5
  # idempotent
  EXIST=$(jq -r --arg s "$SID" '[.watchers[]? | select(.session_id==$s and .status=="active")][0].slot // empty' "$REG" 2>/dev/null | tr -d '\r')
  if [ -n "$EXIST" ]; then _reg_unlock_for "$REG"; printf '%s' "$EXIST"; return 0; fi
  # per-project cap
  CNT=$(jq -r --arg p "$PN" '[.watchers[]? | select(.status=="active" and .project!=null and ((.project|gsub("\\\\";"/")|sub("/+$";"")|ascii_downcase)==$p))] | length' "$REG" 2>/dev/null | tr -d '\r')
  [ -n "$CNT" ] || CNT=0
  if [ "$CNT" -ge "$MAX" ]; then _reg_unlock_for "$REG"; return 1; fi
  # lowest free global slot not used by any ACTIVE watcher
  USED=$(jq -r '[.watchers[]? | select(.status=="active") | .slot] | sort | .[]' "$REG" 2>/dev/null | tr -d '\r' | tr '\n' ' ')
  SLOT=1
  while case " $USED " in *" $SLOT "*) true ;; *) false ;; esac; do SLOT=$((SLOT + 1)); done
  # drop any stale non-active entry on that slot, append the new active watcher
  NEW=$(jq -c --argjson sl "$SLOT" --arg s "$SID" --arg p "$PROJ" --arg t "$NOW" \
    '.watchers |= (map(select((.slot != $sl) or (.status == "active"))) + [{"slot":$sl,"project":$p,"session_id":$s,"status":"active","claimed_by":"Claude","claimed_at":$t,"cron_job_id":null,"cron_interval":null,"task":null}])' \
    "$REG" 2>/dev/null)
  [ -n "$NEW" ] && printf '%s' "$NEW" > "$REG"
  _reg_unlock_for "$REG"
  printf '%s' "$SLOT"; return 0
}

# watcher_release_pp SESSION [REG] — remove this session's watcher entry (under lock)
watcher_release_pp() {
  local SID="$1" REG="${2:-${HARNESS_REGISTRY:-$HOME/.openclaw/watchers/REGISTRY.json}}" NEW
  [ -f "$REG" ] || return 0
  _reg_lock_for "$REG" || return 1
  NEW=$(jq -c --arg s "$SID" '.watchers |= map(select(.session_id != $s))' "$REG" 2>/dev/null)
  [ -n "$NEW" ] && printf '%s' "$NEW" > "$REG"
  _reg_unlock_for "$REG"
  return 0
}

# watcher_set_cron SESSION CRON_ID [CRON_INTERVAL] [REG] — record the cron on this session's watcher entry
watcher_set_cron() {
  local SID="$1" CID="$2" CI="${3:-*/3 * * * *}" REG="${4:-${HARNESS_REGISTRY:-$HOME/.openclaw/watchers/REGISTRY.json}}" NEW
  [ -f "$REG" ] || return 1
  _reg_lock_for "$REG" || return 1
  NEW=$(jq -c --arg s "$SID" --arg c "$CID" --arg i "$CI" '.watchers |= map(if .session_id==$s then (.cron_job_id=$c | .cron_interval=$i) else . end)' "$REG" 2>/dev/null)
  [ -n "$NEW" ] && printf '%s' "$NEW" > "$REG"
  _reg_unlock_for "$REG"
  return 0
}
