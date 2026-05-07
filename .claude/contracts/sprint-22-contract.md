# Sprint 22 Contract: Compound Reliability Foundations

## Goal

Add a compound reliability layer inside the existing enforcement framework: role prompts for agent decomposition, an iteration loop with real test feedback during BUILD, a codebase context snapshot mechanism, and structured verification feedback. These are the highest-impact foundations — adversarial planning consensus and parallel dispatch follow in sprint 23+.

## Deliverables

### D1: Role Prompt Files (`.claude/roles/`)

5 focused role prompts, each self-contained with identity, constraints, output format, and explicit "does NOT do" boundary:

- `planner.md` — Explores codebase, writes specs. Never writes code.
- `critic.md` — Challenges specs/plans adversarially. Never writes specs or code.
- `executor.md` — Implements one focused task. Never plans or reviews itself.
- `verifier.md` — Reads code + test output, returns structured verdicts. Never implements.
- `explorer.md` — Reads target codebase, produces bounded context snapshot. Read-only.

### D2: Iteration Loop State

New state file `.claude/state/build-iteration.json` tracking:
- Current feature being implemented
- Iteration count (0-based, max 5 default)
- Verbatim last test output (stdout/stderr)
- Last test exit code
- Status: running | passed | stuck

### D3: Turn Packet BUILD Guidance

`on-prompt-submit.sh` enhanced with a BUILD-phase-only guidance block:
- Instructs agent to spawn executor sub-agent with role prompt
- Instructs test-after-every-change with output capture
- Injects verbatim last_test_output from build-iteration.json on failure
- Emits STUCK escalation at max iterations
- Emits "proceed to next feature" on pass
- References context snapshot for first BUILD entry
- Does NOT fire during PLAN/NEGOTIATE/EVALUATE/COMPLETE

### D4: Structured Verification Feedback

`validate-phase.sh` writes structured phase-feedback.md:
- Verdict line (PASS/FAIL) — backward compatible with existing readers
- Specific failures: file paths, line numbers, error type
- Verbatim test output section
- Expected vs found comparison

### D5: Context Snapshot Mechanism

New state file `.claude/state/context-snapshot.md`:
- Turn packet guidance instructs context exploration before first BUILD implementation
- Explorer sub-agent reads target files, identifies patterns/tests/dependencies
- Writes bounded summary (~100 lines max)
- Snapshot path injected into executor sub-agent context

## Files Modified

| File | Change Type |
|------|------------|
| `.claude/roles/planner.md` | NEW |
| `.claude/roles/critic.md` | NEW |
| `.claude/roles/executor.md` | NEW |
| `.claude/roles/verifier.md` | NEW |
| `.claude/roles/explorer.md` | NEW |
| `.claude/state/build-iteration.json` | NEW (state) |
| `.claude/state/context-snapshot.md` | NEW (state) |
| `on-prompt-submit.sh` | MODIFIED — new BUILD guidance block |
| `validate-phase.sh` | MODIFIED — structured feedback output |

## Files NOT Modified (Backward Compatibility)

- pre-write-gate.sh
- pre-bash-gate.sh
- pre-flight-gate.sh
- generate-pre-flight-challenge.sh
- validate-pre-flight.sh
- lib-helpers.sh
- on-session-end.sh
- startup-recovery.sh
- create-evidence-checkpoint.sh

## Acceptance Criteria (32 items)

### D1: Role Prompts (7)
| # | Criterion | Verify By |
|---|-----------|-----------|
| AC1 | `.claude/roles/planner.md` exists with identity, constraints, output format | File read |
| AC2 | `.claude/roles/critic.md` exists with adversarial review focus | File read |
| AC3 | `.claude/roles/executor.md` exists with implementation-only scope | File read |
| AC4 | `.claude/roles/verifier.md` exists with structured verdict output format | File read |
| AC5 | `.claude/roles/explorer.md` exists with read-only snapshot output format | File read |
| AC6 | Each role prompt explicitly states what it does NOT do | Grep for "NOT" / "Never" / "does not" in each file |
| AC7 | No role prompt exceeds 100 lines | `wc -l` on each file |

### D2: Iteration Loop State (3)
| # | Criterion | Verify By |
|---|-----------|-----------|
| AC8 | build-iteration.json schema includes: feature, iteration, max_iterations, last_test_output, last_test_exit_code, status | File read / schema doc |
| AC9 | Default max_iterations is 5 | Grep in on-prompt-submit.sh |
| AC10 | Status enum is: running, passed, stuck | Grep in guidance output or schema |

