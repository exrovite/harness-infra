# Cognitive Guidance Layer (Sprint 21)

## The Problem: Gates Block, But Don't Guide

After 20 sprints of harness development, we built a strong gate system: pre-flight MCQ challenges, phase-feedback blocks, evidence checkpoints, strategy loop breakers, watcher enforcement, contract gates, must-do enforcement, and the turn packet cockpit. These gates are effective at *blocking wrong actions*.

But agents still struggle to tow the line. They hit gates, get blocked, spend tokens figuring out what the harness wants, and then comply minimally. The gates tell agents what they *can't* do, but never teach them *how to think*.

This was confirmed by a deep study of oh-my-codex (OMX), an open-source Codex CLI workflow layer. OMX invests heavily in **cognitive shaping** — injecting role-specific behavioral prompts that frame how the agent approaches each phase of work. Their agents don't just follow a state machine; they adopt different *thinking modes* depending on their role.

## What We Learned From OMX

We studied 30+ source files across OMX's architecture and identified 13 capability gaps. The most impactful ones:

1. **No requirements clarification step** — OMX has `$deep-interview` with input-lock that prevents agents from rubber-stamping assumptions. Our agents jump straight to PLAN.
2. **No role-specific behavioral constraints** — OMX injects different prompts for planners ("outcome-first"), executors ("auto-continue on safe steps"), and verifiers ("evidence-dense verdicts, default FAIL"). Our agents get identical instructions in every phase.
3. **No auto-continue vs ask framework** — OMX teaches agents when to proceed autonomously vs when to ask. Our gates are binary (blocked or allowed) with no decision heuristics.
4. **No task size adaptation** — OMX auto-classifies tasks as narrow/medium/broad and adjusts ceremony. Our harness applies the same 5-phase protocol to config changes and new systems.
5. **No fix loop hard ceiling** — OMX's team orchestrator terminates after `max_fix_attempts: 3`. Our strategy loop breaker nudges and blocks but never forces terminal failure.

The core insight: **our harness is strong on enforcement but weak on guidance**. Gates are safety nets. Guidance shapes the path so gates rarely fire.

## What We Built

### D1: Phase-Specific Cognitive Prompts

A `GUIDANCE:` line injected into every turn packet, immediately after the state summary. Each phase gets a different cognitive frame:

| Phase | Frame | Purpose |
|-------|-------|---------|
| PLAN | Outcome-first: define result, criteria, constraints, stop condition BEFORE spec | Prevents vague specs by forcing structure |
| NEGOTIATE | Skeptical reviewer: challenge your proposal, binary pass/fail criteria | Prevents weak contracts by forcing self-criticism |
| BUILD | Executor: proceed on safe steps, ASK only for destructive/irreversible/scope-changing | Prevents permission paralysis and over-asking |
| EVALUATE | Adversarial verifier: default FAIL, fresh evidence only, no benefit of doubt | Prevents rubber-stamp verification |
| COMPLETE | Structured handoff: name outcome, list evidence, no softeners | Prevents vague completion reports |

Each line is static (case statement lookup), under 160 chars, zero computation overhead.

### D2: Task Size Advisory

Reads the watcher SCOPE field and injects a `PROTOCOL:` hint when the task clearly fits LIGHTWEIGHT or FULL:

- **LIGHTWEIGHT** (config, typo, rename, single file): skip contract, skip sub-agent verifier, implement-test-verify inline
- **FULL** (new system, architecture, migration): require PRD artifact and test spec before BUILD
- **STANDARD** (default): nothing injected, zero overhead

This is advisory — not a gate. It prevents trivial tasks from drowning in ceremony and ensures large tasks get proper planning artifacts.

### D3: Fix Attempt Hard Ceiling

Extends `strategy-loop-state.json` with `fix_cycle_count`, `max_fix_cycles`, and `last_sprint`:

- Each time an agent clears a tier-2 strategy loop block (writes strategy-ack.md after being blocked), `fix_cycle_count` increments
- When `fix_cycle_count >= max_fix_cycles` (default 3): terminal STUCK block fires
- Agent must write `stuck-report.md` and WAIT for user — no soft action clears this
- Sprint advance resets the counter to 0
- `max_fix_cycles` is configurable per project via the state file

This closes the gap where agents could infinitely retry with "new strategies" that were just rephrased versions of the same approach.

### D4: Verifier Prompt Injection

During EVALUATE phase, injects a `VERIFIER RULES:` section with 4 hard constraints:

1. Do NOT read builder's progress-notes.md
2. Test from scratch using sprint contract criteria only
3. Default verdict is FAIL — pass requires positive evidence for every criterion
4. Report format: criterion number, pass/fail, evidence snippet

This transforms soft "please verify" sub-agents into adversarial evaluators with a structured output contract.

## Why This Matters

The harness enforcement stack now has two complementary layers:

**Layer A — Gates (sprints 1-20)**: Deterministic scripts that block wrong actions. Phase gates, contract gates, MCQ challenges, evidence checkpoints, strategy loop breakers. These fire when the agent does something wrong.

**Layer B — Cognitive Guidance (sprint 21)**: Behavioral prompts that shape how the agent thinks before it acts. Phase-specific frames, decision heuristics, task sizing. These reduce how often gates need to fire.

The goal: gates become true safety nets that rarely activate, because the agent already knows the correct path.

## Verification

- 33 acceptance criteria, all PASS
- Independent verifier (Opus sub-agent) approved with per-criterion evidence
- Syntax checks pass on all changed files
- Gate scripts confirmed untouched (zero diff)
- Packet size budgets: worst-case 1183 chars (budget: 2000), BUILD steady-state 524 chars (budget: 700)

## Files Changed

| File | Change |
|------|--------|
| `~/.claude/hooks/on-prompt-submit.sh` | Phase guidance, task size advisory, fix ceiling, verifier injection, hard cap raised to 2000 |
| `~/.claude/state/strategy-loop-state.json` | New fields: fix_cycle_count, max_fix_cycles, last_sprint |

## Files NOT Changed

| File | Reason |
|------|--------|
| `pre-write-gate.sh` | Gates are safety nets, not in scope |
| `pre-bash-gate.sh` | Gates are safety nets, not in scope |
| `pre-flight-gate.sh` | Gates are safety nets, not in scope |
| `lib-helpers.sh` | No new helpers needed |

## Future Work (Identified From OMX Study, Not Yet Built)

- **Requirements clarification hard gate** — `$deep-interview` equivalent with input-lock
- **PRD + test spec as hard gates** for FULL protocol tasks
- **Worker scope boundaries** — restrict sub-agent file access to assigned slice
- **Idle detection / active nudging** — detect stalled agents and send targeted prods
- **Specialist routing** — route research/explore/dependency tasks to specialized sub-agents
- **Commit quality protocol** — structured decision-record commit messages
