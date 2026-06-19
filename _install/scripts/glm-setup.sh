#!/usr/bin/env bash
# glm-setup.sh — enable (or disable) the opt-in claude-glm launcher + GLM compression proxy.
#
#   enable  (default): render the launcher template with your z.ai key injected, create the isolated
#                      GLM config dir, and touch ~/.headroom/glm.enabled so the headroom supervisor
#                      also keeps the 8791 (-> z.ai) compression proxy alive.
#   disable          : remove the marker and the generated launcher. 8787 / normal `claude` untouched.
#
# The z.ai key is taken from $1, then $ZAI_API_KEY, then an interactive prompt (tty only). The key is
# NEVER echoed and is written ONLY to the generated launcher, which lives at a gitignored path.
#
# Usage: bash glm-setup.sh [enable|disable] [ZAI_API_KEY]
set -u
ACTION="${1:-enable}"
case "$ACTION" in enable|disable) ;; *) KEYARG="$ACTION"; ACTION="enable" ;; esac
KEYARG="${KEYARG:-${2:-}}"

BASE="$HOME/.headroom"
MARKER="$BASE/glm.enabled"
CFGDIR="$HOME/.claude-glm-config"

# Resolve template dir (installed alongside scripts under ~/.claude/templates; repo fallback).
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
TPL_DIR="$SELF_DIR/../templates"
[ -d "$TPL_DIR" ] || TPL_DIR="$HOME/.claude/templates"

case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) OS=windows ;;
  Darwin) OS=mac ;;
  *) OS=linux ;;
esac

if [ "$OS" = windows ]; then
  TPL="$TPL_DIR/claude-glm.cmd.template"
  OUT="$HOME/AppData/Roaming/npm/claude-glm.cmd"
else
  TPL="$TPL_DIR/claude-glm.template.sh"
  OUT="$HOME/.local/bin/claude-glm"
fi

if [ "$ACTION" = "disable" ]; then
  rm -f "$MARKER" 2>/dev/null || true
  rm -f "$OUT" 2>/dev/null || true
  echo "[glm] disabled. Removed marker + generated launcher. 8787 / normal claude untouched."
  exit 0
fi

# ---------- enable ----------
[ -f "$TPL" ] || { echo "[glm] template not found ($TPL); cannot render launcher."; exit 1; }

KEY="$KEYARG"
[ -n "$KEY" ] || KEY="${ZAI_API_KEY:-}"
if [ -z "$KEY" ]; then
  if [ -t 0 ]; then
    printf '[glm] enter your z.ai API key (id.secret): '
    read -r KEY
  fi
fi
if [ -z "$KEY" ]; then
  echo "[glm] no z.ai key provided (arg / \$ZAI_API_KEY / prompt all empty); skipping. 8787 untouched."
  exit 0
fi

mkdir -p "$CFGDIR" "$(dirname "$OUT")" "$BASE" 2>/dev/null || true

# Render: substitute the placeholder with the key WITHOUT shelling the key through sed/eval.
TEMPLATE_CONTENT="$(cat "$TPL")"
RENDERED="${TEMPLATE_CONTENT//__ZAI_API_KEY__/$KEY}"
printf '%s\n' "$RENDERED" > "$OUT"
[ "$OS" = windows ] || chmod +x "$OUT" 2>/dev/null || true

# Put the isolated GLM config dir UNDER the harness: copy the hooks block + global CLAUDE.md so the
# same deterministic gates (pre-write/pre-flight/watcher/must-do/evidence) and protocol apply to
# claude-glm. We copy ONLY .hooks — never .env/auth — so the GLM routing (8791, z.ai token from the
# launcher) is untouched and the Anthropic 8787 redirect in user settings is NOT inherited.
SRC_SETTINGS="$HOME/.claude/settings.json"
SRC_CLAUDEMD="$HOME/.claude/CLAUDE.md"
if command -v jq >/dev/null 2>&1 && [ -f "$SRC_SETTINGS" ]; then
  [ -f "$CFGDIR/settings.json" ] || printf '{}' > "$CFGDIR/settings.json"
  _gtmp="$(mktemp)"
  if jq --slurpfile src "$SRC_SETTINGS" '.hooks = ($src[0].hooks // {})' "$CFGDIR/settings.json" > "$_gtmp" 2>/dev/null; then
    mv "$_gtmp" "$CFGDIR/settings.json"
    echo "[glm] harness hooks merged into $CFGDIR/settings.json (env/auth NOT copied)"
  else
    rm -f "$_gtmp" 2>/dev/null || true
    echo "[glm] WARN: could not merge harness hooks into GLM config (jq failed); GLM runs without gates."
  fi
else
  echo "[glm] note: jq or ~/.claude/settings.json absent; GLM config not placed under harness hooks."
fi
[ -f "$SRC_CLAUDEMD" ] && cp "$SRC_CLAUDEMD" "$CFGDIR/CLAUDE.md" 2>/dev/null \
  && echo "[glm] global CLAUDE.md copied into GLM config dir (harness protocol active for claude-glm)"

: > "$MARKER"   # touch the opt-in marker so the supervisor brings up 8791

echo "[glm] enabled."
echo "      launcher : $OUT   (gitignored; contains your z.ai key)"
echo "      config   : $CFGDIR (isolated; no claude.ai OAuth -> clean z.ai auth)"
echo "      marker   : $MARKER (supervisor will keep 8791 -> z.ai alive)"
echo "      Restart the headroom supervisor (or re-login) to bring up 8791, then run: claude-glm"
