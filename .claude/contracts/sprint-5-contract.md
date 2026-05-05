# Sprint 5 Contract: Verification Enforcement

**Rev 3** — 2026-04-06
**Reviewer issues addressed:** 14 original (4 HIGH, 6 MEDIUM, 4 LOW) + 2 from Rev 2 review

## What We Will Build

A three-point verification enforcement system that prevents agents from self-certifying work without independent subagent verification. Uses the existing MCQ infrastructure, with hard gates at structural checkpoints.

---

## Deliverable 1: MCQ Q5 — Verification Self-Report

### generate-pre-flight-challenge.sh

**Change 1a — New function `shuffle_binary` (insert after `pick_distractors` function, ~line 119):**

```bash
shuffle_binary() {
  local opt_a="$1"
  local opt_b="$2"
  local tmpf
  tmpf=$(mktemp)
  printf "CORRECT_MARK|%s\n" "$opt_a" > "$tmpf"
  printf "DISTRACT|%s\n" "$opt_b" >> "$tmpf"
  local shuffled
  shuffled=$(shuf "$tmpf")
  local labels=("A" "B")
  local idx=0
  local correct_label=""
  while IFS= read -r line; do
    local marker="${line%%|*}"
    local text="${line#*|}"
    printf "%s) %s\n" "${labels[$idx]}" "$text"
    if [ "$marker" = "CORRECT_MARK" ]; then
      correct_label="${labels[$idx]}"
    fi
    idx=$((idx + 1))
  done <<< "$shuffled"
  rm -f "$tmpf"
  printf "%s" "$correct_label" >&3
}
```

