# Harness GPU Contention & Test Coordination Fix

## Background

The harness auto-runs the full project test suite in `validate-phase.sh` (lines 116-123) as a Layer 1 defense against **Failure Mode #11: Phantom TDD** — agents claiming tests pass without actually running them, or biasing sub-agent verifiers to skip tests. This was a deliberate design choice: the harness runs tests independently so the agent cannot self-report results.

The auto-test-run must be kept. Removing it reopens Phantom TDD.

---

## The Problems

### Problem 1: GPU Exclusivity Violation

Tests that load ML models (image generation, inference pipelines) need exclusive GPU access. Currently nothing prevents two test processes from competing for VRAM simultaneously:

- The harness runs `python -m pytest` inside validate-phase.sh (triggered by post-write-check.sh)
- The agent runs `python -m pytest` via Bash as part of its TDD workflow
- Both try to load models onto the GPU at the same time
- Result: one crashes, both OOM, or orphaned GPU processes

This affects any project that loads models during tests (e.g., Private Content Wizard with Stable Diffusion, any ML inference pipeline).

### Problem 2: Agent Is Unaware Harness Tests Are Running

The validate-phase.sh test run happens inside the PostToolUse hook (post-write-check.sh). The agent has zero visibility:

- It doesn't see "tests are running, wait"
- It continues issuing tool calls
- It launches its own `python -m pytest` via Bash — creating GPU contention
- The harness test results are never surfaced to the agent (only written to phase-feedback.md, which the agent may not read until much later)

### Problem 3: Duplicate Test Runs

Two independent test runs serve the same purpose:

- **Harness-run** (validate-phase.sh): Phantom TDD defense — proves tests actually execute
- **Agent-run** (TDD workflow): The agent's own development loop

Neither knows about the other. Running the full suite twice is wasteful even without GPU issues. With GPU models involved, it's destructive.

### Problem 4: No Timeout or Process Cleanup

The current test run in validate-phase.sh has:

- No timeout — browser/e2e tests can run indefinitely
- No process tree cleanup — child processes (Chromium, model servers) orphaned when parent killed
- No test filtering — runs the entire suite including heavy e2e/browser tests
- No respect for pyproject.toml ignore patterns already configured by the project

---

## Required Fix: Test Execution Protocol

### 1. Test Lock (GPU Mutex)

A lockfile that any test runner must acquire before starting:

- **Location**: `.claude/state/test-lock.json`
- **Contents**: `{"pid": N, "started_at": "ISO8601", "command": "python -m pytest", "source": "harness|agent"}`
- **Acquire**: before any `pytest`/`npm test` invocation (both harness and agent)
- **Release**: when test process exits (or on stale detection if process died)
- **Stale threshold**: if PID is dead or lock older than configurable timeout, auto-release

### 2. Agent Blocking During Harness Tests

When the harness acquires the test lock:

- `pre-bash-gate.sh` detects test-running commands (`pytest`, `npm test`, `python -m pytest`, etc.)
- Checks test-lock.json — if locked by harness, block with message: "HARNESS TESTS RUNNING — wait for completion"
- The agent cannot launch competing test processes while harness tests execute
- This is the hard enforcement of GPU exclusivity — one test runner at a time, no exceptions

### 3. Agent Awareness (Result Injection)

When the harness test run completes:

- Write result to `.claude/state/harness-test-result.json`: `{"exit_code": N, "ran_at": "ISO8601", "passed": true/false, "test_count": N, "source": "harness"}`
- Inject into the turn packet (post-write-check.sh output or on-prompt-submit.sh): `[HARNESS TESTS: PASSED]` or `[HARNESS TESTS: FAILED — see phase-feedback.md]`
- The agent SEES the result and knows tests were already run — doesn't duplicate
- The main agent must STOP and wait for the harness test result before proceeding

### 4. One-At-A-Time / No-Duplicate Enforcement

Avoid redundant test runs:

- If the **agent** already ran tests AND evidence exists (tdd-events.jsonl has recent test run with exit code 0, timestamp within current sprint), the harness can skip re-running
- If the **harness** already ran tests AND they passed (harness-test-result.json exists with recent timestamp), the agent's turn packet says "tests already verified by harness — skip re-run"
- Freshness check: test results older than N minutes (configurable) are considered stale

### 5. Timeout and Process Tree Cleanup

Safe test execution in validate-phase.sh:

- **Timeout**: configurable per project via `.claude/state/test-config.json`, default 60 seconds
- **Process group**: run tests in a new process group (`setsid` or equivalent) so the entire tree can be killed
- **Cleanup on timeout**: `kill -- -$PGID` to kill the entire process group (pytest + Chromium + model servers)
- **Respect project config**: read pyproject.toml `[tool.pytest.ini_options]` for existing ignore patterns, pass them through
- **Custom command override**: `.claude/state/test-config.json` can specify `{"command": "python -m pytest tests/unit/ -x", "timeout": 30}`

---

## Files to Modify

| File | Change |
|------|--------|
| `validate-phase.sh` | Add lock acquire/release, timeout, process group, config reading |
| `post-write-check.sh` | Inject harness test result into turn packet output |
| `pre-bash-gate.sh` | Check test-lock.json before allowing test commands |
| `on-prompt-submit.sh` | Inject harness test result into turn packet |
| `lib-helpers.sh` | Add `test_lock_acquire()`, `test_lock_release()`, `test_lock_check()` helpers |

## Files to Create

| File | Purpose |
|------|---------|
| `.claude/state/test-lock.json` | Runtime lock file (created/deleted dynamically) |
| `.claude/state/test-config.json` | Per-project test configuration (optional, user-created) |
| `.claude/state/harness-test-result.json` | Last harness test run result (written by validate-phase.sh) |

---

## Design Constraints

- The harness test run MUST be kept — it's the Phantom TDD defense (Failure Mode #11)
- The lock must work on Windows/MSYS (use `mkdir` atomic lock, same pattern as registry locking)
- Agent can never self-certify test results — harness result is authoritative
- Test config is optional — zero-config projects get sensible defaults (60s timeout, full suite)
- Lock must auto-release on stale detection — no permanent deadlocks from crashed processes
- GPU-heavy projects need the lock enforced; lightweight projects (no GPU) still benefit from deduplication
