# Sprint 21 Contract: Cognitive Guidance Layer

## Scope

Add phase-specific behavioral prompts, task-size-adaptive protocol guidance, and a fix-attempt hard ceiling to the harness. The turn packet already tells agents WHAT to do; this sprint teaches them HOW to think in each phase. Gates remain untouched as safety nets.

## Deliverables

### D1: Phase-Specific Cognitive Prompts (on-prompt-submit.sh)

Add a new `GUIDANCE` section to the turn packet, positioned immediately after the state summary line and before READ FIRST. Contains a single line of phase-appropriate behavioral framing:

**PLAN phase:**
```
GUIDANCE: Outcome-first — define result, criteria, constraints, stop condition BEFORE spec. Ambiguous request? Ask — do not assume.
```

**NEGOTIATE phase:**
```
GUIDANCE: Skeptical reviewer — challenge your proposal. What fails? What's vague? Binary pass/fail criteria. Max 3 self-revisions.
```

**BUILD phase:**
```
GUIDANCE: Executor — proceed on clear, low-risk, reversible steps. ASK only for destructive/irreversible/scope-changing. No "should I continue?" — continue.
```

**EVALUATE phase:**
```
GUIDANCE: Adversarial verifier — default FAIL. Every criterion needs fresh evidence. Do not read progress-notes.md. No benefit of doubt.
```

**COMPLETE phase:**
```
GUIDANCE: Handoff — name outcome (finished/blocked/failed), list evidence, state what user verifies. No "would you like me to..." softeners.
```

**UNKNOWN phase:** No guidance injected.

Guidance text is static per phase — read from a case statement, not computed. Each line is under 160 chars. Adds ~100-150 chars to packet.

### D2: Task Size Advisory (on-prompt-submit.sh)

Detect task size from watcher slot SCOPE text and inject a protocol-level hint. Detection uses keyword matching on the watcher SCOPE field (already extracted by `read_watcher_step_scope`):

**Trivial detection patterns** (any match → LIGHTWEIGHT):
- SCOPE contains: "config", "typo", "rename", "single file", "one file", "one-line", "env var", "bump version"

**Large detection patterns** (any match → FULL):
- SCOPE contains: "new system", "cross-cutting", "multi-feature", "architecture", "refactor all", "migration"

**Default**: STANDARD (no extra hint injected — this is the normal path)

When detected:
- LIGHTWEIGHT: `PROTOCOL: Lightweight — implement, test, verify inline. No contract or sub-agent verifier required.`
- FULL: `PROTOCOL: Full — PRD artifact (.claude/specs/prd-*.md) and test spec (.claude/specs/test-spec-*.md) required before BUILD.`
- STANDARD: Nothing injected (zero overhead for normal tasks).

This is advisory guidance, not a gate. It appears after the GUIDANCE line when applicable. Adds 0-120 chars.

### D3: Fix Attempt Hard Ceiling (on-prompt-submit.sh only)

Extend strategy loop state with fix attempt tracking:

**In `strategy-loop-state.json`**: Add `fix_cycle_count` (integer) and `max_fix_cycles` (integer, default 3) fields.

**Increment logic in `on-prompt-submit.sh`**: The existing strategy loop section already reads `strategy-loop-state.json` and processes tier-2 blocks. Add detection for the transition from `"blocked":true` to strategy-ack.md existing — this means the agent wrote a new strategy to clear a tier-2 block. When this transition is detected, increment `fix_cycle_count` in the state file via `atomic_write`. (Note: strategy-ack.md acceptance/clearing happens in `pre-write-gate.sh`, but the gate scripts are NOT IN SCOPE. The increment is detected in on-prompt-submit.sh by observing the state change.)

**STUCK injection in `on-prompt-submit.sh`**: When `fix_cycle_count >= max_fix_cycles` (default 3):
- Inject as hard block: `BLOCKED BY: STUCK — 3 fix cycles exhausted. STOP. Write .claude/state/stuck-report.md (approaches tried, raw errors, what you need). WAIT for user.`
- This is a terminal state — no soft action can clear it. Only user intervention (deleting `strategy-loop-state.json` or resetting `fix_cycle_count` to 0) resets.

**Sprint reset**: When `on-prompt-submit.sh` detects the current sprint number differs from a `last_sprint` field stored in `strategy-loop-state.json`, reset `fix_cycle_count` to 0.

### D4: Verifier Prompt Injection (on-prompt-submit.sh)

When the phase is EVALUATE, inject additional verifier constraints into the turn packet:

```
VERIFIER RULES: 1) Do NOT read .claude/state/progress-notes.md 2) Test from scratch using sprint contract criteria only 3) Default verdict is FAIL — pass requires positive evidence for every criterion 4) Report: criterion number, pass/fail, evidence snippet (file:line or command output)
```

This is ~250 chars. It appears after GUIDANCE when phase is EVALUATE. Combined with the EVALUATE guidance line, this gives verifiers a hard behavioral frame.

## NOT In Scope

