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

### Capability 2: Context Snapshot Before Work

Before any BUILD work begins, the agent explores the target codebase and writes a grounded context snapshot.

### Capability 3: Agent Decomposition via Sub-Agents (Same Model)

Focused sub-agents: Planner, Critic, Executor, Verifier. Same model, different role prompts.

### Capability 4: Verification With Actionable Feedback

Replace binary PASS/FAIL with structured feedback including exact error output.

### Capability 5: Planning Consensus (Adversarial Review)

Adversarial sub-agent review during NEGOTIATE. Critic challenges specs.

### Capability 6: Parallel Sub-Agent Dispatch

Independent sub-agents fire simultaneously.

## What We Are NOT Building

- No model routing — same model everywhere
- No MCP state server — file-based state continues
- No Node.js hook rewrite — bash hooks stay

## Success Criteria

The compound reliability system is successful when:
1. BUILD phase uses an iteration loop that retries with real test feedback
2. A context snapshot exists before implementation starts
3. Planner/Critic/Executor/Verifier roles run as independent sub-agents
4. Verification feedback includes exact error output, not just PASS/FAIL
5. NEGOTIATE uses adversarial critic review, not self-review
6. Independent sub-agent tasks can fire in parallel
7. All existing enforcement gates continue to function unchanged
