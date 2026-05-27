# Sprint 28 Contract — Watcher Lifecycle Completion Protocol

## Deliverable
Three features: cron pause/resume, watcher release guard, and verifier PASS completion reminder. Fixes lifecycle gaps where crons interrupt discussions, agents release watchers prematurely, and agents lack forewarning about the release protocol.

## Build Order
1. F1 helpers (lib-helpers.sh) — cron_pause() and cron_resume()
2. F1 auto-resume (post-write-check.sh) — clear pause on Write/Edit
3. F1 injection (on-prompt-submit.sh) — show pause status in turn packet
4. F2 release guard (pre-bash-gate.sh) — block release if phase != COMPLETE
5. F3 PASS reminder (post-write-check.sh) — add to existing verdict injection
6. R5 stale cleanup (startup-recovery.sh) — clear old cron-paused.json on startup

## Files Modified
| File | Features |
|------|----------|
| `lib-helpers.sh` | F1: cron_pause(), cron_resume() |
| `post-write-check.sh` | F1: auto-resume on write; F3: PASS completion reminder |
| `on-prompt-submit.sh` | F1: pause status injection |
| `pre-bash-gate.sh` | F2: watcher release guard |
| `startup-recovery.sh` | R5: stale cron-paused.json cleanup |
| `CLAUDE.md` (global install) | F1: updated watcher section with cron pause/resume protocol |

## Files NOT Modified
- validate-phase.sh, pre-write-gate.sh, pre-flight-gate.sh, on-session-end.sh

## Accepted Limitations
- **CronDelete is not directly blockable.** CronDelete is a Claude Code internal tool, not a Bash command — pre-bash-gate.sh cannot intercept it. Mitigation: the watcher release guard (F2) is the real enforcement. If the agent deletes the cron but can't release the watcher, the watcher gate still blocks writes until a new cron is created. The PASS reminder (F3) prewarns the agent not to delete prematurely.

## Acceptance Criteria

### F1: Cron Pause/Resume (AC1-AC9)
- AC1: `cron_pause [minutes]` writes `.claude/state/cron-paused.json` with `{"paused":true,"resume_at":"ISO","resume_on_write":true,"paused_at":"ISO"}`
- AC2: Default pause duration is 30 minutes when no argument given
- AC3: `cron_resume` deletes `.claude/state/cron-paused.json`
- AC4: post-write-check.sh: if cron-paused.json exists with `resume_on_write:true`, deletes it (auto-resume on write)
- AC5: Auto-resume only triggers on non-state-file writes (writes to `.claude/state/` do NOT trigger resume — only real code edits do)
- AC6: on-prompt-submit.sh: injects `[CRON PAUSED until HH:MM]` when cron-paused.json exists and not expired
- AC7: on-prompt-submit.sh: injects nothing when file doesn't exist or `resume_at` has passed
- AC8: CLAUDE.md global install watcher section updated with: "When the watcher cron fires: FIRST check `.claude/state/cron-paused.json`. If it exists and `resume_at` has not passed, acknowledge silently and continue — do NOT print the reminder. If `resume_at` has passed, delete the file and proceed with the normal reminder."
- AC9: startup-recovery.sh: clears cron-paused.json older than 2 hours (same pattern as phase-feedback.md stale clear)

### F2: Watcher Release Guard (AC10-AC16)
- AC10: pre-bash-gate.sh detects commands that write to REGISTRY.json with "available" value pattern
- AC11: Detection matches: jq with "available", printf/echo/cat redirect to REGISTRY.json containing "available"
- AC12: Does NOT false-positive on REGISTRY.json reads (jq -r, cat without redirect)
- AC13: When phase is BUILD/EVALUATE/PLAN/NEGOTIATE → exit 2 with block message
- AC14: When phase is COMPLETE → allowed through (exit 0 from this check)
- AC15: When no current-phase.json exists → allowed through
- AC16: Block message: "BLOCKED: Cannot release watcher — phase is [PHASE], not COMPLETE. Write phase-complete-marker.md first, then release."

### F3: PASS Completion Reminder (AC17-AC19)
- AC17: post-write-check.sh verdict injection for PASS includes: "DO NOT release watcher or delete cron yet. Sequence: write phase-complete-marker.md, confirm COMPLETE, THEN release."
- AC18: FAIL verdict injection does NOT include the release reminder
- AC19: Existing ralph auto-deactivation logic (Sprint 26) unchanged

### Sync + Syntax (AC20-AC21)
- AC20: All 6 modified files synced to _install/ copies (5 scripts + CLAUDE.md)
- AC21: `bash -n` passes on all 12 copies (5 scripts x 2 locations + CLAUDE.md verified by diff)

### Non-Regression (AC22-AC25)
- AC22: post-write-check.sh existing phase validation, evidence checkpoint, ralph deactivation, harness test injection unchanged
- AC23: pre-bash-gate.sh existing ralph, evidence, watcher, phase, GPU gates unchanged
- AC24: on-prompt-submit.sh existing turn packet assembly unchanged
- AC25: lib-helpers.sh existing functions unchanged

### Functional TDD Tests — MUST EXECUTE LIVE (AC26-AC36)
- AC26: Source lib-helpers.sh, call `cron_pause 30` → cron-paused.json created with correct fields, `resume_at` ~30 min ahead
- AC27: Call `cron_resume` → cron-paused.json deleted
- AC28: Create cron-paused.json with `resume_on_write:true`, pipe a Write event (non-state-file) to post-write-check.sh → cron-paused.json deleted
- AC29: Create cron-paused.json with `resume_on_write:true`, pipe a Write event for `.claude/state/foo.json` to post-write-check.sh → cron-paused.json NOT deleted (state files don't trigger resume)
- AC30: Set current-phase.json to BUILD, pipe REGISTRY.json release command to pre-bash-gate.sh → exit 2
- AC31: Set current-phase.json to COMPLETE, pipe same release command → NOT exit 2
- AC32: Create evidence-verdict.json with PASS, pipe Write event to post-write-check.sh → stdout contains "DO NOT release watcher"
- AC33: Create evidence-verdict.json with FAIL, pipe Write event to post-write-check.sh → stdout does NOT contain "DO NOT release watcher"
- AC34: Pipe a REGISTRY.json read command (`jq -r '.watchers[0].status' REGISTRY.json`) to pre-bash-gate.sh → NOT exit 2 (reads are not blocked)
- AC35: Remove current-phase.json, pipe REGISTRY.json release command to pre-bash-gate.sh → NOT exit 2 (fresh project allowed)
- AC36: `bash -n` on all 10 script copies (5 scripts x 2 locations) + `diff` on 2 CLAUDE.md copies → all pass
- AC37: Source lib-helpers.sh, call `cron_pause` with NO argument → cron-paused.json created with `resume_at` ~30 min ahead (tests AC2 default)

## Verification Method
- Build each feature, run its TDD tests immediately
- After all features: independent sub-agent verifies all 37 criteria
- Sub-agent runs functional tests (AC26-AC37) live
