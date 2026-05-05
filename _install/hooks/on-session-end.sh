#!/bin/bash
# on-session-end.sh — Claude Code Stop hook
# Memory-hardened: atomic writes, append-only JSONL, no jq WRITE.
# Writes session summary, updates active-tasks, logs session end, trims JSONL files.

source "$HOME/.claude/scripts/lib-helpers.sh" 2>/dev/null

STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
MEMORY_DIR=".agent-memory"
TIMESTAMP=$(date -Iseconds)

# Auto-initialize if needed
if [ -d ".claude" ] && [ ! -f "${STATE_DIR}/current-phase.json" ]; then
  bash "$HOME/.claude/scripts/init-project.sh" 2>/dev/null
fi

# Only run memory updates if .agent-memory exists
if [ ! -d "$MEMORY_DIR" ]; then
  exit 0
fi

# --- READ current state (jq READ only, safe) ---
PHASE="UNKNOWN"
SPRINT=0
ITERATION=0
if [ -f "${STATE_DIR}/current-phase.json" ]; then
  PHASE=$(jq -r '.phase // "UNKNOWN"' "${STATE_DIR}/current-phase.json" 2>/dev/null || printf "UNKNOWN")
  SPRINT=$(jq -r '.sprint // 0' "${STATE_DIR}/current-phase.json" 2>/dev/null || printf "0")
  ITERATION=$(jq -r '.iteration // 0' "${STATE_DIR}/current-phase.json" 2>/dev/null || printf "0")
fi

WRITE_COUNT=0
if [ -f "${STATE_DIR}/write-count.txt" ]; then
  WRITE_COUNT=$(cat "${STATE_DIR}/write-count.txt" 2>/dev/null || printf "0")
fi

# --- 1. Session summary (atomic write to new file — never edits existing) ---
SESSIONS_DIR="${MEMORY_DIR}/episodic/sessions"
mkdir -p "$SESSIONS_DIR" 2>/dev/null
SESSION_FILE="${SESSIONS_DIR}/$(date +%Y-%m-%d_%H-%M-%S).md"

PROGRESS_NOTES=""
if [ -f "${STATE_DIR}/progress-notes.md" ]; then
  PROGRESS_NOTES=$(cat "${STATE_DIR}/progress-notes.md" 2>/dev/null)
fi

# Get modified files — prefer git, fallback to unverified-writes tracker
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  MODIFIED_FILES=$(git diff --name-only HEAD~5 2>/dev/null | head -20 | sed 's/^/  - /')
  [ -z "$MODIFIED_FILES" ] && MODIFIED_FILES="(no uncommitted changes)"
else
  if [ -f "${STATE_DIR}/unverified-writes.jsonl" ]; then
    MODIFIED_FILES=$(jq -r '.file' "${STATE_DIR}/unverified-writes.jsonl" 2>/dev/null | sort -u | head -20 | sed 's/^/  - /')
  fi
  [ -z "$MODIFIED_FILES" ] && MODIFIED_FILES="(not a git repo — no file tracking available)"
fi

BLOCKED_STATUS="Normal session end"
if [ -f "${STATE_DIR}/agent-blocked.md" ]; then
  BLOCKED_STATUS="BLOCKED — agent was paused at session end"
fi

SESSION_CONTENT="# Session Summary — ${TIMESTAMP}

## Phase at End
Phase: ${PHASE}, Sprint: ${SPRINT}, Iteration: ${ITERATION}

## Progress Notes
${PROGRESS_NOTES:-No progress notes.}

## Files Modified
${MODIFIED_FILES}

## Status
${BLOCKED_STATUS}

## Write Count
Total writes this session: ${WRITE_COUNT}"

atomic_write "$SESSION_CONTENT" "$SESSION_FILE"

# --- 2. Session log (append-only JSONL — can't corrupt previous sessions) ---
append_jsonl "{\"event\":\"session_end\",\"ts\":\"${TIMESTAMP}\",\"phase\":\"${PHASE}\",\"sprint\":${SPRINT},\"writes\":${WRITE_COUNT}}" \
  "${MEMORY_DIR}/sessions.jsonl"

# --- 3. MEMORY_MANIFEST.json — lightweight atomic update (no jq WRITE) ---
# Read current count, increment, write atomically
MANIFEST="${MEMORY_DIR}/MEMORY_MANIFEST.json"
if [ -f "$MANIFEST" ]; then
  # jq READ only — check both root and quick_access locations
  OLD_COUNT=$(jq -r '(.sessions_count // .quick_access.sessions_count // 0) | tonumber' "$MANIFEST" 2>/dev/null || printf "0")
  if ! [[ "$OLD_COUNT" =~ ^[0-9]+$ ]]; then OLD_COUNT=0; fi
  NEW_COUNT=$((OLD_COUNT + 1))

  # Atomic update: read entire file, sed the fields, write atomically
  # This avoids jq WRITE (which reads+parses+transforms+writes the whole file)
  # Use a two-pass approach: first update last_accessed, then sessions_count
  # For sessions_count, only update the LAST occurrence (root-level, not nested)
  UPDATED=$(sed \
    -e "s/\"last_accessed\": *\"[^\"]*\"/\"last_accessed\": \"${TIMESTAMP}\"/" \
    "$MANIFEST" 2>/dev/null)
  # Update sessions_count at all locations (both root and quick_access)
  UPDATED=$(printf '%s' "$UPDATED" | sed \
    -e "s/\"sessions_count\": *[0-9]*/\"sessions_count\": ${NEW_COUNT}/g")

  if [ -n "$UPDATED" ]; then
    atomic_write "$UPDATED" "$MANIFEST"
  fi
fi

# --- 4. active-tasks.json — what to resume next session (atomic write) ---
TASKS_CONTENT="{\"last_session_end\":\"${TIMESTAMP}\",\"phase_at_end\":\"${PHASE}\",\"sprint_at_end\":${SPRINT},\"resume_action\":\"Continue from phase ${PHASE}\"}"
mkdir -p "${MEMORY_DIR}/working" 2>/dev/null
atomic_write "$TASKS_CONTENT" "${MEMORY_DIR}/working/active-tasks.json"

# --- 5. Trim JSONL files (prevent unbounded growth) ---
trim_jsonl "${MEMORY_DIR}/working/recent-activity.jsonl" 50
trim_jsonl "${MEMORY_DIR}/sessions.jsonl" 100

# --- 6. Reset write counter ---
# write-count NOT reset on session end — persists across sessions for gate enforcement

# --- 7. Wiki dropbox (collect raw session data for LLM-driven ingest) ---
# Collects session summary + progress notes into G:\AgentWiki\_dropbox\.
# The LLM processes these at next session start (Karpathy self-evolving approach).
bash "$HOME/.claude/scripts/wiki-dropbox.sh" "." 2>/dev/null || true

# --- 8. Watcher auto-release REMOVED ---
# Sub-agents trigger the Stop hook when they finish, which was releasing the
# PARENT agent's watchers mid-session. This caused watchers to disappear
# every time the Agent tool was used (or interrupted).
# Stale watchers are now cleaned ONLY by startup-recovery.sh (>4h threshold)
# on the next session start. Agents can still manually release watchers.

exit 0
