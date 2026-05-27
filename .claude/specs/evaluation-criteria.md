# Evaluation Criteria — Sprint 27: GPU Test Coordination Protocol

## C1: Test Lock Helpers (lib-helpers.sh)
1. `test_lock_acquire()` exists and creates lock dir + writes test-lock.json with PID, timestamp, command, source
2. `test_lock_release()` exists and removes lock dir + test-lock.json
3. `test_lock_check()` exists and returns 0 if locked, 1 if unlocked, handles stale detection
4. Stale lock auto-released when PID is dead (checked via `kill -0`)
5. Uses `mkdir` atomic pattern (same as registry locking)

## C2: Agent Blocking (pre-bash-gate.sh)
6. Detects test commands: pytest, npm test, python -m pytest, npx jest (pattern match)
7. When test-lock.json exists with source=harness → exit 2 with "HARNESS TESTS RUNNING" message
8. When test-lock.json does not exist or source=agent → allows test command through

## C3: Result Injection
9. validate-phase.sh writes harness-test-result.json after test run (exit_code, ran_at, passed, source)
10. post-write-check.sh output includes harness test status when result file exists
11. on-prompt-submit.sh turn packet includes `[HARNESS TESTS: PASSED/FAILED]` when result file exists

## C4: Deduplication
12. validate-phase.sh skips test re-run when harness-test-result.json has fresh PASS (within 5 min default)
13. on-prompt-submit.sh tells agent "tests verified by harness" when fresh result exists

## C5: Timeout and Process Cleanup
14. validate-phase.sh reads test-config.json for custom command and timeout (default 60s)
15. Test process runs in a process group (setsid or equivalent for MSYS)
16. On timeout, entire process group killed (no orphans)
17. Lock released in all exit paths (success, failure, timeout, signal)

## Sync + Syntax
18. All modified files: live copy and _install/ copy are identical for changed sections
19. bash -n passes on all modified files (both live and install copies)

## Non-Regression
20. Existing phase validation logic in validate-phase.sh (ledger checks, verification type) unchanged
21. Existing ralph, evidence, watcher logic in pre-bash-gate.sh unchanged
22. Existing turn packet assembly in on-prompt-submit.sh unchanged (new injection is additive)
23. Existing phase validation + evidence checkpoint logic in post-write-check.sh unchanged

## Functional TDD Tests (REAL — must execute and pass)
24. TEST: Create test-lock.json manually, run `bash pre-bash-gate.sh` with pytest command in stdin → must exit 2
25. TEST: Remove test-lock.json, run `bash pre-bash-gate.sh` with pytest command in stdin → must exit 0
26. TEST: Call `test_lock_acquire` twice without release → second call detects lock, returns non-zero
27. TEST: Call `test_lock_acquire`, kill the PID, call `test_lock_check` → stale lock detected and cleared
28. TEST: Write harness-test-result.json with fresh timestamp, run validate-phase.sh test section → skips re-run
29. TEST: Write harness-test-result.json with stale timestamp (>5 min), run validate-phase.sh → runs tests
30. TEST: Run validate-phase.sh test section with timeout=2 and `sleep 10` as command → process killed within 5s, lock released
31. TEST: bash -n on every modified file (live + install) → all exit 0
