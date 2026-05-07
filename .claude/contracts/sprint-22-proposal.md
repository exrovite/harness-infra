# Sprint 22 Proposal: Compound Reliability Foundations

## Sprint Scope

Sprint 22 delivers the **foundations**: role prompts, iteration loop, context snapshot, and structured feedback. These are the highest-impact capabilities and the prerequisites for everything else (adversarial planning consensus, parallel dispatch come in sprint 23+).

## Why This Ordering

| Capability | Impact | Dependency |
|-----------|--------|------------|
| Iteration loop with real feedback | Highest — turns one-shot into retry-with-feedback | Needs role prompts for executor |
| Role prompts | Foundation — everything else uses them | None |
| Structured feedback | High — makes iteration loop effective | Needs iteration loop |
| Context snapshot | High — grounds implementation in facts | Needs role prompts for explorer |
| Adversarial planning (sprint 23) | Medium — improves specs before build | Needs role prompts for critic |
| Parallel dispatch (sprint 23) | Medium — speeds up independent work | Needs role prompts |

## Deliverables

### D1: Role Prompt Files

Create focused role prompts at `.claude/roles/`:

- `planner.md` — Explores codebase, writes specs. Never writes code.
- `critic.md` — Challenges specs/plans adversarially. Never writes specs or code.
- `executor.md` — Implements one focused task. Never plans or reviews itself.
- `verifier.md` — Reads code + test output, returns structured verdicts. Never implements.
- `explorer.md` — Reads target codebase, produces context snapshot. Read-only.

Each prompt is self-contained: identity, constraints, what it does, what it does NOT do, output format. ~50-80 lines each. These are NOT copies of OMX prompts — they're tuned for our harness and Claude models.

### D2: Iteration Loop State + Tracking

New state file: `.claude/state/build-iteration.json`
```json
{
  "feature": "description of current feature",
  "iteration": 0,
  "max_iterations": 5,
  "last_test_output": "verbatim stderr/stdout from last run",
  "last_test_exit_code": 0,
  "status": "running|passed|stuck"
}
```

### D3: Turn Packet Enhancement — BUILD Iteration Guidance

Modify `on-prompt-submit.sh` to inject iteration loop guidance during BUILD phase:

- **On entering BUILD**: instruct agent to spawn executor sub-agent with role prompt, run tests after each change, capture output to build-iteration.json
- **On test failure**: inject the exact error output and instruct retry (not blind retry)
- **On max iterations**: inject STUCK escalation instruction
- **On test pass**: inject "proceed to next feature" instruction

This is guidance in the turn packet, not a new gate. The existing gates continue to enforce process; this guides the agent toward effective execution within BUILD.

### D4: Structured Verification Feedback

Enhance `phase-feedback.md` format from binary PASS/FAIL to structured:

```markdown
# Phase Feedback
## Verdict: FAIL

## Specific Failures
- File: `src/auth.ts:42` — TypeError: validateToken is not a function
- File: `tests/auth.test.ts:15` — Expected 200, got 401

## Test Output (verbatim)
[exact stdout/stderr from test run]

## What Was Expected
[from evaluation criteria]

## What Was Found
[from actual test/review output]
```

Update `validate-phase.sh` to write this structured format. Update `phase-feedback.md` readers (pre-write-gate.sh) to still detect FAIL from the verdict line (backward compatible).

### D5: Context Snapshot Mechanism

New state file: `.claude/state/context-snapshot.md`

Turn packet guidance during BUILD start instructs agent to spawn explorer sub-agent that:
1. Reads relevant source files in the target project
2. Identifies patterns, test structure, dependencies
3. Writes a bounded summary (~100 lines) to context-snapshot.md
4. This snapshot is injected into executor sub-agent prompts

## What Changes (Files Modified)

| File | Change |
|------|--------|
| `on-prompt-submit.sh` | New BUILD guidance block: iteration loop instructions, context snapshot injection, role prompt references |
| `validate-phase.sh` | Structured feedback output format |
| `.claude/roles/*.md` | NEW: 5 role prompt files |
| `.claude/state/build-iteration.json` | NEW: iteration loop state |
| `.claude/state/context-snapshot.md` | NEW: codebase context snapshot |

