# Enhanced Agent Harness — Complete Playbook

## What This Is

A complete instruction manual for the Enhanced Agent Harness — a deterministic enforcement system for Claude Code that keeps AI agents on task through hard gates, evidence collection, cognitive guidance, and forward visibility. This document covers every layer: what problem it solves, how it was built, and how all the pieces fit together.

Use this playbook to:
- Understand why each layer exists
- Rebuild or extend the harness on any system
- Debug agent behaviour when gates fire
- Train new developers on the system

---

## The Origin Problem

AI agents (Claude, GPT, etc.) running in Claude Code drift. They skip steps, lose track of where they are in a multi-step protocol, self-certify their own work, and rationalize shortcuts. Soft enforcement (markdown instructions saying "you must do X") degrades under context pressure — the agent reads the instruction, agrees with it, and then ignores it when the context window fills up.

The fundamental insight: **if you want an agent to follow a process, you cannot rely on the agent choosing to follow it. You must make it structurally impossible to skip.**

This led to three design principles:
1. Never use Layer 3 (LLM) for something Layer 2 (deterministic scripts) can do
2. Never use Layer 2 for something Layer 1 (harness outer loop) should control
3. Every "the agent must..." becomes "a script checks whether the agent did... and blocks if not"

---

## Architecture Overview

```
Layer 0: First Principles Research
Layer 1: Protocol (The Constitution — CLAUDE.md)
Layer 2: Integration Blueprint (three-tier architecture)
Layer 3: Hard Gate System (pre-write, pre-bash, pre-flight gates)
Layer 4: Pre-Flight Evidence (MCQ quiz system)
Layer 5: Must-Do Reference (forced reading of project docs)
Layer 6: Evidence Checkpoints (periodic independent verification)
Layer 7: Strategy Loop Breaker (break repeated failure cycles)
Layer 8: Memory & Knowledge (session persistence)
Layer 9: Cognitive Guidance (phase-specific thinking modes)
Layer 10: Compound Reliability / $ralph (persistent execution loop)
Layer 11: Smoother Agent Journey (forward visibility, gate labels)
```

Each layer was added because a real failure mode proved the previous layers weren't enough.

---

## Layer 0: First Principles Research

### Problem
No existing system solved the full problem. Individual techniques (RAG, chain-of-thought, tool use) addressed fragments but nothing kept an agent deterministically on a multi-step protocol across sessions.

### Solution
Combined four expert perspectives:
- **Agent Systems Architect** — state machines, event loops, context isolation
- **Distributed Systems Engineer** — checkpointing, idempotent operations, circuit breakers
- **Clinical Protocol Designer** — structured protocols with fidelity checks at each gate
- **Cognitive Systems Engineer** — instruction degradation under attention constraints

### Key Insight
The agent has limited working memory. Instructions degrade under context pressure. The only reliable enforcement is structural — bash scripts that block tool calls before they execute. The agent cannot talk its way past a script that returns `exit 2`.

### Artefacts
- `harness-strategies-so-far/source-documents/Harness  big idea.txt`

---

## Layer 1: The Protocol (Constitution)

### Problem
Agents need a comprehensive operating procedure — what phases to follow, how to manage memory, when to escalate. Without a shared protocol, every session starts from scratch.

### Solution
The Enhanced Agent Harness protocol document — 11 parts covering:
- **Agent Memory System**: startup protocol, core identity, working memory, episodic sessions
- **State Machine**: PLAN → NEGOTIATE → BUILD → EVALUATE → COMPLETE (never skip)
- **Builder/Verifier Separation**: the builder cannot verify its own work
- **Escalation Protocol**: same error 3x = stop and tell the user (facts, not theories)
- **TDD Protocol**: write tests first, tests must fail first, one feature at a time
- **Protocol Levels**: Full (multi-feature), Lightweight (single edit), Emergency (production down)

### Key Insight
This is soft enforcement — it works when the agent reads and follows it, but degrades under pressure. It's the constitution, not the police force. You need both.

### Artefacts
- `harness-strategies-so-far/source-documents/enhanced-agent-harness.md`
- `_install/CLAUDE.md` (distilled version installed globally)

