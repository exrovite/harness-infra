# Cognitive Guidance Layer — Product Spec

## Problem

Agents routinely hit gates, get blocked, and spend tokens figuring out what the harness wants. The turn packet (sprint 20) solved the *navigational* problem — agents now see what's blocked and what to do. But agents still struggle with:

1. **Vague plans** — PLAN phase produces weak specs because agents aren't told HOW to think about planning
2. **Permission paralysis or overreach** — agents either stop to ask about every decision or make scope-changing choices without checking, because they have no framework for autonomous judgment
3. **Uniform ceremony** — a one-line config change gets the same 5-phase treatment as a new system, wasting tokens and patience
4. **Infinite retry loops** — strategy loop breaker nudges and blocks but never forces terminal failure
5. **Soft verifiers** — evaluator sub-agents get the same instructions as builders, so they're too lenient
6. **No requirements check** — agents jump from user request to spec without verifying they understand the problem

## Solution

Add a **cognitive guidance layer** that injects phase-specific behavioral prompts into the turn packet. This shapes HOW agents think, not just WHAT gates they'll hit.

Three delivery areas:

### A. Phase-Specific Thinking Prompts

Inject 2-4 lines of phase-appropriate behavioral guidance into the turn packet. Different phases get different cognitive frames:

| Phase | Cognitive Frame |
|-------|----------------|
| PLAN | Outcome-first: define target result, success criteria, constraints, and stop condition BEFORE writing the spec. Ask clarifying questions if the request is ambiguous — don't assume. |
| NEGOTIATE | Skeptical reviewer: challenge your own proposal. What could go wrong? What's missing? What's vague? Tighten acceptance criteria until they're binary pass/fail. |
| BUILD | Executor mode: proceed automatically on clear, low-risk, reversible steps. ASK only for destructive, irreversible, or scope-changing decisions. Don't stop to ask "should I continue?" — continue. |
| EVALUATE | Adversarial verifier: your DEFAULT is FAIL. Every criterion must have fresh evidence. Do not read the builder's progress notes. Do not give benefit of the doubt. |
| COMPLETE | Structured handoff: name the outcome (finished/blocked/failed), evidence, and what the user should check. No "would you like me to..." softeners. |

### B. Task Size Detection + Protocol Adaptation

Before the first phase, detect task size from the user's request and watcher scope:

| Size | Detection | Protocol |
|------|-----------|----------|
| **Trivial** | Single file, config change, typo, rename | LIGHTWEIGHT: implement → test → verify inline. No contract, no sub-agent verifier. |
| **Standard** | Multi-file, single feature, bug fix | STANDARD: full PLAN→NEGOTIATE→BUILD→EVALUATE→COMPLETE |
| **Large** | Multi-feature, new system, cross-cutting | FULL: same as standard but with mandatory PRD artifact, test spec artifact, and evidence checkpoints |

Size detection is advisory (injected as guidance), not a gate. The user can override.

### C. Fix Attempt Hard Ceiling

Add `max_fix_attempts` to the strategy loop state. After N consecutive fix cycles on the same problem (default: 3), force terminal failure instead of another nudge:

- Tier 1: Nudge (existing)
- Tier 2: Block requiring new strategy (existing)
- Tier 3 (NEW): Terminal failure — write STUCK state, release watcher, tell user

## What Success Looks Like

- Agent entering PLAN phase sees "define target result and success criteria BEFORE writing spec"
- Agent entering BUILD sees "proceed automatically on clear, low-risk steps"
- Evaluator sub-agent sees "your default is FAIL; every criterion needs evidence"
- Trivial task doesn't trigger 5-phase ceremony
- Agent stuck 3+ times on same problem STOPS and escalates
- Turn packet stays under budget (2000 chars worst-case realistic, hard cap raised from 1490)

## Design Constraints

1. Guidance injection lives in `on-prompt-submit.sh` — no new hook scripts
2. Task size detection reads watcher slot + user prompt context — no new state files
3. Fix ceiling lives in strategy loop breaker state — extends existing `strategy-loop-state.json`
4. Gates are UNCHANGED — guidance shapes behavior; gates remain safety nets
5. Phase-specific prompts are 2-4 lines max — not paragraphs
