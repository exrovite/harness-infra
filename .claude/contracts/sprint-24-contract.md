# Sprint 24 Contract: Co-Pilot Research Document

**Status**: LOCKED
**Locked at**: 2026-05-23

## Objective
Write a comprehensive research document that a developer can use to build a co-pilot system for monitoring and correcting Claude Code agent drift.

## Deliverables
1. `docs/co-pilot-claude/research-findings.md` — the research document

## What Will Be Built
A single markdown document containing:
- Problem statement
- Technical feasibility analysis (interactive TUI limitation, what works/doesn't)
- 4 architecture patterns (Stream-JSON, tmux Monitor, Agent SDK, Hooks-based)
- Each pattern with: how it works, architecture diagram/pseudocode, pros, cons, setup complexity, platform support
- Comparison matrix table
- Phased recommendation (build order)
- CLI flags and commands reference
- Drift rule format suggestion
- Open questions for developer
- All sources with URLs

## What Will NOT Be Built
- No scripts, no code changes, no harness modifications
- No actual co-pilot implementation
- No changes to existing hooks or settings

## Acceptance Criteria (8)
- AC1: Document exists at `docs/co-pilot-claude/research-findings.md`
- AC2: At least 4 architecture patterns documented with distinct approaches
- AC3: Each pattern has: how it works, pros, cons, setup complexity, platform support
- AC4: Comparison matrix (table) covering all patterns side-by-side
- AC5: Phased recommendation (what to build first/second/third)
- AC6: CLI flags and commands are accurate and complete
- AC7: All sources cited with URLs
- AC8: Committed to git

## Verification Method
Independent sub-agent reads the document and checks each AC against the content.