---

## Layer 2: Integration Blueprint

### Problem
The protocol (Layer 1) tells agents what to do. The bash scripts tell the system how to enforce it. These were designed separately and needed to be merged into a coherent architecture.

### Solution
Three-tier architecture:
- **Layer 1 — Harness**: outer loop, session lifecycle, phase transitions. `run-harness.sh`, `startup-recovery.sh`, `on-session-end.sh`
- **Layer 2 — Deterministic Guards**: phase validation, loop detection, fix matching. Bash scripts, no LLM.
- **Layer 3 — Agents**: planner, generator, evaluator. LLM within constraints set by Layers 1-2.

### Key Insight
*"The OpenClaw document is the constitution. Our scripts are the executive branch that enforces it. They're complementary, not competing."*

### Artefacts
- `harness-strategies-so-far/source-documents/making th enhanced agent harnes and the  new big Idea work together.txt`

---

## Layer 3: Hard Gate System

### Problem
Agents write source code in the wrong phase (coding during PLAN), skip contracts (coding without scope), and work without task tracking (no watcher claimed). Soft instructions saying "don't do this" are ignored.

### Solution
Three gate scripts that run as Claude Code hooks on every Write, Edit, and Bash call:

**pre-write-gate.sh** (PreToolUse on Write|Edit) — 19 block points:
- Phase gates: block source code writes in PLAN, NEGOTIATE, EVALUATE, COMPLETE
- Contract gate: block BUILD writes without `sprint-N-contract.md`
- Watcher gate: block writes after 2+ writes without an active watcher + cron
- Cron gate: block writes when watcher is claimed but no cron reminder set
- Ralph gates: block completion without PASS verdict, block agent from touching ralph-mode.json

**pre-bash-gate.sh** (PreToolUse on Bash) — 13 block points:
- Same enforcement as pre-write-gate but for Bash commands that write files
- Detects: `python open/write`, `tee`, `sed -i`, `echo/printf/cat redirect`, heredoc, `cp/mv`
- Closes the gap where agents used `python3 -c` to bypass Write/Edit hooks

**pre-flight-gate.sh** (PreToolUse on Write|Edit) — 4 block points:
- Phase feedback FAIL block
- Verification step check-off block
- Pre-flight MCQ challenge (see Layer 4)
- Challenge generation failure

### How It Works
Claude Code hooks fire BEFORE the tool executes. The hook reads stdin (JSON with tool input), checks conditions, and either exits 0 (allow) or exits 2 (block with message). The agent sees the block message and must comply — there is no way to bypass a hook that returns exit 2.

### Key Insight
All gates use `exit 2` (block) not `exit 1` (error). Exit 2 is Claude Code's "deny this tool call" signal. The agent receives the stderr output as feedback explaining what to do.

### Exemptions
Gates exempt harness infrastructure paths so agents can always update state:
`.claude/state/`, `.claude/contracts/`, `.claude/specs/`, `.claude/pre-flight/`, `.openclaw/watchers/`, `.agent-memory/`, `.claude/evidence/`

### Artefacts
- `_install/hooks/pre-write-gate.sh`
- `_install/hooks/pre-bash-gate.sh`
- `_install/hooks/pre-flight-gate.sh`
- `_install/hooks/allow-claude-dir.sh` (quick-pass for .claude/ paths)

---

## Layer 4: Pre-Flight Evidence (MCQ Quiz)

### Problem
Agents claim to know what they're doing but drift from their task. A watcher slot says "implement payment system" but the agent is refactoring the logger. There's no way to test whether the agent actually knows its current task, step, target file, and scope.

### Solution
An MCQ challenge system that quizzes the agent on its own watcher slot:

1. **generate-pre-flight-challenge.sh** reads the agent's watcher slot and generates 4-5 questions:
   - Q1: What is your current task? (1 correct + 3 distractors)
   - Q2: Which step are you on? (1 correct + 3 distractors)
   - Q3: What file should this edit target? (1 correct + 3 distractors)
   - Q4: What should you avoid / what's out of scope? (1 correct + 3 distractors)
   - Q5: Have you done work that should be independently verified? (yes/no)

