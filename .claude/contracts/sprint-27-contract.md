# Sprint 27 Contract — GPU Test Coordination Protocol

## Deliverable
A test execution protocol enforcing one-test-runner-at-a-time across the harness: GPU mutex lock, agent blocking during harness tests, result injection into turn packets, test deduplication, and timeout with process tree cleanup.

## Build Order
1. C1 first (lock helpers) — foundation for everything else
2. C5 next (timeout/cleanup in validate-phase.sh) — uses C1, highest risk (MSYS process groups)
3. C2 next (agent blocking in pre-bash-gate.sh) — uses C1
4. C3 next (result injection) — uses harness-test-result.json from C5
5. C4 last (deduplication) — uses harness-test-result.json from C5

## Files Modified
| File | Components |
|------|-----------|
| `lib-helpers.sh` | C1: test_lock_acquire, test_lock_release, test_lock_check |
| `validate-phase.sh` | C3 (result file), C4 (dedup check), C5 (timeout, process group, config) |
| `pre-bash-gate.sh` | C2 (test command detection + lock check) |
| `post-write-check.sh` | C3 (result injection into additionalContext) |
| `on-prompt-submit.sh` | C3 (result injection into turn packet), C4 (skip-rerun guidance) |

## Files NOT Modified
- pre-write-gate.sh
- pre-flight-gate.sh
- on-session-end.sh
- startup-recovery.sh

## Acceptance Criteria

### C1: Test Lock Helpers (AC1-AC5)
- AC1: `test_lock_acquire "source" "command"` creates `.claude/state/.test-lock/` dir (atomic) + writes test-lock.json
- AC2: `test_lock_release` removes lock dir and test-lock.json
- AC3: `test_lock_check` returns 0 if locked (file exists + PID alive), 1 if unlocked or stale
- AC4: Stale detection: PID dead (`kill -0` fails) OR timestamp older than timeout → auto-release + return 1
- AC5: Double acquire without release → second call returns non-zero (lock already held)

### C2: Agent Blocking (AC6-AC8)
- AC6: pre-bash-gate.sh detects test commands: `pytest`, `python -m pytest`, `npm test`, `npx jest` (word-boundary match, not substring)
- AC7: When test-lock.json exists with `"source":"harness"` and PID alive → exit 2 with "HARNESS TESTS RUNNING" message
- AC8: When no lock or lock source is "agent" → test command allowed through (exit 0 from this check)

### C3: Result Injection (AC9-AC11)
- AC9: validate-phase.sh writes `.claude/state/harness-test-result.json` with `{"exit_code":N,"ran_at":"ISO","passed":bool,"test_count":N,"source":"harness"}`
- AC10: post-write-check.sh additionalContext includes `HARNESS_TESTS: PASSED` or `HARNESS_TESTS: FAILED` when result file exists
- AC11: on-prompt-submit.sh turn packet includes `[HARNESS TESTS: PASSED/FAILED]` when result file exists

### C4: Deduplication (AC12-AC14b)
- AC12: validate-phase.sh checks harness-test-result.json; if `passed:true` and `ran_at` within 5 minutes → skips test run, logs "tests already verified"
- AC13: on-prompt-submit.sh adds "tests verified by harness — skip re-run" to turn packet when fresh PASS exists
- AC14a: validate-phase.sh checks tdd-events.jsonl for recent agent test run with exit code 0 within freshness window → skips harness re-run, logs "agent tests verified"
- AC14b: If pyproject.toml contains `[tool.pytest.ini_options]` with `--ignore` or `addopts` ignore patterns, validate-phase.sh passes them through to the test command

### C5: Timeout and Cleanup (AC15-AC18)
- AC15: validate-phase.sh reads `.claude/state/test-config.json` for `command` and `timeout` (default: detected command, 60s)
- AC16: Test process launched in a killable group (setsid on Linux/Mac, or taskkill /T fallback on MSYS/Windows)
- AC17: On timeout: entire process tree killed, lock released, harness-test-result.json written with `passed:false`
- AC18: Lock released in ALL exit paths: success, failure, timeout, signal (via trap)

### Sync + Syntax (AC19-AC20)
- AC19: All 5 modified files: live (`~/.claude/hooks/` or `~/.claude/scripts/`) and install (`_install/`) copies identical for changed sections
- AC20: `bash -n` passes on all 10 copies (5 files x 2 locations)

### Non-Regression (AC21-AC24)
- AC21: validate-phase.sh verification ledger checks (lines 60-113) unchanged
- AC22: pre-bash-gate.sh existing ralph, evidence, watcher, phase gates unchanged
- AC23: on-prompt-submit.sh existing turn packet assembly unchanged (injection is additive only)
- AC24: post-write-check.sh existing phase validation, evidence checkpoint, ralph deactivation unchanged

### Functional TDD Tests — MUST EXECUTE AND PASS (AC25-AC33)
- AC25: Create test-lock.json with `"source":"harness"` + valid PID → `bash pre-bash-gate.sh` with pytest stdin → exits 2
- AC26: No test-lock.json exists → `bash pre-bash-gate.sh` with pytest stdin → exits 0 (from this check)
- AC27: `test_lock_acquire "harness" "pytest"` succeeds → second `test_lock_acquire` returns non-zero
- AC28: `test_lock_acquire` with fake PID 99999 → `test_lock_check` detects stale, auto-releases, returns 1
- AC29: Write harness-test-result.json with `ran_at` = now, `passed:true` → validate-phase.sh test section skips re-run
- AC30: Write harness-test-result.json with `ran_at` = 10 minutes ago → validate-phase.sh runs tests (stale)
- AC31: validate-phase.sh with test-config.json `{"command":"sleep 10","timeout":2}` → process killed within 5s, lock released, result written with `passed:false`
- AC32: Write tdd-events.jsonl entry with exit_code 0 and timestamp = now → validate-phase.sh skips harness re-run (agent dedup)
- AC33: `bash -n` on all 10 file copies → all exit 0

## Verification Method
- Build each component, run its TDD tests immediately (red then green)
- After all 5 components: independent sub-agent verifies all 33 criteria
- Sub-agent runs the functional tests (AC25-AC33) live, not by reading code
