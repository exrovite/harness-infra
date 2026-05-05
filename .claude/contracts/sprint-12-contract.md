# Sprint 12 Contract — Strategy Loop Breaker

**Locked**: Yes
**Spec**: `.claude/specs/strategy-loop-breaker-spec.md` (Rev 4)
**Eval Criteria**: `.claude/specs/strategy-loop-breaker-eval-criteria.md` (Rev 4, final — 49 criteria)

---

## Deliverables (implementation order)

### D1: Extend `startup-recovery.sh` — Session boundary
- Clear `bash-failure-log.jsonl` on session start
- Criteria: #20

### D2: Extend `collect-test-evidence.sh` — General failure/success logging
- Add BEFORE the BUILD/TDD early-exit gates (before line 33)
- Extract exit code from tool_result (reuse existing patterns)
- Extract output fingerprint (last nonempty line, strip ANSI + digits + whitespace)
- Extract files_edited_since_last from unverified-writes.jsonl
- Command exclusion: split on `&&`/`||`/`;`/`|`, extract first token per sub-command, strip `(`/`VAR=`, check all tokens against exclusion list
- Log failures to `.claude/state/bash-failure-log.jsonl`, successes as `{"success":true}`
- Trim log to 50 entries
- Criteria: #9-22

### D3: `detect-strategy-loop.sh` — New detection script
- 14-step algorithm per spec
- 4 reset conditions
- Graceful fallback on missing/corrupt state
- Deconfliction: exit 0 if agent-blocked.md exists
- Criteria: #1-8, #42-45

### D4: Extend `on-prompt-submit.sh` — Nudge injection
- Call detect-strategy-loop.sh
- Exit 1: increment nudge_count (60s cooldown), inject nudge message with must-do file list (mistake files marked PRIORITY)
- Exit 2: set blocked=true, inject block warning
- No-must-do fallback: generic message
- Criteria: #23-28

### D5: Extend `pre-write-gate.sh` — Block gate + ack validation
- Check strategy-loop-state.json for blocked=true
- Validate strategy-ack.md: must-do basename (if folder exists), 150 chars, "## New Approach" header
- Clear block on valid ack: reset state, delete ack, truncate failure log
- Exempt harness paths
- Criteria: #29-41

### D6: Extend `pre-bash-gate.sh` — Mirror block gate
- Same block/ack logic as D5
- Criteria: #30-33

---

## Implementation Protocol

- TDD: Write tests for each deliverable BEFORE implementation
- Tests must fail before implementation begins
- Run all tests after each deliverable
- One deliverable at a time, in order (D1 → D2 → D3 → D4 → D5 → D6)

## Scope Boundary

### In Scope
- All 6 deliverables above
- Tests for each signal and gate
- Integration with existing hooks

### Out of Scope
- Changes to the must-do system
- Changes to detect-loop.sh
- Changes to the watcher system
- New hook registrations in settings.json
- LLM-based strategy validation
- Changes to existing gate logic (phase gate, contract gate, must-do gate, pre-flight gate)

## Verification

After BUILD, an independent sub-agent verifier will:
1. Test each signal individually (fires / does not fire)
2. Test the 3-signal conjunction
3. Test the excluded command list (chained commands, env vars, subshells)
4. Test nudge injection and cooldown
5. Test Tier 2 block enforcement in both pre-write-gate.sh and pre-bash-gate.sh
6. Test ack validation and clearing
7. Test deconfliction with detect-loop.sh
8. Test session boundary (startup clearing)
9. Test no-must-do fallback

All 49 criteria must pass. Default: FAIL if in doubt.

## Rollback

Remove new sections from each modified script. Delete `strategy-loop-state.json` and `bash-failure-log.jsonl`. No other cleanup needed.
