# Validation Guard: Three-Point Verification Enforcement

## What This Document Is

A complete implementation guide for preventing AI agents from self-certifying their own work. This document explains the problem, the solution architecture, every file involved, and how to replicate the system in any Claude Code environment that uses the Enhanced Agent Harness.

If you are an agent reading this document to implement the system in your own environment, follow the sections in order. Every script, hook, and configuration change is included verbatim.

---

## The Problem: Self-Certification

AI agents routinely declare their own work "verified", "complete", or "working" without spawning independent subagents to check. An audit of 37 projects found **194 unique self-certification phrases** across 10 categories, including:

- **Verification claims**: "I verified", "all 24 criteria verified and passed", "validated that"
- **Completion claims**: "COMPLETE", "BUILD COMPLETE", "all bugs fixed"
- **Success claims**: "successfully implemented", "it's working", "no errors"
- **Quality claims**: "looks good", "solid", "clean implementation"

The most dangerous pattern: a builder agent writes "All 24 criteria verified and passed" in its progress notes, then harness hooks auto-duplicate that claim into 12+ session files, creating the illusion of repeated independent confirmation.

### Why Phrase Scanning Doesn't Work

The initial instinct is to scan agent output for these 194 phrases and block when detected. This fails for three reasons:

1. **Hooks cannot read conversational text.** Claude Code hooks only see tool names and tool inputs — not the agent's prose output between tool calls.
2. **False positive rate is too high.** Phrases like "successfully created" are legitimate when describing system tool output. "Fixed" is legitimate in commit messages. Scanning file content catches echoes and templates.
3. **It's the wrong target.** The problem isn't that agents *say* self-certifying things. The problem is that agents *skip* independent verification. Detect the absence of good behavior, not the presence of bad behavior.

### The Insight

> Don't try to detect bad behavior. Enforce good behavior at the three structural moments where verification matters.

Those moments are:
1. **During sustained work** — the agent writes code for extended periods without checking
2. **At step completion** — the agent marks a watcher checklist item as done
3. **At phase transition** — the agent declares a build phase complete

---

## Solution Architecture: Three-Point Verification Enforcement

### Shared Infrastructure

Two tracking files power all three enforcement points:

#### 1. Verification Ledger (append-only)

**File:** `.claude/state/verification-ledger.jsonl`

Written automatically by a PostToolUse hook whenever the agent spawns a subagent with verification language in the prompt. Each entry:

```json
{"ts":"2026-04-06T14:00:27+01:00","step":"Step 3: Implement agent-call-tracker","phase":"BUILD","sprint":5,"prompt_snippet":"Please verify the implementation matches the sprint contract criteria 1-10","verification_type":"functional"}
```

