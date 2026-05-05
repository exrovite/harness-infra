# Sprint 11 Report: Codex CLI Under Harness Control

**Date**: 2026-04-08
**Objective**: Bring OpenAI's Codex CLI under the same kind of steering that Claude Code has
**Outcome**: Installed oh-my-codex (OMX) as the orchestration/enforcement layer for Codex

---

## Research Findings

### The Problem
Claude Code has deterministic harness control via PreToolUse/PostToolUse/UserPromptSubmit/Stop hooks — bash scripts that fire on every Write/Edit and make non-compliance structurally impossible. We wanted the same for Codex.

### What We Investigated

| Approach | Result |
|----------|--------|
| **Codex native hooks** | Codex has the same hook events (PreToolUse, PostToolUse, UserPromptSubmit, Stop) but they are **disabled on Windows** (PR #15252, merged 2026-03-20, temporary) |
| **Feature flag `codex_hooks = true`** | Tested — does NOT override the Windows disable. Hook log never created despite flag being set. |
| **Codex plugin for Claude Code** (`codex-plugin-cc`) | Already installed (v1.0.2) and functional. But runs Codex THROUGH Claude Code, **burning Claude tokens** for orchestration. |
| **MCP server approaches** | Multiple options (tuannvm, daviiidle, cexll, codex-as-mcp). All require Claude Code as orchestrator = Claude tokens. |
| **`codex exec` via Bash** | Works but black-box — no per-operation hooks. |
| **WSL** | Full hook support but user rejected — models get confused about Windows vs Linux paths, wastes time. |
| **oh-my-codex (OMX)** | Orchestration layer that controls Codex WITHOUT hooks. Uses AGENTS.md, planning gates, stateless execution loops, external verification. **Zero Claude tokens.** |
| **ralph-codex** | Spec-driven execution controller with immutable contracts, external test verification, git isolation. Same philosophy as our harness. |

### Key Insight
Developers are NOT using hooks for Codex control. They use **outer loop wrappers + immutable contracts + external verification + AGENTS.md**. This works on all platforms including Windows.

---

## What Was Installed

### oh-my-codex (OMX) v0.12.1
- **Install**: `npm install -g oh-my-codex`
- **Setup**: `omx setup` (user scope)
- **Diagnostics**: `omx doctor` — 11 passed, 1 warning (Rust harness optional)

### psmux v3.3.1
- **Install**: `winget install psmux`
- **Purpose**: Native Windows terminal multiplexer for OMX team mode (parallel agents in isolated worktrees). No WSL needed.
- **Aliases**: `psmux`, `pmux`, `tmux` (all mapped)

### Components Deployed

| Component | Location | Count |
|-----------|----------|-------|
| AGENTS.md (global) | `~/.codex/AGENTS.md` | 1 |
| Agent prompts | `~/.codex/prompts/` | 24 (architect, executor, verifier, etc.) |
| Skills | `~/.codex/skills/` | 25 (ralph, ralplan, team, deep-interview, etc.) |
| Native agents | `~/.codex/agents/*.toml` | 20 (analyst, debugger, security-reviewer, etc.) |
| hooks.json | `~/.codex/hooks.json` | 1 (ready for when Windows hooks are enabled) |
| State directory | `<project>/.omx/` | plans, logs, state |
| HUD config | `<project>/.omx/hud-config.json` | focused preset |
| Config updates | `~/.codex/config.toml` | OMX entries + `codex_hooks = true` flag |

---

## How It Works (Architecture)

### Three-Layer Mapping

| Layer | Claude Code (existing) | Codex via OMX (new) |
|-------|----------------------|-------------------|
| **Layer 1: Harness** | Claude Code hooks (`settings.json`) | OMX wrapper + AGENTS.md + planning gates |
| **Layer 2: Guards** | Bash scripts (pre-write-gate, pre-flight, etc.) | External verification, `.rules` files, git isolation |
| **Layer 3: Agent** | Claude Opus 4.6 + CLAUDE.md | GPT-5.4 + AGENTS.md + OMX skills |

### Enforcement Mechanisms

| Mechanism | How It Works |
|-----------|-------------|
| **AGENTS.md** | Loaded automatically as "operating contract". Routing rules, enforcement gates, working agreements. |
| **Planning gate** | `$ralph` blocks implementation until both `.omx/plans/prd-*.md` AND `.omx/plans/test-spec-*.md` exist. Like our contract gate. |
| **Stateless execution** | Each `$ralph` iteration can run as fresh process — no accumulated confusion. |
| **External verification** | "Verify before claiming done" — test suites decide success, not the agent. |
| **`.rules` files** | Hard enforcement — Codex sandbox evaluates rules before executing commands. |
| **Git isolation** | Team mode uses isolated worktrees per agent. Changes reversible. |
| **Append-only logs** | `.omx/logs/` — execution audit trail. |
| **Lore commit protocol** | Structured commit messages with decision records. |

### What We Lose vs Claude Code

| Feature | Claude Code | Codex via OMX |
|---------|------------|--------------|
| Pre-write gating (per file) | ✅ Hook fires on every Write/Edit | ❌ No mid-session hooks on Windows |
| Pre-flight MCQ | ✅ Challenge before writes | ❌ Not available |
| Phase feedback block | ✅ Blocks on FAIL | ❌ Not available |
| Watcher system | ✅ 3-minute cron reminders | ❌ Not available (OMX has HUD instead) |
| Contract gate | ✅ Hook checks sprint contract | ✅ Planning gate checks PRD + test spec |
| Builder/verifier separation | ✅ Independent sub-agent evaluator | ✅ External verification + `$team` mode |
| TDD enforcement | ✅ Tests must fail first | ⚠️ AGENTS.md instructs but doesn't enforce |
| Command gating | ⚠️ Bash hook detects patterns | ✅ `.rules` files — hard sandbox enforcement |

---

## How To Use It

### Launch
```bash
cd "G:\Your Project"
omx --madmax --high
```

### Workflow Commands (inside Codex session)
| Command | Purpose | Our Equivalent |
|---------|---------|---------------|
| `$deep-interview` | Scope vague requirements | PLAN phase |
| `$ralplan` | Create PRD + test spec | NEGOTIATE phase |
| `$ralph` | Persistent execution loop with verification | BUILD + EVALUATE phases |
| `$team 3:executor "task"` | Spawn parallel agents in isolated worktrees | Agent tool with worktree isolation |
| `$architect` | Architecture analysis | Planner agent |
| `$verifier` | Independent verification | Evaluator agent |

### Flags
| Flag | Meaning |
|------|---------|
| `--madmax` | Full autonomy (don't stop to ask) |
| `--high` | High reasoning effort from GPT-5.4 |
| `--tmux` | Explicit tmux/psmux execution |

### Team Management
```bash
omx team status <name>      # Monitor progress
omx team resume <name>      # Reconnect to running team
omx team shutdown <name>    # Graceful termination
```

---

## Codex Plugin for Claude Code (Also Available)

The official OpenAI plugin (`codex-plugin-cc` v1.0.2) is also installed and functional. This runs Codex THROUGH Claude Code (burns Claude tokens) but is useful for:

| Command | Purpose |
|---------|---------|
| `/codex:setup` | Check plugin readiness |
| `/codex:review` | Codex reviews Claude's work |
| `/codex:adversarial-review` | Skeptical review challenging design decisions |
| `/codex:rescue` | Delegate a task to Codex with write access |
| `/codex:status` | Check background task progress |
| `/codex:result` | Get results from completed task |

**Use case**: When you're already in a Claude Code session and want a second opinion from Codex, or want to delegate a subtask. Not for standalone Codex work.

---

## Configuration Files Modified

| File | Change |
|------|--------|
| `~/.codex/config.toml` | Added `codex_hooks = true` under `[features]`, OMX config entries |
| `~/.codex/hooks.json` | OMX hooks (SessionStart, PreToolUse, PostToolUse, UserPromptSubmit, Stop) |
| `~/.codex/AGENTS.md` | Generated by OMX — orchestration brain with routing, skills, enforcement gates |
| `~/.codex/agents/` | 20 native agent TOML configs |
| `~/.codex/prompts/` | 24 agent prompt files |
| `~/.codex/skills/` | 25 skill definitions |
| `<project>/.omx/` | State directory with plans, logs, state, HUD config |

---

## Future Work

1. **Customize AGENTS.md** — Layer our harness principles (escalation protocol, TDD mandate, append-only progress notes) into the OMX AGENTS.md template
2. **Per-project `.codex/AGENTS.md`** — Project-specific instructions that mirror project CLAUDE.md conventions
3. **When Windows hooks are re-enabled** — OMX hooks.json is already configured and ready. Our bash enforcement scripts can be adapted as additional hooks.
4. **Wrapper script** — Optional `codex-harness.sh` that validates phase/contract before launching OMX, and runs tests after. Adds Layer 1 outer-loop control.
5. **`.rules` files** — Define command-level hard gates specific to our workflow (block destructive git operations, etc.)

---

## Key Sources

- [oh-my-codex GitHub](https://github.com/Yeachan-Heo/oh-my-codex) — 18.5k stars, MIT license
- [ralph-codex](https://github.com/JH427/ralph-codex) — Spec-driven execution controller
- [Codex Hooks Documentation](https://developers.openai.com/codex/hooks) — "Hooks are currently disabled on Windows"
- [Codex Hooks Windows Disable PR](https://github.com/openai/codex/pull/15252) — Temporary, merged 2026-03-20
- [Codex AGENTS.md Guide](https://developers.openai.com/codex/guides/agents-md)
- [Codex Config Reference](https://developers.openai.com/codex/config-reference) — `features.codex_hooks` flag
- [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) — Official OpenAI plugin for Claude Code
- [psmux](https://github.com/psmux/psmux) — Native Windows terminal multiplexer
