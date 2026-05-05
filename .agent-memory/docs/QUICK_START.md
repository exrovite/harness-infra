# Quick Start — Harness Infrastructure Controller

## What Is This?
The master system that controls ALL AI models on this machine through three-layer deterministic enforcement. It ensures every model follows the Enhanced Agent Harness protocol: state machine discipline, builder/verifier separation, evidence-first verification, and automatic escalation.

## Session Startup (Every Time)
1. Read `MEMORY_MANIFEST.json`
2. Read `core/identity.md` and `core/mission.md`
3. Read `working/session-context.md`
4. Read `procedural/scripts/SCRIPT_REGISTRY.json`

## Key Concepts

### Three Layers
- **Layer 1 (Harness)**: Outer loop, controls everything. 10 scripts.
- **Layer 2 (Guards)**: Deterministic checks. 5 scripts. No LLM.
- **Layer 3 (Agents)**: Planner, Generator, Evaluator. LLM within constraints.

### State Machine
```
REQUESTED -> CONTRACT_LOCKED -> IMPLEMENTED -> VERIFIED -> ACCEPTED
```

### Enforcement Rule
Every "the agent must..." becomes "a script checks whether the agent did."

## Current Status
- Architecture: COMPLETE (fully designed through developer pushback)
- Scripts: SPECIFIED but NOT BUILT (0/15 implemented)
- Testing: NOT STARTED

## What To Do Next
Check `prospective/backlog.json` for the prioritised work queue.
