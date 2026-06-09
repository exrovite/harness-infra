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
#
# Prerequisites: bash, jq  (node/npm optional — step 8 is skipped with a warning if absent)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -W 2>/dev/null || pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -W 2>/dev/null || pwd)"

CLAUDE_DIR="$HOME/.claude"
OPENCLAW_DIR="$HOME/.openclaw"
LAVISH_VERSION="0.1.20"

echo "=== Enhanced Agent Harness Installer ==="
echo "Source:  $SCRIPT_DIR"
echo "Target:  $CLAUDE_DIR"
echo ""

# --- Step 1: Create directories ---
echo "[1/8] Creating directories..."
mkdir -p "$CLAUDE_DIR/hooks"
mkdir -p "$CLAUDE_DIR/scripts"
mkdir -p "$CLAUDE_DIR/roles"
mkdir -p "$OPENCLAW_DIR/watchers"
mkdir -p "$OPENCLAW_DIR/distractor-pool"

# --- Step 2: Copy hooks ---
echo "[2/8] Installing hooks..."
cp "$SCRIPT_DIR/hooks/"* "$CLAUDE_DIR/hooks/"
chmod +x "$CLAUDE_DIR/hooks/"*
echo "  -> $(ls "$SCRIPT_DIR/hooks/" | wc -l) hooks installed"

# --- Step 3: Copy role prompts ---
echo "[3/8] Installing role prompts..."
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
echo "[4/8] Installing scripts..."
cp "$SCRIPT_DIR/scripts/"* "$CLAUDE_DIR/scripts/"
chmod +x "$CLAUDE_DIR/scripts/"*
echo "  -> $(ls "$SCRIPT_DIR/scripts/" | wc -l) scripts installed"

# --- Step 5: Copy settings.json ---
echo "[5/8] Installing settings.json..."
if [ -f "$CLAUDE_DIR/settings.json" ]; then
  BACKUP="$CLAUDE_DIR/settings.json.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$CLAUDE_DIR/settings.json" "$BACKUP"
  echo "  -> Existing settings backed up to $BACKUP"
fi
cp "$SCRIPT_DIR/settings.json" "$CLAUDE_DIR/settings.json"

# --- Step 6: Copy CLAUDE.md ---
echo "[6/8] Installing global CLAUDE.md..."
if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
  BACKUP="$CLAUDE_DIR/CLAUDE.md.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$CLAUDE_DIR/CLAUDE.md" "$BACKUP"
  echo "  -> Existing CLAUDE.md backed up to $BACKUP"
fi
cp "$SCRIPT_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"

# --- Step 7: Set up openclaw infrastructure ---
echo "[7/8] Installing openclaw infrastructure..."
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
echo "[8/8] Installing bundled lavish-axi (HTML-artifact feedback)..."
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
echo ""
echo "To initialize a new project, run from the project directory:"
echo "  bash ~/.claude/scripts/init-project.sh"
