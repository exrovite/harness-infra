#!/bin/bash
# create-evidence-checkpoint.sh — Build an evidence checkpoint brief
# Called by post-write-check.sh when write count threshold is reached.
# Reads must-do source files and writes evidence-checkpoint.json.
# Exit 0 = checkpoint created, Exit 1 = no must-do folder or already active

STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
# resolve STATE_DIR to the PROJECT ROOT (avoid creating a nested .claude in a subdir cwd)
if [ -z "${HARNESS_STATE_DIR:-}" ]; then . "$HOME/.claude/scripts/lib-helpers.sh" 2>/dev/null; type find_project_state_dir >/dev/null 2>&1 && { _r="$(find_project_state_dir "$(pwd -W 2>/dev/null || pwd)" 2>/dev/null)"; if [ -n "$_r" ]; then STATE_DIR="$_r"; else exit 0; fi; }; fi
CHECKPOINT_FILE="${STATE_DIR}/evidence-checkpoint.json"
SUMMARY_FILE="${STATE_DIR}/must-do-summary.md"
PATHS_FILE="${STATE_DIR}/evidence-paths.json"
MEMORY_DIR=".agent-memory"

# --- Guard: don't overwrite active checkpoint (unless step changed) ---
if [ -f "$CHECKPOINT_FILE" ]; then
  if [ "$1" = "step_change" ]; then
    # Step changed — clear stale checkpoint artifacts and rebuild for current work
    rm -f "$CHECKPOINT_FILE" "${STATE_DIR}/evidence-verdict.json" \
          "${STATE_DIR}/evidence-remediation.md" "$PATHS_FILE" 2>/dev/null
    echo "create-evidence-checkpoint: replacing stale checkpoint (step_change)" >&2
  else
    exit 1
  fi
fi

# --- Guard: must-do summary must exist ---
if [ ! -f "$SUMMARY_FILE" ]; then
  exit 1
fi

# --- Find must-do folder ---
MUST_DO_DIR=""
for CAND in "docs/must do" "docs/must-do" ".claude/must-do"; do
  if [ -d "$CAND" ]; then
    MUST_DO_DIR="$CAND"
    break
  fi
done

if [ -z "$MUST_DO_DIR" ]; then
  exit 1
fi

# --- Find must-do index file ---
MUST_DO_INDEX=""
if [ -f "${MUST_DO_DIR}/must-do.md" ]; then
  MUST_DO_INDEX="${MUST_DO_DIR}/must-do.md"
elif [ -f "${MUST_DO_DIR}/index.md" ]; then
  MUST_DO_INDEX="${MUST_DO_DIR}/index.md"
fi

if [ -z "$MUST_DO_INDEX" ]; then
  # Try first .md file in the folder
  MUST_DO_INDEX=$(find "$MUST_DO_DIR" -maxdepth 1 -name "*.md" -type f 2>/dev/null | head -1)
fi

# --- Read must-do summary ---
SUMMARY_TEXT=$(head -c 3000 "$SUMMARY_FILE" 2>/dev/null)

# --- Read must-do source files ---
SOURCE_FILES_JSON="[]"
if [ -n "$MUST_DO_INDEX" ] && [ -f "$MUST_DO_INDEX" ]; then
  TMPFILE=$(mktemp)
  printf '[]' > "$TMPFILE"

  while IFS= read -r LINE || [ -n "$LINE" ]; do
    LINE=$(printf '%s' "$LINE" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$LINE" ] && continue
    # Skip headers and separators
    case "$LINE" in "#"*|"---"*|">"*) continue ;; esac

    # LINE is a file path — read it if it exists
    if [ -f "$LINE" ]; then
      FILE_CONTENT=$(head -c 3000 "$LINE" 2>/dev/null | tr -d '\r')
      # Flatten newlines for readability; jq --arg handles JSON escaping
      FLAT_CONTENT=$(printf '%s' "$FILE_CONTENT" | tr '\n' ' ')

      # Append to array via jq (--arg escapes backslashes/quotes automatically)
      jq --arg p "$LINE" --arg c "$FLAT_CONTENT" '. + [{"path": $p, "content": $c}]' "$TMPFILE" > "${TMPFILE}.new" 2>/dev/null
      if [ -s "${TMPFILE}.new" ]; then
        mv "${TMPFILE}.new" "$TMPFILE"
      fi
    fi
  done < "$MUST_DO_INDEX"

  SOURCES_TMPFILE="$TMPFILE"
  # Keep temp file alive — will use --slurpfile in final build to avoid arg length limits
