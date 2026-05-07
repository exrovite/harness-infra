# Evaluation Criteria — Compound Reliability System (Sprint 22+)

## Scope Note

This is a multi-sprint effort. Sprint 22 will scope a deliverable subset. These criteria cover the full vision — the sprint contract will select which criteria apply to sprint 22.

## C1: Iteration Loop

- C1.1: BUILD phase wraps feature implementation in a retry loop
- C1.2: Loop runs project tests after each implementation attempt
- C1.3: Test stdout/stderr is captured verbatim
- C1.4: On failure, exact error output is fed back to the next attempt
- C1.5: Loop exits on test pass
- C1.6: Loop has a hard max iteration cap (configurable, default 5)
- C1.7: Hitting max iterations triggers STUCK escalation
- C1.8: Iteration count is tracked in harness state

## C2: Context Snapshot

- C2.1: Before BUILD implementation, agent explores target codebase
- C2.2: Snapshot captures: relevant files, patterns, test structure, dependencies
- C2.3: Snapshot is written to a known location in harness state
- C2.4: Snapshot is size-bounded (summary, not full file dumps)
- C2.5: Executor sub-agent receives snapshot as input context

## C3: Agent Decomposition

- C3.1: Planner role runs as independent sub-agent during PLAN
- C3.2: Critic role runs as independent sub-agent during NEGOTIATE
- C3.3: Executor role runs as independent sub-agent during BUILD
- C3.4: Verifier role runs as independent sub-agent during EVALUATE
- C3.5: Each sub-agent gets a focused role prompt (not the full harness prompt)
- C3.6: Sub-agents use the same model as the parent (no model routing)
- C3.7: Sub-agents cannot see each other's internal reasoning

## C4: Actionable Verification Feedback

- C4.1: Verifier returns specific file paths and line numbers on failure
- C4.2: Verifier includes verbatim error messages from test output
- C4.3: Verifier states what was expected vs what was found
- C4.4: Feedback is structured enough to act on without re-investigation
- C4.5: phase-feedback.md includes actionable detail, not just PASS/FAIL

## C5: Planning Consensus

- C5.1: NEGOTIATE spawns a critic sub-agent to review the proposal
- C5.2: Critic's job is to find gaps (adversarial, not rubber-stamp)
- C5.3: Max 5 revision rounds between planner and critic
- C5.4: Contract is written only after critic approves
- C5.5: If 5 rounds exhausted without approval, escalate to user

## C6: Parallel Dispatch

- C6.1: Independent sub-agent tasks are dispatched simultaneously
- C6.2: Dependent tasks remain sequential
- C6.3: Parallel dispatch uses existing Agent tool with multiple calls
- C6.4: Results are collected and integrated by the parent agent

## C7: Backward Compatibility

- C7.1: All existing hooks (pre-write-gate, pre-bash-gate, pre-flight-gate) unchanged
- C7.2: Phase validation (validate-phase.sh) unchanged
- C7.3: Evidence checkpoint system unchanged
- C7.4: Must-do enforcement unchanged
- C7.5: Watcher system unchanged
- C7.6: MCQ gate unchanged
