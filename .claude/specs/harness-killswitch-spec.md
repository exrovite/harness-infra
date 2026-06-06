# Harness Kill-Switch — Product Spec (Sprint 30, QUEUED — build after Sprint 29)

## Problem
No way to quickly disable the entire harness for a single project during
exploratory/throwaway work. Currently every write goes through phase gates,
watcher requirement, pre-flight MCQ, evidence checkpoints, must-do, and contract
gates — appropriate for real sprints, heavy for quick edits.

## Solution
A per-project on/off switch driven by exact-match prompt tokens:
- Message is exactly `---`  -> write `.claude/state/harness-disabled.flag` (harness OFF)
- Message is exactly `===`  -> delete the flag (harness ON)
- ON by default (no flag present)
- PROJECT-SCOPED: flag lives in the project-local `.claude/state/`, so it never
  affects other projects.

## Trigger rule (DECIDED 2026-06-02)
EXACT MATCH ONLY: the trimmed prompt must equal `---` or `===` with nothing else.
Prevents false toggles from pasted markdown / YAML front-matter / horizontal rules.

## Behavior when OFF
Every enforcement hook short-circuits at the TOP (exit 0 / allow) when the flag
exists: pre-write-gate.sh, pre-bash-gate.sh, pre-flight-gate.sh, post-write-check.sh,
and the phase/watcher/evidence/must-do/contract checks. No MCQ, no watcher
requirement, no phase lock, no counters.

## Visibility (safety)
While OFF, on-prompt-submit.sh injects a visible banner every turn:
`[HARNESS OFF — {project}]` so it is never silently disabled. On `===` it injects
`[HARNESS ON]` once.

## Constraints
- Detection in on-prompt-submit.sh via stdin prompt JSON; exact-match after trim.
- Single guard helper (e.g. `harness_is_disabled`) in lib-helpers.sh used by all hooks.
- Flag write/delete must be atomic; tolerate missing dir.
- The `---`/`===` toggle messages themselves must NOT be blocked by any gate.
- Windows/MSYS-safe (tr -d '\r', no sed backslash subs, temp files not here-strings).

## Open question for NEGOTIATE
- Should OFF also suppress the watcher cron reminders, or leave any active cron alone?
- Should there be an auto-timeout (re-enable after N hours) or stay off until `===`?
