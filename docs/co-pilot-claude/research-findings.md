# Co-Pilot Claude — Technical Research Findings

**Date**: 2026-05-23
**Goal**: Build a system that monitors a running Claude Code session's output, detects when the agent is drifting from key instructions, and injects corrective prompts — automating what the human operator currently does manually.

---

## 1. The Problem

An agent working in Claude Code periodically forgets one or two specific instructions. Not all the time — just often enough to require constant human attention. The human watches the terminal stream in VS Code, spots the drift, types a correction ("you forgot to do X"), and the agent course-corrects.

This works but requires the human to babysit the terminal. The goal is to automate this "watchful human" role: a second process that reads the same output stream, pattern-matches against known drift behaviors, and injects corrective prompts through the CLI — exactly like the human would.

The key constraint: this is a **real-time stream watcher that intervenes mid-conversation**, not a gate or hook that fires at predefined lifecycle points.

---

## 2. Technical Feasibility: Can You Inject Into a Running Session?

### Short Answer: Not directly into the interactive TUI — but there are viable workarounds.

### 2.1 The Interactive TUI Limitation

Claude Code's interactive mode uses the [Ink](https://github.com/vadimdemedes/ink) React-based terminal UI library. Its text input component (`ink-text-input`) treats programmatic stdin differently from keyboard input:

- A **physical Enter keypress** triggers `onSubmit` and the prompt is processed
- A **programmatic `\r` or `\n`** sent via pipe/stdin is treated as a literal newline — the prompt is **NOT submitted**

This means you **cannot** pipe text into a running `claude` interactive session via stdin redirection or named pipes.

