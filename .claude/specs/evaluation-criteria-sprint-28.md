# Sprint 28 Evaluation Criteria — Watcher Lifecycle Completion Protocol

## F1: Cron Pause/Resume

### State File
- EC1: `cron_pause()` writes `.claude/state/cron-paused.json` with `{"paused":true,"resume_at":"ISO+30min","resume_on_write":true,"paused_at":"ISO"}`
- EC2: `cron_resume()` deletes `.claude/state/cron-paused.json`
- EC3: cron-paused.json path is exempted from pre-flight gate (it's a state file, already under `.claude/state/`)

### Auto-Resume on Write
- EC4: post-write-check.sh checks for cron-paused.json; if exists and `resume_on_write:true`, deletes it (resume)
- EC5: After resume, next cron prompt fires normally (agent sees the reminder)

### Auto-Resume on Timeout
- EC6: Cron prompt includes instruction to check cron-paused.json; if `resume_at` has passed, agent deletes the file
- EC7: Default pause duration is 30 minutes (configurable via pause function argument)

### Turn Packet Injection
- EC8: on-prompt-submit.sh injects `[CRON PAUSED until HH:MM]` into turn packet when cron-paused.json exists and not expired
- EC9: on-prompt-submit.sh injects nothing when cron-paused.json doesn't exist or is expired

## F2: Watcher Release Guard

### Detection
- EC10: pre-bash-gate.sh detects Bash commands that write to REGISTRY.json with `"available"` pattern (covers jq, printf, echo, cat redirects to REGISTRY.json)
- EC11: Detection uses the file path, not just the word "available" — won't false-positive on unrelated commands

### Blocking
- EC12: When phase is BUILD/EVALUATE/PLAN/NEGOTIATE and a release attempt is detected → exit 2 with message explaining the required sequence
- EC13: When phase is COMPLETE → release attempt allowed through (exit 0 from this check)
- EC14: When no current-phase.json exists → release attempt allowed through (fresh project)

### Block Message
- EC15: Block message says: "BLOCKED: Cannot release watcher — phase is [PHASE], not COMPLETE. Write phase-complete-marker.md first, then release."

## F3: Verifier PASS Completion Reminder

### Injection
- EC16: post-write-check.sh verdict injection for PASS includes: "DO NOT release watcher or delete cron yet. Sequence: write phase-complete-marker.md, confirm COMPLETE, THEN release."
- EC17: FAIL verdict injection does NOT include the release reminder (irrelevant on failure)
- EC18: Existing ralph auto-deactivation logic (Sprint 26) is unchanged

## Sync + Syntax
- EC19: All modified files synced to _install/ copies
- EC20: `bash -n` passes on all modified file copies (live + install)

## Non-Regression
- EC21: post-write-check.sh existing phase validation, evidence checkpoint, ralph deactivation unchanged
- EC22: pre-bash-gate.sh existing ralph, evidence, watcher, phase, GPU gates unchanged
- EC23: on-prompt-submit.sh existing turn packet assembly unchanged
- EC24: lib-helpers.sh existing functions (atomic_write, registry_lock, test_lock_*) unchanged

## Functional TDD Tests (MUST EXECUTE LIVE)

- EC25: Call `cron_pause 30` → cron-paused.json created with correct fields, `resume_at` ~30 min in future
- EC26: Call `cron_resume` → cron-paused.json deleted
- EC27: Create cron-paused.json with `resume_on_write:true` → pipe a Write event to post-write-check.sh → cron-paused.json is deleted
- EC28: Create REGISTRY.json release command, set current-phase.json to BUILD → pipe to pre-bash-gate.sh → exit 2
- EC29: Same release command, set current-phase.json to COMPLETE → pipe to pre-bash-gate.sh → NOT exit 2 (allowed)
- EC30: Create evidence-verdict.json with PASS → pipe Write event to post-write-check.sh → stdout contains "DO NOT release watcher"
- EC31: Create evidence-verdict.json with FAIL → pipe Write event → stdout does NOT contain "DO NOT release watcher"
- EC32: `bash -n` on all modified file copies → all exit 0