fi

# --- Get modified files since last checkpoint ---
MODIFIED_JSON="[]"
if [ -f "${MEMORY_DIR}/working/session-context.md" ]; then
  TMPMOD=$(mktemp)
  printf '[]' > "$TMPMOD"

  # Extract file paths from session-context.md (lines starting with "  - ")
  # Use process substitution to avoid subshell pipe problem
  while IFS= read -r MFILE; do
    MFILE=$(printf '%s' "$MFILE" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$MFILE" ] && continue
    # jq --arg handles JSON escaping (no sed needed — breaks on MSYS)
    jq --arg f "$MFILE" '. + [$f]' "$TMPMOD" > "${TMPMOD}.new" 2>/dev/null
    if [ -s "${TMPMOD}.new" ]; then
      mv "${TMPMOD}.new" "$TMPMOD"
    fi
  done < <(grep -E '^  - ' "${MEMORY_DIR}/working/session-context.md" 2>/dev/null | sed 's/^  - //')

  MODIFIED_TMPFILE="$TMPMOD"
  # Keep temp file alive — will use --slurpfile in final build
fi

# --- Check for agent-provided paths (from previous FAIL cycle) ---
AGENT_PATHS_JSON="[]"
if [ -f "$PATHS_FILE" ] && jq '.' "$PATHS_FILE" >/dev/null 2>&1; then
  AGENT_PATHS_JSON=$(cat "$PATHS_FILE" | tr -d '\r')
fi

# --- Read watcher checklist (agent's declared work plan) ---
WATCHER_CHECKLIST=""
WATCHER_REGISTRY="$HOME/.openclaw/watchers/REGISTRY.json"
if [ -f "$WATCHER_REGISTRY" ]; then
  WC_PROJECT=$(pwd -W 2>/dev/null || pwd)
  WC_PROJECT=$(printf '%s' "$WC_PROJECT" | tr '\\' '/' | sed 's|/$||' | tr '[:upper:]' '[:lower:]')
  WC_SLOT=$(jq -r --arg proj "$WC_PROJECT" \
    '[.watchers[] | select(.status == "active" and .project != null and ((.project | gsub("\\\\";"/") | sub("/$";"") | ascii_downcase) == $proj))] | .[0].slot // empty' \
    "$WATCHER_REGISTRY" 2>/dev/null)
  if [ -n "$WC_SLOT" ]; then
    WC_FILE="$HOME/.openclaw/watchers/slot-${WC_SLOT}.md"
    if [ -f "$WC_FILE" ]; then
      WATCHER_CHECKLIST=$(cat "$WC_FILE" 2>/dev/null | tr -d '\r' | head -c 3000)
    fi
  fi
fi

# --- Build verifier instruction ---
INSTRUCTION="You are an evidence checkpoint verifier. Your job is to check whether the agent has followed the process it declared in its must-do summary."
INSTRUCTION="${INSTRUCTION} Read the must_do_source_files above — they define the FULL process requirements."
INSTRUCTION="${INSTRUCTION} Read the must_do_summary — this is what the agent declared it would do."
INSTRUCTION="${INSTRUCTION} Read the watcher_checklist — this is the agent's step-by-step work plan with checked-off [x] and unchecked [ ] items. Verify that checked-off steps actually have evidence."
INSTRUCTION="${INSTRUCTION} For each phase/step in the declared process: check whether evidence exists."
INSTRUCTION="${INSTRUCTION} Look in .claude/evidence/, check the modified files list, and check any agent_provided_paths."
INSTRUCTION="${INSTRUCTION} For each phase, report: found (with file path and quality assessment) or missing."
INSTRUCTION="${INSTRUCTION} If evidence is MISSING for a phase: name the phase, say what you looked for, and tell the agent: 'If this evidence exists elsewhere, write the file paths to .claude/state/evidence-paths.json and delete the verdict file to re-trigger verification.'"
INSTRUCTION="${INSTRUCTION} If agent_provided_paths are present: READ those specific files and judge whether they constitute real evidence for the claimed phase."
INSTRUCTION="${INSTRUCTION} Write your verdict to .claude/state/evidence-verdict.json with format: {\"verdict\":\"PASS|FAIL\",\"checked_at\":\"ISO\",\"phases_found\":[],\"phases_missing\":[],\"findings\":[{\"phase\":\"X\",\"evidence_file\":\"path|null\",\"quality\":\"substantive|insufficient|null\",\"note\":\"details\"}],\"summary\":\"text\"}"

# --- Build trigger reason ---
TRIGGER_REASON="${1:-write_count}"

# --- Write checkpoint JSON ---
TIMESTAMP=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')

# Write large values to temp files to avoid Windows command-line length limits.
# jq --slurpfile reads JSON arrays from file; --rawfile reads raw strings.
SUMMARY_TMP=$(mktemp)
printf '%s' "$SUMMARY_TEXT" | tr '\n' ' ' > "$SUMMARY_TMP"

CHECKLIST_TMP=$(mktemp)
printf '%s' "$WATCHER_CHECKLIST" > "$CHECKLIST_TMP"

INSTRUCTION_TMP=$(mktemp)
printf '%s' "$INSTRUCTION" > "$INSTRUCTION_TMP"

# Ensure source/modified/agent-paths temp files exist with defaults
if [ -z "$SOURCES_TMPFILE" ]; then
  SOURCES_TMPFILE=$(mktemp)
  printf '[]' > "$SOURCES_TMPFILE"
fi
if [ -z "$MODIFIED_TMPFILE" ]; then
  MODIFIED_TMPFILE=$(mktemp)
  printf '[]' > "$MODIFIED_TMPFILE"
fi
AGENT_PATHS_TMP=$(mktemp)
printf '%s' "$AGENT_PATHS_JSON" > "$AGENT_PATHS_TMP"

# Build checkpoint JSON using temp files (avoids arg length limits on Windows)
CHECKPOINT_JSON=$(jq -n \
  --arg status "pending" \
  --arg ts "$TIMESTAMP" \
  --arg reason "$TRIGGER_REASON" \
  --rawfile summary "$SUMMARY_TMP" \
  --rawfile checklist "$CHECKLIST_TMP" \
  --rawfile instruction "$INSTRUCTION_TMP" \
  --slurpfile sources "$SOURCES_TMPFILE" \
  --slurpfile modified "$MODIFIED_TMPFILE" \
  --slurpfile agent_paths "$AGENT_PATHS_TMP" \
  '{
    status: $status,
    triggered_at: $ts,
    trigger_reason: $reason,
    must_do_summary: $summary,
    watcher_checklist: $checklist,
    must_do_source_files: $sources[0],
    modified_files_since_last: $modified[0],
    agent_provided_paths: $agent_paths[0],
    evidence_dir: ".claude/evidence/",
    instruction: $instruction
  }' 2>/dev/null)

# Clean up all temp files
rm -f "$SUMMARY_TMP" "$CHECKLIST_TMP" "$INSTRUCTION_TMP" \
      "$SOURCES_TMPFILE" "${SOURCES_TMPFILE}.new" \
      "$MODIFIED_TMPFILE" "${MODIFIED_TMPFILE}.new" \
      "$AGENT_PATHS_TMP" 2>/dev/null

if [ -z "$CHECKPOINT_JSON" ]; then
  echo "create-evidence-checkpoint: jq build failed" >&2
  exit 1
fi

# Clear stale remediation from previous cycle
rm -f "${STATE_DIR}/evidence-remediation.md" 2>/dev/null

# Load helpers for atomic write
source "$HOME/.claude/scripts/lib-helpers.sh" 2>/dev/null
mkdir -p "$STATE_DIR" 2>/dev/null

if type atomic_write >/dev/null 2>&1; then
  atomic_write "$CHECKPOINT_JSON" "$CHECKPOINT_FILE"
else
  printf '%s' "$CHECKPOINT_JSON" > "$CHECKPOINT_FILE"
fi

echo "create-evidence-checkpoint: checkpoint created at $CHECKPOINT_FILE" >&2
exit 0
