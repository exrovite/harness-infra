# Sprint 22 Contract: Persistent Execution Loop ($ralph)

## Scope

Add a user-activated persistent execution loop that forces the agent through implement → verify → fix cycles until an independent verifier approves or an iteration ceiling triggers terminal failure. The agent cannot skip verification, cannot self-certify, and cannot deactivate the loop. Three Layer 2 gate enforcement points make this unbypassable.

## Deliverables

### D1: Keyword Detection + State Creation (on-prompt-submit.sh)

Add `PROMPT_INPUT=$(cat)` at the top of on-prompt-submit.sh to capture user prompt from stdin JSON. Extract prompt text with `PROMPT_TEXT=$(printf '%s' "$PROMPT_INPUT" | jq -r '.prompt // ""' 2>/dev/null | tr -d '\r')`. If jq fails or returns empty, `PROMPT_TEXT` is empty (safe no-op — no ralph activation).

**Phase guard**: Only activate ralph when current phase is BUILD. If `$ralph` appears during PLAN/NEGOTIATE/EVALUATE/COMPLETE, inject a warning into the turn packet: `[RALPH IGNORED] $ralph only activates in BUILD phase.` Do not create ralph-mode.json.

When phase is BUILD and prompt contains `$ralph` (case-insensitive, word-boundary match via `grep -qi '\$ralph'`):

1. If `.claude/state/ralph-mode.json` does not exist or has `"active": false`, create it:
```json
{
  "active": true,
  "activated_by": "user_prompt",
  "activated_at": "<ISO8601>",
  "iteration": 1,
  "max_iterations": 5,
  "last_verdict": null,
  "last_verdict_at": null,
  "failed_criteria": [],
  "sprint": <current_sprint>
}
```
2. If it already exists with `"active": true`, do nothing (preserve current iteration state).

`max_iterations` default is 5. User can override by writing `$ralph:N` (e.g., `$ralph:3` sets max to 3).

### D2: Turn Packet Ralph Section (on-prompt-submit.sh)

When ralph-mode.json is active, inject a `RALPH LOOP:` section into the turn packet after GUIDANCE and before READ FIRST:

**When last_verdict is null (first iteration):**
```
RALPH LOOP: Iteration 1/5 | Implement, then spawn verifier sub-agent. You CANNOT complete until verifier returns PASS.
```

**When last_verdict is FAIL:**
```
RALPH LOOP: Iteration 2/5 | FAIL — fix failures in evidence-verdict.json, then spawn verifier. Cannot complete until PASS.
```

**When last_verdict is PASS:**
```
RALPH LOOP: PASSED at iteration 2. Write phase-complete-marker.md to finish.
```

**When iteration > max_iterations:**
```
RALPH LOOP: STUCK — 5 iterations exhausted without PASS. STOP. Write stuck-report.md. WAIT for user.
```

### D3: Completion Gate (pre-write-gate.sh)

When ralph-mode.json exists with `"active": true`:

**Block phase-complete-marker.md** writes UNLESS:
- `evidence-verdict.json` exists AND
- Its `verdict` field is `"PASS"` AND
- Its timestamp is newer than `ralph-mode.json`'s `last_verdict_at` from the previous iteration (prevents reusing stale verdicts)

Block message: `BLOCKED: Ralph loop active — verifier must return PASS before completion. Spawn a verifier sub-agent, get PASS verdict in evidence-verdict.json, then retry.`

### D4: Ralph State Protection (pre-write-gate.sh + pre-bash-gate.sh)

Block any agent write to `ralph-mode.json`:
- In `pre-write-gate.sh`: if target path matches `ralph-mode.json`, exit 2 with message: `BLOCKED: ralph-mode.json is user-controlled. Only the user can activate/deactivate ralph mode.`
- In `pre-bash-gate.sh`: add `ralph-mode.json` to the file-write detection patterns. Same block message.

Exception: `on-prompt-submit.sh` creates the file via atomic_write — hooks don't gate hook scripts, only agent tool calls.

### D5: Iteration Accounting (on-prompt-submit.sh)

On each prompt when ralph-mode is active:

1. Read `evidence-verdict.json`. If it has a newer timestamp than `last_verdict_at`:
   - If verdict is PASS: set `last_verdict: "PASS"`, set `active: false`, update `last_verdict_at`. Ralph auto-deactivates — completion gate now allows phase-complete-marker.md.
   - If verdict is FAIL: increment `iteration`, set `last_verdict: "FAIL"`, update `last_verdict_at`, capture failed criteria list. Delete `evidence-verdict.json` to force a fresh verification cycle.
2. If `iteration > max_iterations` and `last_verdict != "PASS"`: inject STUCK block (terminal).
3. Sprint mismatch (current sprint != ralph-mode sprint): auto-deactivate ralph mode (task changed).

### D6: Verifier Brief Auto-Generation (on-prompt-submit.sh)

When ralph-mode is active and the agent has made writes since the last verdict, auto-generate `evidence-checkpoint.json` (reusing existing evidence checkpoint infrastructure) to give the verifier sub-agent a brief. This bridges ralph with the existing evidence checkpoint system rather than duplicating it.

## NOT In Scope

- Changing the EVALUATE phase behavior (ralph operates within BUILD phase)
- Team/multi-agent parallel execution (ralph is single-agent)
- Auto-spawning the verifier (agent still spawns it; harness blocks completion until it does)
- Visual verdict integration
- PRD/test-spec hard gates (future sprint)

## Acceptance Criteria (42 items)

