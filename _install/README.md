# Enhanced Agent Harness — Installer

Deterministic enforcement layer for Claude Code. Installs hooks, scripts, role prompts, and infrastructure that keep AI agents on task via hard gates — not soft instructions.

## Prerequisites

- **bash** (Linux native, or Git Bash on Windows)
- **jq** (JSON processor)
- **Claude Code CLI** installed and authenticated

### Install jq

```bash
# Ubuntu/Debian
sudo apt install jq

# macOS
brew install jq

# Windows (Git Bash) — download from https://jqlang.github.io/jq/download/
```

## Install

```bash
git clone <repo-url> harness-infra
cd harness-infra
bash _install/install.sh
```

This installs to `~/.claude/` and `~/.openclaw/`:

| Component | Location | Count |
|-----------|----------|-------|
| Hooks | `~/.claude/hooks/` | 12 |
| Role prompts | `~/.claude/roles/` | 5 |
| Scripts | `~/.claude/scripts/` | 28 |
| Settings | `~/.claude/settings.json` | 1 |
| Global protocol | `~/.claude/CLAUDE.md` | 1 |
| Watcher slots | `~/.openclaw/watchers/` | 5 |
| Distractor pool | `~/.openclaw/distractor-pool/` | 4 |

Existing `settings.json` and `CLAUDE.md` are backed up with timestamps before overwriting.

## Initialize a project

After installing, run from any project directory:

```bash
bash ~/.claude/scripts/init-project.sh
```

This creates the `.claude/state/`, `.claude/contracts/`, `.claude/specs/` directories and initial state files that the harness needs.

## What it enforces

- **Phase state machine**: PLAN → NEGOTIATE → BUILD → EVALUATE → COMPLETE (no skipping)
- **Pre-flight MCQ gate**: Agent must prove it knows its task before writing code
- **Contract gate**: Sprint contract required before BUILD phase
- **Must-do reference gate**: Forces agent to read designated files before coding
- **Evidence checkpoints**: Periodic independent verification of agent work
- **Watcher system**: 3-minute recurring reminders keep agents on task
- **Bash bypass prevention**: Catches file writes via `python -c`, `tee`, heredocs
- **Loop detection**: Detects and breaks strategy loops and repeated failures
- **Builder/verifier separation**: Agent cannot self-certify — independent sub-agent verifies

## Platform support

- **Windows** (Git Bash / MSYS2)
- **Linux** (Ubuntu, Debian, RHEL, Alpine with bash)
- **macOS** (with GNU coreutils recommended)

All scripts use portable patterns with proper fallbacks for platform differences.
