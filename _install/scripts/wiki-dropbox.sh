#!/bin/bash
# wiki-dropbox.sh — Collect raw session data into AgentWiki dropbox
# Called from on-session-end.sh. This script ONLY collects — it does NOT
# parse, extract, categorize, or write wiki pages. The LLM does that
# during the next session's ingest phase (Karpathy self-evolving approach).
#
# Writes to: G:\AgentWiki\_dropbox\{slug}_{timestamp}.md
# Non-blocking: if anything fails, exits 0 silently.

VAULT="G:/AgentWiki"
DROPBOX="${VAULT}/_dropbox"
PROJECT_DIR="${1:-.}"
STATE_DIR="${PROJECT_DIR}/${HARNESS_STATE_DIR:-.claude/state}"
MEMORY_DIR="${PROJECT_DIR}/.agent-memory"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)

# Guard: only run if vault exists
if [ ! -d "$VAULT" ]; then
  exit 0
fi

# Guard: only run if session had meaningful work (>5 writes)
WRITE_COUNT=0
if [ -f "${STATE_DIR}/write-count.txt" ]; then
  WRITE_COUNT=$(cat "${STATE_DIR}/write-count.txt" 2>/dev/null || printf "0")
  WRITE_COUNT=$(printf '%s' "$WRITE_COUNT" | grep -o '[0-9]*' | head -1)
  WRITE_COUNT=${WRITE_COUNT:-0}
fi
if [ "$WRITE_COUNT" -le 5 ]; then
  exit 0
fi

# Derive project slug from project-map or basename
PROJECT_MAP="${VAULT}/_global/project-map.md"
CURRENT_PATH=$(cd "$PROJECT_DIR" && pwd -W 2>/dev/null || pwd)
SLUG=""

if [ -f "$PROJECT_MAP" ]; then
  # Try to match current path in project map (case-insensitive)
  SLUG=$(grep -i "$(printf '%s' "$CURRENT_PATH" | tr '\\' '/')" "$PROJECT_MAP" 2>/dev/null \
    | head -1 | sed 's/.*| *\([a-z0-9-]*\) *|.*/\1/' | tr -d '[:space:]')
fi

if [ -z "$SLUG" ]; then
  # Fallback: derive from basename
  SLUG=$(basename "$CURRENT_PATH" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
fi

if [ -z "$SLUG" ]; then
  SLUG="unknown-project"
fi

# Collect raw material
DROPBOX_FILE="${DROPBOX}/${SLUG}_${TIMESTAMP}.md"

{
  printf "# Dropbox: %s — %s\n\n" "$SLUG" "$TIMESTAMP"
  printf "Source: %s\n" "$CURRENT_PATH"
  printf "Writes: %s\n\n" "$WRITE_COUNT"

  # Phase info
  if [ -f "${STATE_DIR}/current-phase.json" ]; then
    PHASE=$(jq -r '.phase // "UNKNOWN"' "${STATE_DIR}/current-phase.json" 2>/dev/null || printf "UNKNOWN")
    SPRINT=$(jq -r '.sprint // 0' "${STATE_DIR}/current-phase.json" 2>/dev/null || printf "0")
    printf "Phase: %s, Sprint: %s\n\n" "$PHASE" "$SPRINT"
  fi

  # Progress notes
  printf "## Progress Notes\n\n"
  if [ -f "${STATE_DIR}/progress-notes.md" ]; then
    cat "${STATE_DIR}/progress-notes.md" 2>/dev/null
  else
    printf "(none)\n"
  fi
  printf "\n\n"

  # Latest session summary
  printf "## Session Summary\n\n"
  LATEST_SESSION=""
  if [ -d "${MEMORY_DIR}/episodic/sessions" ]; then
    LATEST_SESSION=$(ls -t "${MEMORY_DIR}/episodic/sessions/"*.md 2>/dev/null | head -1)
  fi
  if [ -n "$LATEST_SESSION" ] && [ -f "$LATEST_SESSION" ]; then
    cat "$LATEST_SESSION" 2>/dev/null
  else
    printf "(no session summary)\n"
  fi
  printf "\n\n"

  # Claude auto-memory (MEMORY.md) — project-specific
  printf "## MEMORY.md Excerpt\n\n"
  # Try Claude's project memory location
  PROJECT_NORM=$(printf '%s' "$CURRENT_PATH" | tr '/' '-' | tr '\\' '-' | tr ':' '-' | tr '[:upper:]' '[:lower:]' | sed 's/^-*//')
  CLAUDE_MEMORY="$HOME/.claude/projects/${PROJECT_NORM}/memory/MEMORY.md"
  if [ -f "$CLAUDE_MEMORY" ]; then
    head -100 "$CLAUDE_MEMORY" 2>/dev/null
  else
    printf "(no MEMORY.md found)\n"
  fi
  printf "\n"

} > "$DROPBOX_FILE" 2>/dev/null

if [ -f "$DROPBOX_FILE" ]; then
  printf "wiki-dropbox: Collected session data to %s\n" "$DROPBOX_FILE" >&2
fi

exit 0