2. **Distractor pool** at `~/.openclaw/distractor-pool/` — 4 files (constraints.txt, files.txt, steps.txt, tasks.txt) with 60 entries each, rotated via `shuf`

3. **validate-pre-flight.sh** checks the agent's answers against the watcher slot. Wrong answers = blocked.

### How It Works
The gate fires every 4th write (configurable) or when the watcher step changes. The challenge is written to `.claude/pre-flight/challenge.md`. The agent reads it, writes answers to `.claude/pre-flight/response.md`, then retries the write. The gate validates and allows if correct.

### Key Insight
The answer key is never stored — it's derived from the watcher slot at validation time. The agent cannot cheat by reading a stored answer. The distractors are shuffled randomly so the correct answer position changes every time.

### Artefacts
- `_install/hooks/pre-flight-gate.sh`
- `_install/scripts/generate-pre-flight-challenge.sh`
- `_install/scripts/validate-pre-flight.sh`
- `_install/openclaw/distractor-pool/` (4 files)

---

## Layer 5: Must-Do Reference Enforcement

### Problem
Projects have critical documentation (API specs, architecture decisions, migration guides) that agents must read before coding. But agents skip reading and jump straight to implementation, producing code that violates documented constraints.

### Solution
A convention-based system:
1. Project places a `docs/must-do/must-do.md` file listing critical file paths (one per line)
2. The harness detects this folder and activates enforcement
3. Agent must read all listed files and write `.claude/state/must-do-summary.md` (200+ chars, must reference file basenames)
4. Summary is checked for staleness when the watcher step changes (drift detection)

### Four Block Variants
- No summary file exists → BLOCKED
- Summary is stale (watcher step changed) → BLOCKED
- Summary too short (<200 chars) → BLOCKED
- Summary doesn't reference any required file basenames → BLOCKED

### Key Insight
The must-do summary is injected into every prompt via the turn packet, so the agent's own summary stays in context throughout the session. And the summary is checked for staleness — if the agent moves to a new step, it must re-read and re-summarize.

### Artefacts
- Must-do gates in `_install/hooks/pre-write-gate.sh` (lines 395-437)
- Must-do injection in `_install/hooks/on-prompt-submit.sh`

---

## Layer 6: Evidence Checkpoints

### Problem
The entry gate (must-do summary) proves the agent read the docs at the start. The exit gate (evaluator at EVALUATE phase) checks the final output. But during sustained BUILD work (50+ writes), the agent can drift far from the requirements with no checkpoint in between.

### Solution
Periodic independent verification during BUILD:
1. A counter increments on every Write/Edit (tracked in `checkpoint-counter.json`)
2. Every N writes (default 15, configurable via `checkpoint-config.json`), a checkpoint triggers
3. **create-evidence-checkpoint.sh** builds a checkpoint brief from must-do source files
4. The harness injects the brief into `.claude/state/evidence-checkpoint.json`
5. Agent must spawn a verifier sub-agent (cannot tell it what to check — brief is pre-built)
6. Verifier writes verdict to `.claude/state/evidence-verdict.json`
7. PASS → resume. FAIL → agent must write remediation plan, produce evidence, re-verify.

### Key Insight
The harness controls what the verifier sees, not the builder. The builder cannot filter the evidence brief — it's generated from the must-do source files directly. This prevents the builder from hiding failures from its own verifier.

### Artefacts
- `_install/scripts/create-evidence-checkpoint.sh`
- Evidence gates in `_install/hooks/pre-write-gate.sh` (lines 589-663)
- Counter in `_install/hooks/post-write-check.sh`
- Injection in `_install/hooks/on-prompt-submit.sh`

---

## Layer 7: Strategy Loop Breaker

### Problem
Agents get stuck in loops — trying the same failed approach repeatedly. They modify the same file, get the same error, try the same fix, fail again. Each cycle burns tokens and produces no progress.

### Solution
**detect-strategy-loop.sh** analyses recent activity:
- Tracks file modification patterns and error signatures
- Detects Tier 1 (warning) and Tier 2 (block) loop conditions
- At Tier 2: locks writes via `strategy-loop-state.json`

