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
  local WATCHER_REGISTRY="${WATCHER_REGISTRY:-$HOME/.openclaw/watchers/REGISTRY.json}"
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

# check_watcher_for_project Ã¢â‚¬â€ Return active watcher slot for a project, or empty string
# Usage: check_watcher_for_project "G:/path" [registry_path]
check_watcher_for_project() {
  local PROJECT_PATH="$1"
  local REGISTRY="${2:-$HOME/.openclaw/watchers/REGISTRY.json}"

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
