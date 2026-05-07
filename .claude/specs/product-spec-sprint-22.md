# Product Spec: Compound Reliability System (Sprint 22+)

## Problem Statement

The harness enforces process compliance (phase gates, pre-flight MCQ, write blocking) but does not enable the conditions that produce working code. Analysis of oh-my-codex (OMX) reveals that 90% working-code rates come from compound reliability — iteration loops, agent decomposition, codebase context grounding, and actionable verification feedback — not from enforcement alone.

The same model (GPT-5.4, Claude Opus) produces dramatically better results under OMX's structural patterns than under raw invocation. The quality gain comes from focused context per agent, retry-with-feedback loops, and adversarial planning review — not from model routing or cheaper models.

## What We're Building

A compound reliability layer that sits INSIDE our existing enforcement framework. The gates stay. We add a drivetrain between them.

### Capability 1: Iteration Loop with Real Feedback

During BUILD phase, the agent enters a persist-until-done loop:
- Execute one feature/fix
- Run tests, capture ACTUAL stdout/stderr
- If tests fail: feed the exact error output back, re-enter execution
- If tests pass: proceed to next feature
- Max N iterations before STUCK escalation

Current behavior: build → evaluate → binary PASS/FAIL → retry blind.
New behavior: build → test → read error → fix → test → pass → evaluate.

The evaluator receives a working result instead of being the first time anyone runs the code.

### Capability 2: Context Snapshot Before Work

Before any BUILD work begins, the agent (or a sub-agent) explores the target codebase and writes a grounded context snapshot:
- Relevant files and their purposes
- Existing patterns and conventions
- Test structure and runner
- Dependencies and API shapes

This snapshot is injected into the executor's context so it works from facts, not assumptions.

### Capability 3: Agent Decomposition via Sub-Agents (Same Model)

Replace the single-agent-does-everything pattern with focused sub-agents:

| Role | Responsibility | Boundary |
|------|---------------|----------|
| Planner | Writes spec from codebase exploration | Never writes code |
| Critic | Challenges specs and plans adversarially | Never writes specs or code |
| Executor | Implements one focused task | Never plans or reviews itself |
| Verifier | Reads code + test output, returns specific verdicts | Never implements fixes |

All roles use the SAME model. Separation comes from focused prompts and clean context windows, not model differences.

### Capability 4: Verification With Actionable Feedback

Replace binary PASS/FAIL with structured feedback:
- Exact test output (stdout/stderr)
- Specific files and lines that failed
- Error messages verbatim
- What the verifier expected vs what it found

The agent receiving feedback can act on it immediately instead of guessing what went wrong.

### Capability 5: Planning Consensus (Adversarial Review)

During NEGOTIATE phase, replace self-review with adversarial sub-agent review:
- Planner sub-agent drafts the contract/spec
- Critic sub-agent challenges it (its job is to find gaps)
- Max 5 rounds of revision before escalating to user
- Contract is approved only when the critic passes it

### Capability 6: Parallel Sub-Agent Dispatch

When multiple independent tasks exist, dispatch sub-agents simultaneously rather than sequentially. This applies to:
- Independent feature implementations during BUILD
- Parallel exploration during context snapshot
- Simultaneous test + lint + build verification

## What We Are NOT Building

- No model routing (no cheap/expensive model tiers — same model everywhere)
- No MCP state server (file-based state continues to work)
- No Node.js hook rewrite (bash hooks stay)
- No changes to existing gates (pre-flight, must-do, evidence checkpoints all stay)
- No OMX dependency (this is native to our harness)

## Constraints

- Must work with Claude (Opus/Sonnet) and any model that supports the Agent tool
- Must not break any existing enforcement (gates, hooks, phase validation)
- Sub-agents must still pass through our existing Write/Edit hooks
- Iteration loop must have a hard cap to prevent infinite retry
- Context snapshot must not bloat the context window (summarize, don't dump)

## Success Criteria

The compound reliability system is successful when:
1. BUILD phase uses an iteration loop that retries with real test feedback
2. A context snapshot exists before implementation starts
3. Planner/Critic/Executor/Verifier roles run as independent sub-agents
4. Verification feedback includes exact error output, not just PASS/FAIL
5. NEGOTIATE uses adversarial critic review, not self-review
6. Independent sub-agent tasks can fire in parallel
7. All existing enforcement gates continue to function unchanged
