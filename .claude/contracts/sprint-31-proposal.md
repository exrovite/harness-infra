# Sprint 31 Proposal — Multilane Workers

## What I will build
Concurrent multi-instance support: up to 5 Claude Code instances per project folder,
each with isolated harness state and correct, self-only situational awareness, keyed
by session_id. Per the locked spec (.claude/specs/multilane-workers-spec.md).

## Build order (probe-gated)
1. session_id probe (AC1) — confirm session_id per event + sub-agent behavior. GATE.
2. resolve_instance chokepoint + registry v2 + claim/release/cap (lib-helpers).
3. Wire every hook to resolve_instance; namespace all state by lane (lane 1 = flat).
4. Awareness layer: lane-stamped turn packet, block messages, pre-flight, claim briefing.
5. Shared-codebase advisory (lane-activity log + warning injection).
6. Migration v1->v2; backward-compat; docs.

## Skeptical self-review
- "session_id might be absent" -> AC1 probe gates everything; env-var fallback path.
- "sub-agent burns a lane / writes wrong namespace" -> lazy claim only at UserPromptSubmit;
  sub-agent handling finalized by probe; release keyed by session cannot touch parent.
- "two same-folder instances both grab lane 1" -> claim under mkdir-lock; identical cwd
  groups them; lock serializes -> distinct lanes. Tested (T3).
- "a lane sees another lane's context (a surprise)" -> single resolve_instance chokepoint;
  dedicated awareness ACs + an independent verifier that ACTIVELY tries to cross-contaminate.
- "huge blast radius across ~10 hooks" -> lane 1 = flat means zero change for single
  instances; every test runs single-instance regression first.
- "memory interleave" -> hot working files per-lane; shared knowledge stays shared.
- "silent code clobber" -> advisory warning injection, visible + reminded, never blocking.

## Verification
Independent sub-agent runs the functional TDD in a REAL multi-lane sandbox (2-3 live
session_ids driving the real hooks), confirms isolation + awareness, and specifically
attempts to make one lane observe another's phase/contract/must-do and confirms it cannot.
