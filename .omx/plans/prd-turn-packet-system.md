# PRD: Sprint 20 Turn Packet System

## Problem
The harness currently teaches agents by blocking them after invalid actions. Multiple independent gates create costly trial-and-error, token waste, and occasional deadlocks.

## Goal
Convert on-prompt-submit.sh into a turn packet assembler that presents the current harness state, ordered required actions, hard blockers, exempt paths, and current watcher step before the agent acts.

## Non-goals
- No gate script behavior changes.
- No new gates or gate removals.
- No multi-model or notification bridge work.

## Requirements
1. Preserve a concise state summary for every prompt.
2. Show an ordered action queue only when setup work is required.
3. Represent hard blockers separately from soft setup actions.
4. Preserve evidence checkpoint sub-state guidance.
5. Preserve strategy loop tier-1 nudge vs tier-2 block semantics.
6. Show exempt paths only when tools are locked.
7. Show watcher current step/scope/mistakes when project watcher is active.
8. Keep unblocked output under 200 chars and fully loaded packet under 1500 chars.
9. Keep packet assembly fast and local-only.
10. Leave pre-write, pre-bash, and pre-flight gates untouched.

## Acceptance source
Derived from .claude/contracts/sprint-20-contract.md and validated against ig -harness-fix.md.