**Feature request**: [GitHub Issue #15553](https://github.com/anthropics/claude-code/issues/15553) — proposes `CLAUDE_ACCEPT_STDIN_SUBMIT=true` env var, `--accept-stdin` flag, or IPC mechanism. **Status: Open, not implemented (May 2026).**

### 2.2 What DOES Work

Four architecture patterns achieve the same outcome through different means. Each is detailed below.

---

## 3. Architecture Pattern A: Stream-JSON Persistent Session

### How It Works

Instead of the interactive TUI, run Claude Code in **headless mode** with bidirectional JSON streaming. This creates a persistent subprocess where stdin accepts JSON messages and stdout emits NDJSON events.

```bash
claude -p \
  --input-format stream-json \
  --output-format stream-json \
  --verbose \
  --include-partial-messages
```

**Input format** — one JSON line per user message on stdin:
```json
{"type": "user", "message": {"role": "user", "content": "Your correction here"}}
```

**Output** — NDJSON events on stdout (tool calls, text deltas, results, session metadata).

### Architecture

```
+----------------------------------------------------+
|  CO-PILOT CONTROLLER (Python/Node script)          |
|                                                    |
|  1. Spawns claude as subprocess with stream-json   |
|  2. Reads stdout NDJSON events in real-time        |
|  3. Pattern-matches against drift rules            |
|  4. When drift detected:                           |
|     -> Writes corrective JSON message to stdin     |
|     -> Agent receives it as next user turn          |
|     -> Agent course-corrects                        |
|                                                    |
|  Drift rules loaded from: rules.json               |
+----------------------------------------------------+
         | stdin (JSON lines)          | stdout (NDJSON events)
         v                             v
+----------------------------------------------------+
|  CLAUDE CODE (headless, stream-json mode)          |
|  Working on the actual task                        |
+----------------------------------------------------+
```

### Pros
- Full programmatic control over the conversation
- Multi-turn context preserved within one subprocess
- No TUI limitation — stdin is processed properly in headless mode
- Real-time event stream for monitoring (tool calls, text, results)
- Same tools, hooks, and context as interactive mode

### Cons
- `--input-format stream-json` is **largely undocumented** ([GitHub Issue #24594](https://github.com/anthropics/claude-code/issues/24594))
- Known stdout buffering bug when piped ([GitHub Issue #25670](https://github.com/anthropics/claude-code/issues/25670)) — may need `stdbuf -oL` workaround
- The user doesn't see a TUI — needs a custom dashboard or log viewer to watch
- Protocol reverse-engineered from Elixir SDK; Python/TypeScript equivalents require similar work

### Setup Complexity: Medium
Requires building a controller script (Python or Node) that manages the subprocess, parses NDJSON, and implements drift rule matching.

### Platform Support: Windows, Linux, macOS
Works everywhere Claude Code runs. On Windows, use `encoding="utf-8"` when spawning the subprocess.

---

## 4. Architecture Pattern B: tmux Monitor + Session Resume

### How It Works

Run the working Claude Code instance inside **tmux**. A separate monitor script captures terminal output via `pipe-pane` and, when drift is detected, attempts to inject corrections.

### Architecture

```
+--------------------------------------+
|  TMUX SESSION "claude-worker"        |
|  +------------------------------+   |
|  | claude (interactive TUI)     |   |
|  | Working on the actual task   |   |
|  +------------------------------+   |
|         | pipe-pane                  |
|         v                            |
|  /tmp/claude-output.log             |
+--------------------------------------+
         |
         v
+--------------------------------------+
|  MONITOR SCRIPT                      |
|  tail -f /tmp/claude-output.log      |
|  | pattern match against rules       |
|  | on drift:                         |
|     Option 1: tmux send-keys         |
|     Option 2: claude -p --continue   |
+--------------------------------------+
```

### Step-by-Step

```bash
# 1. Start Claude Code in a tmux session
tmux new-session -d -s worker "claude"

# 2. Pipe all terminal output to a log file
tmux pipe-pane -t worker "cat >> /tmp/claude-worker.log"

# 3. Monitor script watches the log in a separate terminal
tail -f /tmp/claude-worker.log | while IFS= read -r line; do
    if echo "$line" | grep -qF "DRIFT_PATTERN"; then
        # Option 1: Send keystrokes directly to the tmux pane
        tmux send-keys -t worker "STOP - you forgot to run tests. Do it now." Enter

        # Option 2: Use --continue to inject via separate process
        # claude -p "CORRECTION: You forgot to run tests" --continue
    fi
done
```

### Key tmux Commands

| Command | Purpose |
|---------|---------|
| `tmux new-session -d -s worker "claude"` | Start Claude in detached tmux session |
| `tmux pipe-pane -t worker "cat >> log"` | Stream all pane output to a file |
| `tmux capture-pane -t worker -p` | Screenshot current visible pane content |
| `tmux send-keys -t worker "text" Enter` | Inject keystrokes as if typed |
| `tmux attach -t worker` | Human attaches to watch/interact |

### Pros
- Uses standard tools (tmux, bash, grep) — no SDK needed
- Human can still `tmux attach` to watch and interact normally
- `tmux send-keys` is the closest equivalent to "typing into the terminal"
- Low setup complexity — bash script only

### Cons
- **Unknown**: whether `tmux send-keys` + Enter triggers Ink's `onSubmit` — this needs testing. If it doesn't work, `send-keys` won't submit the correction
- Fallback (`--continue` / `--resume`) may not inject into an actively-running session — it may start a parallel turn
- Pattern matching on raw terminal output is noisy (ANSI escape codes, partial lines, spinner characters)
- Requires tmux — native on Linux/macOS, needs WSL or similar on Windows

### Setup Complexity: Low
Just bash scripts and tmux. No SDK, no API, no custom framework.

### Platform Support: Linux and macOS native. Windows needs WSL.

---

## 5. Architecture Pattern C: Agent SDK Orchestrator

### How It Works

Use the **Claude Agent SDK** (Python or TypeScript) to build an orchestrator that runs the worker agent as a **subagent**. The orchestrator IS the co-pilot — it can inspect every tool call and text output, and inject corrections programmatically.

### Architecture (Python pseudocode)

```python
from claude_agent_sdk import Agent, Subagent

# Define drift rules
DRIFT_RULES = [
    {
        "pattern": "Edit called without subsequent test run",
        "correction": "Run tests before continuing"
    },
    {
        "pattern": "Skipped must-do summary",
        "correction": "Write must-do-summary.md first"
    },
]

# Orchestrator = the co-pilot (cheap model for monitoring)
orchestrator = Agent(
    model="claude-sonnet-4-6",
    system_prompt="You monitor a worker agent for drift...",
    allowed_tools=["Agent", "Read"],
)

# Worker = the agent doing actual work (powerful model)
worker = Subagent(
    name="worker",
    model="claude-opus-4-6",
    prompt="Build feature X...",
    allowed_tools=["Read", "Edit", "Bash", "Glob", "Grep"],
)

# Hook: inspect every tool call from the worker
@worker.on("PreToolUse")
def check_drift(tool_name, tool_input):
    for rule in DRIFT_RULES:
        if matches(rule["pattern"], tool_name, tool_input):
            worker.send_message(rule["correction"])

# Hook: inspect worker's text output
@worker.on("text_delta")
def monitor_output(text):
    for rule in DRIFT_RULES:
        if rule["pattern"] in text:
            worker.send_message(f"CORRECTION: {rule['correction']}")
```

### Pros
- Full programmatic control — inspect tool calls, not just text output
- Can intercept **before** drift happens (PreToolUse hooks)
- Mixed-model: cheap model (Sonnet) monitors, expensive model (Opus) works — cost efficient
- Subagent isolation — worker's context doesn't pollute orchestrator
- Production-ready patterns from Anthropic's official SDK

### Cons
- Agent SDK billing starts June 15, 2026 (separate credit pool from interactive usage)
- More complex to set up than bash scripts — requires Python or TypeScript project
- SDK is still evolving — API surface may change
- Requires Anthropic API key (not just Claude subscription)

### Setup Complexity: High
Requires Python or TypeScript project, dependency management, Agent SDK installation, API key configuration.

### Platform Support: Windows, Linux, macOS
Works everywhere Python or Node.js runs.

---

## 6. Architecture Pattern D: Hooks-Based Drift Detection

### How It Works

Use Claude Code's existing **hook system** to detect drift patterns deterministically — no second process needed. PostToolUse hooks fire after every tool call and can check whether the agent is following its instructions.

### Architecture

```json
// In settings.json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": { "tool_name": "Edit" },
        "hooks": [{
          "type": "command",
          "command": "bash ~/.claude/scripts/drift-check.sh"
        }]
      }
    ]
  }
}
```

```bash
#!/bin/bash
# drift-check.sh -- runs after every Edit tool call
# Check: did the agent run tests since the last edit?

LAST_TEST=$(stat -c %Y /tmp/last-test-run 2>/dev/null || echo 0)
NOW=$(date +%s)

if [ $((NOW - LAST_TEST)) -gt 60 ]; then
    echo "WARNING: You edited a file but haven't run tests in over 60 seconds." >&2
    echo "Run tests now before making any more changes." >&2
    exit 2  # blocks the next tool call
fi
```

### What Hooks CAN Do
- **Block tool calls** when drift conditions are met (exit 2 from PreToolUse)
- **Inject context** on every prompt (UserPromptSubmit stdout becomes context)
- **Track state** across tool calls (file-based counters, timestamps)
- **Fire selectively** — match specific tool names (Edit, Bash, Write)

### What Hooks CANNOT Do
- Read the agent's text output or reasoning (hooks only see tool inputs/outputs)
- Detect **semantic drift** ("the agent is going off on a tangent")
- Inject corrections mid-response — hooks only fire at tool-call boundaries
- Handle drift caused by the **absence** of a tool call (agent doesn't call a tool it should)

### Pros
- Zero extra cost — no additional tokens or API calls
- Uses existing infrastructure (same hooks the harness already uses)
- Deterministic — no LLM interpretation needed for structural drift
- Works on all platforms
- Already battle-tested in this harness

### Cons
- Cannot detect semantic drift — only structural (wrong tool order, missing tool calls)
- Cannot read agent reasoning — only tool inputs/outputs
- Cannot inject mid-response — only at tool boundaries
- Cannot handle "the agent didn't do something it should have" unless there's a subsequent tool call to trigger the check

### Setup Complexity: Low
Add hook entries to settings.json, write detection scripts. Same pattern already used throughout the harness.

### Platform Support: Windows, Linux, macOS
Works everywhere Claude Code runs.

---

## 7. Comparison Matrix

| Feature | A: Stream-JSON | B: tmux Monitor | C: Agent SDK | D: Hooks |
|---------|---------------|-----------------|-------------|----------|
| Inject mid-conversation | Yes | Maybe (Ink issue) | Yes | No (tool boundaries) |
| Read agent's text output | Yes (NDJSON) | Yes (terminal scrape) | Yes (events) | No |
| Detect semantic drift | Yes (parse text) | Yes (grep patterns) | Yes (hooks + text) | No (structural only) |
| Human can watch too | Custom UI needed | Yes (tmux attach) | Custom UI needed | Yes (normal TUI) |
| Setup complexity | Medium | Low | High | Low |
| Officially documented | Partially | N/A (tmux is standard) | Yes | Yes |
| Windows support | Yes | Needs WSL | Yes | Yes |
| Extra token cost | Same session | Same + monitor process | SDK credits (June 2026) | Zero |
| Can block before drift | No (reactive) | No (reactive) | Yes (PreToolUse) | Yes (PreToolUse) |
| Handles absent tool calls | Yes | Yes | Yes | No |

---

## 8. Recommended Phased Approach

### Phase 1: Extend Hooks (Pattern D) — BUILD NOW
Extend the existing harness with PostToolUse and UserPromptSubmit hooks targeting the specific drift patterns. This covers **structural drift** (skipping steps, wrong tool order) with zero extra cost. The infrastructure already exists — just add new detection scripts.

**Best for**: "Agent must run tests after every edit", "Agent must update progress notes every N edits", "Agent must not call Edit before reading the file".

**Limitation**: Cannot catch semantic drift or the absence of expected actions.

### Phase 2: Add tmux Monitoring (Pattern B) — TEST NEXT
For semantic drift that hooks can't catch, run Claude Code inside tmux and add a `pipe-pane` monitor script. The first thing to test: **does `tmux send-keys "text" Enter` actually submit a prompt in Claude Code's TUI?** If yes, this is the simplest full solution. If not, fall back to `--resume` for corrections.

**Best for**: "Agent is going off on a tangent", "Agent is working on the wrong file", "Agent's output mentions something it shouldn't".

### Phase 3: Migrate to Agent SDK (Pattern C) — JUNE 2026+
When the Agent SDK billing stabilises and the API matures, migrate the co-pilot to a proper orchestrator/subagent architecture. This gives full programmatic control and is the long-term production answer.

**Best for**: Production deployment, multi-agent orchestration, fine-grained control over the entire agent loop.

### Pattern A (Stream-JSON) is viable now but:
- Requires giving up the interactive TUI (human can't easily watch)
- Input format is undocumented and could change
- Best suited for **fully automated pipelines**, not human-supervised work
- Consider it if Patterns B or D don't cover your needs

---

## 9. CLI Reference

### Headless / Non-Interactive Mode
```bash
claude -p "prompt"                          # one-shot, exits after response
claude -p "prompt" --continue               # continue most recent session
claude -p "prompt" --resume SESSION_ID      # continue specific session
```

### Streaming JSON (Bidirectional)
```bash
claude -p \
  --input-format stream-json \
  --output-format stream-json \
  --verbose \
  --include-partial-messages
```

### Output Formats
```bash
--output-format text                        # plain text (default)
--output-format json                        # structured JSON with cost/session_id
--output-format stream-json                 # NDJSON event stream
```

### Permission Modes for Automation
```bash
--permission-mode default                   # interactive approval (safest)
--permission-mode acceptEdits               # auto-approve file edits
--permission-mode auto                      # auto-approve most things
--permission-mode bypassPermissions         # skip all (sandboxed environments only)
--allowedTools "Read,Edit,Bash"             # restrict available tools
```

### Session ID Capture (for --resume)
```bash
SESSION_ID=$(claude -p "Start task" --output-format json | jq -r '.session_id')
claude -p "CORRECTION: You forgot X" --resume "$SESSION_ID"
```

### Context Injection
```bash
--append-system-prompt "extra instructions" # add to system prompt
```

### Safety Limits
```bash
--max-turns 50                              # prevent runaway agent loops
```

### tmux Commands for Co-Pilot
```bash
tmux new-session -d -s worker "claude"                    # start in detached session
tmux pipe-pane -t worker "cat >> /tmp/claude-output.log"  # log all output
tmux send-keys -t worker "correction text" Enter          # inject keystrokes
tmux capture-pane -t worker -p                            # screenshot current screen
tmux attach -t worker                                     # human watches/interacts
```

---

## 10. Suggested Drift Rule Format

For any pattern that needs configurable rules:

```json
{
  "rules": [
    {
      "id": "must-run-tests",
      "description": "Agent must run tests after every code edit",
      "detect": {
        "type": "tool_sequence",
        "condition": "Edit called without subsequent Bash containing 'pytest' within 2 tool calls"
      },
      "correction": "STOP. You edited code without running tests. Run python -m pytest now.",
      "severity": "block"
    },
    {
      "id": "must-update-progress",
      "description": "Agent must update progress notes every 10 edits",
      "detect": {
        "type": "counter",
        "condition": "10 Edit calls since last Write to progress-notes.md"
      },
      "correction": "You have made 10 edits without updating progress-notes.md. Update it now.",
      "severity": "warn"
    },
    {
      "id": "no-tangent",
      "description": "Agent must not work on files outside scope",
      "detect": {
        "type": "text_match",
        "condition": "Edit target path not in watcher SCOPE list"
      },
      "correction": "STOP. That file is outside your task scope. Return to the files listed in your watcher.",
      "severity": "block"
    }
  ]
}
```

---

## 11. Open Questions for the Developer

1. **Does `tmux send-keys` + Enter trigger Ink's `onSubmit`?**
   This is the single biggest unknown. If yes, Pattern B is trivially simple. If not, `--resume` is the fallback. Needs hands-on testing.

2. **Does `--resume` inject into an actively-running session?**
   The docs say "continue a specific conversation" but don't clarify concurrent access. If the session is mid-turn, does `--resume` queue or conflict?

3. **Will `--input-format stream-json` remain stable?**
   It is undocumented — Anthropic could change the protocol. The Agent SDK is the safer long-term bet.

4. **Token cost for the monitoring agent?**
   Pattern A and C consume tokens for the monitoring process. Pattern D (hooks) is free. Pattern B with `--resume` costs one turn per correction. What is the budget?

5. **Windows without WSL?**
   tmux does not run natively on Windows. Options: use WSL, or skip Pattern B and go with A, C, or D. Hooks (Pattern D) work everywhere.

6. **How to handle rapid-fire corrections?**
   If the agent drifts on three consecutive turns, should the co-pilot inject three corrections or batch them? Need a debounce/cooldown strategy.

7. **False positive management?**
   If the co-pilot injects corrections when the agent is not actually drifting, it disrupts flow. How to tune rule sensitivity?

---

## 12. Sources

### Official Anthropic Documentation
- [Run Claude Code Programmatically (Headless Mode)](https://code.claude.com/docs/en/headless)
- [Hooks Reference](https://code.claude.com/docs/en/hooks)
- [How to Configure Claude Code Hooks](https://claude.com/blog/how-to-configure-hooks)
- [Agent SDK Overview](https://code.claude.com/docs/en/agent-sdk/overview)
- [Subagents in the SDK](https://platform.claude.com/docs/en/agent-sdk/subagents)
- [Claude Code SDK Features](https://platform.claude.com/docs/en/agent-sdk/claude-code-features)

### GitHub Issues
- [Feature: Programmatic Input in Interactive Mode -- #15553](https://github.com/anthropics/claude-code/issues/15553)
- [Docs: --input-format stream-json undocumented -- #24594](https://github.com/anthropics/claude-code/issues/24594)
- [Bug: stdout buffering in stream-json -- #25670](https://github.com/anthropics/claude-code/issues/25670)
- [Bug: UserPromptSubmit prompt injection false positive -- #17804](https://github.com/anthropics/claude-code/issues/17804)

### Third-Party Guides and Tools
- [Wrapping Claude CLI for Agentic Applications](https://avasdream.com/blog/claude-cli-agentic-wrapper)
- [Claude Code stream-json Deep Dive](https://backgroundclaude.com/blog/stream-json)
- [Running Claude Code in a Loop (Persistent Agent)](https://dev.to/agentdm/running-claude-code-in-a-loop-the-script-that-turns-it-into-a-persistent-agent-4i3f)
- [Claude Code Hooks Mastery -- GitHub](https://github.com/disler/claude-code-hooks-mastery)
- [File-Based Signaling in Claude Code](https://www.mindstudio.ai/blog/claude-code-monitor-tool-background-processes)
- [Wake: Terminal History for Claude Code](https://dev.to/joemckenney/wake-give-claude-code-visibility-into-your-terminal-history-55o4)
- [Pipe Terminal Output to Claude Code Safely](https://clipgate.github.io/blog/pipe-terminal-output-to-claude-cursor-aider/)
- [Claude Code Session Management](https://stevekinney.com/courses/ai-development/claude-code-session-management)
- [Claude Code CLI Reference](https://opentools.ai/resources/claude-code-cli-reference)
- [Elixir SDK Streaming Module](https://hexdocs.pm/claude_code_sdk/ClaudeCodeSDK.Streaming.html)
- [Building Agents with Claude Code's SDK](https://blog.promptlayer.com/building-agents-with-claude-codes-sdk/)
- [Claude Agent SDK TypeScript Guide](https://www.codewithseb.com/blog/claude-agent-sdk-typescript-production-guide)

### tmux / Terminal Automation
- [tmux-echelon: Automate tmux with pexpect](https://github.com/jnurmine/tmux-echelon)
- [Using tmux to Test Console Applications](https://www.drmaciver.com/2015/05/using-tmux-to-test-your-console-applications/)
- [Monitoring tmux Output](https://aritang.github.io/posts/tail_tmux_outputs/)
- [pexpect Documentation](https://pexpect.readthedocs.io/en/stable/api/pexpect.html)
