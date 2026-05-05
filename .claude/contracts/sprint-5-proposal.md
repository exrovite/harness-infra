# Sprint 5 Contract Proposal: Verification Enforcement

**Rev 1** — 2026-04-06

## What We Will Build

A three-point verification enforcement system that prevents agents from self-certifying work without independent subagent verification. Uses the existing MCQ infrastructure as the primary delivery mechanism, with hard gates at structural checkpoints.

## Deliverables

### 1. MCQ Q5 — Verification Self-Report (modify existing scripts)

**generate-pre-flight-challenge.sh changes:**
- Add Q5 after Q4 with two options: "Yes — I completed work that an independent subagent should check" and "No — all work since the last gate was trivial / already verified by a subagent"
- Shuffle the Yes/No options using the existing `shuffle_options` function (so the agent can't memorise position)
- Update header text from "Answer all 4 questions" to "Answer all 5 questions"
- Update format example to include `Q5: A`

**validate-pre-flight.sh changes:**
- Parse Q5 answer from response.md
- Q5 has no "wrong" answer — both Yes and No are accepted
- If agent answers the "No" option: increment `no_verify_count` in `.claude/pre-flight/verify-counter.json`
- If agent answers the "Yes" option: output nudge to stderr: "You acknowledged unverified work. Spawn an independent subagent (Agent tool) to verify before continuing."
- If `verify-counter.json` has `hardened: true` AND no new entry in `.claude/state/verification-ledger.jsonl` since `last_reset` timestamp: exit 1 (fail validation, block the write)
- Q5 validation runs AFTER Q1-Q4 validation — if Q1-Q4 fail, Q5 is not reached

### 2. Agent Call Tracker (new PostToolUse hook)

**New file: `~/.claude/hooks/agent-call-tracker.sh`**
- Fires on PostToolUse for Agent tool calls
- Reads Agent prompt from stdin (JSON `tool_input.prompt` field)
- Checks prompt for verification language: `grep -iE 'verify|review|evaluate|check|validate|test|audit|assess'`
- If verification language found:
  - Extract current step from active watcher slot (same sed pattern as pre-flight-gate.sh)
  - Read current phase+sprint from `.claude/state/current-phase.json`
  - Append entry to `.claude/state/verification-ledger.jsonl`:
    ```json
    {"ts":"...","step":"...","phase":"...","sprint":N,"prompt_snippet":"first 100 chars"}
    ```
  - Reset `.claude/pre-flight/verify-counter.json` to `{"no_verify_count":0,"last_reset":"...","hardened":false}`
- If no verification language: do nothing (silent pass)
- Output: empty JSON or minimal hookSpecificOutput (no additionalContext needed)

**settings.json addition:**
```json
{
  "matcher": "Agent",
  "hooks": [{ "type": "command", "command": "bash $HOME/.claude/hooks/agent-call-tracker.sh" }]
}
```
Added to PostToolUse array alongside existing Write|Edit and Bash entries.

### 3. Step Completion Gate (add to pre-flight-gate.sh)

**pre-flight-gate.sh changes — insert before counter logic (after exemptions):**
- Detect if target file matches `.openclaw/watchers/slot-*.md`
- If yes, read the `new_string` (Edit) from stdin
- Check if `new_string` contains `[x]` AND the original `old_string` contained `[ ]` (a step being checked off)
- If step check-off detected:
  - Extract the step text from the `new_string` line containing `[x]`
  - Check if step is trivial (contains "read", "search", "explore", "set up", "claim") — if so, allow
  - Otherwise, check `.claude/state/verification-ledger.jsonl` for an entry where `step` field fuzzy-matches the step text (first 30 chars, case-insensitive)
  - No match → exit 2: "BLOCKED: You cannot mark this step complete without independent verification. Spawn a subagent to verify this step first."
  - Match found → allow (continue to normal gate logic)

### 4. Phase Completion Gate (add to validate-phase.sh)

**validate-phase.sh changes — add check for BUILD and EVALUATE phases:**
- When validating BUILD or EVALUATE phase completion:
  - Read `.claude/state/verification-ledger.jsonl`
  - Check if at least one entry exists with matching `phase` and `sprint`
  - No entries → validation fails: "Phase completion requires at least one independent verification during this phase."
  - Entry exists → continue normal validation

## Verification Criteria (25 total)

### MCQ Q5 (9 criteria)
1. challenge.md contains Q5 with Yes/No options about unverified work
2. challenge.md header says "Answer all 5 questions"
3. challenge.md format example includes Q5
4. Q5 Yes/No options are shuffled (not always in same position)
5. Q5 "No" answer increments `no_verify_count` in verify-counter.json
6. Q5 "Yes" answer outputs nudge text to stderr
7. After 5 consecutive "No" answers, `hardened` is set to true
8. When hardened + no new ledger entry, validate-pre-flight.sh exits 1
9. Q1-Q4 validation is unchanged (same logic, same consumed-on-use)

### Agent Call Tracker (4 criteria)
10. Agent call with "verify" in prompt appends to verification-ledger.jsonl
11. Same call resets verify-counter.json to count 0 and hardened false
12. Agent call without verification language does NOT write ledger or reset counter
13. Ledger entry contains ts, step, phase, sprint, prompt_snippet fields

### Step Completion Gate (4 criteria)
14. Edit to watcher slot changing `[ ]` to `[x]` is detected
15. Non-trivial step without ledger entry is blocked (exit 2)
16. Non-trivial step with matching ledger entry is allowed
17. Trivial steps (read/search/explore/setup/claim) are allowed without ledger

### Phase Completion Gate (3 criteria)
18. BUILD phase-complete blocked if no ledger entries for current phase+sprint
19. EVALUATE phase-complete blocked if no ledger entries for current phase+sprint
20. Phase-complete allowed when ledger entry exists for current phase+sprint

### Integration (5 criteria)
21. pre-write-gate.sh continues to work unchanged
22. post-write-check.sh continues to work unchanged
23. settings.json has new PostToolUse Agent entry without breaking existing entries
24. All modified scripts pass bash -n syntax check
25. verify-counter.json missing = count 0 (not hardened); verification-ledger.jsonl missing = no entries (gates block)

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Agent games Q5 by always answering "No" | Counter hardens at 5 — eventually blocks |
| Agent spawns trivial subagent to reset counter | Verification language check filters non-verification calls |
| Step text fuzzy matching produces false negatives | Use first-30-chars case-insensitive match; if no match, fall back to any ledger entry for current phase |
| Q5 shuffling breaks existing Q1-Q4 shuffle logic | Q5 uses same `shuffle_options` function; isolated from Q1-Q4 |
| Watcher slot edit detection false positives | Only triggers on files matching `slot-*.md` path pattern AND `[x]` in new_string |

## Out of Scope

- Scanning file content for self-certification phrases (dropped — too noisy)
- Scanning agent conversational text (hooks can't see it)
- Modifying Agent tool behavior (we want to encourage Agent use, not restrict it)
- Changes to watcher system or cron reminders
- Changes to distractor pool