Rationale: `shuffle_options` expects 4 args (1 correct + 3 distractors). Q5 has only 2 options. A separate function avoids breaking existing Q1-Q4 logic. (Addresses reviewer Issue #1)

**Change 1b — Generate Q5 (insert after Q4 generation, ~line 140):**

```bash
# --- Generate Q5: Verification self-report ---
Q5_YES="Yes — I completed work that an independent subagent should check"
Q5_NO="No — all work since the last gate was trivial or already verified"
Q5_OPTIONS=$(shuffle_binary "$Q5_YES" "$Q5_NO" 3>/tmp/pf_q5_label)
Q5_YES_LABEL=$(cat /tmp/pf_q5_label 2>/dev/null)
```

Note: `Q5_YES_LABEL` is the letter (A or B) where the "Yes" option landed. This is written to the challenge via a metadata comment so the validator can re-derive it. (Addresses reviewer Issue #5)

**Change 1c — Update challenge.md template (line 143-167):**

Change header from "Answer all 4 questions" to "Answer all 5 questions".
Add `Q5: A` to the format example.
Add after Q4 block:

```
## Q5: Have you done work since the last gate that should be independently verified?
$Q5_OPTIONS
```

Add metadata comment at top (alongside existing source_slot comment):
```
<!-- q5_yes_label: $Q5_YES_LABEL -->
```

### validate-pre-flight.sh

**Change 1d — Extract Q5 Yes label from challenge metadata (insert at ~line 24, after SLOT_FILE extraction):**

```bash
Q5_YES_LABEL=$(grep -oP '<!-- q5_yes_label: \K[AB]' "$CHALLENGE_FILE" 2>/dev/null | head -1)
```

This is extracted BEFORE any file deletion. (Addresses reviewer Issue #5)

**Change 1e — Parse and validate Q5 (insert AFTER Q1-Q4 comparison block at ~line 178, BEFORE the rm -f on line 186):**

```bash
# --- Q5: Verification self-report (no wrong answer, but tracks behavior) ---
AGENT_Q5=$(parse_answer 5)
VERIFY_COUNTER=".claude/pre-flight/verify-counter.json"

# Read current counter state
if [ -f "$VERIFY_COUNTER" ]; then
  NO_COUNT=$(jq -r '.no_verify_count // 0' "$VERIFY_COUNTER" 2>/dev/null) || NO_COUNT=0
  HARDENED=$(jq -r '.hardened // false' "$VERIFY_COUNTER" 2>/dev/null) || HARDENED="false"
  LAST_RESET=$(jq -r '.last_reset // ""' "$VERIFY_COUNTER" 2>/dev/null) || LAST_RESET=""
  if ! [[ "$NO_COUNT" =~ ^[0-9]+$ ]]; then NO_COUNT=0; fi
else
  NO_COUNT=0
  HARDENED="false"
  LAST_RESET=""
fi

# Check hardened state BEFORE processing Q5
if [ "$HARDENED" = "true" ]; then
  LEDGER=".claude/state/verification-ledger.jsonl"
  HAS_NEW_ENTRY="false"
  if [ -f "$LEDGER" ] && [ -n "$LAST_RESET" ]; then
    LATEST_TS=$(tail -1 "$LEDGER" | jq -r '.ts // ""' 2>/dev/null)
    if [ -n "$LATEST_TS" ] && [[ "$LATEST_TS" > "$LAST_RESET" ]]; then
      HAS_NEW_ENTRY="true"
    fi
  fi
  if [ "$HAS_NEW_ENTRY" = "false" ]; then
    FAILURES=$((FAILURES + 1))
    FAIL_MSG="${FAIL_MSG}BLOCKED: You have answered 'no verification needed' 5 times without spawning a verification subagent. You MUST use the Agent tool to spawn an independent verifier before continuing. The Agent prompt must include verification language (verify, review, evaluate, validate, audit, assess).\n"
  fi
fi

# Process Q5 answer (only if Q1-Q4 passed and not hardened-blocked)
if [ "$FAILURES" -eq 0 ] && [ -n "$AGENT_Q5" ] && [ -n "$Q5_YES_LABEL" ]; then
  if [ "$AGENT_Q5" = "$Q5_YES_LABEL" ]; then
    # Agent said "Yes" — needs verification
    printf "NUDGE: You acknowledged unverified work. Spawn an independent subagent (Agent tool) to verify before continuing.\n" >&2
    # Don't increment no_verify_count for "Yes" answers
  else
    # Agent said "No" — increment counter
    NO_COUNT=$((NO_COUNT + 1))
    if [ "$NO_COUNT" -ge 5 ]; then
      HARDENED="true"
    fi
  fi
  # Save counter (timestamp format: ISO 8601 for lexicographic comparison)
  mkdir -p .claude/pre-flight
  jq -n --argjson nc "$NO_COUNT" --arg h "$HARDENED" --arg lr "$LAST_RESET" \
    '{"no_verify_count": $nc, "hardened": ($h == "true"), "last_reset": $lr}' > "$VERIFY_COUNTER"
fi
```

Timestamp comparison uses ISO 8601 strings with `[[ "$a" > "$b" ]]` which works for lexicographic ordering. (Addresses reviewer Issues #9, #11)

Hardened check runs BEFORE Q5 processing. The hardened block takes effect on the SAME MCQ cycle where it's detected (not the next one). If hardened, the validation fails and the agent must spawn a subagent before retrying. (Addresses reviewer Issue #11)

---

## Deliverable 2: Agent Call Tracker

### New file: `~/.claude/hooks/agent-call-tracker.sh`

**Data access:** PostToolUse hooks receive data via environment variables. For Agent tool, the expected variable is `TOOL_INPUT_PROMPT`. BUILD step 1 will empirically verify this by deploying a test hook that dumps all available env vars for an Agent call. If `TOOL_INPUT_PROMPT` is not available, fall back to reading stdin JSON. (Addresses reviewer Issue #2)

**Verification language pattern:** To reduce false positives from common words like "check" and "test", use a compound pattern requiring EITHER:
- A strong verification keyword: `verify|validate|audit|assess|evaluate independently|independent review`
- OR a moderate keyword + context: `(review|check|test|evaluate).*(work|output|result|implementation|changes|code|document|step|criteria)`

This is implemented as two grep passes. The first checks for strong keywords. If not found, the second checks for moderate+context. (Addresses reviewer Issue #8)

**Logic:**
1. Read prompt from `TOOL_INPUT_PROMPT` env var (or stdin fallback)
2. Check for verification language (compound pattern above)
3. If verification language found:
   - Extract current step from watcher slot (same sed pattern as pre-flight-gate.sh step 3)
   - Read phase+sprint from `.claude/state/current-phase.json`
   - Append to `.claude/state/verification-ledger.jsonl`:
     ```json
     {"ts":"ISO8601","step":"step text","phase":"BUILD","sprint":5,"prompt_snippet":"first 100 chars"}
     ```
   - Reset `.claude/pre-flight/verify-counter.json`:
     ```json
     {"no_verify_count":0,"hardened":false,"last_reset":"ISO8601"}
     ```
4. If no verification language: silent pass, no output
5. Output: `printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":""}}'`

### settings.json change

Add to PostToolUse array as a NEW third entry (after existing Write|Edit and Bash entries):

```json
{
  "matcher": "Agent",
  "hooks": [
    {
      "type": "command",
      "command": "bash $HOME/.claude/hooks/agent-call-tracker.sh"
    }
  ]
}
```

Final PostToolUse array will have 3 entries: Write|Edit, Bash, Agent. (Addresses reviewer Issue #13)

---

## Deliverable 3: Step Completion Gate

### pre-flight-gate.sh changes

**The watcher exemption problem (reviewer Issues #3, #4):**

Currently line 26-28 exempts ALL writes to `.openclaw/watchers/`:
```bash
if printf '%s' "$TARGET_NORM" | grep -qF '.openclaw/watchers/'; then
  exit 0
fi
```

**Change 3a — Replace the blanket watcher exemption with a conditional one (lines 26-28):**

```bash
# Exempt: watcher slot files — UNLESS this is a step check-off (Edit with [x])
if printf '%s' "$TARGET_NORM" | grep -qF '.openclaw/watchers/'; then
  # Check if this is an Edit changing [ ] to [x]
  TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
  if [ "$TOOL_NAME" = "Edit" ]; then
    OLD_STR=$(printf '%s' "$INPUT" | jq -r '.tool_input.old_string // ""' 2>/dev/null)
    NEW_STR=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // ""' 2>/dev/null)
    if printf '%s' "$OLD_STR" | grep -qF '[ ]' && printf '%s' "$NEW_STR" | grep -qF '[x]'; then
      # This IS a step check-off — do NOT exempt, fall through to step gate
      :
    else
      exit 0  # Normal watcher edit — exempt
    fi
  else
    exit 0  # Write to watcher — exempt (accepted limitation: agent could use Write to bypass)
  fi
fi
```

This addresses Issues #3 and #4. Write-based bypass is an accepted limitation documented in the contract. The agent would need to rewrite the entire slot file to bypass, which is detectable but not worth the complexity to gate. (Addresses reviewer Issue #12)

**Change 3b — Step completion gate logic (insert after the modified watcher exemption, before counter logic at ~line 54):**

```bash
# --- Step completion gate: block [x] check-off without verification ---
if printf '%s' "$TARGET_NORM" | grep -qF '.openclaw/watchers/slot-'; then
  # We reach here only for Edit check-offs ([ ] -> [x])
  STEP_TEXT=$(printf '%s' "$NEW_STR" | grep -F '[x]' | head -1 | sed 's/^[[:space:]]*- \[x\][[:space:]]*//')

  # Trivial steps don't need verification
  TRIVIAL_PATTERN='[Rr]ead|[Ss]earch|[Ee]xplore|[Ss]et up|[Cc]laim|[Ll]oad|[Ll]ist'
  if printf '%s' "$STEP_TEXT" | grep -qE "$TRIVIAL_PATTERN"; then
    exit 0  # Trivial step — allow without ledger check
  fi

  # Check verification ledger for matching entry
  LEDGER=".claude/state/verification-ledger.jsonl"
  if [ -f "$LEDGER" ]; then
    # Extract first 30 chars of step text, lowercase, for matching
    MATCH_PREFIX=$(printf '%s' "$STEP_TEXT" | head -c 30 | tr '[:upper:]' '[:lower:]')
    if grep -iF "$MATCH_PREFIX" "$LEDGER" >/dev/null 2>&1; then
      exit 0  # Matching ledger entry found — allow
    fi
  fi

  # No match — block
  printf "BLOCKED: You cannot mark this step complete without independent verification.\n" >&2
  printf "Step: %s\n\n" "$STEP_TEXT" >&2
  printf "Spawn a subagent to verify this step first:\n" >&2
  printf "  Agent tool with prompt containing 'verify' + description of what to check.\n" >&2
  printf "  The Agent call will be tracked and added to the verification ledger.\n" >&2
  printf "  Then retry checking off this step.\n" >&2
  exit 2
fi
```

Step text matching uses first 30 chars, case-insensitive, via grep on the ledger file. The step text in the ledger is extracted by agent-call-tracker.sh using the same sed pattern, so prefixes should align. No fallback to "any entry for current phase" — each non-trivial step needs its own verification. (Addresses reviewer Issue #10)

---

## Deliverable 4: Phase Completion Gate

### validate-phase.sh changes

**Change 4a — Add verification ledger check (insert at the START of the BUILD case branch, before existing checks):**

```bash
# Check verification ledger for this phase+sprint
LEDGER=".claude/state/verification-ledger.jsonl"
CURRENT_SPRINT=$(jq -r '.sprint // 0' "${STATE_DIR}/current-phase.json" 2>/dev/null)
if [ -f "$LEDGER" ]; then
  PHASE_ENTRIES=$(grep -c "\"phase\":\"BUILD\"" "$LEDGER" 2>/dev/null || echo 0)
  # Tighter: also match sprint
  SPRINT_ENTRIES=$(grep "\"phase\":\"BUILD\"" "$LEDGER" | grep -c "\"sprint\":${CURRENT_SPRINT}" 2>/dev/null || echo 0)
else
  SPRINT_ENTRIES=0
fi

if [ "$SPRINT_ENTRIES" -eq 0 ]; then
  printf "FAIL: Phase completion requires at least one independent verification during BUILD (sprint %s).\n" "$CURRENT_SPRINT" >&2
  printf "Spawn a subagent to verify your work, then retry phase completion.\n" >&2
  exit 1
fi
```

Same pattern for EVALUATE case branch but with `"phase\":\"EVALUATE\"`.

**Note on phase naming:** `current-phase.json` stores phases as uppercase strings ("PLAN", "NEGOTIATE", "BUILD", "EVALUATE", "COMPLETE"). The ledger grep matches these exact strings. The `validate-phase.sh` case branch uses `3|"BUILD"|"EXECUTE")` — but the phase stored in JSON and written to the ledger is always "BUILD", never "EXECUTE" or "3". No mismatch risk.

Placed at START of case branch so it fails fast before other checks run. (Addresses reviewer Issue #7)

---

## Verification Criteria (26 total)

### MCQ Q5 (10 criteria)
1. challenge.md contains Q5 with Yes/No options about unverified work
2. challenge.md header says "Answer all 5 questions"
3. challenge.md format example includes Q5
4. Q5 options are shuffled using `shuffle_binary` (not `shuffle_options`)
5. Q5 "No" answer increments `no_verify_count` in verify-counter.json
6. Q5 "Yes" answer outputs nudge text to stderr
7. After 5 consecutive "No" answers, `hardened` is set to true in verify-counter.json
8. When hardened + no new ledger entry since last_reset, validate-pre-flight.sh exits 1 with block message
9. Q1-Q4 validation is unchanged (same logic, same consumed-on-use)
10. Q5 Yes label is extracted from challenge.md metadata comment BEFORE file deletion (consumed-on-use preserved)

### Agent Call Tracker (5 criteria)
11. Agent call with strong verification keyword appends to verification-ledger.jsonl
12. Same call resets verify-counter.json to count 0 and hardened false
13. Agent call without verification language does NOT write ledger or reset counter
14. Ledger entry contains ts, step, phase, sprint, prompt_snippet fields (all ISO 8601 timestamps)
15. BUILD step 1 empirically verifies whether Agent PostToolUse provides TOOL_INPUT_PROMPT env var

### Step Completion Gate (5 criteria)
16. Edit to watcher slot changing `[ ]` to `[x]` is detected (falls through watcher exemption)
17. Non-trivial step without ledger entry is blocked (exit 2) with instructive message
18. Non-trivial step with matching ledger entry (first 30 chars prefix match) is allowed
19. Trivial steps (read/search/explore/setup/claim/load/list) are allowed without ledger
20. Normal watcher edits (not check-offs) still pass through the exemption unchanged

### Phase Completion Gate (3 criteria)
21. BUILD phase-complete blocked if no ledger entries for current phase+sprint
22. EVALUATE phase-complete blocked if no ledger entries for current phase+sprint
23. Phase-complete allowed when ledger entry exists for current phase+sprint

### Integration (3 criteria)
24. pre-write-gate.sh and post-write-check.sh continue to work unchanged
25. settings.json has PostToolUse Agent entry as third array element, existing entries unchanged
26. All modified scripts pass bash -n syntax check

## Accepted Limitations

- Agent can use Write (not Edit) to rewrite entire watcher slot with steps pre-checked — accepted because this requires deliberate circumvention and is detectable in git history
- Q5 self-report is honesty-based for first 4 cycles — the counter hardens at 5 to catch sustained dishonesty
- `TOOL_INPUT_PROMPT` env var existence for Agent PostToolUse is unverified — BUILD step 1 tests this empirically; fallback to stdin documented

## Out of Scope

- Scanning file content for self-certification phrases
- Scanning agent conversational text
- Modifying Agent tool behavior
- Changes to watcher system, cron, or distractor pool
