#!/bin/bash
# ensure-dev-server.sh — Pre-evaluator server check
# Detects project type (package.json/requirements.txt), starts dev server if not running,
# waits up to 60s for HTTP response. Blocks evaluation if server won't start.
# For CLI-only projects, exits 0 immediately (no server needed).
#
# Usage: bash ensure-dev-server.sh
# Exit: 0 = server running (or not needed), 1 = server failed to start

STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
# resolve STATE_DIR to the PROJECT ROOT (avoid creating a nested .claude in a subdir cwd)
if [ -z "${HARNESS_STATE_DIR:-}" ]; then . "$HOME/.claude/scripts/lib-helpers.sh" 2>/dev/null; type find_project_state_dir >/dev/null 2>&1 && { _r="$(find_project_state_dir "$(pwd -W 2>/dev/null || pwd)" 2>/dev/null)"; [ -n "$_r" ] && STATE_DIR="$_r"; }; fi
MAX_RETRIES=30
RETRY_INTERVAL=2

# Detect project type
if [ -f "package.json" ]; then
  PROJECT_TYPE="node"
  PORTS="5173 3000 8080"
elif [ -f "requirements.txt" ] || [ -f "pyproject.toml" ]; then
  PROJECT_TYPE="python"
  PORTS="8000 5000"
else
  printf "ensure-dev-server: No web project detected (no package.json/requirements.txt). Skipping.\n" >&2
  exit 0
fi

# Check if already running on any expected port
for PORT in $PORTS; do
  if curl -s --max-time 2 "http://localhost:$PORT" > /dev/null 2>&1; then
    printf "ensure-dev-server: Server already running on port %s.\n" "$PORT" >&2
    exit 0
  fi
done

# Start server based on project type
printf "ensure-dev-server: Starting %s dev server...\n" "$PROJECT_TYPE" >&2
case "$PROJECT_TYPE" in
  "node")
    bash -c "npm run dev &" &
    DEV_PID=$!
    ;;
  "python")
    bash -c "uvicorn main:app --reload &" &
    DEV_PID=$!
    ;;
esac

mkdir -p "$STATE_DIR" 2>/dev/null
printf "%s" "$DEV_PID" > "${STATE_DIR}/dev-server.pid"

# Wait for server to respond
RETRIES=0
while [ "$RETRIES" -lt "$MAX_RETRIES" ]; do
  for PORT in $PORTS; do
    if curl -s --max-time 2 "http://localhost:$PORT" > /dev/null 2>&1; then
      printf "ensure-dev-server: Server responding on port %s after %ss.\n" "$PORT" "$(( RETRIES * RETRY_INTERVAL ))" >&2
      exit 0
    fi
  done
  sleep "$RETRY_INTERVAL"
  RETRIES=$(( RETRIES + 1 ))
done

printf "ensure-dev-server: Server failed to start after %s attempts.\n" "$MAX_RETRIES" >&2
exit 1