To unblock, the agent must write `.claude/state/strategy-ack.md` with:
- A `## New Approach` section header
- At least 150 characters describing a genuinely new strategy
- Reference at least one must-do file by name

### Key Insight
Forcing the agent to articulate a new approach in writing (not just retry) breaks the cognitive loop. The 150-char minimum prevents minimal-effort acknowledgments like "I'll try again differently."

### Artefacts
- `_install/scripts/detect-strategy-loop.sh`
- Strategy loop gates in `_install/hooks/pre-write-gate.sh` and `_install/hooks/pre-bash-gate.sh`

---

## Layer 8: Memory & Knowledge Persistence

### Problem
Every new Claude Code session starts with a blank context. The agent doesn't know what it did yesterday, what decisions were made, or what's already been tried and failed.

### Solution
**Automated memory system** via hooks:

**post-write-check.sh** (PostToolUse on Write|Edit) — runs after every write:
- Updates `.agent-memory/working/session-context.md` (hash-gated, only writes if changed)
- Appends to `.agent-memory/working/recent-activity.jsonl` (append-only log)
- Logs phase transitions to `.agent-memory/episodic/decisions/transitions.jsonl`

**on-session-end.sh** (Stop hook) — runs when session ends:
- Creates session summary at `.agent-memory/episodic/sessions/YYYY-MM-DD_HH-MM-SS.md`
- Updates `.agent-memory/MEMORY_MANIFEST.json`
- Writes `.agent-memory/working/active-tasks.json` (what to resume next session)

**startup-recovery.sh** — runs on startup:
- Clears stale phase-feedback.md (>2 hours old)
- Cleans stale watcher claims (>4 hours old, project-scoped)
- Clears phantom cron IDs from dead sessions

### Memory Hardening (reliability fixes)
- **Append-only JSONL**: no more overwrite-on-read corruption
- **Atomic writes**: `atomic_write()` in lib-helpers.sh — write to temp, mv to target
- **Hash-based change detection**: `write_if_changed()` — only write if content hash differs
- **STDIN not env vars**: PostToolUse hooks receive tool context via STDIN JSON, not environment variables. Use `HOOK_INPUT=$(cat)` + jq extraction.

### Artefacts
- `_install/hooks/post-write-check.sh`
- `_install/hooks/on-session-end.sh`
- `_install/scripts/startup-recovery.sh`
- `_install/scripts/lib-helpers.sh` (atomic_write, append_jsonl, trim_jsonl, write_if_changed)

---

## Layer 9: Cognitive Guidance

### Problem
After 20 sprints, the gate system was strong at blocking wrong actions. But agents still struggled — they hit gates, spent tokens figuring out what the harness wanted, then complied minimally. Gates tell agents what they *can't* do, but never teach them *how to think*.

### Root Cause (from OMX analysis)
oh-my-codex (OMX) achieved 9/10 success rates vs our 1/4 — same models, same tasks. The difference wasn't enforcement but **cognitive shaping**. OMX injected role-specific prompts that framed how the agent approached each phase.

### Solution
Phase-specific cognitive prompts injected into every turn packet:

| Phase | Cognitive Frame |
|-------|----------------|
| PLAN | Outcome-first: define result, criteria, constraints before writing spec |
| NEGOTIATE | Skeptical reviewer: challenge your proposal, binary pass/fail criteria |
| BUILD | Executor: proceed on safe steps, ASK only for destructive/irreversible |
| EVALUATE | Adversarial verifier: default FAIL, fresh evidence only |
| COMPLETE | Structured handoff: name outcome, list evidence, no softeners |

Plus:
- **Segfault detection**: catches silent crashes in test runners
- **Stale timeout**: detects progress notes unchanged for too long
- **Fix ceiling**: hard limit on iteration count before STUCK

### Key Insight
*"Our harness is strong on enforcement but weak on guidance. Gates are safety nets. Guidance shapes the path so gates rarely fire."*

### Artefacts
- `_install/roles/` (critic.md, executor.md, explorer.md, planner.md, verifier.md)
- GUIDANCE line in `_install/hooks/on-prompt-submit.sh`

---

## Layer 10: Compound Reliability / $ralph

