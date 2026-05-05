# AGENT MEMORY SYSTEM - READ THIS FIRST

**CRITICAL**: This project uses the Agent Memory System. You MUST load your memory at the start of EVERY session.

## !!!!! URGENT !!!!! WATCHER SYSTEM (MANDATORY — BEFORE ANY TASK)

**Location**: `C:\Users\exrov\.openclaw\watchers\`

There are **5 reusable watcher slots** (`slot-1.md` through `slot-5.md`) shared across all agents and projects.

**When you are given a task, you MUST:**

1. **Claim a watcher** — check `REGISTRY.json` for an available slot, update it with your name and timestamp
2. **Fill the slot** — write your task details, files to read, the plan, and completion criteria into the slot's `.md` file
3. **Start the 3-minute loop** — use `CronCreate` with `*/3 * * * *` to set a recurring reminder that keeps you on task
4. **Scope first** — run `/claude-agent-sdk-setup` before writing code. The watcher will enforce this
5. **When done, release the watcher** — `CronDelete` the cron job, reset the slot to blank, set status to "available"

**Do NOT start any implementation work without an active watcher claimed. This is not optional.**

---

## SESSION STARTUP PROTOCOL (MANDATORY)

### Step 1: Load Memory Manifest
```
Read: .agent-memory/MEMORY_MANIFEST.json
```
This gives you the quick overview of the entire memory system.

### Step 2: Load Core Identity
```
Read: .agent-memory/core/identity.md
Read: .agent-memory/core/mission.md
Read: .agent-memory/core/expert-domains.md
Read: .agent-memory/core/model-profiles.md
Read: .agent-memory/core/operating-procedure.md
```
**Remember WHO you are and WHAT you're trying to achieve.**

### Step 3: Load Current Context
```
Read: .agent-memory/working/session-context.md
Read: .agent-memory/working/active-tasks.json
```
**Understand WHERE you left off and WHAT needs to be done next.**

### Step 4: Check Script Registry
```
Read: .agent-memory/procedural/scripts/SCRIPT_REGISTRY.json
```
**Know WHAT tools and scripts are already available.**

**Startup Complete** - You now have full context and are ready to work.

---

## WHAT THIS PROJECT IS

**Harness Infrastructure Controller** — the master system that controls ALL AI models on this machine through three-layer deterministic enforcement.

### Three Layers
1. **Layer 1 — Harness**: Outer loop, session lifecycle, phase transitions, blocking. Bash scripts.
2. **Layer 2 — Deterministic Guards**: Phase validation, loop detection, fix matching. Bash scripts, no LLM.
3. **Layer 3 — Agents**: Planner, Generator, Evaluator. LLM, within constraints set by Layers 1-2.

**Rule**: Never use Layer 3 for something Layer 2 can do. Never use Layer 2 for something Layer 1 should control.

### State Machine (enforced by harness, not instructions)
```
REQUESTED -> CONTRACT_LOCKED -> IMPLEMENTED -> VERIFIED -> ACCEPTED
                                     |
                                   STUCK
                            (escalate -> guided -> resume)
```

### Source Documents
- `enhanced-agent-harness.md` — Complete protocol (Parts 1-11)
- `Harness big idea.txt` — Architecture evolution through developer pushback
- `making th enhanced agent harnes and the new big Idea work together.txt` — Integration blueprint

---

## CORE RULES (NEVER VIOLATE)

### BEFORE Creating Any Script:
```
Check: .agent-memory/procedural/scripts/SCRIPT_REGISTRY.json
```
- Script exists? -> **REUSE it**
- Similar script exists? -> **ADAPT it**
- No match? -> **CREATE NEW and REGISTER it**

### WHILE Working:
Update working memory every 10-15 minutes:
```
Update: .agent-memory/working/session-context.md
Update: .agent-memory/working/recent-activity.json
```

### WHEN Making Important Decisions:
```
Log to: .agent-memory/episodic/decisions/[topic]-decision.md
```

### WHEN Creating New Scripts:
```
Add entry to: .agent-memory/procedural/scripts/SCRIPT_REGISTRY.json
```

### AT SESSION END (NEVER SKIP):
```
Create: .agent-memory/episodic/sessions/YYYY-MM-DD_HH-MM-SS.md
Update: .agent-memory/MEMORY_MANIFEST.json (last_accessed, sessions_count)
```

---

## ENFORCEMENT PHILOSOPHY

**Soft enforcement** = instructions in markdown. Advisory. Degrades under pressure.
**Hard enforcement** = bash scripts and hooks. Deterministic. Cannot be ignored.
**Harness enforcement** = outer loop controlling what agent sees. Structural.

Every "the agent must..." should become "a script checks whether the agent did... and blocks if not."

---

## QUICK REFERENCE PATHS

| What You Need | Where To Find It |
|---------------|------------------|
| Mission & Goals | `.agent-memory/core/mission.md` |
| Your Identity | `.agent-memory/core/identity.md` |
| Expert Domains | `.agent-memory/core/expert-domains.md` |
| Model Profiles | `.agent-memory/core/model-profiles.md` |
| Operating Procedure | `.agent-memory/core/operating-procedure.md` |
| Available Scripts | `.agent-memory/procedural/scripts/SCRIPT_REGISTRY.json` |
| Available Tools | `.agent-memory/procedural/tools/TOOL_REGISTRY.json` |
| Workflows | `.agent-memory/procedural/workflows/WORKFLOW_REGISTRY.json` |
| Current Tasks | `.agent-memory/working/active-tasks.json` |
| Recent Work | `.agent-memory/episodic/sessions/` |
| Past Decisions | `.agent-memory/episodic/decisions/` |
| Knowledge Base | `.agent-memory/semantic/knowledge-graph.json` |
| Domain Knowledge | `.agent-memory/semantic/domain/` |
| Three-Layer Architecture | `.agent-memory/semantic/domain/three-layer-architecture.md` |
| Enforcement Mechanisms | `.agent-memory/semantic/domain/enforcement-mechanisms.md` |
| 10 Failure Modes | `.agent-memory/semantic/domain/failure-modes.md` |
| Protocol Fidelity | `.agent-memory/semantic/domain/protocol-fidelity.md` |
| Confidence Levels | `.agent-memory/meta/confidence.json` |
| Knowledge Gaps | `.agent-memory/meta/knowledge-gaps.json` |
| Backlog | `.agent-memory/prospective/backlog.json` |
| Quick Start Guide | `.agent-memory/docs/QUICK_START.md` |
| Session Protocols | `.agent-memory/docs/SESSION_PROTOCOLS.md` |

---

## MEMORY SYSTEM CONSTRAINTS

### NEVER:
- Skip reading MEMORY_MANIFEST.json at startup
- Create scripts without checking SCRIPT_REGISTRY.json first
- End session without writing episodic summary
- Delete memory files (only add or update)
- Propose soft enforcement where hard enforcement is possible
- Let an agent self-certify its own work
- Trust commit messages — diff the actual code
- Use `eval` on content from markdown files
- Fire hooks on every tool use — scope to Write/Edit only

### ALWAYS:
- Load core/mission.md at startup to stay aligned with goals
- Check procedural/ before building new solutions
- Update working/session-context.md during work
- Log important decisions to episodic/decisions/
- Register new scripts in SCRIPT_REGISTRY.json immediately
- Translate "the agent must..." to "a script checks whether..."