- Changing gate scripts (pre-write-gate.sh, pre-bash-gate.sh, pre-flight-gate.sh)
- Adding new gate scripts or hooks
- Changing any gate exit code or blocking behavior
- Implementing requirements clarification as a hard gate (future sprint)
- Implementing PRD/test-spec as hard gates for FULL protocol (future sprint)
- Worker scope boundaries for sub-agents (future sprint)
- Idle detection / active nudging (future sprint)

## Acceptance Criteria (33 items)

### Phase Guidance (8)
1. PLAN phase packet contains outcome-first guidance text.
2. NEGOTIATE phase packet contains skeptical-reviewer guidance text.
3. BUILD phase packet contains executor-mode guidance text with auto-continue/ask rules.
4. EVALUATE phase packet contains adversarial-verifier guidance text.
5. COMPLETE phase packet contains structured-handoff guidance text.
6. UNKNOWN phase injects no guidance.
7. Guidance appears immediately after the state summary line, before READ FIRST.
8. Each guidance line is under 160 characters.

### Task Size Advisory (5)
9. Watcher SCOPE containing "config" or "typo" or "single file" triggers LIGHTWEIGHT advisory.
10. Watcher SCOPE containing "new system" or "architecture" or "migration" triggers FULL advisory.
11. Default (no pattern match) injects nothing (zero overhead).
12. Advisory appears after GUIDANCE line when present.
13. Task size detection is read-only — no state files written.

### Fix Ceiling (8)
14. `strategy-loop-state.json` gains `fix_cycle_count`, `max_fix_cycles`, and `last_sprint` fields.
15. `fix_cycle_count` increments when on-prompt-submit.sh detects transition from `blocked:true` state to strategy-ack.md existing.
16. When `fix_cycle_count >= max_fix_cycles` (default 3), a STUCK hard block appears in the turn packet.
17. STUCK block message tells agent to write `stuck-report.md` and STOP.
18. STUCK state cannot be cleared by the agent — only by user intervention.
19. Sprint advance resets `fix_cycle_count` to 0 (detected via `last_sprint` field mismatch).
20. Setting `max_fix_cycles` to 5 in the state file results in STUCK triggering at 5, not 3.
21. When `fix_cycle_count` is 2 and a tier-2 block is cleared, count becomes 3 (confirmed by reading state file).

### Verifier Injection (4)
22. EVALUATE phase packet contains VERIFIER RULES section.
23. VERIFIER RULES explicitly prohibits reading progress-notes.md.
24. VERIFIER RULES requires per-criterion evidence format (criterion, pass/fail, evidence).
25. VERIFIER RULES section appears only during EVALUATE phase.

### Safety (4)
26. Gate scripts have zero diff: pre-write-gate.sh, pre-bash-gate.sh, pre-flight-gate.sh untouched.
27. lib-helpers.sh existing functions unchanged; only additive changes allowed.
28. on-prompt-submit.sh existing features preserved: must-do injection/log, evidence checkpoint guidance, strategy loop nudge/block, watcher cockpit.
29. The hard packet cap in on-prompt-submit.sh is raised from 1490 to 2000 to accommodate new sections without truncation.

### Quality (4)
30. Worst-case realistic packet (EVALUATE + FULL + verifier rules + watcher cockpit + 1 hard block) stays under 2000 chars.
31. Unblocked BUILD-phase steady-state packet (guidance + state summary + watcher cockpit) stays under 700 chars.
32. Unblocked PLAN-phase packet (guidance + state summary, no watcher) stays under 300 chars.
33. EVALUATE-phase packet without blocks (guidance + verifier rules + watcher cockpit) stays under 900 chars.

## Verification

Independent verifier must:
1. Syntax-check changed shell files with `bash -n`.
2. Simulate each phase (PLAN, NEGOTIATE, BUILD, EVALUATE, COMPLETE, UNKNOWN) and confirm correct guidance text appears or is absent.
3. Simulate trivial/large/standard watcher SCOPE and confirm advisory behavior.
4. Simulate fix_cycle_count at 0, 2, 3, 4, 5 with both default and custom max_fix_cycles and confirm tier escalation.
5. Verify EVALUATE phase includes both GUIDANCE and VERIFIER RULES.
6. Measure packet lengths: worst-case realistic (under 2000), steady-state BUILD (under 700), bare PLAN (under 300), EVALUATE no-blocks (under 900).
7. Diff gate scripts against pre-sprint state; must be zero diff.
8. Verify the hard cap in on-prompt-submit.sh was raised to 2000.
9. Verify all 33 acceptance criteria with explicit pass/fail per criterion.

## Implementation Constraints

- `sed 's|\\|/|g'` crashes on MSYS — use `tr '\\' '/'` for path normalization.
- Strip Windows jq CR with `tr -d '\r'`.
- `while IFS= read -r` loops need `|| [ -n "$var" ]`.
- `grep -E` does not support `\d`; use `[0-9]`.
- Avoid here-strings in hook subprocesses; use pipes/temp files.
- Hook runs on every prompt; all new logic must be bounded/static lookups.
- Watcher project matching uses `pwd -W` fallback, lowercase, forward slashes.
- Guidance text is hardcoded per phase — no file reads, no computation.