### Problem
The harness had all pieces for iterative work — gates, checkpoints, verifiers — but agents had to manually drive the BUILD → EVALUATE → BUILD cycle. Three failure modes:
1. Agents skip verification — declare success without spawning a verifier
2. Agents self-certify — read their own notes instead of testing independently
3. Fix loops are shallow — fix one thing, declare done instead of re-verifying

### Solution (inspired by OMX's $ralph)
A persistent execution loop activated by the user:

```
User types: $ralph implement the payment system

     IMPLEMENT ──> VERIFY ──> PASS? ──> COMPLETE
          ^                     |
          |                     | FAIL
          |                     v
          └──────── FIX <──────┘

     Hard ceiling: 5 iterations (configurable)
     Terminal: STUCK after ceiling
```

Three unbypassable enforcement points:
1. **Completion block**: cannot write phase-complete-marker.md without PASS verdict
2. **State protection**: cannot write or delete ralph-mode.json (user-only)
3. **Stuck ceiling**: too many iterations → forced STUCK state

### Five Multipliers (from OMX analysis)
1. **Iteration with real feedback** — verbatim test output fed back, not just "FAIL"
2. **Agent decomposition** — 5 role prompts (explorer, planner, executor, critic, verifier)
3. **Context snapshots** — explorer reads codebase first, produces grounded summary
4. **Structured verification feedback** — error lines, test output, expected vs found
5. **Fix ceiling** — hard limit prevents infinite loops

### Key Insight
A model with 60% first-try accuracy reaches 97% after 3 iterations with feedback (1 - 0.4^3). The loop IS the quality multiplier.

### Artefacts
- Ralph gates in `_install/hooks/pre-write-gate.sh` and `_install/hooks/pre-bash-gate.sh`
- Auto-transition in `_install/hooks/on-prompt-submit.sh`
- `_install/scripts/validate-phase.sh` (structured verification feedback)
- `_install/scripts/detect-loop.sh`
- `_install/roles/` (5 role prompts)

---

## Layer 11: Smoother Agent Journey

### Problem
Agents discover gates by crashing into them one at a time. Each crash costs a round-trip. Agents can't distinguish "you forgot setup" (admin gate) from "you're being tested" (evidence gate). No gate tells what's coming next. Agents resent the process for "simple" tasks.

### Solution
Four changes to gate messaging (no gate logic changed):

**1. Gate Type Labels**
Every BLOCKED message prefixed with `[ADMIN GATE]` or `[EVIDENCE GATE]`:
- Admin gates: setup prerequisites (watcher, contract, cron, phase). "Complete this and move on."
- Evidence gates: verification tests (MCQ, must-do, checkpoints, strategy loop). "You're being tested. This cannot be shortcut."

**2. Forward Visibility ("GATES AHEAD")**
Every block message appends upcoming gates using `compute_pending_gates()`:
```
GATES AHEAD (after you clear this):
 -> [ADMIN] contract gate — need sprint-5-contract.md
 -> [EVIDENCE] pre-flight MCQ — you will be quizzed on your task
```
Dynamic — only shows gates that are still pending. Already-cleared and non-applicable gates excluded.

**3. Turn Packet Pipeline Status**
PENDING line during BUILD showing uncompleted gates:
```
PENDING: [ADMIN] contract -> [EVIDENCE] pre-flight-MCQ
```
When all clear: `GATES: all clear — write freely`

**4. No-Shortcut Messaging**
```
PROCESS NOTE: Every task follows the full gate sequence — no exceptions
for "simple" edits. The process IS the work.
```

### Key Insight
The gates didn't get harder or softer. We just gave agents a map instead of a series of surprise walls. Same enforcement, dramatically less friction.

### Artefacts
- `compute_pending_gates()` in `_install/scripts/lib-helpers.sh`
- Labels + GATES AHEAD in all three gate scripts
- PENDING line + process note in `_install/hooks/on-prompt-submit.sh`

---

## Supporting Infrastructure