## What Does NOT Change

- pre-write-gate.sh (no changes)
- pre-bash-gate.sh (no changes)
- pre-flight-gate.sh (no changes)
- generate-pre-flight-challenge.sh (no changes)
- Evidence checkpoint system (no changes)
- Must-do system (no changes)
- Watcher system (no changes)
- lib-helpers.sh (no changes unless shared functions needed)

## Acceptance Criteria

### D1: Role Prompts
| # | Criterion |
|---|-----------|
| AC1 | `.claude/roles/planner.md` exists with identity, constraints, output format |
| AC2 | `.claude/roles/critic.md` exists with adversarial review focus |
| AC3 | `.claude/roles/executor.md` exists with implementation-only scope |
| AC4 | `.claude/roles/verifier.md` exists with structured verdict output |
| AC5 | `.claude/roles/explorer.md` exists with read-only codebase snapshot output |
| AC6 | Each role prompt explicitly states what it does NOT do |
| AC7 | No role prompt exceeds 100 lines |

### D2: Iteration Loop State
| # | Criterion |
|---|-----------|
| AC8 | `build-iteration.json` schema includes: feature, iteration, max_iterations, last_test_output, last_test_exit_code, status |
| AC9 | Default max_iterations is 5 |
| AC10 | Status values are: running, passed, stuck |

### D3: Turn Packet BUILD Guidance
| # | Criterion |
|---|-----------|
| AC11 | on-prompt-submit.sh emits iteration loop guidance when phase is BUILD |
| AC12 | Guidance references specific role prompt file paths |
| AC13 | Guidance includes instruction to run tests and capture output |
| AC14 | Guidance includes instruction to write test output to build-iteration.json |
| AC15 | When build-iteration.json shows failure, guidance includes the verbatim last_test_output |
| AC16 | When iteration reaches max, guidance includes STUCK escalation |
| AC17 | When tests pass, guidance includes "proceed to next feature" |
| AC18 | BUILD guidance does not fire during PLAN/NEGOTIATE/EVALUATE/COMPLETE |

### D4: Structured Feedback
| # | Criterion |
|---|-----------|
| AC19 | validate-phase.sh writes structured feedback with: verdict, specific failures, test output, expected vs found |
| AC20 | pre-write-gate.sh still detects FAIL from structured format (backward compatible) |
| AC21 | Structured format includes verbatim test output section |

### D5: Context Snapshot
| # | Criterion |
|---|-----------|
| AC22 | Turn packet guidance instructs context snapshot before first BUILD implementation |
| AC23 | context-snapshot.md location is referenced in guidance |
| AC24 | Snapshot guidance specifies: relevant files, patterns, test structure, dependencies |
| AC25 | Snapshot is bounded (guidance says ~100 lines max) |

### Backward Compatibility
| # | Criterion |
|---|-----------|
| AC26 | pre-write-gate.sh unchanged |
| AC27 | pre-bash-gate.sh unchanged |
| AC28 | pre-flight-gate.sh unchanged |
| AC29 | Evidence checkpoint system unchanged |
| AC30 | Must-do system unchanged |

## Risks

1. **Turn packet bloat** — Adding iteration loop guidance could push packet size beyond useful limits. Mitigation: keep guidance concise, conditional (only emit what's relevant to current iteration state).
2. **Sub-agent hook conflicts** — Sub-agents trigger Write/Edit hooks including pre-write-gate. This is DESIRED (they should be gated too) but could cause unexpected blocks if sub-agent writes to non-exempt paths. Mitigation: sub-agents work within the same phase/sprint context.
3. **Context snapshot staleness** — Snapshot taken at BUILD start could become stale if implementation changes the codebase significantly. Mitigation: snapshot is guidance, not enforcement — agent can re-explore.

## Verification Plan

Independent verifier sub-agent checks:
1. All 5 role prompt files exist and meet format criteria
2. on-prompt-submit.sh output includes iteration guidance during BUILD (not other phases)
3. validate-phase.sh produces structured feedback format
4. pre-write-gate.sh still blocks on FAIL in new format
5. No changes to gate scripts (diff check)
