#!/bin/bash
# install.sh — Restore the Enhanced Agent Harness from backup
# Run this script from the repo root: bash _install/install.sh
#
# What it does:
#   1. Copies hooks to ~/.claude/hooks/
#   2. Copies role prompts to ~/.claude/roles/
#   3. Copies scripts to ~/.claude/scripts/
#   4. Copies settings.json to ~/.claude/settings.json
#   5. Copies CLAUDE.md to ~/.claude/CLAUDE.md
#   6. Sets up ~/.openclaw/watchers/ with blank registry
#   7. Sets up ~/.openclaw/distractor-pool/ with MCQ distractors
#   8. Installs lavish-axi (HTML-artifact human feedback) + wires its SessionStart hook
#   9. Installs headroom (token-compression wrapper) into an ISOLATED uv-managed Python 3.10
#      venv at ~/.claude/headroom-venv — system Python and other installs are never touched.
#  10. Installs Arbor (autonomous research-agent CLI) into an ISOLATED uv-managed Python venv
#      at ~/.claude/arbor-venv — system Python untouched. Opt-in run (never auto-runs).
#
# Skills bundled in _install/skills/ (e.g. lavish-review, last30days, arbor-agent-*) are copied
# to ~/.claude/skills/ during step 3 and are available to ALL agents/projects.
#
# Prerequisites: bash, jq  (node/npm optional — step 8 skipped if absent; uv optional — steps 9
#                & 10 skipped if absent. All skips are non-fatal; the harness installs normally.)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -W 2>/dev/null || pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -W 2>/dev/null || pwd)"

CLAUDE_DIR="$HOME/.claude"
OPENCLAW_DIR="$HOME/.openclaw"

# --- Hard prerequisite: jq (every gate/hook parses JSON with it) ---
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found." >&2
  echo "  Install it first:  Debian/Ubuntu: sudo apt-get install jq | Fedora: sudo dnf install jq" >&2
  echo "                     macOS: brew install jq | Windows (Git Bash): winget install jqlang.jq" >&2
  exit 1
fi
LAVISH_VERSION="0.1.20"
HEADROOM_VENV="$CLAUDE_DIR/headroom-venv"   # ISOLATED Python 3.10 venv just for headroom
HEADROOM_PYTHON="3.10"
ARBOR_VENV="$CLAUDE_DIR/arbor-venv"         # ISOLATED Python venv just for Arbor CLI
ARBOR_PYTHON="3.10"
ARBOR_REPO="git+https://github.com/RUC-NLPIR/Arbor.git"

echo "=== Enhanced Agent Harness Installer ==="
echo "Source:  $SCRIPT_DIR"
echo "Target:  $CLAUDE_DIR"
echo ""

# --- Step 1: Create directories ---
echo "[1/11] Creating directories..."
mkdir -p "$CLAUDE_DIR/hooks"
mkdir -p "$CLAUDE_DIR/scripts"
mkdir -p "$CLAUDE_DIR/roles"
mkdir -p "$OPENCLAW_DIR/watchers"
mkdir -p "$OPENCLAW_DIR/distractor-pool"

# --- Step 2: Copy hooks ---
echo "[2/11] Installing hooks..."
cp "$SCRIPT_DIR/hooks/"* "$CLAUDE_DIR/hooks/"
chmod +x "$CLAUDE_DIR/hooks/"*
echo "  -> $(ls "$SCRIPT_DIR/hooks/" | wc -l) hooks installed"

# --- Step 3: Copy role prompts ---
echo "[3/11] Installing role prompts..."
cp "$SCRIPT_DIR/roles/"* "$CLAUDE_DIR/roles/"
echo "  -> $(ls "$SCRIPT_DIR/roles/" | wc -l) roles installed"

