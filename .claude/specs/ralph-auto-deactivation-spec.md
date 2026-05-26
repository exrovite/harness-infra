# Ralph Mode Auto-Deactivation on Verifier PASS

## Problem

When ralph mode is active, the only hook that processes verifier verdicts and deactivates ralph is `on-prompt-submit.sh` (UserPromptSubmit). This hook fires only when the **user** types a new prompt.

The typical flow during ralph mode:
1. User types `$ralph` -> on-prompt-submit activates ralph
2. Agent works autonomously: writes code, spawns verifier sub-agent
3. Verifier writes `evidence-verdict.json` with `{"verdict": "PASS"}`
4. Agent continues **same turn** - tries to write `phase-complete-marker.md`
5. `pre-write-gate.sh` checks ralph active + evidence-verdict.json (allows if PASS)
6. `post-write-check.sh` triggers phase validation
7. Phase validation may pass, but the ralph state file still has `active: true`

The problem: between steps 3 and 4, no hook updates the ralph state. The `pre-write-gate.sh` works around this by checking `evidence-verdict.json` directly for the phase-complete-marker write. But the ralph state stays stale, causing:
- Turn packet still shows "RALPH LOOP: active" on subsequent prompts until on-prompt-submit catches up
- If the agent or session ends before the next user prompt, ralph stays permanently active
- Sprint mismatch detection only fires on next prompt, not immediately

## Solution

Add ralph verdict processing to `post-write-check.sh` (PostToolUse hook for Write/Edit). When the file just written IS `evidence-verdict.json` and ralph mode is active, check the verdict and auto-deactivate if PASS.

## Where

- `post-write-check.sh` — add a new section after the evidence checkpoint counter block
- Both live (`~/.claude/hooks/post-write-check.sh`) and install (`_install/hooks/post-write-check.sh`)

## What Changes

1. After evidence checkpoint logic, detect if the file just written is `evidence-verdict.json`
2. If the ralph state file is active AND evidence-verdict.json has verdict "PASS" with a timestamp newer than `last_verdict_at`
3. Update the ralph state: set `active: false`, `last_verdict: "PASS"`, `last_verdict_at: <timestamp>`
4. Use the same `iso_newer_than` comparison and `jq -c` update pattern already in on-prompt-submit.sh

## What Does NOT Change

- `on-prompt-submit.sh` verdict processing stays as-is (serves as fallback)
- `pre-write-gate.sh` ralph completion gate stays as-is
- `pre-bash-gate.sh` ralph blocks stay as-is
- Agent still cannot write the ralph state file directly (only hooks can)
- Ralph activation logic unchanged
- Ralph FAIL/iteration logic stays in on-prompt-submit.sh only (FAIL needs turn packet guidance)

## Constraints

- Only fires when the written file path matches `evidence-verdict.json`
- Only fires when the ralph state file exists and has `active: true`
- Uses atomic_write if available
- No new scripts, no new files, no new dependencies
- Must pass `bash -n` syntax check

## Success Criteria

- When a verifier writes PASS to evidence-verdict.json during ralph mode, the ralph state is immediately updated to active:false
- The on-prompt-submit.sh fallback still works if post-write-check.sh misses it
- No regression in existing phase validation, evidence checkpoint, or write tracking
