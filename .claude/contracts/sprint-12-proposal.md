# Sprint 12 Proposal — Strategy Loop Breaker

## What Will Be Built

A graduated detection + intervention system that identifies when agents are stuck in a strategy loop (tunnel vision) and forces them to consult their knowledge base for alternative approaches.

### Deliverables

1. **`detect-strategy-loop.sh`** — New Layer 2 detection script
   - Reads `bash-failure-log.jsonl` (last 10 entries)
   - Checks 3 signals: same output fingerprint, consecutive failures, same files churning
   - Returns exit 0 (no loop), exit 1 (nudge), exit 2 (block)
   - Handles resets, deconfliction with detect-loop.sh, graceful fallback on missing/corrupt state

2. **Extend `collect-test-evidence.sh`** — General failure/success logging
   - Add failure/success logging BEFORE the BUILD/TDD early-exit gates
   - Log failing commands to `.claude/state/bash-failure-log.jsonl` with output fingerprint + files edited
   - Log success commands as `{"success": true}` markers
   - Command exclusion logic (split on `&&`/`||`/`;`/`|`, check tokens, strip subshells/env-vars)
   - Trim log to 50 entries

3. **Extend `on-prompt-submit.sh`** — Nudge injection
   - Call `detect-strategy-loop.sh`
   - On exit 1: increment nudge_count (with 60s cooldown), inject nudge message with must-do file list
   - On exit 2: set blocked=true, inject block warning

4. **Extend `pre-write-gate.sh`** — Block gate + ack validation
   - Check `strategy-loop-state.json` for `blocked: true`
   - Validate `strategy-ack.md` (basename reference if must-do exists, 150 chars, "## New Approach" header)
   - Clear block on valid ack (reset state, delete ack, truncate failure log)
   - Exempt harness paths

5. **Extend `pre-bash-gate.sh`** — Mirror block gate
   - Same logic as pre-write-gate.sh block section

6. **Extend `startup-recovery.sh`** — Session boundary
   - Clear `bash-failure-log.jsonl` on session start

## Verification Criteria

Per the 49 evaluation criteria in `.claude/specs/strategy-loop-breaker-eval-criteria.md`. Key verification points:

### Detection Tests
- 3 consecutive failures with same fingerprint + same files → nudge (exit 1)
- Different fingerprints across failures → no loop (exit 0)
- Different files edited between failures → no loop (exit 0)
- Success entry between failures → resets counter, no loop
- First entry has empty files_edited_since_last → minimum 4 failures to trigger

### Command Handling Tests
- `cd dir && npm test` (failing) → logged (npm is non-excluded)
- `cd dir && ls` → excluded (both trivial)
- `ENV=prod npm test` → logged (npm after stripping env var)
- `ls`, `cat`, `git status` → excluded
- `python -m pytest` → logged

### Tier 1 Tests
- Nudge message includes must-do files with "mistake" files marked PRIORITY
- Nudge counter respects 60s cooldown
- Nudge does NOT block writes

### Tier 2 Tests
- Block triggers at nudge_count >= 3
- Block enforced in BOTH pre-write-gate.sh and pre-bash-gate.sh
- Harness paths (.claude/state/ etc.) exempt from block
- Valid ack clears block + resets state + deletes ack + truncates log
- Invalid ack (too short, no header, no must-do reference) does NOT clear block
- No-must-do project: ack only needs length + header

### Deconfliction Tests
- agent-blocked.md present → strategy loop breaker exits cleanly
- agent-blocked.md removed → nudge_count resets to 0

## Sprint Scope

### In Scope
- All 6 deliverables above
- Unit-style tests for each signal and gate
- Integration with existing harness infrastructure

### Out of Scope
- Changes to the must-do system itself
- Changes to detect-loop.sh
- Changes to the watcher system
- New hook registrations in settings.json
- LLM-based strategy validation

## Risk Assessment

**Low risk**: All changes extend existing scripts with new sections. No existing logic is modified. The failure logging is placed before existing early-exits, and all new gate sections use the same exemption patterns as existing gates.

**Rollback**: If the system causes problems, removing the new sections from each script restores previous behavior. The state file (`strategy-loop-state.json`) and log (`bash-failure-log.jsonl`) can be deleted without side effects.