### Turn Packet System (on-prompt-submit.sh)
The UserPromptSubmit hook that fires on every user prompt. Assembles a context packet injected into the agent's view:
- Phase, sprint, iteration, write count, watcher status
- GUIDANCE line (cognitive frame for current phase)
- PENDING gates or "all clear"
- PROCESS NOTE (no-shortcut messaging)
- Must-do summary injection
- Evidence checkpoint status
- Strategy loop warnings
- Role-based read-first files

### Watcher System
5 reusable watcher slots at `~/.openclaw/watchers/`:
- REGISTRY.json with atomic locking (`registry_lock()`, `registry_unlock()` via mkdir)
- Each slot has: status, claimed_by, claimed_at, project, cron_job_id
- Slot .md files contain: task, scope, out-of-scope, mistakes-to-avoid, to-do checklist
- 3-minute cron reminders via CronCreate
- Stale auto-clean on startup (>4 hours, project-scoped)

### lib-helpers.sh (Shared Utilities)
- `atomic_write()` — write to temp, mv to target
- `append_jsonl()` — append JSON line to log file
- `trim_jsonl()` — keep last N lines
- `write_if_changed()` — hash-gated writes
- `registry_lock()` / `registry_unlock()` — mkdir-based atomic locking
- `registry_modify()` — locked read-modify-write cycle
- `read_watcher_step_scope()` — extract current step from watcher slot
- `compute_pending_gates()` — dynamic gate status for forward visibility

### Hook Architecture (settings.json)
```
UserPromptSubmit → on-prompt-submit.sh (turn packet injection)
PreToolUse Write|Edit → allow-claude-dir.sh (quick-pass .claude/)
PreToolUse Write|Edit|Agent → pre-write-gate.sh (main gate)
PreToolUse Write|Edit → pre-flight-gate.sh (MCQ challenge)
PreToolUse Bash → pre-bash-gate.sh (bash bypass prevention)
PostToolUse Write|Edit → post-write-check.sh (memory + counters)
PostToolUse Bash → collect-test-evidence.sh (test output capture)
PostToolUse Agent → agent-call-tracker.sh (sub-agent tracking)
Stop → on-session-end.sh (session summary + memory)
```

---

## Platform Compatibility

All scripts work on:
- **Windows** (Git Bash / MSYS2)
- **Linux** (Ubuntu, Debian, RHEL, Alpine with bash)
- **macOS** (with GNU coreutils recommended)

Key patterns for cross-platform:
- `pwd -W 2>/dev/null || pwd` — Windows absolute path with fallback
- `tr '\\\\' '/'` — backslash to forward-slash (harmless on Linux)
- `tr -d '\r'` — strip carriage returns from jq output (essential on Windows)
- `date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S'` — ISO timestamp with fallback
- `stat --format='%Y' ... 2>/dev/null || stat -f %m ...` — GNU/BSD stat fallback
- `while IFS= read -r var || [ -n "$var" ]` — handle files without trailing newline
- Never use `sed 's|\\|/|g'` on MSYS — use `tr` instead

Prerequisites: `bash`, `jq`

---

## Installation

```bash
git clone https://github.com/exrovite/harness-infra
cd harness-infra
bash _install/install.sh
```

Then for each project:
```bash
cd your-project
bash ~/.claude/scripts/init-project.sh
```

---

## File Inventory

### Hooks (12 files → ~/.claude/hooks/)
| File | Hook Type | Purpose |
|------|-----------|---------|
| on-prompt-submit.sh | UserPromptSubmit | Turn packet, guidance, pipeline status |
| pre-write-gate.sh | PreToolUse Write/Edit/Agent | Main gate (19 blocks) |
| pre-bash-gate.sh | PreToolUse Bash | Bash bypass prevention (13 blocks) |
| pre-flight-gate.sh | PreToolUse Write/Edit | MCQ challenge (4 blocks) |
| allow-claude-dir.sh | PreToolUse Write/Edit | Quick-pass for .claude/ paths |
| post-write-check.sh | PostToolUse Write/Edit | Memory, counters, checkpoints |
| collect-test-evidence.sh | PostToolUse Bash | Test output capture |
| agent-call-tracker.sh | PostToolUse Agent | Sub-agent tracking |
| on-session-end.sh | Stop | Session summary, memory update |
| pre-phase-start.sh | PreToolUse | Known-fix injection |
| on-stuck-detected.sh | PostToolUse | Auto-escalation on stuck |
| on-test-failure.sh | PostToolUse | Test failure handling |

