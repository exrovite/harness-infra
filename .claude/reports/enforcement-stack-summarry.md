  What We've Built: 14-Layer Enforcement Stack                                             
                                                                                                                       
  A fully deterministic control system that blocks AI agent tool calls at the platform level. No soft enforcement —      every layer is bash scripts firing on Claude Code hooks, rejecting Write/Edit/Bash calls with exit code 2 before they
   reach the filesystem.                                                                                                                                                                 
  The Stack (in execution order)

  ┌─────┬──────────────────┬───────────────────────────────────────────────────────────────────────────────────────┐
  │  #  │      Layer       │                                     What It Does                                      │
  ├─────┼──────────────────┼───────────────────────────────────────────────────────────────────────────────────────┤
  │ 1   │ Phase Gate       │ Only BUILD allows code writes. PLAN/NEGOTIATE/EVALUATE/COMPLETE all blocked.          │
  ├─────┼──────────────────┼───────────────────────────────────────────────────────────────────────────────────────┤
  │ 2   │ Contract Gate    │ BUILD requires sprint-specific contract. Prevents scope drift.                        │
  ├─────┼──────────────────┼───────────────────────────────────────────────────────────────────────────────────────┤
  │ 3   │ Strategy Loop    │ 3-signal detection (same error, consecutive failures, same file churn). Nudge → block │
  │     │ Breaker          │  → requires written new approach.                                                     │
  ├─────┼──────────────────┼───────────────────────────────────────────────────────────────────────────────────────┤
  │ 4   │ Must-Do Summary  │ Must read process docs + write comprehension summary before any code.                 │
  │     │ Gate             │                                                                                       │
  ├─────┼──────────────────┼───────────────────────────────────────────────────────────────────────────────────────┤
  │ 5   │ Evidence         │ Every N writes, harness assembles verifier brief from source docs (not agent's        │
  │     │ Checkpoint       │ summary). Builder can't filter what verifier sees.                                    │
  ├─────┼──────────────────┼───────────────────────────────────────────────────────────────────────────────────────┤
  │ 6   │ Pre-Flight MCQ   │ Quiz derived from watcher slot. Must answer correctly per-write.                      │
  │     │ Gate             │                                                                                       │
  ├─────┼──────────────────┼───────────────────────────────────────────────────────────────────────────────────────┤
  │ 7   │ Bash Bypass Gate │ Detects file-writing patterns in shell commands (python -c, tee, sed -i, heredocs,    │
  │     │                  │ cp/mv). Same enforcement as Write/Edit.                                               │
  ├─────┼──────────────────┼───────────────────────────────────────────────────────────────────────────────────────┤
  │ 8   │ Watcher/Cron     │ After 2 free writes, locked until watcher claimed + 3-min cron running.               │
  │     │ Gate             │                                                                                       │
  ├─────┼──────────────────┼───────────────────────────────────────────────────────────────────────────────────────┤
  │ 9   │ Phase Validation │ When agent declares phase complete, harness validates requirements actually met.      │
  ├─────┼──────────────────┼───────────────────────────────────────────────────────────────────────────────────────┤
  │ 10  │ TDD Enforcement  │ Detects phantom TDD — claims of test-first that aren't.                               │
  ├─────┼──────────────────┼───────────────────────────────────────────────────────────────────────────────────────┤
  │ 11  │ Prompt Injection │ State + obligations injected every turn. Sub-agents see it too.                       │
  ├─────┼──────────────────┼───────────────────────────────────────────────────────────────────────────────────────┤
  │ 12  │ Session          │ Startup recovery (stale cleanup), session end (summaries, handoffs).                  │
  │     │ Lifecycle        │                                                                                       │
  ├─────┼──────────────────┼───────────────────────────────────────────────────────────────────────────────────────┤
  │ 13  │ File Write       │ Audit trail to unverified-writes.jsonl.                                               │
  │     │ Tracking         │                                                                                       │
  ├─────┼──────────────────┼───────────────────────────────────────────────────────────────────────────────────────┤
  │ 14  │ Agent Call       │ Tracks sub-agent spawns, resets verification debt on actual verification calls.       │
  │     │ Tracking         │                                                                                       │
  └─────┴──────────────────┴───────────────────────────────────────────────────────────────────────────────────────┘

  Key Design Principles

  - Hard over soft: exit codes, not markdown instructions
  - Builder/verifier separation: harness controls what the verifier sees
  - Bootstrap safety: infrastructure paths always writable (prevent catch-22)
  - Zero impact without opt-in: must-do, evidence checkpoints, TDD only activate when configured
  - Project-scoped: watchers and enforcement match project paths

  Sprints 3 through 18 have been shipped. We're at Sprint 19, BUILD phase, iteration 0.