# Copy skills (slash-command skills available to ALL agents/projects), if shipped
if [ -d "$SCRIPT_DIR/skills" ]; then
  mkdir -p "$CLAUDE_DIR/skills"
  cp -r "$SCRIPT_DIR/skills/"* "$CLAUDE_DIR/skills/"
  chmod +x "$CLAUDE_DIR/skills/"*/*.sh 2>/dev/null || true
  echo "  -> $(ls "$SCRIPT_DIR/skills/" | wc -l) skill(s) installed"
fi

# --- Step 4: Copy scripts ---
echo "[4/11] Installing scripts..."
cp "$SCRIPT_DIR/scripts/"* "$CLAUDE_DIR/scripts/"
chmod +x "$CLAUDE_DIR/scripts/"*
echo "  -> $(ls "$SCRIPT_DIR/scripts/" | wc -l) scripts installed"

# Copy launcher templates (used by the opt-in GLM step), if shipped.
if [ -d "$SCRIPT_DIR/templates" ]; then
  mkdir -p "$CLAUDE_DIR/templates"
  cp "$SCRIPT_DIR/templates/"* "$CLAUDE_DIR/templates/" 2>/dev/null || true
  echo "  -> $(ls "$SCRIPT_DIR/templates/" 2>/dev/null | wc -l) template(s) installed"
fi

# --- Step 5: Copy settings.json ---
echo "[5/11] Installing settings.json..."
if [ -f "$CLAUDE_DIR/settings.json" ]; then
  BACKUP="$CLAUDE_DIR/settings.json.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$CLAUDE_DIR/settings.json" "$BACKUP"
  echo "  -> Existing settings backed up to $BACKUP"
fi
cp "$SCRIPT_DIR/settings.json" "$CLAUDE_DIR/settings.json"

# --- Step 6: Copy CLAUDE.md ---
echo "[6/11] Installing global CLAUDE.md..."
if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
  BACKUP="$CLAUDE_DIR/CLAUDE.md.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$CLAUDE_DIR/CLAUDE.md" "$BACKUP"
  echo "  -> Existing CLAUDE.md backed up to $BACKUP"
fi
cp "$SCRIPT_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"

# Deploy the canonical must-do system guide (referenced by CLAUDE.md startup pointers)
if [ -f "$SCRIPT_DIR/MUST-DO-SYSTEM.md" ]; then
  cp "$SCRIPT_DIR/MUST-DO-SYSTEM.md" "$CLAUDE_DIR/MUST-DO-SYSTEM.md"
  echo "  -> Installed MUST-DO-SYSTEM.md"
fi

# --- Step 7: Set up openclaw infrastructure ---
echo "[7/11] Installing openclaw infrastructure..."
cp "$SCRIPT_DIR/openclaw/distractor-pool/"* "$OPENCLAW_DIR/distractor-pool/" 2>/dev/null || true

# Create blank watcher registry if none exists (v3 per-project pool: max_per_project=5)
if [ ! -f "$OPENCLAW_DIR/watchers/REGISTRY.json" ]; then
  cat > "$OPENCLAW_DIR/watchers/REGISTRY.json" <<'REGISTRY'
{
  "version": "3.0.0",
  "max_per_project": 5,
  "watchers": []
}
REGISTRY
  echo "  -> Fresh watcher registry created (per-project pool, 5/project)"
else
  echo "  -> Watcher registry already exists, preserving"
fi

# Create blank slot files if missing
for i in 1 2 3 4 5; do
  if [ ! -f "$OPENCLAW_DIR/watchers/slot-${i}.md" ]; then
    printf "# Watcher Slot %d\n\n**Status**: available\n" "$i" > "$OPENCLAW_DIR/watchers/slot-${i}.md"
  fi
done

# --- Step 8: Install the BUNDLED lavish-axi (HTML-artifact feedback) ---
# lavish-axi ships VENDORED inside this pack (_install/vendor/lavish-axi-<ver>.tgz) with all its
# dependencies bundled, so it installs fully OFFLINE — no npm registry needed. The always-on
# SessionStart ambient-context hook is baked (portably, no machine-specific path) into settings.json,
# which step 5 already copied to ~/.claude/settings.json. If node/npm is absent this step is skipped
# with a warning and the harness installs normally; the baked SessionStart command no-ops (via
# `command -v lavish-axi`) until lavish is present.
echo "[8/11] Installing bundled lavish-axi (HTML-artifact feedback)..."
LAVISH_TGZ="$SCRIPT_DIR/vendor/lavish-axi-${LAVISH_VERSION}.tgz"
if command -v npm >/dev/null 2>&1; then
  if [ -f "$LAVISH_TGZ" ]; then
    if npm install -g "$LAVISH_TGZ" --offline --ignore-scripts >/dev/null 2>&1 \
       || npm install -g "$LAVISH_TGZ" --ignore-scripts >/dev/null 2>&1; then
      echo "  -> lavish-axi@${LAVISH_VERSION} installed from bundled vendor/ (offline)"
    else
      echo "  -> WARN: bundled install failed; trying npm registry..."
      if npm install -g "lavish-axi@${LAVISH_VERSION}" >/dev/null 2>&1; then
        echo "  -> lavish-axi@${LAVISH_VERSION} installed from npm registry"
      else
        echo "  -> WARN: lavish-axi install failed. Harness unaffected; SessionStart hook no-ops."
      fi
    fi
  else
    echo "  -> vendor bundle missing; installing lavish-axi@${LAVISH_VERSION} from npm registry..."
    if npm install -g "lavish-axi@${LAVISH_VERSION}" >/dev/null 2>&1; then
      echo "  -> lavish-axi@${LAVISH_VERSION} installed from npm registry"
    else
      echo "  -> WARN: lavish-axi install failed. Harness unaffected; SessionStart hook no-ops."
    fi
  fi
else
  echo "  -> SKIP: node/npm not found. lavish-axi not installed (optional). Harness unaffected."
fi

# --- Step 9: Install headroom (token-compression wrapper) into an ISOLATED uv venv ---
# headroom needs Python 3.10+. To guarantee that floor WITHOUT touching the system Python or any
# other Python install on this machine, it gets its OWN standalone interpreter + packages, managed
# by `uv` and confined to ~/.claude/headroom-venv. Nothing lands in system site-packages or PATH.
# Uninstall == delete that folder. Everything here is GUARDED: if uv is absent, or the network /
# build fails, this step SKIPs with a warning and the harness installs normally (set -e safe — every
# fallible command is the condition of an `if`). The transparent wrapper is invoked later, opt-in,
# via the `claude-hr` launcher (installed in step 4) which runs `headroom wrap claude`.
echo "[9/11] headroom (isolated token-compression venv + always-on)..."
# Installs the FIXED headroom (2026-06-14): isolated uv venv, agent-90 profile, HEADROOM_RUST_DETECT=0
# (the fix that stopped compression hanging), a supervisor watchdog that keeps the proxy alive across
# reboots, and a HEALTH-GATED global redirect.
#
# DEFAULTS: install ON (set HEADROOM_INSTALL=0 to skip) and always-on ON (set HEADROOM_ALWAYSON=0 to
# install the venv but stay opt-in via claude-hr.sh).
#
# SAFETY (the 2026-06-13 incident lesson): the always-on step writes ANTHROPIC_BASE_URL into
# settings.json ONLY AFTER the proxy answers /livez (see headroom-alwayson.sh). If uv/network/the
# proxy isn't healthy, the redirect is NOT set — Claude keeps talking to Anthropic directly and no
# session is ever bricked. The shipped settings.json never contains the redirect for this reason.
if [ "${HEADROOM_INSTALL:-1}" != "1" ]; then
  echo "  -> SKIP: headroom install disabled (HEADROOM_INSTALL=0). Harness unaffected."
elif command -v uv >/dev/null 2>&1; then
  if uv venv --python "$HEADROOM_PYTHON" "$HEADROOM_VENV" >/dev/null 2>&1 \
     && uv pip install --python "$HEADROOM_VENV" "headroom-ai[all]" >/dev/null 2>&1; then
    echo "  -> headroom installed into isolated venv: $HEADROOM_VENV (Python $HEADROOM_PYTHON)"
    if [ "${HEADROOM_ALWAYSON:-1}" = "1" ]; then
      # health-gated: sets the global redirect only if the proxy comes up healthy
      bash "$CLAUDE_DIR/scripts/headroom-alwayson.sh" enable || \
        echo "  -> WARN: always-on enable returned non-zero; redirect left unset (safe). Use claude-hr.sh."
    else
      echo "     Always-on skipped (HEADROOM_ALWAYSON=0). Opt-in: bash ~/.claude/scripts/claude-hr.sh"
    fi
  else
    echo "  -> WARN: headroom venv/install failed (network/build?). Trimming partial venv."
    rm -rf "$HEADROOM_VENV" 2>/dev/null || true
    echo "     Harness unaffected; no redirect set, no proxy. Re-run installer to retry."
  fi
else
  echo "  -> SKIP: 'uv' not found. headroom not installed. Harness unaffected (no redirect set)."
  echo "     To enable later: install uv (https://docs.astral.sh/uv/) then re-run this installer."
fi

# --- Step 10: Install Arbor (autonomous research-agent CLI) into an ISOLATED uv venv ---
# Arbor (https://github.com/RUC-NLPIR/Arbor, Apache-2.0) needs Python >=3.10 + Git. Like headroom it
# gets its OWN isolated uv-managed venv at ~/.claude/arbor-venv (system Python untouched). The 11
# arbor-agent-* Claude Code skills are already installed via step 3 (bundled in _install/skills/).
# DEFAULT: install ON (ARBOR_INSTALL=0 to skip). Auto-configure scaffolds a default ~/.arbor/config.yaml
# (provider=anthropic) if absent and runs `arbor doctor` — but does NOT fabricate API keys; add your
# key with `bash ~/.claude/scripts/arbor.sh setup`. Arbor is AUTONOMOUS (edits code in worktrees,
# spends LLM money) and NEVER auto-runs — it only runs when you launch arbor.sh. GUARDED + set -e safe.
echo "[10/11] Arbor (isolated autonomous research-agent CLI)..."
if [ "${ARBOR_INSTALL:-1}" != "1" ]; then
  echo "  -> SKIP: Arbor install disabled (ARBOR_INSTALL=0). Skills still available; harness unaffected."
elif command -v uv >/dev/null 2>&1 && command -v git >/dev/null 2>&1; then
  if uv venv --python "$ARBOR_PYTHON" "$ARBOR_VENV" >/dev/null 2>&1 \
     && uv pip install --python "$ARBOR_VENV" "$ARBOR_REPO" >/dev/null 2>&1; then
    echo "  -> Arbor installed into isolated venv: $ARBOR_VENV (Python $ARBOR_PYTHON)"
    # auto-configure: scaffold a default config if none exists (no API key fabricated)
    if [ ! -f "$HOME/.arbor/config.yaml" ]; then
      mkdir -p "$HOME/.arbor"
      cat > "$HOME/.arbor/config.yaml" <<'ARBORCFG'
# Arbor config scaffold (created by the harness installer). Add your API key, then run:
#   bash ~/.claude/scripts/arbor.sh doctor
provider: anthropic
model: claude-opus-4-8
# api_key: "sk-ant-..."   # or set ANTHROPIC_API_KEY in your environment
ARBORCFG
      echo "     Scaffolded ~/.arbor/config.yaml (add your API key)."
    fi
    bash "$CLAUDE_DIR/scripts/arbor.sh" doctor >/dev/null 2>&1 \
      && echo "     arbor doctor: OK" \
      || echo "     arbor doctor: needs config (add API key via: bash ~/.claude/scripts/arbor.sh setup)"
    echo "     Run Arbor with: bash ~/.claude/scripts/arbor.sh   (autonomous; never auto-runs)"
  else
    echo "  -> WARN: Arbor venv/install failed (network/build/git?). Trimming partial venv."
    rm -rf "$ARBOR_VENV" 2>/dev/null || true
    echo "     Harness unaffected; arbor-agent skills still installed. Re-run installer to retry."
  fi
else
  echo "  -> SKIP: 'uv' and/or 'git' not found. Arbor CLI not installed (skills still available)."
  echo "     To enable later: install uv + git, then re-run this installer."
fi

# --- Step 11: GLM launcher (claude-glm via z.ai through headroom 8791) — OPT-IN, secret-safe ---
# Packages the proven claude-glm fix: a dedicated CLAUDE_CONFIG_DIR (no OAuth hijack) + the official
# z.ai ANTHROPIC_AUTH_TOKEN method, routed through the headroom 8791 compression proxy, pinned glm-5.1.
#
# OPT-IN: runs ONLY when a z.ai key is provided (env ZAI_API_KEY). With no key, this step SKIPs and the
# install path is identical to before (single 8787 proxy; normal `claude` untouched). The dual-proxy
# supervisor only brings up 8791 when glm-setup.sh has written ~/.headroom/glm.enabled, so shipping the
# updated supervisor is itself a no-op until GLM is enabled. The z.ai key is NEVER written to a tracked
# file — only to the gitignored generated launcher. Set GLM_INSTALL=0 to skip entirely. set -e safe.
echo "[11/11] GLM launcher (claude-glm, opt-in)..."
if [ "${GLM_INSTALL:-1}" = "1" ]; then
  if [ -n "${ZAI_API_KEY:-}" ]; then
    if bash "$CLAUDE_DIR/scripts/glm-setup.sh" enable "$ZAI_API_KEY"; then
      echo "  -> claude-glm enabled (key injected into gitignored launcher; marker set)."
    else
      echo "  -> WARN: glm-setup returned non-zero; GLM not enabled. Normal claude unaffected."
    fi
  else
    echo "  -> SKIP: no ZAI_API_KEY in env. GLM stays off (zero change to normal claude/8787)."
    echo "     Enable later: ZAI_API_KEY=<id.secret> bash ~/.claude/scripts/glm-setup.sh enable"
  fi
else
  echo "  -> SKIP: GLM_INSTALL=0. Enable later: bash ~/.claude/scripts/glm-setup.sh enable"
fi

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Installed:"
echo "  Hooks:      $CLAUDE_DIR/hooks/ ($(ls "$CLAUDE_DIR/hooks/" | wc -l) files)"
echo "  Roles:      $CLAUDE_DIR/roles/ ($(ls "$CLAUDE_DIR/roles/" | wc -l) files)"
echo "  Scripts:    $CLAUDE_DIR/scripts/ ($(ls "$CLAUDE_DIR/scripts/" | wc -l) files)"
echo "  Settings:   $CLAUDE_DIR/settings.json"
echo "  CLAUDE.md:  $CLAUDE_DIR/CLAUDE.md"
echo "  Watchers:   $OPENCLAW_DIR/watchers/"
echo "  Distractors:$OPENCLAW_DIR/distractor-pool/"
echo "  lavish-axi: $(command -v lavish-axi >/dev/null 2>&1 && echo "installed ($(lavish-axi --version 2>/dev/null))" || echo "not installed (optional)")"
echo "  headroom:   $([ -x "$HEADROOM_VENV/Scripts/headroom" ] || [ -x "$HEADROOM_VENV/bin/headroom" ] && echo "installed (isolated venv: $HEADROOM_VENV)" || echo "not installed (optional)")"
echo "  arbor:      $([ -x "$ARBOR_VENV/Scripts/arbor.exe" ] || [ -x "$ARBOR_VENV/bin/arbor" ] && echo "installed (isolated venv: $ARBOR_VENV)" || echo "not installed (optional)") + 11 arbor-agent skills"
echo "  claude-glm: $([ -f "$HOME/.headroom/glm.enabled" ] && echo "enabled (8791 -> z.ai, glm-5.1, isolated config)" || echo "off (opt-in: ZAI_API_KEY=... bash ~/.claude/scripts/glm-setup.sh enable)")"
echo ""
echo "To initialize a new project, run from the project directory:"
echo "  bash ~/.claude/scripts/init-project.sh"
