# PRD: Sprint 21 Cognitive Guidance Layer

## Outcome
Agents receive compact, phase-appropriate behavioral guidance in each turn packet, plus task-size protocol hints, verifier rules during EVALUATE, and a terminal STUCK block after too many strategy fix cycles.

## Scope
- Modify `C:/Users/exrov/.claude/hooks/on-prompt-submit.sh`.
- Do not modify gate scripts.
- Keep `lib-helpers.sh` existing behavior unchanged; avoid changes unless strictly additive.

## Requirements
- Inject static GUIDANCE lines for PLAN, NEGOTIATE, BUILD, EVALUATE, COMPLETE only.
- Inject LIGHTWEIGHT/FULL protocol hints from watcher SCOPE keyword matches; STANDARD injects nothing.
- Track `fix_cycle_count`, `max_fix_cycles`, and `last_sprint` in `.claude/state/strategy-loop-state.json`.
- Increment fix cycles when a prior blocked state is observed with `.claude/state/strategy-ack.md` present.
- Reset fix cycles when sprint changes.
- Inject terminal STUCK hard block when `fix_cycle_count >= max_fix_cycles`.
- Inject VERIFIER RULES only during EVALUATE.
- Raise packet cap to 2000.

## Non-goals
- No gate script changes.
- No new gates.
- No hard enforcement for PRD/test spec advisory.
