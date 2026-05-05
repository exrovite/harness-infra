# Agent Mission

## Primary Objective
Deploy and enforce the Enhanced Agent Harness across ALL AI models on Adewale's machine, ensuring every model operates under deterministic three-layer control with state machine discipline, builder/verifier separation, evidence-first verification, and automatic escalation.

## The Problem This Solves
AI agents fall off the loop. They skip steps, lose track of protocols, drift from plans, declare victory early, spin in circles on the same error, and go silent when stuck. The root causes are:

### 10 Fundamental Failure Modes

| # | Failure Mode | Category | Fix |
|---|-------------|----------|-----|
| 1 | **Context Window Saturation** | Context | Progressive disclosure, phase-specific instruction loading |
| 2 | **No External State Tracking** | Architecture | File-driven state machine, current-phase.json |
| 3 | **No Phase Isolation** | Architecture | Explicit gates, harness-controlled transitions |
| 4 | **No Verification Gate** | Quality | Builder/verifier separation, 7-layer protocol |
| 5 | **No Deterministic Operations** | Efficiency | Push everything scriptable to bash |
| 6 | **Context Anxiety** | Behavioral | Clean context resets at phase boundaries (distinct from saturation) |
| 7 | **Self-Evaluation Bias** | Quality | Structurally separate evaluator with own context |
| 8 | **One-Shotting** | Planning | Sprint contracts negotiated per feature |
| 9 | **Compaction vs Clean Reset** | Context | Handoff artifacts at sprint boundaries |
| 10 | **Speculative Planning Cascades** | Planning | Planner stays high-level, no implementation detail |

## The Solution: Three-Layer Deterministic Control

### Layer 1 — The Harness (deterministic, outside the LLM)
- Controls session lifecycle: start, stop, restart, context reset
- Manages phase transitions via hooks and validation scripts
- Decides what the agent sees (loads active-instructions.md)
- Blocks progression when validation fails
- Handles Telegram/WhatsApp communication including response path
- Runs the Ralph-style outer loop
- Budget/time circuit breaker
- Crash recovery and startup routine
- Concurrency protection (lockfile)

### Layer 2 — Deterministic Guards (scripts, no LLM)
- Phase validation (file existence, required sections, line counts)
- Loop detection (git history analysis)
- Known-fix matching (symptom grep against registry)
- Test execution (test suite, linting, type checking)
- Protocol compliance checks (all binary pass/fail)
- Fix verification (structured checks, no eval)

### Layer 3 — The Agents (LLM, within constraints set by Layers 1-2)
- Planner: expands brief into high-level spec
- Generator: implements features, writes code
- Evaluator: judges quality, usability, architecture (genuine judgment calls only)

## Global vs Per-Project Split

### Built Once in `~/.claude/` (global, works everywhere)
- `settings.json` — Hook registrations (scoped to Write/Edit)
- `scripts/` — All 15 harness scripts
- `agents/` — Planner, Generator, Evaluator definitions
- `hooks/` — Post-write-check, pre-phase-start, on-stuck-detected

### Created Per Project via `init-project.sh`
- `.claude/CLAUDE.md` — Minimal, points to active-instructions.md
- `.claude/state/` — Phase tracking, progress, handoffs
- `.claude/specs/` — Planner output per project
- `.claude/contracts/` — Sprint contracts per feature
- `.claude/protocols/known-fixes.md` — Project-specific fixes

### OR: `.agent-memory/` System (for memory-equipped agents)
- `.agent-memory/core/operating-procedure.md` contains the full enhanced harness
- `.agent-memory/` replaces the thinner `.claude/state/` directory
- CLAUDE.md stays minimal, pointing to `.agent-memory/`

## State Machine (enforced by harness, not by instructions)

```
REQUESTED -> CONTRACT_LOCKED -> IMPLEMENTED -> VERIFIED -> ACCEPTED
                                     |
                                   STUCK
                            (escalate -> guided -> resume)
```

- Builder can ONLY move to IMPLEMENTED — never VERIFIED or ACCEPTED
- States CANNOT be skipped — harness validates each transition
- "Done" is COMPUTED from evidence, not typed by the agent
- STUCK triggers after 3 same errors or 5 minutes no progress
- STUCK = STOP working, send facts not theories, wait for guidance

## Strategic Goals

Detailed implementation priorities with dependencies are tracked in `prospective/backlog.json`.

### Immediate
- Complete the .agent-memory system for this project
- Document all 15 harness scripts in the script registry
- Capture the full three-layer architecture in the knowledge graph

### Short-term
- Build the global `~/.claude/` infrastructure (scripts, hooks, agents)
- Create `init-project.sh` for per-project setup
- Test the harness on a real project end-to-end

### Medium-term
- Deploy harness across all 17 managed AI systems
- Calibrate the evaluator agent for scepticism
- Build the Telegram/WhatsApp bridge (optional, not structural)

### Long-term
- Every model on the machine follows the same discipline
- Known-fixes registry grows with each project
- Harness evolves with model capabilities — stress-test which pieces are load-bearing

## Success Criteria
1. **No agent self-certifies** — builder never moves past IMPLEMENTED
2. **No soft enforcement** where hard enforcement is possible
3. **Every verdict cites evidence** — no "it looks fine"
4. **Loop detection blocks execution** — doesn't just advise
5. **Phase transitions are harness-controlled** — agent writes marker, harness validates
6. **Context resets at sprint boundaries** — fresh sessions with rich handoff artifacts
7. **Known fixes are injected** by scripts, not searched by agents
8. **All models have documented failure taxonomies** with compensations

## Anti-Goals
- Don't over-specify plans (causes cascading errors)
- Don't use Telegram as structural dependency (it's optional transport)
- Don't fire hooks on every tool use (scope to Write/Edit)
- Don't trust commit messages for verification (diff the code)
- Don't use `eval` on markdown content (structured verification format instead)
- Don't skip the harness for "small" changes (use Lightweight protocol level instead)
