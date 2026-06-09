---
name: lavish-review
description: Get human feedback on an HTML artifact you produced. Opens the artifact in lavish-axi's local browser editor where the human annotates elements, selects text, and types feedback; blocks until they respond, then returns their feedback. Use after writing/updating an HTML file the human should review.
---

# lavish-review — human feedback on HTML artifacts

lavish-axi closes the human↔agent loop on rich HTML. You write an HTML artifact; the human opens it
in a local browser editor, annotates elements / selects text / types feedback; you receive that
feedback and iterate. Everything is local — no cloud.

## When to use
- **Planning / mockups (preferred):** during the PLAN phase, when the thing being designed has a
  visual, UI, layout, or document dimension, build a quick HTML **mock** of the proposed result and
  open it in lavish so the human reviews and marks it up BEFORE the spec is finalized or any code is
  written. This is faster and clearer for them than reading long markdown to imagine the outcome.
- **Artifact review:** you generated or updated an `.html` artifact (report, dashboard, document) and
  want the human to review it visually and annotate it, rather than describe changes in chat.

## How to use it (the harness way)
Run the wrapper — it pauses your 3-minute watcher cron during the (blocking) wait so the harness does
not flag the pause as drift, then resumes:

```bash
bash ~/.claude/skills/lavish-review/lavish-review.sh path/to/artifact.html
```

It prints the human's feedback to stdout. After you make changes, you can poll again and show what you
did:

```bash
bash ~/.claude/skills/lavish-review/lavish-review.sh path/to/artifact.html --agent-reply "Updated the heading and chart colors"
```

## Notes
- lavish-axi keeps its primary state in `~/.lavish-axi/` (server log + sessions), and may write a
  `.lavish-axi/` folder in the workspace for artifact assets. The workspace `.lavish-axi/` path is
  exempt from the harness gates, so it won't trigger pre-flight/watcher blocks. (lavish's own server
  process writes state directly, outside Claude's tool hooks, so it is never gated regardless.)
- Sessions are keyed by the HTML file path (no opaque IDs). Re-running with the same file resumes.
- If lavish-axi is not installed: `npm install -g lavish-axi`. The harness installer (`_install/install.sh`)
  installs it automatically when Node/npm are present.
- Direct CLI (advanced): `lavish-axi <file>` open/resume · `lavish-axi poll <file>` wait for feedback ·
  `lavish-axi end <file>` close · `lavish-axi stop` shut down the server.

## Environment
- `LAVISH_POLL_PAUSE_MIN` — minutes to pause the watcher cron during a poll (default 60).
- `HARNESS_SKIP_CRON=1` — skip the cron pause/resume (non-harness or test contexts).