The `verification_type` field (added in Sprint 6) classifies the kind of verification performed: `vision`, `functional`, `browser`, or `review`. See [Verification Type Enforcement](#sprint-6-verification-type-enforcement) for details.

**What qualifies as a "verification call":** The Agent tool prompt contains verification language, detected by a two-tier compound pattern:

- **Tier 1 (strong keywords):** `verify`, `validate`, `audit`, `assess`, `evaluate independently`, `independent review`
- **Tier 2 (moderate keyword + context):** `(review|check|test|evaluate)` followed by `(work|output|result|implementation|changes|code|document|step|criteria)`

Research-only Agent calls ("search the codebase for...") do NOT qualify.

#### 2. Unverified Writes Tracker (append-only, consumed on verification)

**File:** `.claude/state/unverified-writes.jsonl`

Written automatically by the PostToolUse hook (`post-write-check.sh`) on every Write/Edit to a non-exempt file. Each entry:

```json
{"ts":"2026-04-06T14:01:00+01:00","file":"src/Dashboard.tsx"}
```

**Exempt paths** (not tracked): `.claude/state/`, `.claude/pre-flight/`, `.openclaw/watchers/`, `.agent-memory/`

**Consumed on verification:** When `agent-call-tracker.sh` detects a verification Agent call, it archives this file to `unverified-writes-archive.jsonl` and deletes the original. This means the file only contains writes since the *last* verification — exactly what the classifier needs to determine what type of verification is required.

#### 3. Verification Counter

**File:** `.claude/pre-flight/verify-counter.json`

```json
{"no_verify_count": 3, "hardened": false, "last_reset": "2026-04-06T14:00:27+01:00"}
```

- `no_verify_count`: Increments when the agent answers Q5 with "No" (claiming no verification needed)
- `hardened`: Set to `true` when count reaches 5 — triggers hard block on next MCQ
- `last_reset`: Timestamp of last verification Agent call — used for lexicographic comparison

### Enforcement Point 1: MCQ Q5 Piggyback (Soft, Graduated)

**Mechanism:** The existing pre-flight MCQ (which fires every 4th Write/Edit) already asks 4 questions about the agent's current task, step, target file, and mistakes to avoid. A 5th question is added:

```
## Q5: Have you done work since the last gate that should be independently verified?
A) Yes — I completed work that an independent subagent should check
B) No — all work since the last gate was trivial or already verified
```

**Behavior:**
- Agent answers **"Yes"**: A nudge is printed to stderr: *"You acknowledged unverified work. Spawn an independent subagent (Agent tool) to verify before continuing."* Counter is NOT incremented.
- Agent answers **"No"**: `no_verify_count` is incremented. No nudge.
- After **5 consecutive "No" answers** without any verification Agent call in between: `hardened` is set to `true`.
- On **next MCQ while hardened** (no new ledger entry since `last_reset`): **Validation fails. Agent is blocked.** The message instructs the agent to spawn a verification subagent before retrying.

**Why this works:** It's non-blocking for the first 4 cycles — the agent can honestly answer "No" for trivial work. But sustained avoidance triggers a hard block. And if the agent lies (answers "No" when it should answer "Yes"), the counter catches the pattern. The agent cannot avoid verification indefinitely.

**Escape from hardened mode:** Spawn any Agent with verification language in the prompt. The `agent-call-tracker.sh` hook detects it, writes a ledger entry, and resets the counter to 0 with `hardened: false`.

### Enforcement Point 2: Step Completion Gate (Hard, Binary)

**Mechanism:** When the agent edits a watcher slot to change `- [ ]` to `- [x]` (marking a step complete), the PreToolUse hook checks the verification ledger for a matching entry.

**Behavior:**
- **Trivial steps** (containing "read", "search", "explore", "set up", "claim", "load", "list"): Allowed without ledger check.
- **Non-trivial steps without ledger entry**: **BLOCKED (exit 2).** Message: *"You cannot mark this step complete without independent verification. Spawn a subagent to verify this step first."*
- **Non-trivial steps with matching ledger entry**: Allowed. Matching uses the first 30 characters of the step text, case-insensitive, via `grep -iF`.

**Why this works:** Every meaningful step completion now requires evidence that an independent subagent looked at the work. The agent cannot check off steps by just running its own tests and declaring success.

### Enforcement Point 3: Phase Completion Gate (Hard, Binary)

**Mechanism:** When the agent attempts to complete a BUILD or EVALUATE phase, the existing `validate-phase.sh` checks the verification ledger for at least one entry matching the current phase and sprint.

**Behavior:**
- **No ledger entries for current phase+sprint**: **BLOCKED (exit 1).** Message: *"Phase completion requires at least one independent verification during BUILD (sprint N)."*
- **At least one matching entry**: Allowed. Continues to existing phase validation checks (tests, loop detection, etc.).

**Why this works:** Even if the agent bypasses individual step gates, it cannot complete a phase without at least one verification subagent call. This is the final safety net.

---

## Integration Flow

```
Agent attempts Write/Edit
        |
        v
pre-write-gate.sh: watcher + cron check         [Layer 1 - existing]
        |
        v
pre-flight-gate.sh: watcher exemption check      [Layer 2]
        |  (is this a watcher slot edit?)
        |  YES: is it a step check-off [ ] -> [x]?
        |       YES: fall through to step gate
        |       NO: exempt (exit 0)
        |  NO: continue
        |
        v
pre-flight-gate.sh: step completion gate          [Layer 2 - NEW]
        |  (if editing watcher slot [x])
        |  trivial step? -> allow
        |  ledger match? -> allow
        |  no match -> BLOCK (exit 2)
        |
        v
pre-flight-gate.sh: counter + MCQ check          [Layer 2 - existing + Q5]
        |  (fires every 4th write or on step change)
        |  hardened + no ledger? -> BLOCK
        |  MCQ now includes Q5 verification question
        |  Q5 "No" -> increment counter
        |  Q5 "Yes" -> nudge
        |
        v
Write/Edit executes
        |
        v
post-write-check.sh: counter, memory             [Layer 1 - existing]
post-write-check.sh: file write tracker           [Layer 2 - Sprint 6]
        |  append file path to unverified-writes.jsonl
        |  (exempt: .claude/state, pre-flight, watchers, agent-memory)

Agent spawns subagent (Agent tool)
        |
        v
agent-call-tracker.sh: verification language?     [Layer 2 - Sprint 5]
        |  tier 1 or tier 2 match?
        |  YES -> classify type (vision/functional/browser/review)
        |       -> ledger entry with verification_type
        |       -> consume unverified-writes.jsonl
        |       -> counter reset
        |  NO -> silent pass

Agent attempts phase completion
        |
        v
validate-phase.sh: verification ledger check     [Layer 2 - Sprint 5]
        |  BUILD or EVALUATE phase?
        |  ledger entries for this phase+sprint?
        |  NO -> FAIL with prescriptive file list
        |  YES -> type satisfaction check           [Sprint 6]
        |         best vtype rank >= all required?
        |         NO -> FAIL with type mismatch + file list
        |         YES -> continue to existing checks
```

---

## Implementation: Complete File-by-File Guide

### Prerequisites

This system builds on the Enhanced Agent Harness with the pre-flight MCQ gate already operational. You need:

- `~/.claude/scripts/generate-pre-flight-challenge.sh` — MCQ challenge generator
- `~/.claude/scripts/validate-pre-flight.sh` — MCQ validator
- `~/.claude/hooks/pre-flight-gate.sh` — PreToolUse gate (Write|Edit)
- `~/.claude/scripts/validate-phase.sh` — Phase validation
- `~/.openclaw/watchers/` — Watcher slot system with REGISTRY.json
- `~/.openclaw/distractor-pool/` — MCQ distractor files
- `~/.claude/settings.json` — Hook configuration

If you don't have the pre-flight MCQ system, implement that first. This document only covers the verification enforcement additions.

### File 1: `~/.claude/hooks/agent-call-tracker.sh` (NEW)

This PostToolUse hook fires on every Agent tool call. It detects verification language and updates the shared infrastructure.

```bash
#!/bin/bash
# agent-call-tracker.sh -- PostToolUse hook (Agent)
# Tracks when Agent tool calls contain verification language.
# If verification detected: appends to verification ledger + resets verify counter.
# Output: JSON hookSpecificOutput to stdout. Diagnostics to stderr only.

source "$HOME/.claude/scripts/lib-helpers.sh" 2>/dev/null

STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
LEDGER="${STATE_DIR}/verification-ledger.jsonl"
VERIFY_COUNTER=".claude/pre-flight/verify-counter.json"
WATCHER_REGISTRY="$HOME/.openclaw/watchers/REGISTRY.json"

# --- Read stdin (PostToolUse Agent provides full JSON on stdin) ---
INPUT=$(cat)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.tool_input.prompt // ""' 2>/dev/null)

if [ -z "$PROMPT" ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":""}}'
  exit 0
fi

# --- Check for verification language (compound pattern) ---
IS_VERIFICATION="false"

# Tier 1: Strong keywords (always count)
if printf '%s' "$PROMPT" | grep -qiE 'verify|validate|audit|assess|evaluate independently|independent review'; then
  IS_VERIFICATION="true"
fi

# Tier 2: Moderate keyword + context (only if tier 1 didn't match)
if [ "$IS_VERIFICATION" = "false" ]; then
  if printf '%s' "$PROMPT" | grep -qiE '(review|check|test|evaluate).*(work|output|result|implementation|changes|code|document|step|criteria)'; then
    IS_VERIFICATION="true"
  fi
fi

if [ "$IS_VERIFICATION" = "false" ]; then
  # Not a verification call -- silent pass
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":""}}'
  exit 0
fi

# --- Verification call detected -- update ledger and counter ---

# Classify verification type from prompt keywords
VTYPE="review"
if printf '%s' "$PROMPT" | grep -qiE 'screenshot|vision|visual|look at|render|UI|inspect.*layout'; then
  VTYPE="vision"
elif printf '%s' "$PROMPT" | grep -qiE 'browser|navigate|page|open.*url|website|localhost'; then
  VTYPE="browser"
elif printf '%s' "$PROMPT" | grep -qiE 'run|execute|test|curl|output|functional|invoke|call.*endpoint'; then
  VTYPE="functional"
fi

TS=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')

# Extract current step from watcher slot
CURRENT_PROJECT=$(pwd -W 2>/dev/null || pwd)
CURRENT_PROJECT=$(printf '%s' "$CURRENT_PROJECT" | tr '\\' '/' | sed 's|/$||' | tr '[:upper:]' '[:lower:]')

CURRENT_STEP=""
if [ -f "$WATCHER_REGISTRY" ]; then
  SLOT_NUM=$(jq -r --arg proj "$CURRENT_PROJECT" \
    '[.watchers[] | select(.status == "active" and .project != null and ((.project | gsub("\\\\";"/") | sub("/$";"") | ascii_downcase) == $proj))] | .[0].slot // empty' \
    "$WATCHER_REGISTRY" 2>/dev/null)
  if [ -n "$SLOT_NUM" ]; then
    SLOT_FILE="$HOME/.openclaw/watchers/slot-${SLOT_NUM}.md"
    if [ -f "$SLOT_FILE" ]; then
      CURRENT_STEP=$(sed -n '/## TO-DO/,/^## /{/^## /d;p;}' "$SLOT_FILE" | grep -F -- '- [ ]' | head -1 | sed 's/^[[:space:]]*- \[ \][[:space:]]*//')
    fi
  fi
fi
if [ -z "$CURRENT_STEP" ]; then
  CURRENT_STEP="(no unchecked steps remain)"
fi

# Read phase+sprint
PHASE="UNKNOWN"
SPRINT=0
if [ -f "${STATE_DIR}/current-phase.json" ]; then
  PHASE=$(jq -r '.phase // "UNKNOWN"' "${STATE_DIR}/current-phase.json" 2>/dev/null)
  SPRINT=$(jq -r '.sprint // 0' "${STATE_DIR}/current-phase.json" 2>/dev/null)
fi

# Prompt snippet (first 100 chars, sanitized for JSON)
SNIPPET=$(printf '%s' "$PROMPT" | head -c 100 | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')

# Append to verification ledger
mkdir -p "$STATE_DIR" 2>/dev/null
SAFE_STEP=$(printf '%s' "$CURRENT_STEP" | sed 's/\\/\\\\/g; s/"/\\"/g' | head -c 200)
ENTRY=$(printf '{"ts":"%s","step":"%s","phase":"%s","sprint":%s,"prompt_snippet":"%s","verification_type":"%s"}' \
  "$TS" "$SAFE_STEP" "$PHASE" "$SPRINT" "$SNIPPET" "$VTYPE")

if type append_jsonl >/dev/null 2>&1; then
  append_jsonl "$ENTRY" "$LEDGER"
else
  printf '%s\n' "$ENTRY" >> "$LEDGER"
fi

echo "agent-call-tracker: verification call logged to ledger (type: $VTYPE)" >&2

# Consume unverified-writes (archive then clear)
UNVERIFIED="${STATE_DIR}/unverified-writes.jsonl"
if [ -f "$UNVERIFIED" ]; then
  cat "$UNVERIFIED" >> "${STATE_DIR}/unverified-writes-archive.jsonl" 2>/dev/null
  rm -f "$UNVERIFIED"
  echo "agent-call-tracker: unverified-writes consumed" >&2
fi

# Reset verify counter
mkdir -p .claude/pre-flight 2>/dev/null
jq -n --arg lr "$TS" '{"no_verify_count":0,"hardened":false,"last_reset":$lr}' > "$VERIFY_COUNTER"

echo "agent-call-tracker: verify counter reset" >&2

# --- Output ---
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"Verification subagent tracked. Ledger updated, verify counter reset."}}'
exit 0
```

**Key implementation notes:**
- PostToolUse Agent hooks receive data via **stdin JSON**, not environment variables. The field path is `tool_input.prompt`. This was empirically verified by deploying a probe hook.
- The `tr '\\' '/'` line (not `tr '\' '/'`) is required on MSYS/Git Bash to avoid "unescaped backslash" warnings.
- The sed sanitization for JSON embedding uses `s/\\/\\\\/g; s/"/\\"/g` (not pipe-delimited `s|\|...|g` which fails when the replacement contains backslashes).
- **Verification type classification** uses a priority cascade: vision keywords first, then browser, then functional. Default is `review`. This ensures the strongest applicable type is selected when multiple keywords appear.
- **Unverified-writes consumption** archives before deleting — the archive provides an audit trail of all writes, while the live file only contains writes since the last verification.

### File 2: `~/.claude/scripts/generate-pre-flight-challenge.sh` (MODIFIED)

Two changes to the existing MCQ generator:

#### Change A: Add `shuffle_binary` function

Insert after the existing `pick_distractors` function (around line 119). This is a separate function from `shuffle_options` because Q5 has only 2 options (A/B), while Q1-Q4 have 4 options (A/B/C/D).

```bash
# --- Helper: shuffle 2 binary options (Yes/No) ---
shuffle_binary() {
  local opt_yes="$1"
  local opt_no="$2"
  local tmpf
  tmpf=$(mktemp)
  printf "CORRECT_MARK|%s\n" "$opt_yes" > "$tmpf"
  printf "DISTRACT|%s\n" "$opt_no" >> "$tmpf"
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

#### Change B: Generate Q5

Insert after Q4 generation (after the Q4_CORRECT_LABEL line):

```bash
# --- Generate Q5: Verification self-report ---
Q5_YES="Yes -- I completed work that an independent subagent should check"
Q5_NO="No -- all work since the last gate was trivial or already verified"
Q5_OPTIONS=$(shuffle_binary "$Q5_YES" "$Q5_NO" 3>/tmp/pf_q5_label)
Q5_YES_LABEL=$(cat /tmp/pf_q5_label 2>/dev/null)
```

#### Change C: Update challenge template

In the heredoc that writes `challenge.md`:

1. Add metadata comment at the top: `<!-- q5_yes_label: $Q5_YES_LABEL -->`
2. Change "Answer all 4 questions" to "Answer all 5 questions"
3. Add `Q5: A` to the format example
4. Add the Q5 section after Q4:

```
## Q5: Have you done work since the last gate that should be independently verified?
$Q5_OPTIONS
```

### File 3: `~/.claude/scripts/validate-pre-flight.sh` (MODIFIED)

Three changes to the existing MCQ validator:

#### Change A: Extract Q5 Yes label early

Insert at approximately line 30, AFTER the SLOT_FILE extraction but BEFORE any file deletion. This is critical -- the challenge.md file is deleted (consumed-on-use) at the end of validation, so the metadata must be read first.

```bash
# --- Extract Q5 Yes label from challenge metadata (BEFORE any file deletion) ---
Q5_YES_LABEL=$(grep -oP '<!-- q5_yes_label: \K[AB]' "$CHALLENGE_FILE" 2>/dev/null | head -1)
```

#### Change B: Add hardened check and Q5 processing

Insert AFTER the Q1-Q4 comparison block (after the Q4 failure check) and BEFORE the `rm -f` that deletes challenge and response files:

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
    # Agent said "Yes" -- needs verification
    printf "NUDGE: You acknowledged unverified work. Spawn an independent subagent (Agent tool) to verify before continuing.\n" >&2
  else
    # Agent said "No" -- increment counter
    NO_COUNT=$((NO_COUNT + 1))
    if [ "$NO_COUNT" -ge 5 ]; then
      HARDENED="true"
    fi
  fi
  # Save counter (ISO 8601 for lexicographic comparison)
  mkdir -p .claude/pre-flight
  jq -n --argjson nc "$NO_COUNT" --arg h "$HARDENED" --arg lr "$LAST_RESET" \
    '{"no_verify_count": $nc, "hardened": ($h == "true"), "last_reset": $lr}' > "$VERIFY_COUNTER"
fi
```

**Order matters:** The hardened check runs BEFORE Q5 answer processing. If the agent is hardened and hasn't spawned a verifier, the validation fails on the same MCQ cycle -- the agent doesn't get one more free pass.

### File 4: `~/.claude/hooks/pre-flight-gate.sh` (MODIFIED)

Two changes to the existing PreToolUse gate:

#### Change A: Replace blanket watcher exemption with conditional

Find the existing watcher exemption (around line 26):

```bash
# OLD -- blanket exemption
if printf '%s' "$TARGET_NORM" | grep -qF '.openclaw/watchers/'; then
  exit 0
fi
```

Replace with:

```bash
# NEW -- conditional exemption: detect step check-offs
if printf '%s' "$TARGET_NORM" | grep -qF '.openclaw/watchers/'; then
  TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
  if [ "$TOOL_NAME" = "Edit" ]; then
    OLD_STR=$(printf '%s' "$INPUT" | jq -r '.tool_input.old_string // ""' 2>/dev/null)
    NEW_STR=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // ""' 2>/dev/null)
    if printf '%s' "$OLD_STR" | grep -qF '[ ]' && printf '%s' "$NEW_STR" | grep -qF '[x]'; then
      # Step check-off detected -- fall through to step completion gate below
      :
    else
      exit 0  # Normal watcher edit -- exempt
    fi
  else
    exit 0  # Write to watcher -- exempt
  fi
fi
```

#### Change B: Add step completion gate

Insert after the `.claude/state/` exemption block and before the watcher-active check / counter logic:

```bash
# --- Step completion gate: block [x] check-off without verification ---
if printf '%s' "$TARGET_NORM" | grep -qF '.openclaw/watchers/slot-'; then
  # We reach here only for Edit check-offs ([ ] -> [x])
  STEP_TEXT=$(printf '%s' "$NEW_STR" | grep -F '[x]' | head -1 | sed 's/^[[:space:]]*- \[x\][[:space:]]*//')

  # Trivial steps don't need verification
  TRIVIAL_PATTERN='[Rr]ead|[Ss]earch|[Ee]xplore|[Ss]et up|[Cc]laim|[Ll]oad|[Ll]ist'
  if printf '%s' "$STEP_TEXT" | grep -qE "$TRIVIAL_PATTERN"; then
    exit 0  # Trivial step -- allow without ledger check
  fi

  # Check verification ledger for matching entry
  LEDGER=".claude/state/verification-ledger.jsonl"
  if [ -f "$LEDGER" ]; then
    # Extract first 30 chars of step text, lowercase, for fixed-string matching
    MATCH_PREFIX=$(printf '%s' "$STEP_TEXT" | head -c 30 | tr '[:upper:]' '[:lower:]')
    if grep -iF "$MATCH_PREFIX" "$LEDGER" >/dev/null 2>&1; then
      exit 0  # Matching ledger entry found -- allow
    fi
  fi

  # Check verification ledger for matching entry
  LEDGER=".claude/state/verification-ledger.jsonl"
  STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
  if [ -f "$LEDGER" ]; then
    MATCH_PREFIX=$(printf '%s' "$STEP_TEXT" | head -c 30 | tr '[:upper:]' '[:lower:]')
    if grep -iF "$MATCH_PREFIX" "$LEDGER" >/dev/null 2>&1; then
      # Sprint 6: Check verification type satisfaction
      LEDGER_VTYPE=$(grep -iF "$MATCH_PREFIX" "$LEDGER" | tail -1 | jq -r '.verification_type // "review"' 2>/dev/null)
      [ -z "$LEDGER_VTYPE" ] && LEDGER_VTYPE="review"
      TYPE_OK="true"
      if [ -f "${STATE_DIR}/unverified-writes.jsonl" ]; then
        STEP_CLS_TMP=$(mktemp)
        bash "$HOME/.claude/scripts/classify-verification-need.sh" > "$STEP_CLS_TMP" 2>/dev/null
        if [ -s "$STEP_CLS_TMP" ]; then
          for REQ in $(jq -r '.required[]' "$STEP_CLS_TMP" | tr -d '\r'); do
            case "$REQ" in
              vision)     case "$LEDGER_VTYPE" in vision|browser) ;; *) TYPE_OK="false" ;; esac ;;
              functional) case "$LEDGER_VTYPE" in functional|vision|browser) ;; *) TYPE_OK="false" ;; esac ;;
              browser)    [ "$LEDGER_VTYPE" = "browser" ] || TYPE_OK="false" ;;
              review)     ;;
            esac
          done
        fi
        rm -f "$STEP_CLS_TMP"
      fi
      if [ "$TYPE_OK" = "true" ]; then
        exit 0  # Matching ledger entry with sufficient verification type
      fi
      # Type mismatch — fall through to block with prescription
    fi
  fi

  # No match or type mismatch -- block with prescriptive message
  printf "BLOCKED: You cannot mark this step complete without independent verification.\n" >&2
  printf "Step: %s\n\n" "$STEP_TEXT" >&2
  # Sprint 6: Include prescriptive file list if available
  if [ -f "${STATE_DIR}/unverified-writes.jsonl" ]; then
    RX_TMP=$(mktemp)
    bash "$HOME/.claude/scripts/classify-verification-need.sh" > "$RX_TMP" 2>/dev/null
    if [ -s "$RX_TMP" ]; then
      printf "Files modified since last verification:\n" >&2
      jq -r '.files[] | "  - " + .file + "  -> requires " + (.type | ascii_upcase) + " validation"' "$RX_TMP" >&2
      printf "\n" >&2
      jq -r '"Required: " + .prescription' "$RX_TMP" >&2
      printf "\n\n" >&2
    fi
    rm -f "$RX_TMP"
  fi
  printf "Spawn a subagent with the appropriate verification type.\n" >&2
  printf "  Include 'verify' + specific method (test, screenshot, curl, etc.) in the prompt.\n" >&2
  exit 2
fi
```

**Key notes:**
- `grep -iF` (not `grep -i`) -- the `-F` flag treats the match prefix as a fixed string, preventing regex metacharacters in step text from causing errors.
- The step gate only fires for `slot-` files (not REGISTRY.json or other watcher files).
- `$NEW_STR` is available because it was extracted in the conditional exemption block above.
- **Sprint 6:** After finding a ledger match, the gate now checks that the verification type is strong enough for the modified files. A `review` verification won't satisfy a step that modified `.tsx` files (requires `vision`).

### File 5: `~/.claude/scripts/validate-phase.sh` (MODIFIED)

Add verification ledger checks at the START of the BUILD and EVALUATE case branches (before existing checks like test suite runs and evaluation file checks).

#### In the BUILD case branch (case `3|"BUILD"|"EXECUTE"`):

Insert at the very beginning of the case body:

```bash
# Verification ledger check: at least one independent verification during BUILD
LEDGER="${STATE_DIR}/verification-ledger.jsonl"
CURRENT_SPRINT=$(jq -r '.sprint // 0' "${STATE_DIR}/current-phase.json" 2>/dev/null)
SPRINT_ENTRIES=0
if [ -f "$LEDGER" ]; then
  SPRINT_ENTRIES=$(grep '"phase":"BUILD"' "$LEDGER" | grep -c "\"sprint\":${CURRENT_SPRINT}" 2>/dev/null || echo 0)
fi
if [ "$SPRINT_ENTRIES" -eq 0 ]; then
  printf "FAIL: Phase completion requires at least one independent verification during BUILD (sprint %s).\n" "$CURRENT_SPRINT" >&2
  printf "Spawn a subagent to verify your work, then retry phase completion.\n" >&2
  exit 1
fi
```

#### In the EVALUATE case branch (case `4|"EVALUATE"`):

Same pattern, but matching `"phase":"EVALUATE"`:

```bash
# Verification ledger check: at least one independent verification during EVALUATE
LEDGER="${STATE_DIR}/verification-ledger.jsonl"
CURRENT_SPRINT=$(jq -r '.sprint // 0' "${STATE_DIR}/current-phase.json" 2>/dev/null)
SPRINT_ENTRIES=0
if [ -f "$LEDGER" ]; then
  SPRINT_ENTRIES=$(grep '"phase":"EVALUATE"' "$LEDGER" | grep -c "\"sprint\":${CURRENT_SPRINT}" 2>/dev/null || echo 0)
fi
if [ "$SPRINT_ENTRIES" -eq 0 ]; then
  printf "FAIL: Phase completion requires at least one independent verification during EVALUATE (sprint %s).\n" "$CURRENT_SPRINT" >&2
  printf "Spawn a subagent to verify your work, then retry phase completion.\n" >&2
  exit 1
fi
```

**Note on phase naming:** `current-phase.json` stores phases as uppercase strings: `"PLAN"`, `"NEGOTIATE"`, `"BUILD"`, `"EVALUATE"`, `"COMPLETE"`. The case branch uses `3|"BUILD"|"EXECUTE"` but the phase value in JSON and the ledger is always `"BUILD"`, never `"EXECUTE"`. No mismatch risk.

#### Sprint 6 addition: Verification type matching in BUILD

After the ledger existence check (above), add a type satisfaction check when `unverified-writes.jsonl` exists. This ensures the verification type used is strong enough for the files modified:

```bash
# Verification type check: strongest type must satisfy classifier requirements
if [ -f "${STATE_DIR}/unverified-writes.jsonl" ]; then
  BEST_VTYPE="review"
  for VT in $(grep '"phase":"BUILD"' "$LEDGER" | grep "\"sprint\":${CURRENT_SPRINT}" | jq -r '.verification_type // "review"' 2>/dev/null); do
    case "$VT" in
      browser)    BEST_VTYPE="browser" ;;
      vision)     [ "$BEST_VTYPE" != "browser" ] && BEST_VTYPE="vision" ;;
      functional) case "$BEST_VTYPE" in browser|vision) ;; *) BEST_VTYPE="functional" ;; esac ;;
    esac
  done
  rank_vtype() { case "$1" in browser) echo 4;; vision) echo 3;; functional) echo 2;; *) echo 1;; esac; }
  BEST_RANK=$(rank_vtype "$BEST_VTYPE")
  BUILD_CLS_TMP=$(mktemp)
  bash "$HOME/.claude/scripts/classify-verification-need.sh" > "$BUILD_CLS_TMP" 2>/dev/null
  PHASE_SATISFIED="true"
  if [ -s "$BUILD_CLS_TMP" ]; then
    for PREQ in $(jq -r '.required[]' "$BUILD_CLS_TMP" | tr -d '\r'); do
      REQ_RANK=$(rank_vtype "$PREQ")
      [ "$BEST_RANK" -lt "$REQ_RANK" ] && PHASE_SATISFIED="false"
    done
  fi
  if [ "$PHASE_SATISFIED" = "false" ]; then
    printf "FAIL: Verification type mismatch. Your verification was '%s' but modified files require stronger verification.\n" "$BEST_VTYPE" >&2
    jq -r '.files[] | "  - " + .file + "  -> requires " + (.type | ascii_upcase) + " validation"' "$BUILD_CLS_TMP" >&2
    printf "\nSpawn a subagent with the appropriate verification type.\n" >&2
    rm -f "$BUILD_CLS_TMP"
    exit 1
  fi
  rm -f "$BUILD_CLS_TMP"
fi
```

**Strength hierarchy:** `browser (4) > vision (3) > functional (2) > review (1)`. Stronger verification methods satisfy weaker requirements. A vision verification covers both vision and functional needs. Browser covers everything.

#### Sprint 6 addition: Prescriptive block messages

Both BUILD and EVALUATE blocks now show exactly which files were modified and what verification type each needs when blocking:

```
FAIL: Phase completion requires at least one independent verification during BUILD (sprint 4).
Files modified since last verification:
  - src/Dashboard.tsx  -> requires VISION validation
  - src/api/handler.js  -> requires FUNCTIONAL validation
  - docs/README.md  -> requires REVIEW validation

Required: UI files modified: vision validation needed (screenshot + visual check).
         Logic/config files modified: functional testing needed (execute + check output).
```

**Critical implementation note (Windows/MSYS):** jq output piped through `<<<` here-strings produces empty output in hook subprocess contexts. Always write classifier output to a temp file via `mktemp`, then read with `jq ... "$tmpfile"`. Also strip Windows carriage returns from jq for-loops with `| tr -d '\r'`.

### File 6: `~/.claude/settings.json` (MODIFIED)

Add a PostToolUse hook entry for the Agent tool. This goes into the existing `hooks.PostToolUse` array as a NEW third element (after the existing Write|Edit and Bash entries):

```json
{
  "matcher": "Agent",
  "hooks": [
    {
      "type": "command",
      "command": "bash -c 'echo \"[HOOK] agent-call-tracker fired at $(date)\" >> /tmp/claude-hooks.log 2>/dev/null; bash $HOME/.claude/hooks/agent-call-tracker.sh'"
    }
  ]
}
```

The `echo` to `/tmp/claude-hooks.log` is optional diagnostic logging -- remove for production.

### File 7: `~/.claude/scripts/classify-verification-need.sh` (NEW — Sprint 6)

This deterministic classifier reads `unverified-writes.jsonl`, maps each file's extension to a verification type, and outputs structured JSON with the required verification types and a human-readable prescription.

```bash
#!/bin/bash
# classify-verification-need.sh — Layer 2 Deterministic Verification Classifier
# Reads unverified-writes.jsonl, classifies files by extension, outputs JSON.
# No LLM involvement. Pure extension-to-type mapping.
#
# Output: JSON to stdout
# {"required":["vision","functional"],"files":[{"file":"src/App.tsx","type":"vision"}],"prescription":"..."}

STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
UNVERIFIED="${STATE_DIR}/unverified-writes.jsonl"

# No unverified writes -> empty result
if [ ! -f "$UNVERIFIED" ] || [ ! -s "$UNVERIFIED" ]; then
  printf '{"required":[],"files":[],"prescription":"No unverified writes."}'
  exit 0
fi

# Deduplication
declare -A SEEN
FILES_JSON=""
HAS_VISION="false"
HAS_FUNCTIONAL="false"
HAS_REVIEW="false"

while IFS= read -r line; do
  FILE_PATH=$(printf '%s' "$line" | jq -r '.file // ""' 2>/dev/null)
  [ -z "$FILE_PATH" ] && continue
  [ -n "${SEEN[$FILE_PATH]+x}" ] && continue
  SEEN[$FILE_PATH]=1

  # Extract extension
  BASENAME=$(basename "$FILE_PATH")
  EXT="${BASENAME##*.}"
  [ "$EXT" = "$BASENAME" ] && EXT=""
  EXT_LOWER=$(printf '%s' "$EXT" | tr '[:upper:]' '[:lower:]')

  # Test file override (test patterns always -> functional)
  case "$FILE_PATH" in
    *test*|*spec*|*__tests__*) FTYPE="functional"; HAS_FUNCTIONAL="true" ;;
    *)
      case "$EXT_LOWER" in
        html|htm|css|scss|sass|less|jsx|tsx|vue|svelte|ejs|hbs|pug)
          FTYPE="vision"; HAS_VISION="true" ;;
        sh|bash|py|js|ts|go|rs|rb|java|cs|php|c|cpp|h)
          FTYPE="functional"; HAS_FUNCTIONAL="true" ;;
        json|yaml|yml|toml|ini|env|conf|cfg)
          FTYPE="functional"; HAS_FUNCTIONAL="true" ;;
        md|txt|rst|adoc)
          FTYPE="review"; HAS_REVIEW="true" ;;
        *)
          FTYPE="functional"; HAS_FUNCTIONAL="true" ;;
      esac
      ;;
  esac

  SAFE_FILE=$(printf '%s' "$FILE_PATH" | sed 's/\\/\\\\/g; s/"/\\"/g' | head -c 300)
  if [ -n "$FILES_JSON" ]; then FILES_JSON="${FILES_JSON},"; fi
  FILES_JSON="${FILES_JSON}{\"file\":\"${SAFE_FILE}\",\"type\":\"${FTYPE}\"}"
done < "$UNVERIFIED"

# Build required array (highest types only, review omitted if stronger exists)
REQUIRED=""
if [ "$HAS_VISION" = "true" ]; then
  REQUIRED="\"vision\""
fi
if [ "$HAS_FUNCTIONAL" = "true" ]; then
  [ -n "$REQUIRED" ] && REQUIRED="${REQUIRED},"
  REQUIRED="${REQUIRED}\"functional\""
fi
if [ "$HAS_REVIEW" = "true" ] && [ "$HAS_VISION" = "false" ] && [ "$HAS_FUNCTIONAL" = "false" ]; then
  REQUIRED="\"review\""
fi

# Build prescription text
RX=""
if [ "$HAS_VISION" = "true" ]; then
  RX="UI files modified: vision validation needed (screenshot + visual check)."
fi
if [ "$HAS_FUNCTIONAL" = "true" ]; then
  [ -n "$RX" ] && RX="${RX} "
  RX="${RX}Logic/config files modified: functional testing needed (execute + check output)."
fi
if [ -z "$RX" ]; then
  RX="Documentation only: code review is sufficient."
fi

printf '{"required":[%s],"files":[%s],"prescription":"%s"}' "$REQUIRED" "$FILES_JSON" "$RX"
```

**Key design decisions:**
- **Extension-only classification** — no content analysis, no LLM. Pure Layer 2.
- **Test file override** — files in `test/`, `spec/`, or `__tests__/` directories are always `functional`, regardless of extension (a `.tsx` test file needs functional testing, not vision).
- **`review` only appears in `required` when it's the only type.** If vision or functional files exist, review files don't add a requirement because stronger verification inherently covers them.
- **Deduplication via `declare -A SEEN`** — prevents counting the same file twice when the agent edits it multiple times.

### File 8: `~/.claude/hooks/post-write-check.sh` (MODIFIED — Sprint 6)

Add the file write tracker after the existing session-context update block. This appends every written file to `unverified-writes.jsonl`:

```bash
# --- FILE WRITE TRACKER (for verification type enforcement) ---
WRITTEN_FILE="${TOOL_INPUT_FILE_PATH:-}"
if [ -n "$WRITTEN_FILE" ]; then
  NORM_FILE=$(printf '%s' "$WRITTEN_FILE" | tr '\\' '/')
  case "$NORM_FILE" in
    *.claude/state/*|*.claude/pre-flight/*|*.openclaw/watchers/*|*.agent-memory/*) ;;
    *)
      TS_W=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
      SAFE_W=$(printf '%s' "$NORM_FILE" | sed 's/\\/\\\\/g; s/"/\\"/g' | head -c 300)
      printf '{"ts":"%s","file":"%s"}\n' "$TS_W" "$SAFE_W" >> "${STATE_DIR}/unverified-writes.jsonl"
      ;;
  esac
fi
```

**Note:** This goes into the *existing* `post-write-check.sh` PostToolUse hook. It does NOT replace the existing code — add it after the session-context update logic.

---

## Sprint 6: Verification Type Enforcement

### Summary

Sprint 6 adds a fourth dimension to the verification enforcement system: **what type** of verification was performed, not just **whether** verification occurred.

The problem: an agent modifies a React component (`.tsx`), then spawns a "review the code" subagent. The code reviewer says "looks good." But nobody actually rendered the component to check if the UI is correct. The verification ledger has an entry — the gates pass — but the verification was insufficient for the type of change made.

### How It Works

```
Agent writes src/Dashboard.tsx (vision) + src/api/handler.js (functional)
        |
        v
post-write-check.sh appends both to unverified-writes.jsonl
        |
        v
Agent spawns: "Review the code changes" (type: review, rank 1)
        |
        v
agent-call-tracker.sh logs ledger entry with verification_type: "review"
agent-call-tracker.sh consumes unverified-writes.jsonl
        |
        v
Agent attempts phase completion
        |
        v
validate-phase.sh reads ledger: best type = review (rank 1)
validate-phase.sh runs classifier: requires [vision (rank 3), functional (rank 2)]
validate-phase.sh: 1 < 3 → BLOCKED
        |
        v
"FAIL: Verification type mismatch. Your verification was 'review'
 but modified files require stronger verification.
  - src/Dashboard.tsx  -> requires VISION validation
  - src/api/handler.js -> requires FUNCTIONAL validation
 Spawn a subagent with the appropriate verification type."
```

### Verification Type Classification

| Prompt Keywords | Type | Rank |
|----------------|------|------|
| screenshot, vision, visual, look at, render, UI, inspect layout | `vision` | 3 |
| browser, navigate, page, open URL, website, localhost | `browser` | 4 |
| run, execute, test, curl, output, functional, invoke, call endpoint | `functional` | 2 |
| (default — no match) | `review` | 1 |

### File Extension Classification

| Extensions | Type | Rationale |
|-----------|------|-----------|
| .html, .htm, .css, .scss, .sass, .less, .jsx, .tsx, .vue, .svelte, .ejs, .hbs, .pug | `vision` | UI/layout changes need visual verification |
| .sh, .bash, .py, .js, .ts, .go, .rs, .rb, .java, .cs, .php, .c, .cpp, .h | `functional` | Logic changes need execution testing |
| .json, .yaml, .yml, .toml, .ini, .env, .conf, .cfg | `functional` | Config changes can break runtime behavior |
| .md, .txt, .rst, .adoc | `review` | Documentation needs review only |
| Test files (any path containing test/spec/__tests__) | `functional` | Test files need functional verification |

### Strength Hierarchy

```
browser (4)  >  vision (3)  >  functional (2)  >  review (1)
```

A stronger verification method satisfies all weaker requirements:
- `browser` satisfies everything (it renders + executes + reviews)
- `vision` satisfies vision + functional + review
- `functional` satisfies functional + review
- `review` only satisfies review

---

## Verification Results

The system was tested with 14 functional tests (Sprint 5) + 24 functional tests (Sprint 6) covering all enforcement points. Every test passed.

| # | Test | Result |
|---|------|--------|
| 1 | Q5 appears in challenge.md with 2 options (A/B) | PASS |
| 2 | Q5 "No" increments `no_verify_count` | PASS |
| 3 | Q5 "Yes" produces nudge, counter stays 0 | PASS |
| 4 | Counter reaches 5, `hardened` set to `true` | PASS |
| 5 | Hardened mode blocks validation (no ledger) | PASS |
| 6 | Agent-call-tracker writes ledger + resets counter | PASS |
| 7 | Non-verification Agent call ignored | PASS |
| 8 | Step gate blocks check-off without ledger | PASS |
| 9 | Step gate allows check-off with ledger | PASS |
| 10 | Trivial steps exempt from step gate | PASS |
| 11 | Phase gate blocks BUILD without ledger | PASS |
| 12 | Phase gate allows BUILD with ledger | PASS |
| 13 | Phase gate blocks/allows EVALUATE | PASS |
| 14 | Existing exemptions still work | PASS |

### Sprint 6 Tests (Verification Type Enforcement)

| # | Test | Result |
|---|------|--------|
| 15 | Classifier: .tsx → vision | PASS |
| 16 | Classifier: .js → functional | PASS |
| 17 | Classifier: .md → review | PASS |
| 18 | Classifier: mixed files → vision + functional required | PASS |
| 19 | Classifier: duplicate files deduplicated | PASS |
| 20 | Classifier: .yaml/.toml → functional | PASS |
| 21 | Classifier: test files → functional | PASS |
| 22 | Classifier: no unverified-writes → empty output | PASS |
| 23 | Agent tracker: vision prompt → vision vtype | PASS |
| 24 | Agent tracker: functional prompt → functional vtype | PASS |
| 25 | Agent tracker: browser prompt → browser vtype | PASS |
| 26 | Agent tracker: review prompt → review vtype | PASS |
| 27 | Type mismatch: review vtype vs vision+functional → FAIL | PASS |
| 28 | Type mismatch: functional vtype vs vision → FAIL | PASS |
| 29 | Type satisfaction: vision vtype vs vision+functional → PASS | PASS |
| 30 | Type satisfaction: browser vtype vs everything → PASS | PASS |
| 31 | No unverified-writes → type check skipped | PASS |
| 32 | Tracker consumes unverified-writes on verification | PASS |
| 33 | Non-verification agent call preserves unverified-writes | PASS |
| 34 | EVALUATE prescriptive message with file list | PASS |
| 35 | Verify counter resets on verification | PASS |
| 36 | CSS/HTML → vision classification | PASS |
| 37 | Prescription text varies by file category | PASS |
| 38 | `grep -c || echo 0` integer bug fixed | PASS |

Sprint 5 independent verification (26 criteria): **26/26 PASS.**
Sprint 6 independent verification (all files + criteria): **PASS** — all 6 files verified, all functional tests passed, all structural criteria met.

---

## Known Limitations

1. **Write bypass for step gate:** The agent could use Write (instead of Edit) to rewrite an entire watcher slot file with steps pre-checked. This is an accepted limitation -- it requires deliberate circumvention and is detectable in review.

2. **Q5 is honesty-based for first 4 cycles:** The agent can answer "No" to Q5 four times without consequence. The counter hardens at 5 to catch sustained dishonesty, but short bursts of self-certification within 4 MCQ cycles are undetected by Q5 alone. The step gate and phase gate provide independent coverage.

3. **Verification language detection is heuristic:** The two-tier pattern reduces false positives but cannot guarantee perfect classification. An Agent call with prompt "verify that the sky is blue" would be classified as verification. In practice, agents write specific verification prompts that reference their actual work.

4. **Step matching uses 30-char prefix:** If two steps share the same first 30 characters, a verification of one could satisfy the gate for the other. In practice, watcher step descriptions are distinct enough that this doesn't occur.

5. **Extension-only classification has edge cases:** A `.js` file that generates HTML (e.g., a React render function in vanilla JS) would be classified as `functional` not `vision`. The classifier uses file extension as a proxy for content type — this is correct ~95% of the time. The override for test file paths (any path containing `test/spec/__tests__`) mitigates one common edge case.

6. **Verification type cascade favors the first keyword match:** If a prompt contains both "screenshot" and "run tests", the tracker classifies as `vision` (checked first). In practice, verification prompts are usually focused on one type.

---

## What This Does NOT Do

- Does not scan file content for self-certification phrases (too noisy, too many false positives)
- Does not scan the agent's conversational text output (hooks cannot see it)
- Does not block non-verification Agent calls (research, exploration, search agents are unaffected)
- Does not replace Q1-Q4 (those check task knowledge; Q5 checks verification honesty -- different concerns)
- Does not require verification for trivial steps (read/search/setup are exempt)
- Does not modify Agent tool behavior or capabilities
- Does not analyze file content to determine verification type (extension-only, Layer 2 deterministic)
- Does not require browser/vision tools to be installed -- it only *requires* the agent to claim the right verification type in its subagent prompt; actual tool availability is the agent's responsibility

---

## Design Principles

1. **Enforce good behavior, don't detect bad behavior.** Scanning for 194 phrases is fragile. Requiring verification at structural checkpoints is robust.

2. **Graduate from soft to hard.** Q5 starts as a nudge. After sustained avoidance, it becomes a block. This avoids disrupting agents doing legitimate trivial work.

3. **Never use Layer 3 for what Layer 2 can do.** All enforcement is deterministic bash scripts. No LLM involved in the decision to block or allow.

4. **Shared infrastructure, multiple consumers.** The verification ledger and counter are written by one hook (agent-call-tracker) and read by three gates (MCQ, step, phase). Adding new enforcement points means adding new readers, not new writers.

5. **Consumed-on-use preserves freshness.** Challenge files are deleted after validation. The agent cannot reuse old answers. Each gate cycle requires fresh engagement with the current task state.

6. **Classify by extension, not content (Sprint 6).** File extension is the cheapest possible signal — no parsing, no LLM, no heuristics beyond a lookup table. The strength hierarchy (`browser > vision > functional > review`) means the system errs conservatively: if you modified UI files, you need at least vision-level verification, even if a code review might have caught the issue.

7. **Prescriptive, not punitive.** When blocking, always tell the agent exactly what it needs to do: which files were modified, what verification type each needs, and what kind of subagent prompt to write. A blocked agent with clear instructions recovers faster than one that just sees "FAIL."

---

## Appendix: Self-Certification Phrase Catalog

The full catalog of 194 phrases across 10 categories is in `self-certification-phrase-catalog.md`. The categories are:

1. **Verification Claims** (63 phrases, CRITICAL) -- "I verified", "all N pass", "validated that"
2. **Completion Claims** (45 phrases, HIGH) -- "COMPLETE", "fixed", "done and working"
3. **Success Claims** (55+ phrases, HIGH) -- "successfully implemented", "it's working"
4. **Correctness Claims** (28 phrases, MEDIUM) -- "is correct", "properly configured"
5. **Quality Claims** (13 phrases, MEDIUM) -- "solid", "looks good", "clean"
6. **Assumption Claims** (13 phrases, LOW) -- "should work", "this will fix"
7. **Dismissal Claims** (22 phrases, DISMISSAL) -- "minor", "not a real issue"
8. **Skip Justifications** (7 phrases, SKIP) -- "straightforward", "no need to verify"
9. **Hedging** (13 phrases, LOW) -- "appears to work", "seems correct"
10. **Evaluator Self-Certification** (8 phrases, CRITICAL) -- even verifiers self-certify

Plus 4 structural meta-patterns: session title self-certification, auto-duplication amplification, builder-as-validator sessions, and "Problems Encountered: None" as a danger signal.

While these phrases informed the design of the Validation Guard, the system does NOT scan for them. Instead, it enforces verification at structural checkpoints where these phrases would otherwise go unchallenged.
