#!/bin/bash
# check-coverage.sh — Shows which projects are protected by the harness
# Scans common project locations for .claude/ directories and checks initialization status.
#
# Usage: bash ~/.claude/scripts/check-coverage.sh

printf "=== Harness Coverage Report ===\n"
printf "Date: %s\n\n" "$(date -Iseconds)"

PROTECTED=0
UNPROTECTED=0
TOTAL=0

# Search common locations
for BASE in "$HOME" "/g"; do
  while IFS= read -r claude_dir; do
    PROJECT_DIR=$(dirname "$claude_dir")

    # Skip the global .claude directory itself
    [ "$PROJECT_DIR" = "$HOME" ] && continue
    [ "$PROJECT_DIR" = "$HOME/.claude" ] && continue

    TOTAL=$((TOTAL + 1))

    if [ -f "$PROJECT_DIR/.claude/state/current-phase.json" ]; then
      PHASE=$(jq -r '.phase // "?"' "$PROJECT_DIR/.claude/state/current-phase.json" 2>/dev/null)
      printf "  [PROTECTED] %s (phase: %s)\n" "$PROJECT_DIR" "$PHASE"
      PROTECTED=$((PROTECTED + 1))
    else
      HAS_MEMORY=""
      [ -d "$PROJECT_DIR/.agent-memory" ] && HAS_MEMORY=" (has .agent-memory)"
      printf "  [  OPEN   ] %s%s\n" "$PROJECT_DIR" "$HAS_MEMORY"
      UNPROTECTED=$((UNPROTECTED + 1))
    fi
  done < <(find "$BASE" -maxdepth 3 -name ".claude" -type d 2>/dev/null | grep -v "node_modules" | grep -v "AppData" | sort)
done

printf "\n=== Summary ===\n"
printf "Protected: %s / %s projects\n" "$PROTECTED" "$TOTAL"
printf "Unprotected: %s\n" "$UNPROTECTED"

if [ "$UNPROTECTED" -gt 0 ]; then
  printf "\nTo protect a project:\n"
  printf "  cd /path/to/project\n"
  printf "  bash ~/.claude/scripts/init-project.sh\n"
fi
