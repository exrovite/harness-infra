#!/bin/bash
# arbor.sh — run the Arbor autonomous research-agent CLI from its ISOLATED venv.
#
# Arbor (https://github.com/RUC-NLPIR/Arbor, Apache-2.0) is installed into ~/.claude/arbor-venv by
# install.sh (isolated uv-managed Python; system Python untouched). This wrapper finds that venv's
# `arbor` entrypoint and forwards all args.
#
# Usage:
#   arbor.sh setup     # one-time provider/model/API-key config (~/.arbor/config.yaml)
#   arbor.sh doctor    # diagnose the install
#   arbor.sh           # interactive autonomous research session
#   arbor.sh <args...> # any arbor subcommand
#
# NOTE: Arbor is autonomous — it edits code in git worktrees and spends real LLM money. It only runs
# when YOU launch it here; nothing in the harness auto-runs it.
set -euo pipefail

VENV="${ARBOR_VENV:-$HOME/.claude/arbor-venv}"
ARBOR=""
for cand in "$VENV/bin/arbor" "$VENV/Scripts/arbor.exe" "$VENV/Scripts/arbor"; do
  [ -x "$cand" ] && { ARBOR="$cand"; break; }
done

if [ -z "$ARBOR" ]; then
  echo "[arbor] not installed in the isolated venv ($VENV)." >&2
  echo "[arbor] install it (no effect on system Python):" >&2
  echo "          uv venv --python 3.10 \"$VENV\"" >&2
  echo "          uv pip install --python \"$VENV\" 'git+https://github.com/RUC-NLPIR/Arbor.git'" >&2
  echo "        or re-run: bash _install/install.sh" >&2
  exit 1
fi

exec "$ARBOR" "$@"
