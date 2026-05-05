#!/bin/bash
# git-checkpoint.sh — Auto-commit at state transitions
# Stages all changes and commits with harness-prefixed message at every phase boundary.
# Only commits if there are actual changes.
#
# Usage: bash git-checkpoint.sh "PHASE" "SPRINT"
# Exit: 0 always

PHASE="${1:-UNKNOWN}"
SPRINT="${2:-0}"
MESSAGE="harness: ${PHASE} sprint ${SPRINT} [auto-checkpoint]"

# Only run if we're in a git repo
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf "git-checkpoint: Not in a git repo. Skipping.\n" >&2
  exit 0
fi

# Stage everything
git add -A 2>/dev/null

# Only commit if there are staged changes
if ! git diff --cached --quiet 2>/dev/null; then
  git commit -m "$MESSAGE" 2>/dev/null
  printf "git-checkpoint: Committed — %s\n" "$MESSAGE" >&2
else
  printf "git-checkpoint: No changes to commit at checkpoint.\n" >&2
fi

exit 0
