#!/bin/bash
# check-budget.sh — Cost/time circuit breaker
# Checks elapsed time against MAX_HOURS and estimated cost against MAX_COST_USD.
# Cost estimated as iteration_count × $4 (integer arithmetic, no bc).
# Called by run-harness.sh at start of every iteration.
#
# Usage: bash check-budget.sh
# Exit: 0 = within budget, 1 = limit reached (hard stop)

STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
MAX_COST_USD="${MAX_COST:-50}"
MAX_ELAPSED_HOURS="${MAX_HOURS:-4}"

# Ensure state dir exists
mkdir -p "$STATE_DIR" 2>/dev/null

# Track elapsed time
START_TIME_FILE="${STATE_DIR}/session-start-time.txt"
if [ ! -f "$START_TIME_FILE" ]; then
  printf "%s" "$(date +%s)" > "$START_TIME_FILE"
fi

START_TIME=$(cat "$START_TIME_FILE" 2>/dev/null)
NOW=$(date +%s)
ELAPSED_SECONDS=$(( NOW - START_TIME ))
ELAPSED_HOURS=$(( ELAPSED_SECONDS / 3600 ))

# Check time limit
if [ "$ELAPSED_HOURS" -ge "$MAX_ELAPSED_HOURS" ]; then
  bash "$HOME/.claude/scripts/write-handoff.sh" "BUDGET_TIME_LIMIT" 2>/dev/null
  bash "$HOME/.claude/scripts/notify.sh" "Time limit reached (${ELAPSED_HOURS}h/${MAX_ELAPSED_HOURS}h). Session saved." 2>/dev/null
  printf "check-budget: TIME LIMIT REACHED (%sh >= %sh). Hard stop.\n" "$ELAPSED_HOURS" "$MAX_ELAPSED_HOURS" >&2
  exit 1
fi

# Track iterations as cost proxy (integer arithmetic only)
ITERATION_COUNT=0
if [ -f "${STATE_DIR}/current-phase.json" ]; then
  ITERATION_COUNT=$(jq -r '.iteration // 0' "${STATE_DIR}/current-phase.json" 2>/dev/null || printf "0")
fi
ESTIMATED_COST=$(( ITERATION_COUNT * 4 ))

# Check cost limit
if [ "$ESTIMATED_COST" -ge "$MAX_COST_USD" ]; then
  bash "$HOME/.claude/scripts/write-handoff.sh" "BUDGET_COST_LIMIT" 2>/dev/null
  bash "$HOME/.claude/scripts/notify.sh" "Budget limit reached (~\$${ESTIMATED_COST}/\$${MAX_COST_USD}). Session saved." 2>/dev/null
  printf "check-budget: COST LIMIT REACHED (~\$%s >= \$%s). Hard stop.\n" "$ESTIMATED_COST" "$MAX_COST_USD" >&2
  exit 1
fi

printf "check-budget: OK (time: %sh/%sh, cost: ~\$%s/\$%s)\n" "$ELAPSED_HOURS" "$MAX_ELAPSED_HOURS" "$ESTIMATED_COST" "$MAX_COST_USD" >&2
exit 0