### D3: Turn Packet BUILD Guidance (9)
| # | Criterion | Verify By |
|---|-----------|-----------|
| AC11 | on-prompt-submit.sh emits iteration loop guidance when phase is BUILD | Read source, trace BUILD branch |
| AC12 | Guidance references role prompt file paths (`.claude/roles/executor.md` etc.) | Grep in on-prompt-submit.sh |
| AC13 | Guidance instructs running tests and capturing output | Grep for test/capture instructions |
| AC14 | Guidance instructs writing test output to build-iteration.json | Grep for build-iteration.json reference |
| AC15 | When build-iteration.json exists and shows failure, guidance includes verbatim last_test_output | Read source, trace failure branch |
| AC16 | When iteration >= max_iterations, guidance includes STUCK escalation | Read source, trace max branch |
| AC17 | When status is passed, guidance includes "proceed to next feature" | Read source, trace pass branch |
| AC18 | BUILD guidance block is gated by `[[ "$CURRENT_PHASE" == "BUILD" ]]` | Read source |
| AC19 | Guidance references context-snapshot.md for first BUILD entry | Grep for context-snapshot reference |

### D4: Structured Feedback (5)
| # | Criterion | Verify By |
|---|-----------|-----------|
| AC20 | validate-phase.sh writes structured feedback with verdict line | Read source |
| AC21 | Structured format includes specific failures section | Read source |
| AC22 | Structured format includes verbatim test output section | Read source |
| AC23 | Structured format includes expected vs found section | Read source |
| AC24 | pre-write-gate.sh still detects FAIL from structured format (backward compatible) | Read pre-write-gate.sh — FAIL detection must match new format |

### D5: Context Snapshot (3)
| # | Criterion | Verify By |
|---|-----------|-----------|
| AC25 | Turn packet references context-snapshot.md path | Grep in on-prompt-submit.sh |
| AC26 | Guidance specifies snapshot content: files, patterns, test structure, dependencies | Read guidance output |
| AC27 | Guidance specifies ~100 line bound | Grep for bound instruction |

### Backward Compatibility (5)
| # | Criterion | Verify By |
|---|-----------|-----------|
| AC28 | pre-write-gate.sh has zero diff | `git diff` on file |
| AC29 | pre-bash-gate.sh has zero diff | `git diff` on file |
| AC30 | pre-flight-gate.sh has zero diff | `git diff` on file |
| AC31 | generate-pre-flight-challenge.sh has zero diff | `git diff` on file |
| AC32 | create-evidence-checkpoint.sh has zero diff | `git diff` on file |

## Risks + Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Turn packet bloat | Agent ignores long packets | Keep BUILD guidance concise; conditional emission (only relevant iteration state) |
| Sub-agent hook conflicts | Sub-agents blocked by pre-write-gate | Sub-agents operate within same phase/sprint — existing exemptions apply |
| Stale build-iteration.json across sessions | Confusing guidance from old state | startup-recovery.sh cleanup is sprint 23 scope; low risk since sessions are typically continuous |
| validate-phase.sh format change | Breaks FAIL detection | AC24 explicitly verifies backward compatibility of FAIL detection |

## Implementation Constraints

- `on-prompt-submit.sh` already reads stdin via `HOOK_INPUT=$(cat)`. BUILD guidance block added after existing packet assembly logic.
- validate-phase.sh output change is FORMAT only — pass/fail determination logic unchanged.
- Gate scripts already read stdin into `INPUT_DATA` — no changes needed to gates.
- `sed 's|\\|/|g'` crashes on MSYS — use `tr '\\\\' '/'`.
- Strip Windows jq CR with `tr -d '\r'`.
- `while IFS= read -r` loops need `|| [ -n "$var" ]`.

## Verification Plan

Independent verifier sub-agent checks all 32 criteria:
1. Read each role prompt file — verify identity, constraints, output format, boundary statements
2. Read on-prompt-submit.sh — trace BUILD guidance block, confirm phase gating
3. Read validate-phase.sh — confirm structured feedback format
4. Read pre-write-gate.sh — confirm FAIL detection still works with new format
5. Run `git diff` on all "NOT modified" files — confirm zero changes
6. Run `wc -l` on role prompts — confirm under 100 lines
7. Run `bash -n` syntax check on modified shell files
