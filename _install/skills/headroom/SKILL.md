---
name: headroom
description: "Reduce token usage / context size for Claude Code sessions and for one-off blobs. Use when a session is burning tokens fast, when you need to compress large tool output / logs / files before reading them, or when the user asks to make sessions last longer or cut context cost. headroom runs in an isolated Python 3.10 venv and never touches the system Python."
allowed-tools: Bash, Read
user-invocable: true
metadata:
  emoji: "🗜️"
  requires:
    bins: []
---

# headroom — token-compression for Claude Code

headroom (https://github.com/chopratejas/headroom, token-compression toolkit) is installed by the
harness into an **isolated** uv-managed Python 3.10 venv at `~/.claude/headroom-venv`. It never uses
or modifies the system Python or any other Python install. If it isn't installed, every command below
fails gracefully — the harness is unaffected.

## Two ways to use it

### 1. Transparent session compression (the main use)
Launch Claude Code through the wrapper instead of plain `claude`:

```bash
bash ~/.claude/scripts/claude-hr.sh          # = headroom wrap claude
bash ~/.claude/scripts/claude-hr.sh -- --model opus   # pass args to claude
```

This starts a local headroom proxy, points `ANTHROPIC_BASE_URL` at it, and launches `claude` so all
model traffic is compressed before it leaves the machine — typically large token savings on long
sessions with big tool outputs. It is **opt-in** (you must launch via the wrapper); it does not change
how a normal `claude` session runs.

### 2. One-off compression of a blob / file
When you just need to shrink something before reading or passing it on, call the venv's headroom CLI
directly. Resolve the entrypoint first (Windows vs Unix):

```bash
HR="$HOME/.claude/headroom-venv/bin/headroom"
[ -x "$HR" ] || HR="$HOME/.claude/headroom-venv/Scripts/headroom"
"$HR" --help        # discover the available compress/stats subcommands for the installed version
```

## When to reach for this
- A session is consuming context fast and the user wants it to "last longer".
- You're about to read a huge log / JSON / file and only need its substance.
- The user explicitly asks to reduce token usage or cost.

## Notes
- Compression is reversible (headroom caches originals locally), so detail can be retrieved if needed.
- If `~/.claude/headroom-venv` is missing, re-run `bash _install/install.sh` (step 9) or install
  manually: `uv venv --python 3.10 ~/.claude/headroom-venv && uv pip install --python ~/.claude/headroom-venv "headroom-ai[all]"`.
