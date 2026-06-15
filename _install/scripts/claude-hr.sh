#!/bin/bash
# claude-hr — launch Claude Code with headroom token-compression (transparent wrapper)
#
# headroom is installed in an ISOLATED uv-managed Python 3.10 venv at ~/.claude/headroom-venv
# (see _install/install.sh step 9). It NEVER uses the system Python. This launcher finds that
# venv's `headroom` entrypoint and runs `headroom wrap claude "$@"`, which:
#   1. starts a local headroom compression proxy (background),
#   2. sets ANTHROPIC_BASE_URL to that proxy,
#   3. launches `claude` so all model traffic is compressed before leaving the machine.
#
# Usage:
#   claude-hr                       # compressed Claude Code session
#   claude-hr -- --model opus       # pass args through to claude
#   claude-hr --port 9999           # custom proxy port (headroom flag)
#
# If headroom is not installed, this prints how to install it and falls back to plain `claude`
# so you are never blocked.

set -euo pipefail

VENV="${HEADROOM_VENV:-$HOME/.claude/headroom-venv}"

# Resolve the venv's headroom entrypoint (Windows: Scripts/, Unix: bin/).
HEADROOM=""
if [ -x "$VENV/Scripts/headroom.exe" ]; then
  HEADROOM="$VENV/Scripts/headroom.exe"
elif [ -x "$VENV/Scripts/headroom" ]; then
  HEADROOM="$VENV/Scripts/headroom"
elif [ -x "$VENV/bin/headroom" ]; then
  HEADROOM="$VENV/bin/headroom"
fi

if [ -z "$HEADROOM" ]; then
  echo "[claude-hr] headroom is not installed in the isolated venv ($VENV)." >&2
  echo "[claude-hr] Install it (no effect on system Python):" >&2
  echo "             uv venv --python 3.10 \"$VENV\"" >&2
  echo "             uv pip install --python \"$VENV\" \"headroom-ai[all]\"" >&2
  echo "           or re-run: bash _install/install.sh" >&2
  if command -v claude >/dev/null 2>&1; then
    echo "[claude-hr] Falling back to plain 'claude' (no compression)." >&2
    exec claude "$@"
  fi
  exit 1
fi

# Headroom runtime defaults (overridable from the environment):
#  - HEADROOM_RUST_DETECT=0 : skip the native magika detector, which hangs
#    on first call on this host; use the pure-Python regex detector instead.
#  - agent-90 savings profile : aggressive token compression.
export HEADROOM_RUST_DETECT="${HEADROOM_RUST_DETECT:-0}"
export HEADROOM_SAVINGS_PROFILE="${HEADROOM_SAVINGS_PROFILE:-agent-90}"

exec "$HEADROOM" wrap claude "$@"
