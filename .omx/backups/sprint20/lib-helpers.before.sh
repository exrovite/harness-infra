#!/bin/bash
# lib-helpers.sh — Shared helper functions for harness scripts
# Source this file: source "$HOME/.claude/scripts/lib-helpers.sh"

# atomic_write — Write content to file via temp+mv (prevents partial writes)
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

# append_jsonl — Append one JSON line to a JSONL file (append-only, can't corrupt previous entries)
# Usage: append_jsonl '{"key":"value"}' "/path/to/file.jsonl"
append_jsonl() {
  local LINE="$1"
  local TARGET="$2"

  mkdir -p "$(dirname "$TARGET")" 2>/dev/null
  printf "%s\n" "$LINE" >> "$TARGET"
}

# trim_jsonl — Keep only the last N lines of a JSONL file (atomic trim)
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

# write_if_changed — Only write if content differs from current file (hash-based)
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

# registry_lock — Acquire exclusive lock on REGISTRY.json via lockdir (mkdir is atomic)
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
      # Stale lock (crashed process) — force clean and retry once
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

# registry_unlock — Release REGISTRY.json lock
# Usage: registry_unlock
registry_unlock() {
  rm -rf "$HOME/.openclaw/watchers/.registry-lock" 2>/dev/null
}

# registry_modify — Safely modify REGISTRY.json with locking
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

# write_phase — Atomically write current-phase.json (most critical state file)
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
