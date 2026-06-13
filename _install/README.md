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
| Scripts | `~/.claude/scripts/` | 29 |
| Skills | `~/.claude/skills/` | lavish-review, headroom, last30days |
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

## Bundled tools

### lavish-axi (HTML-artifact human feedback)

[**lavish-axi**](https://github.com/kunchenguid/lavish-axi) (pinned `0.1.20`) ships **vendored inside
this pack** at `_install/vendor/lavish-axi-0.1.20.tgz` — a self-contained bundle (all dependencies
included) that installs **fully offline**, no npm registry needed. The installer puts it on the global
PATH and the always-on `SessionStart` ambient-context hook is **baked portably** into `settings.json`
(the command is just `lavish-axi`, no machine-specific path), so it works on any machine.

It gives agents a human↔agent feedback loop on HTML artifacts: the agent writes an `.html` file, the
human annotates it in a local browser editor, and the agent receives that feedback. **Preferred use:
visual mockups during PLAN** — see a proposed UI/layout before any code is written. Drive it through
the `lavish-review` skill (`~/.claude/skills/lavish-review/`). Requires Node/npm to install; if absent,
the step is skipped with a warning, the rest of the harness installs normally, and the baked
`SessionStart` command safely no-ops until lavish is present.

### headroom (token-compression wrapper)

[**headroom**](https://github.com/chopratejas/headroom) reduces token usage by compressing context
(tool output, logs, files, conversation history) before it reaches the model — so sessions last
longer and cost less. Because it needs Python 3.10+, the installer puts it in an **isolated,
uv-managed Python 3.10 venv** at `~/.claude/headroom-venv` — its own standalone interpreter and
packages, **never** the system Python and never any other Python install on the machine. Uninstall is
just `rm -rf ~/.claude/headroom-venv`.

> **DISABLED BY DEFAULT (2026-06-13).** headroom is **not installed** by `install.sh` unless you opt
> in with `HEADROOM_INSTALL=1 bash _install/install.sh`. Its compression layer is not yet verified, so
> it stays off across servers until fixed. Even when enabled, the install is **isolated and opt-in
> only**: it NEVER sets `ANTHROPIC_BASE_URL`, never starts a proxy, and never installs a
> service/scheduled task. Compression happens only when you explicitly run `claude-hr.sh`. (The
> always-on/global setup tried during development is **not** part of this pack and must never be.)

Use it the **transparent** way by launching Claude Code through the bundled wrapper instead of plain
`claude`:

```bash
bash ~/.claude/scripts/claude-hr.sh          # = headroom wrap claude (compressed session)
```

This starts a local headroom proxy, points `ANTHROPIC_BASE_URL` at it, and launches `claude`. It is
**opt-in** — a normal `claude` session is unchanged. Agents can also call the venv's `headroom` CLI
directly to compress a single blob/file (see the `headroom` skill). Requires `uv` to install; if
absent (or the network/build fails), step 9 is skipped with a warning, the partial venv is removed,
and the rest of the harness installs normally. The `claude-hr` launcher falls back to plain `claude`
when headroom isn't present, so you are never blocked.

### last30days (engagement-ranked research skill)

[**last30days**](https://github.com/mvanhorn/last30days-skill) is a Claude Code skill (vendored at
`_install/skills/last30days/`, installed to `~/.claude/skills/`) that researches any topic across
Reddit, X, YouTube, TikTok, Hacker News, Polymarket, GitHub, and the web — ranking results by **real
engagement** (upvotes, likes, money) rather than editorial signals. Useful for finding what an
audience actually cares about and who is most likely to engage with or buy a piece of content. Invoke
it as `/last30days <topic>`. It works with zero config for several sources (Reddit, HN, Polymarket,
GitHub) and unlocks more via optional API keys (see the skill's `CONFIGURATION.md`/`SKILL.md`); it
needs `python3`/`node` (already required by the harness) and degrades gracefully without keys. The
14MB demo assets from upstream are intentionally **not** bundled to keep the pack lean.

#### Third-party notices

This product bundles / installs the following third-party software. License texts are retained under
[`_install/LICENSES/`](LICENSES/):

- **lavish-axi** — MIT © Kun Chen — `_install/LICENSES/lavish-axi-LICENSE`
- **axi-sdk-js** — MIT © kunchenguid — `_install/LICENSES/axi-sdk-js-LICENSE`
- **last30days** — MIT © Matt Van Horn — `_install/LICENSES/last30days-LICENSE` (skill vendored in-tree)
- **headroom** — Apache-2.0 © headroom authors — `_install/LICENSES/headroom-LICENSE` (installed from PyPI into an isolated venv, not vendored in-tree)