### Scripts (28 files → ~/.claude/scripts/)
| File | Purpose |
|------|---------|
| lib-helpers.sh | Shared utilities (atomic write, locking, gate status) |
| init-project.sh | Per-project setup |
| startup-recovery.sh | Crash recovery, stale cleanup |
| run-harness.sh | Outer loop driver |
| validate-phase.sh | Phase validation with structured feedback |
| validate-pre-flight.sh | MCQ answer validation |
| generate-pre-flight-challenge.sh | MCQ question generation |
| create-evidence-checkpoint.sh | Evidence checkpoint brief builder |
| detect-loop.sh | Loop detection |
| detect-strategy-loop.sh | Strategy loop analysis |
| detect-test-runner.sh | Auto-detect project test framework |
| run-project-tests.sh | Run tests with framework detection |
| validate-tdd.sh | TDD compliance checking |
| validate-state-transition.sh | State machine transition validation |
| verify-fix-applied.sh | Known-fix verification |
| evaluate-protocol-compliance.sh | Protocol compliance evaluation |
| classify-verification-need.sh | Classify verification type needed |
| write-handoff.sh | Handoff document generation |
| git-checkpoint.sh | Auto-commit at phase boundaries |
| check-budget.sh | Cost/time circuit breaker |
| check-coverage.sh | Test coverage checking |
| run-claude-safe.sh | Retry wrapper with backoff |
| ensure-dev-server.sh | Pre-verification server check |
| notify.sh | Notification bridge |
| telegram-poll.sh | Telegram polling daemon |
| wait-for-human.sh | Timeout + state save |
| wiki-dropbox.sh | Agent Wiki data collection |
| test-hook-output.sh | Hook output testing |

### Roles (5 files → ~/.claude/roles/)
| File | Cognitive Frame |
|------|----------------|
| explorer.md | Codebase discovery — read first, summarize, never code |
| planner.md | Outcome-first — define result before spec |
| critic.md | Skeptical review — challenge proposals, find gaps |
| executor.md | Auto-continue on safe steps, ask on destructive |
| verifier.md | Default FAIL, fresh evidence only, no benefit of doubt |

---

## Debugging Guide

### Agent is blocked — how to diagnose
1. Read the block message — it tells you exactly what gate fired and what to do
2. Check the prefix: `[ADMIN GATE]` = setup needed, `[EVIDENCE GATE]` = agent being tested
3. Check `GATES AHEAD` section for what's coming next

### Common blocks and fixes
| Block | Fix |
|-------|-----|
| No watcher | Claim a slot in REGISTRY.json, write slot file, create cron |
| No contract | Write sprint-N-contract.md |
| No must-do summary | Read must-do files, write must-do-summary.md (200+ chars) |
| Pre-flight MCQ | Read challenge.md, write response.md with answers |
| Evidence checkpoint | Spawn verifier sub-agent (don't tell it what to check) |
| Strategy loop | Write strategy-ack.md with new approach (150+ chars) |
| Phase feedback FAIL | Read phase-feedback.md, fix the issue, write phase-complete-marker.md |

### Agent complains about "simple task" being blocked
This is expected. The process applies to everything. Simple tasks drift too. The no-shortcut messaging reinforces this. Do not exempt "simple" tasks.

### Stale blocks from previous sessions
startup-recovery.sh auto-clears:
- phase-feedback.md older than 2 hours
- watcher claims older than 4 hours (project-scoped)
- phantom cron IDs from dead sessions

---

## Design Philosophy

**Soft enforcement** = instructions in markdown. Advisory. Degrades under pressure.
**Hard enforcement** = bash scripts and hooks. Deterministic. Cannot be ignored.
**Harness enforcement** = outer loop controlling what agent sees. Structural.

Every "the agent must..." should become "a script checks whether the agent did... and blocks if not."

The harness is not overhead — it IS the work. Each layer exists because a real failure mode proved the previous layers weren't enough. The goal is not to constrain the agent but to make it structurally impossible to produce bad work.
