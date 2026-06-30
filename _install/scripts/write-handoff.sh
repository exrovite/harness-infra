#!/bin/bash
# write-handoff.sh — Rich handoff artifact generator
# Generates structured context document from disk state for session transitions and crash recovery.
# Internal schema: 8 sections covering completed features, codebase, decisions, tests, next steps.
#
# Usage: bash write-handoff.sh "PHASE_LABEL"
# Output: writes handoff-artifact.md to state directory

PHASE_LABEL="${1:-UNKNOWN}"
STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"

# Never create a .claude in a non-project folder. Resolve to an existing project root; if none, do
# nothing (a handoff only makes sense inside a real project). Defense-in-depth: callers should already
# pass HARNESS_STATE_DIR, but this guards direct/future invocations too.
if [ -z "${HARNESS_STATE_DIR:-}" ]; then
  . "$HOME/.claude/scripts/lib-helpers.sh" 2>/dev/null
  if type find_project_state_dir >/dev/null 2>&1; then
    _wh_root="$(find_project_state_dir "$(pwd -W 2>/dev/null || pwd)" 2>/dev/null)"
    if [ -n "$_wh_root" ]; then STATE_DIR="$_wh_root"; else exit 0; fi
  fi
fi
HANDOFF_FILE="${STATE_DIR}/handoff-artifact.md"

mkdir -p "$STATE_DIR" 2>/dev/null

# Gather data safely (each section tolerates missing files/repos)
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  COMPLETED_FEATURES=$(git log --oneline -20 2>/dev/null || printf "No commits yet\n")
  FILES_MODIFIED=$(git diff --name-only HEAD~5 2>/dev/null | head -20 | sed 's/^/  - /')
  [ -z "$FILES_MODIFIED" ] && FILES_MODIFIED="No recent changes"
else
  COMPLETED_FEATURES="(not a git repo)"
  if [ -f "${STATE_DIR}/unverified-writes.jsonl" ]; then
    FILES_MODIFIED=$(jq -r '.file' "${STATE_DIR}/unverified-writes.jsonl" 2>/dev/null | sort -u | head -20 | sed 's/^/  - /')
  fi
  [ -z "$FILES_MODIFIED" ] && FILES_MODIFIED="No recent changes"
fi
CODEBASE_STATE=$(find src/ -type f \( -name "*.ts" -o -name "*.py" -o -name "*.jsx" -o -name "*.js" -o -name "*.sh" \) 2>/dev/null | head -30 || printf "No src/ directory found\n")
PROGRESS_NOTES=$(cat "${STATE_DIR}/progress-notes.md" 2>/dev/null || printf "No progress notes yet\n")
DEFERRED_WORK=$(cat "${STATE_DIR}/deferred.md" 2>/dev/null || printf "No deferred work\n")
ACTIVE_CONTRACT=$(cat .claude/contracts/current-contract.md 2>/dev/null || cat .claude/contracts/sprint-*-contract.md 2>/dev/null | tail -50 || printf "No active contract\n")
TEST_STATUS=$(bash "$HOME/.claude/scripts/validate.sh" --summary 2>&1 || printf "Validation script not available\n")
KNOWN_ISSUES=$(cat "${STATE_DIR}/agent-blocked.md" 2>/dev/null || printf "None\n")

# Write handoff artifact using printf (LF enforcement)
{
  printf "# Session Handoff — %s\n" "$(date -Iseconds)"
  printf "# Phase: %s\n\n" "$PHASE_LABEL"

  printf "## Completed Features\n%s\n\n" "$COMPLETED_FEATURES"
  printf "## Current Codebase State\n%s\n\n" "$CODEBASE_STATE"
  printf "## Files Modified This Session\n%s\n\n" "$FILES_MODIFIED"
  printf "## Architectural Decisions Made\n%s\n\n" "$PROGRESS_NOTES"
  printf "## Known Issues / Deferred Work\n%s\n\n" "$DEFERRED_WORK"
  printf "## Active Sprint Contract\n%s\n\n" "$ACTIVE_CONTRACT"
  printf "## Test Status\n%s\n\n" "$TEST_STATUS"
  printf "## What To Do Next\nRead .claude/state/active-instructions.md for current phase instructions.\n"
} > "$HANDOFF_FILE"

printf "write-handoff: Handoff artifact written to %s (phase: %s)\n" "$HANDOFF_FILE" "$PHASE_LABEL" >&2
exit 0
