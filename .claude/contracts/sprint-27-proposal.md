# Sprint 27 Proposal — GPU Test Coordination Protocol

## What I Will Build

A test execution protocol that enforces one-test-runner-at-a-time across the harness, with GPU mutex, agent blocking, result injection, deduplication, and timeout/cleanup. Five components across 5 existing files + 3 helper functions.

## Delivery

### C1: Test Lock Helpers in lib-helpers.sh
- `test_lock_acquire(source, command)` — mkdir atomic lock + write test-lock.json
- `test_lock_release()` — remove lock dir + file
- `test_lock_check()` — check if locked, handle stale (dead PID)

### C2: Agent Blocking in pre-bash-gate.sh
- Detect test commands via pattern match on stdin command
- Check test-lock.json; if locked by harness → exit 2

### C3: Result Injection in validate-phase.sh + post-write-check.sh + on-prompt-submit.sh
- validate-phase.sh writes harness-test-result.json after tests
- post-write-check.sh includes result in additionalContext output
- on-prompt-submit.sh includes result in turn packet

### C4: Deduplication in validate-phase.sh
- Before running tests, check harness-test-result.json freshness
- If PASS within 5 minutes → skip, log "tests already verified"

### C5: Timeout + Cleanup in validate-phase.sh
- Read test-config.json for command/timeout overrides
- setsid + timeout wrapper; kill process group on expiry
- Lock release in all exit paths (trap)

## Self-Critical Review

### What could go wrong?

1. **setsid may not exist on MSYS/Git Bash.** Need to test and fall back to `cmd /c start /b` or plain background + timeout loop. This is the highest risk item.

2. **Lock dir left behind on hard crash.** The stale PID detection handles this — `kill -0 $PID` returns non-zero if process died. But on Windows, PIDs get recycled fast. Mitigation: also check timestamp age (>timeout → stale).

3. **pre-bash-gate.sh pattern matching false positives.** A command like `echo "pytest is cool"` matches "pytest". Need to match at word boundaries or at command position only. Mitigate with `^\s*(python\s+-m\s+)?pytest` style matching.

4. **Deduplication freshness race.** Agent runs tests at T=0, harness checks at T=4:59 (fresh), agent modifies code at T=5:01 — stale result used. Acceptable: 5 minutes is conservative, and the verification ledger still catches this at phase completion.

5. **test-config.json missing.** Must be fully optional. All defaults must work with no config file present.

6. **Timeout kill doesn't reach grandchild processes on Windows.** Chromium spawns its own subprocess tree. `taskkill /T /PID` on Windows or `kill -- -$PGID` on Unix. Need platform detection.

### Is the scope right?

- 5 files modified, 3 helpers added — moderate scope, but each component is small and testable independently
- The functional TDD tests (criteria 24-31) will catch integration issues early
- No new hook files needed — all changes extend existing files

### Verdict: Proceed with caution on MSYS process group handling. Build C1 (lock) first, test on Windows, then layer the rest.
