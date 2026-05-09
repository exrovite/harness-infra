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
#
# Prerequisites: bash, jq

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -W 2>/dev/null || pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -W 2>/dev/null || pwd)"

CLAUDE_DIR="$HOME/.claude"
OPENCLAW_DIR="$HOME/.openclaw"

echo "=== Enhanced Agent Harness Installer ==="
echo "Source:  $SCRIPT_DIR"
echo "Target:  $CLAUDE_DIR"
echo ""

# --- Step 1: Create directories ---
echo "[1/7] Creating directories..."
mkdir -p "$CLAUDE_DIR/hooks"
mkdir -p "$CLAUDE_DIR/scripts"
mkdir -p "$CLAUDE_DIR/roles"
mkdir -p "$OPENCLAW_DIR/watchers"
mkdir -p "$OPENCLAW_DIR/distractor-pool"

# --- Step 2: Copy hooks ---
echo "[2/7] Installing hooks..."
cp "$SCRIPT_DIR/hooks/"* "$CLAUDE_DIR/hooks/"
chmod +x "$CLAUDE_DIR/hooks/"*
echo "  -> $(ls "$SCRIPT_DIR/hooks/" | wc -l) hooks installed"

# --- Step 3: Copy role prompts ---
echo "[3/7] Installing role prompts..."
cp "$SCRIPT_DIR/roles/"* "$CLAUDE_DIR/roles/"
echo "  -> $(ls "$SCRIPT_DIR/roles/" | wc -l) roles installed"

# --- Step 4: Copy scripts ---
echo "[4/7] Installing scripts..."
cp "$SCRIPT_DIR/scripts/"* "$CLAUDE_DIR/scripts/"
chmod +x "$CLAUDE_DIR/scripts/"*
echo "  -> $(ls "$SCRIPT_DIR/scripts/" | wc -l) scripts installed"

# --- Step 5: Copy settings.json ---
echo "[5/7] Installing settings.json..."
if [ -f "$CLAUDE_DIR/settings.json" ]; then
  BACKUP="$CLAUDE_DIR/settings.json.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$CLAUDE_DIR/settings.json" "$BACKUP"
  echo "  -> Existing settings backed up to $BACKUP"
fi
cp "$SCRIPT_DIR/settings.json" "$CLAUDE_DIR/settings.json"

# --- Step 6: Copy CLAUDE.md ---
echo "[6/7] Installing global CLAUDE.md..."
if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
  BACKUP="$CLAUDE_DIR/CLAUDE.md.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$CLAUDE_DIR/CLAUDE.md" "$BACKUP"
  echo "  -> Existing CLAUDE.md backed up to $BACKUP"
fi
cp "$SCRIPT_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"

# --- Step 7: Set up openclaw infrastructure ---
echo "[7/7] Installing openclaw infrastructure..."
cp "$SCRIPT_DIR/openclaw/distractor-pool/"* "$OPENCLAW_DIR/distractor-pool/" 2>/dev/null || true

# Create blank watcher registry if none exists
if [ ! -f "$OPENCLAW_DIR/watchers/REGISTRY.json" ]; then
  cat > "$OPENCLAW_DIR/watchers/REGISTRY.json" <<'REGISTRY'
{
  "watchers": [
    {"slot": 1, "status": "available", "claimed_by": null, "claimed_at": null, "project": null, "cron_job_id": null, "cron_interval": null},
    {"slot": 2, "status": "available", "claimed_by": null, "claimed_at": null, "project": null, "cron_job_id": null, "cron_interval": null},
    {"slot": 3, "status": "available", "claimed_by": null, "claimed_at": null, "project": null, "cron_job_id": null, "cron_interval": null},
    {"slot": 4, "status": "available", "claimed_by": null, "claimed_at": null, "project": null, "cron_job_id": null, "cron_interval": null},
    {"slot": 5, "status": "available", "claimed_by": null, "claimed_at": null, "project": null, "cron_job_id": null, "cron_interval": null}
  ]
}
REGISTRY
  echo "  -> Fresh watcher registry created (5 slots)"
else
  echo "  -> Watcher registry already exists, preserving"
fi

# Create blank slot files if missing
for i in 1 2 3 4 5; do
  if [ ! -f "$OPENCLAW_DIR/watchers/slot-${i}.md" ]; then
    printf "# Watcher Slot %d\n\n**Status**: available\n" "$i" > "$OPENCLAW_DIR/watchers/slot-${i}.md"
  fi
done

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
echo ""
echo "To initialize a new project, run from the project directory:"
echo "  bash ~/.claude/scripts/init-project.sh"