### Keyword Detection (8)
1. User prompt containing `$ralph` during BUILD phase activates ralph-mode.json with active:true.
2. User prompt containing `$ralph:3` sets max_iterations to 3.
3. User prompt containing `$RALPH` (uppercase) also activates (case-insensitive).
4. User prompt without `$ralph` does not create ralph-mode.json.
5. If ralph-mode.json already active, `$ralph` in prompt does not reset iteration count.
6. Ralph activation only creates the file — does not modify any other state files.
7. `$ralph` during PLAN/NEGOTIATE/EVALUATE/COMPLETE injects warning but does NOT create ralph-mode.json.
8. Malformed or empty stdin (jq parse failure) results in no activation (safe no-op).

### Turn Packet (5)
9. Active ralph with null verdict shows iteration count and "spawn verifier" instruction.
10. Active ralph with FAIL verdict shows iteration count and "fix failures" instruction.
11. Active ralph with PASS verdict shows "PASSED" and "write phase-complete-marker" instruction.
12. Active ralph past max_iterations shows STUCK message with stuck-report.md instruction.
13. Inactive/missing ralph-mode.json injects no RALPH LOOP section (zero overhead).

### Completion Gate (5)
14. With ralph active, writes to phase-complete-marker.md are BLOCKED when no evidence-verdict.json exists.
15. With ralph active, writes to phase-complete-marker.md are BLOCKED when evidence-verdict.json has verdict FAIL.
16. With ralph active, writes to phase-complete-marker.md are ALLOWED when evidence-verdict.json has verdict PASS with fresh timestamp.
17. Without ralph active, phase-complete-marker.md writes are unaffected (existing behavior preserved).
18. Block message names the specific resolution path (spawn verifier, get PASS).

### State Protection (4)
19. Agent Write to ralph-mode.json is BLOCKED with exit 2.
20. Agent Edit to ralph-mode.json is BLOCKED with exit 2.
21. Agent Bash write (echo/cat/python) targeting ralph-mode.json is BLOCKED.
22. Block message states ralph-mode.json is user-controlled.

### Iteration Accounting (9)
23. Fresh FAIL verdict increments iteration count in ralph-mode.json.
24. Fresh PASS verdict sets last_verdict to PASS AND sets active to false (auto-deactivation).
25. Stale verdict (same timestamp as last_verdict_at) does not increment.
26. Iteration exceeding max_iterations triggers STUCK block in turn packet.
27. STUCK state blocks all source code writes (same as strategy loop STUCK).
28. Sprint mismatch auto-deactivates ralph mode (sets active:false).
29. After processing a FAIL verdict, evidence-verdict.json is deleted to force fresh verification.
30. After auto-deactivation on PASS, subsequent turns inject no RALPH LOOP section.
31. Timestamp comparison uses lexicographic ISO8601 fallback when `date -d` fails.

### Evidence Bridge (3)
32. When ralph is active and writes have occurred since last verdict, evidence-checkpoint.json is created/updated.
33. Evidence checkpoint contains the sprint contract path and ralph iteration number.
34. Existing evidence checkpoint behavior is preserved when ralph is inactive.

### Safety (4)
35. lib-helpers.sh existing functions unchanged.
36. Existing pre-write-gate.sh phase gate, watcher gate, contract gate, must-do gate, evidence gate, strategy loop gate behavior is preserved.
37. Existing pre-bash-gate.sh behavior is preserved (ralph protection is additive).
38. Existing on-prompt-submit.sh features preserved: guidance, protocol, verifier rules, must-do, evidence, strategy loop, watcher cockpit.

### Quality (4)
39. RALPH LOOP section is placed before READ FIRST in the packet assembly — early enough to survive truncation.
40. In a simulated worst-case packet (BUILD + ralph + guidance + all blocks + watcher cockpit + must-do), the RALPH LOOP section is NOT truncated by the 2000-char cap.
41. Steady-state BUILD packet with ralph active and no blocks stays under 800 chars.
42. `bash -n` syntax check passes on all changed files.

## Verification

Independent verifier must:
1. Syntax-check all changed shell files with `bash -n`.
2. Simulate $ralph activation from user prompt and confirm ralph-mode.json creation.
3. Simulate iteration cycle: null → FAIL → FAIL → PASS and confirm state transitions.
4. Simulate max_iterations exceeded and confirm STUCK block.
5. Attempt to write phase-complete-marker.md without PASS verdict — confirm BLOCKED.
6. Attempt to write ralph-mode.json as agent — confirm BLOCKED in both Write and Bash.
7. Confirm sprint mismatch deactivation.
8. Measure packet sizes with ralph section.
9. Verify all 42 criteria with explicit pass/fail and evidence.

## Implementation Constraints

- `on-prompt-submit.sh` does NOT currently read stdin. Add `PROMPT_INPUT=$(cat)` at the very top (before any other logic) to capture user prompt JSON. All ralph keyword detection uses `PROMPT_TEXT` extracted from this.
- Gate scripts (`pre-write-gate.sh`, `pre-bash-gate.sh`) already read stdin into `INPUT_DATA` at their top. Ralph protection checks in gates use the existing `INPUT_DATA` variable.
- Ralph state file writes use `atomic_write` from lib-helpers.sh.
- Timestamp comparison via `date -d` for ISO8601 parsing. MSYS fallback: if `date -d` fails, compare raw ISO8601 strings lexicographically (`[[ "$NEW_TS" > "$OLD_TS" ]]`). This works because ISO8601 is lexicographically sortable.
- `sed 's|\\|/|g'` crashes on MSYS — use `tr '\\' '/'`.
- Strip Windows jq CR with `tr -d '\r'`.
- `while IFS= read -r` loops need `|| [ -n "$var" ]`.
- Ralph protection pattern in pre-bash-gate.sh follows same structure as existing file-write detection.
