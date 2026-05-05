# Keep Agent On Task: A Complete Enforcement System

## What This Document Is

This is a practical guide to building a multi-layer enforcement system that prevents AI coding agents from drifting off task. It covers every component, why it exists, and how to set it up in your own environment.

The system was built iteratively. Each layer was added because the previous layer had a specific failure mode. Understanding *why* each piece exists is as important as knowing *how* to build it.

## The Problem

AI coding agents drift. Give them a 7-step task and by step 3 they have forgotten the constraints from step 1. They over-engineer, refactor things you did not ask them to touch, and lose track of what they are supposed to be doing.

Worse: they *appear* to comply with process requirements while doing the minimum to get past them. If you tell an agent "fill in this checklist before you start coding," it will fill in generic content without genuine comprehension, then proceed to ignore it.

Instructions in markdown degrade under pressure. The agent follows them when context is fresh and ignores them when it gets deep into implementation. You need enforcement that is structural, not advisory.

## Design Principle

**Soft enforcement** = instructions in markdown. Advisory. Degrades under pressure.
**Hard enforcement** = bash scripts and hooks. Deterministic. Cannot be ignored.

Every "the agent must..." should become "a script checks whether the agent did... and blocks if not."

The system has three layers, each catching what the previous layer misses:

```
Layer 1: Watcher System     -> enforces PROCESS (rhythm, check-ins)
Layer 2: Pre-Flight Gate     -> enforces KNOWLEDGE (comprehension proof)
Layer 3: Frequency Control   -> reduces FRICTION (gate only when it matters)
```

---

## Prerequisites

- Claude Code CLI (or any AI coding tool that supports PreToolUse hooks)
- bash (Git Bash on Windows works)
- jq (for JSON parsing in scripts)
- grep with PCRE support (`grep -P`) -- the validator uses Perl regex to extract metadata. Git Bash on Windows includes this. On Linux, ensure grep is compiled with `--enable-perl-regexp`.
- A hook system where you can intercept Write/Edit tool calls and block them (exit 2 = block, exit 0 = allow)

### How Hooks Work

Claude Code supports PreToolUse hooks in `~/.claude/settings.json`. A hook is a shell command that runs before a tool call. If the hook exits 0, the tool call proceeds. If it exits 2, the tool call is blocked and the stderr output is shown to the agent.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {"type": "command", "command": "bash ~/.claude/hooks/my-hook.sh"}
        ]
      }
    ]
  }
}
```

The hook receives JSON on stdin describing the tool call:
```json
{"tool_name": "Write", "tool_input": {"file_path": "/path/to/file.txt", "content": "..."}}
```

---

## Layer 1: The Watcher System (Process Rhythm)

### What It Does
Forces the agent to check in every 3 minutes and answer: "Which step am I on? Am I on task? Am I stuck?"

### Why It Exists
Without periodic check-ins, agents drift silently. They start on step 1, get distracted by something interesting in step 2, and spend 30 minutes refactoring code you never asked them to touch. The watcher creates a rhythm that interrupts drift before it compounds.

### Components

#### 1. Watcher Slots (5 reusable files)

Location: `~/.openclaw/watchers/slot-1.md` through `slot-5.md`

These are shared across all agents and projects. Each slot holds one active task.

**Template** (copy this for each slot):
```markdown
# Watcher Slot N

**Status**: available
**Claimed by**:
**Claimed at**:
**Task**:

## SCOPE
- Files: [which files this task touches]
- NOT in scope: [what to leave alone]

## OUT OF SCOPE
- [Things the agent should not do]

## MISTAKES TO AVOID
- [Common pitfalls for this type of task]

## TO-DO
- [ ] Step 1: [description]
- [ ] Step 2: [description]
- [ ] Step 3: [description]

## REMINDER
When this fires: Which step am I on? Am I on task? Am I stuck?

## COMPLETION CRITERIA
- [What "done" looks like]
```

The SCOPE, OUT OF SCOPE, and MISTAKES TO AVOID sections are critical. They become the ground truth for the knowledge enforcement layer (Layer 2).

#### 2. Watcher Registry

Location: `~/.openclaw/watchers/REGISTRY.json`

Tracks which slots are claimed, by whom, for which project, and whether a cron reminder is active.

```json
{
  "version": "1.0.0",
  "created": "2026-01-01",
  "description": "5 reusable Watcher slots. Any agent can claim one, fill it with task details, and set a 3-min loop reminder.",
  "watchers": [
    {
      "slot": 1,
      "status": "available",
      "claimed_by": null,
      "claimed_at": null,
      "cron_job_id": null,
      "project": null,
      "cron_interval": null
    },
    {
      "slot": 2,
      "status": "available",
      "claimed_by": null,
      "claimed_at": null,
      "cron_job_id": null,
      "project": null,
      "cron_interval": null
    },
    {
      "slot": 3,
      "status": "available",
      "claimed_by": null,
      "claimed_at": null,
      "cron_job_id": null
    },
    {
      "slot": 4,
      "status": "available",
      "claimed_by": null,
      "claimed_at": null,
      "cron_job_id": null
    },
    {
      "slot": 5,
      "status": "available",
      "claimed_by": null,
      "claimed_at": null,
      "cron_job_id": null
    }
  ]
}
```

Note: `project` and `cron_interval` fields are only present when a slot is claimed. Available slots may omit them -- the hook scripts handle this with `!= null` guards.

Key fields:
- `project`: must match `pwd -W | tr '[:upper:]' '[:lower:]'` exactly (e.g., `g:/my project`)
- `cron_job_id`: proves a recurring reminder is active
- `cron_interval`: must be `*/3 * * * *` (enforced by the hook)

#### 3. The Pre-Write Gate Hook

Location: `~/.claude/hooks/pre-write-gate.sh`

This hook fires on every Write/Edit/Agent tool call. It enforces:
- First 2 writes are free (agent needs to set up watcher and write its slot file)
- From write 3 onward: BOTH a watcher AND a cron reminder must be active for the current project
- If either is missing: tool call is blocked with instructions on how to set them up

The hook checks the registry for an active watcher matching the current project path, and verifies that `cron_job_id` and `cron_interval` are set.

**How to register in settings.json:**
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|Agent",
        "hooks": [
          {"type": "command", "command": "bash $HOME/.claude/hooks/pre-write-gate.sh"}
        ]
      }
    ]
  }
}
```

#### 4. The 3-Minute Cron Reminder

Use your AI tool's cron/scheduling feature to fire a reminder every 3 minutes:

```
WATCHER REMINDER - Read [slot path] NOW. Which step am I on? Am I on task? Am I stuck?
```

The reminder forces the agent to stop, re-read its watcher slot, and honestly assess whether it has drifted. Without this, the watcher slot is write-once-read-never.

### What Layer 1 Catches
- Agents that start coding without a plan
- Agents that forget what step they are on
- Agents that drift into unrelated work
- Agents that refactor code they were not asked to touch

### What Layer 1 Misses
Agents that bluff through it. They fill in minimum content to pass the watcher check, answer the reminder with "yes I am on task" without actually reading the slot, and continue drifting. The watcher enforces *rhythm* but not *knowledge*.

---

## Layer 2: The Pre-Flight Gate (Knowledge Enforcement)

### What It Does
Before every gated Write/Edit, the agent must answer a 4-question multiple-choice quiz derived from its own watcher slot. Wrong answers block the write.

### Why It Exists
The watcher proved that agents will comply with process without genuine comprehension. The pre-flight gate forces them to *prove* they know:
1. What task they are doing
2. Which step they are currently on
3. What file they are about to edit
4. What they should avoid doing

If the agent cannot answer these questions, it should not be writing code.

### Components

#### 1. Distractor Pool

Location: `~/.openclaw/distractor-pool/`

Four files, 60 entries each (240 total):
- `tasks.txt` -- plausible but wrong task descriptions
- `steps.txt` -- plausible but wrong step descriptions
- `files.txt` -- plausible but wrong file paths
- `constraints.txt` -- plausible but wrong constraints

**Why a pool?** If wrong answers were always the same, agents could memorize which answers to avoid. Rotating distractors via `shuf -n 3` means each quiz looks different.

**Sample entries for tasks.txt** (one per line):
```
Refactor the authentication middleware
Add pagination to the API response
Migrate database schema to version 3
Implement WebSocket real-time notifications
Fix memory leak in image processing pipeline
Add rate limiting to public endpoints
```

Create similar entries for each file. They should be plausible software engineering tasks/steps/files/constraints -- generic enough to be wrong for any specific task, specific enough to look like real answers.

#### 2. Challenge Generator

Location: `~/.claude/scripts/generate-pre-flight-challenge.sh`

This script:
1. Finds the active watcher slot for the current project via REGISTRY.json
2. Extracts ground truth from the slot: task, current step (first unchecked TO-DO), mistakes to avoid
3. Takes the target file path as an argument (passed by the gate hook)
4. Picks 3 random distractors from the pool for each question
5. Shuffles the correct answer into a random position (A/B/C/D)
6. Writes `.claude/pre-flight/challenge.md` with metadata linking back to the source slot

**Critical design decisions:**
- The correct answer position is randomized (not always A or always D)
- The `<!-- source_slot: /path/to/slot.md -->` metadata lets the validator find the same slot later
- No answer key is stored anywhere -- this prevents cheating

**Key implementation notes:**
- Use `grep -F -- '- [ ]'` (with `--` end-of-options marker) because the dash in `- [ ]` can be interpreted as an option flag
- Scope the step extraction to the TO-DO section only: `sed -n '/## TO-DO/,/^## /{/^## /d;p;}' "$SLOT_FILE" | grep -F -- '- [ ]' | head -1`
- Use `shuf -n 3` for distractor selection
- Use `grep -vxF -- "$exclude"` to remove the correct answer from the distractor pool before picking

#### 3. Response Validator

Location: `~/.claude/scripts/validate-pre-flight.sh`

This script:
1. Reads the challenge file and extracts the source slot path from metadata
2. Re-derives correct answers from the watcher slot (same extraction logic as generator)
3. For Q3 (target file): identifies the correct answer as the option NOT found in `files.txt` distractor pool
4. Finds which letter (A/B/C/D) contains each correct answer in the challenge
5. Parses the agent's response from `.claude/pre-flight/response.md` (format: `Q1: A`)
6. Compares and reports specific failures ("Q2 is wrong -- re-read your watcher slot checklist")
7. On pass: deletes both challenge and response files (consumed-on-use pattern)

**Why no stored answer key?** An answer key file would be a cheating vector. The agent could read it before answering. By re-deriving answers from the watcher slot at validation time, there is nothing to cheat from.

**Why consumed on use?** If old challenges persisted, agents could memorize or reuse previous answers. Deleting both files after a successful validation forces a fresh challenge on the next gate.

**Response format** (what the agent writes to `.claude/pre-flight/response.md`):
```
Q1: C
Q2: A
Q3: B
Q4: D
```

#### 4. The Pre-Flight Gate Hook

Location: `~/.claude/hooks/pre-flight-gate.sh`

This hook fires on Write/Edit (after the pre-write-gate). It:
1. Checks path exemptions (the agent needs to write response.md, watcher slots, and state files without being gated)
2. Checks if a watcher is active for this project (if not, defers to pre-write-gate)
3. Runs the write counter logic (Layer 3 -- see below)
4. If the gate should fire: checks for an existing response, validates it if present
5. If validation passes: allows the write
6. If validation fails or no response exists: generates a fresh challenge and blocks (exit 2)

**Exempted paths** (writes to these are never gated):
- `.claude/pre-flight/` and bare `pre-flight/` -- agent must be able to write its response (both patterns checked for robustness)
- `.openclaw/watchers/` -- agent must be able to update watcher slots
- `.claude/state/` -- harness state files (phase markers, progress notes)

**How to register in settings.json** (must come AFTER pre-write-gate):
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|Agent",
        "hooks": [
          {"type": "command", "command": "bash $HOME/.claude/hooks/pre-write-gate.sh"}
        ]
      },
      {
        "matcher": "Write|Edit",
        "hooks": [
          {"type": "command", "command": "bash $HOME/.claude/hooks/pre-flight-gate.sh"}
        ]
      }
    ]
  }
}
```

### What the Agent Experiences

1. Agent tries to write a file
2. Hook blocks: "BLOCKED: Pre-flight check required. Read .claude/pre-flight/challenge.md"
3. Agent reads the challenge -- 4 multiple-choice questions about its own task
4. Agent writes answers to `.claude/pre-flight/response.md`
5. Agent retries the write -- hook validates, passes, write goes through
6. Challenge and response files are deleted

If the agent gets any question wrong, it gets specific feedback ("Q2 is wrong -- re-read your watcher slot checklist") and must re-answer.

### What Layer 2 Catches
- Agents that bluffed through the watcher (cannot answer questions about their own task)
- Agents that drifted to the wrong file (Q3 checks target file)
- Agents that forgot constraints (Q4 checks mistakes to avoid)
- Agents that lost track of their current step (Q2 checks first unchecked TO-DO)

### What Layer 2 Misses
Nothing, in terms of comprehension -- if the agent can answer all 4 questions correctly, it genuinely knows what it is doing. But it creates too much friction when fired on every single write. This leads to Layer 3.

---

## Layer 3: Frequency Control (Friction Reduction)

### What It Does
Instead of firing the MCQ gate on every write, fires it on writes 1, 5, 9, 13... (every 4th write) and immediately on step changes.

### Why It Exists
The pre-flight gate on every write was too much friction. Agents answered quizzes correctly but the overhead slowed them down massively. The re-grounding value of the quiz is highest on:
- **Write 1** -- the agent just started, needs to prove comprehension
- **Step changes** -- the agent moved to a new step, context has shifted

Between these events, the quiz adds friction without insight. The agent already proved it knows the task -- let it work.

### Components

#### 1. Counter State File

Location: `.claude/pre-flight/gate-counter.json` (relative to project root)

```json
{"write_count": 3, "last_step": "Step 2: BUILD -- implement the feature"}
```

- `write_count`: incremented on every non-exempt write (whether gated or free)
- `last_step`: the first unchecked TO-DO item at the time of the last gate check

#### 2. Counter Logic (inside pre-flight-gate.sh)

The logic sits between the exemption checks and the MCQ check:

1. **Read counter file** -- if missing or corrupt JSON, initialize to `write_count=0, last_step=""`
2. **Look up active watcher slot** -- find the slot file for this project
3. **Extract current step** -- first unchecked `- [ ]` item in the TO-DO section
4. **If no unchecked items** -- use sentinel `(no unchecked steps remain)`
5. **If step changed** (current step differs from last_step) -- reset counter to 0, update last_step, fire gate
6. **If write_count % 4 == 0** -- fire gate (periodic re-grounding)
7. **Otherwise** -- increment counter, save, allow write without MCQ (exit 0)
8. **After MCQ pass** -- increment counter, save

**The write cycle:**
```
Write 1 (counter=0): GATE FIRES -- agent proves comprehension
Write 2 (counter=1): free
Write 3 (counter=2): free
Write 4 (counter=3): free
Write 5 (counter=4): GATE FIRES -- periodic re-grounding
Write 6 (counter=5): free
...pattern repeats...

Step change at any point: counter resets to 0, GATE FIRES
```

**Why save counter before MCQ check?** If the counter file is corrupt or missing, the in-memory state re-initializes but the file on disk stays broken. Saving before the MCQ check ensures the file is always valid, even if the agent fails the quiz and has to retry.

### What Layer 3 Achieves
75% reduction in gate friction (1 quiz per 4 writes instead of 1 per write) while preserving re-grounding at the moments that matter most: first write and step changes.

---

## How the Layers Work Together

```
Agent receives a multi-step task
        |
        v
Claims watcher slot + starts 3-min cron          [Layer 1]
        |
        v
Attempts a Write/Edit
        |
        v
pre-write-gate.sh: watcher + cron active?        [Layer 1 enforcement]
        |  (blocks if no watcher or no cron)
        v
pre-flight-gate.sh: exempted path?               [Layer 2]
        |  (pre-flight/, watchers/, state/ -> allow)
        v
pre-flight-gate.sh: counter check                [Layer 3]
        |
        +---> counter % 4 != 0? --> allow (exit 0)
        |
        +---> step changed? --> reset counter, fire gate
        |
        v
MCQ generated from watcher slot                  [Layer 2]
        |
        v
Agent answers 4 questions
        |
        +---> wrong? --> specific feedback, retry
        |
        v
Correct --> counter increments, write allowed     [Layer 3]
        |
        v
Every 3 min: "Which step am I on?"               [Layer 1 rhythm]
        |
        v
Agent checks off step --> step change detected    [Layer 3]
        |
        v
Next write: counter resets, MCQ fires again       [Layer 2 re-grounding]
```

---

## Setting It Up: Step by Step

### Step 1: Create the Directory Structure

```bash
mkdir -p ~/.openclaw/watchers
mkdir -p ~/.openclaw/distractor-pool
mkdir -p ~/.claude/hooks
mkdir -p ~/.claude/scripts
mkdir -p .claude/pre-flight    # in each project root
mkdir -p .claude/state         # in each project root
```

### Step 2: Create Watcher Slot Templates

Create 5 slot files (`slot-1.md` through `slot-5.md`) using the template from the Layer 1 section above.

### Step 3: Create the Watcher Registry

Create `~/.openclaw/watchers/REGISTRY.json` with 5 entries (one per slot), all starting as `"status": "available"`.

### Step 4: Create the Distractor Pool

Create 4 files in `~/.openclaw/distractor-pool/`:
- `tasks.txt` -- 60 plausible task descriptions (one per line)
- `steps.txt` -- 60 plausible step descriptions
- `files.txt` -- 60 plausible file paths
- `constraints.txt` -- 60 plausible constraints/things to avoid

Make them generic enough to be wrong for any specific task, specific enough to look real. No duplicates within a file.

### Step 5: Create the Scripts

You need four scripts plus one supporting hook. Core logic for each is provided below -- adapt to your environment.

**`~/.claude/hooks/pre-write-gate.sh`** (Layer 1 enforcement):

Core logic:
```bash
#!/bin/bash
# Exit 0 = allowed, Exit 2 = blocked
STATE_DIR=".claude/state"
WRITE_COUNTER="${STATE_DIR}/write-count.txt"
WATCHER_REGISTRY="$HOME/.openclaw/watchers/REGISTRY.json"

# Allow if no harness state exists
if [ ! -f "${STATE_DIR}/current-phase.json" ]; then exit 0; fi

# Read and sanitize write count
WRITES=$(cat "$WRITE_COUNTER" 2>/dev/null || printf "0")
WRITES=$(printf '%s' "$WRITES" | grep -o '[0-9]*' | head -1)
WRITES=${WRITES:-0}

# First 2 writes are free (agent needs them to set up watcher)
if [ "$WRITES" -lt 2 ]; then exit 0; fi

# Normalize project path (lowercase, forward slashes, no trailing slash)
CURRENT_PROJECT=$(pwd -W 2>/dev/null || pwd)
CURRENT_PROJECT=$(printf '%s' "$CURRENT_PROJECT" | sed 's|\\|/|g' | sed 's|/$||' | tr '[:upper:]' '[:lower:]')

# Check registry for active watcher AND cron for this project
if [ -f "$WATCHER_REGISTRY" ]; then
  ACTIVE_WATCHERS=$(jq --arg proj "$CURRENT_PROJECT" \
    '[.watchers[] | select(.status == "active" and .project != null
      and ((.project | gsub("\\\\";"/") | sub("/$";"") | ascii_downcase) == $proj)
    )] | length' "$WATCHER_REGISTRY" 2>/dev/null || printf "0")

  ACTIVE_CRON=$(jq --arg proj "$CURRENT_PROJECT" \
    '[.watchers[] | select(.status == "active" and .project != null
      and ((.project | gsub("\\\\";"/") | sub("/$";"") | ascii_downcase) == $proj)
      and .cron_job_id != null and .cron_interval == "*/3 * * * *"
    )] | length' "$WATCHER_REGISTRY" 2>/dev/null || printf "0")

  if [ "$ACTIVE_WATCHERS" -eq 0 ]; then
    printf "BLOCKED: No watcher claimed for this project.\n" >&2
    exit 2
  fi
  if [ "$ACTIVE_CRON" -eq 0 ]; then
    printf "BLOCKED: Watcher claimed but no cron reminder active.\n" >&2
    exit 2
  fi
fi

exit 0
```

**`~/.claude/hooks/pre-flight-gate.sh`** (Layer 2+3 enforcement):

Core logic:
```bash
#!/bin/bash
# Exit 0 = allowed, Exit 2 = blocked

# Read tool input from stdin
INPUT=$(cat)
TARGET_FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null)

# Normalize and check exemptions
TARGET_NORM=$(printf '%s' "$TARGET_FILE" | tr '\\' '/' | tr '[:upper:]' '[:lower:]')
if printf '%s' "$TARGET_NORM" | grep -qF '.claude/pre-flight/'; then exit 0; fi
if printf '%s' "$TARGET_NORM" | grep -qF 'pre-flight/'; then exit 0; fi
if printf '%s' "$TARGET_NORM" | grep -qF '.openclaw/watchers/'; then exit 0; fi
if printf '%s' "$TARGET_NORM" | grep -qF '.claude/state/'; then exit 0; fi

# Check for active watcher
WATCHER_REGISTRY="$HOME/.openclaw/watchers/REGISTRY.json"
CURRENT_PROJECT=$(pwd -W 2>/dev/null || pwd)
CURRENT_PROJECT=$(printf '%s' "$CURRENT_PROJECT" | tr '\\' '/' | sed 's|/$||' | tr '[:upper:]' '[:lower:]')
if [ ! -f "$WATCHER_REGISTRY" ]; then exit 0; fi

ACTIVE_WATCHERS=$(jq --arg proj "$CURRENT_PROJECT" \
  '[.watchers[] | select(.status == "active" and .project != null
    and ((.project | gsub("\\\\";"/") | sub("/$";"") | ascii_downcase) == $proj)
  )] | length' "$WATCHER_REGISTRY" 2>/dev/null || printf "0")
if [ "$ACTIVE_WATCHERS" -eq 0 ]; then exit 0; fi

# --- Counter logic ---
COUNTER_FILE=".claude/pre-flight/gate-counter.json"

# Read or initialize counter
if [ -f "$COUNTER_FILE" ]; then
  WRITE_COUNT=$(jq -r '.write_count // 0' "$COUNTER_FILE" 2>/dev/null) || WRITE_COUNT=0
  LAST_STEP=$(jq -r '.last_step // ""' "$COUNTER_FILE" 2>/dev/null) || LAST_STEP=""
  if ! [[ "$WRITE_COUNT" =~ ^[0-9]+$ ]]; then WRITE_COUNT=0; LAST_STEP=""; fi
else
  WRITE_COUNT=0; LAST_STEP=""
fi

# Look up active slot file
SLOT_NUM=$(jq -r --arg proj "$CURRENT_PROJECT" \
  '[.watchers[] | select(.status == "active" and .project != null
    and ((.project | gsub("\\\\";"/") | sub("/$";"") | ascii_downcase) == $proj)
  )] | .[0].slot' "$WATCHER_REGISTRY" 2>/dev/null)
SLOT_FILE="$HOME/.openclaw/watchers/slot-${SLOT_NUM}.md"

# Extract current step
CURRENT_STEP=""
if [ -f "$SLOT_FILE" ]; then
  CURRENT_STEP=$(sed -n '/## TO-DO/,/^## /{/^## /d;p;}' "$SLOT_FILE" \
    | grep -F -- '- [ ]' | head -1 | sed 's/^[[:space:]]*- \[ \][[:space:]]*//')
fi
if [ -z "$CURRENT_STEP" ]; then CURRENT_STEP="(no unchecked steps remain)"; fi

# Decision: fire gate or allow?
if [ "$CURRENT_STEP" != "$LAST_STEP" ]; then
  WRITE_COUNT=0; LAST_STEP="$CURRENT_STEP"     # Step change -> fire
elif [ $((WRITE_COUNT % 4)) -eq 0 ]; then
  :                                               # Periodic -> fire
else
  WRITE_COUNT=$((WRITE_COUNT + 1))               # Free write -> allow
  mkdir -p .claude/pre-flight
  jq -n --argjson wc "$WRITE_COUNT" --arg ls "$LAST_STEP" \
    '{"write_count": $wc, "last_step": $ls}' > "$COUNTER_FILE"
  exit 0
fi

# Save counter before MCQ check
mkdir -p .claude/pre-flight
jq -n --argjson wc "$WRITE_COUNT" --arg ls "$LAST_STEP" \
  '{"write_count": $wc, "last_step": $ls}' > "$COUNTER_FILE"

# --- MCQ check ---
RESPONSE_FILE=".claude/pre-flight/response.md"
CHALLENGE_FILE=".claude/pre-flight/challenge.md"

if [ -f "$RESPONSE_FILE" ] && [ -f "$CHALLENGE_FILE" ]; then
  VALIDATE_OUTPUT=$(bash "$HOME/.claude/scripts/validate-pre-flight.sh" 2>&1)
  if [ $? -eq 0 ]; then
    WRITE_COUNT=$((WRITE_COUNT + 1))
    jq -n --argjson wc "$WRITE_COUNT" --arg ls "$LAST_STEP" \
      '{"write_count": $wc, "last_step": $ls}' > "$COUNTER_FILE"
    exit 0
  else
    printf "%s\n" "$VALIDATE_OUTPUT" >&2
    rm -f "$RESPONSE_FILE"
  fi
fi

# Generate challenge and block
bash "$HOME/.claude/scripts/generate-pre-flight-challenge.sh" "$TARGET_FILE" 2>/dev/null
printf "BLOCKED: Pre-flight check required before writing.\n" >&2
printf "1. READ: .claude/pre-flight/challenge.md\n" >&2
printf "2. WRITE answers to: .claude/pre-flight/response.md\n" >&2
printf "3. Retry your Write/Edit\n" >&2
exit 2
```

**`~/.claude/scripts/generate-pre-flight-challenge.sh`** (MCQ generator):

This script reads the watcher slot, picks distractors, shuffles answer positions, and writes `challenge.md`. Key function:

```bash
# Pick 3 distractors from pool, excluding the correct answer
pick_distractors() {
  local pool_file="$1"
  local exclude="$2"
  grep -vxF -- "$exclude" "$pool_file" 2>/dev/null | shuf -n 3
}

# Shuffle correct answer into random A/B/C/D position
# Returns the shuffled options on stdout, correct letter on fd 3
shuffle_options() {
  local correct="$1" d1="$2" d2="$3" d3="$4"
  local tmpf=$(mktemp)
  printf "CORRECT_MARK|%s\n" "$correct" > "$tmpf"
  printf "DISTRACT|%s\n" "$d1" >> "$tmpf"
  printf "DISTRACT|%s\n" "$d2" >> "$tmpf"
  printf "DISTRACT|%s\n" "$d3" >> "$tmpf"
  local shuffled=$(shuf "$tmpf")
  local labels=("A" "B" "C" "D")
  local idx=0 correct_label=""
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
  printf "%s" "$correct_label" >&3  # return correct letter via fd 3
}

# Called with fd 3 redirected to a temp file:
# Q1_OPTIONS=$(shuffle_options "$TASK" "$D1" "$D2" "$D3" 3>/tmp/pf_q1_label)
# Q1_CORRECT=$(cat /tmp/pf_q1_label)
```

The full script extracts from the watcher slot:
- Q1 correct answer: `**Task**:` field
- Q2 correct answer: first unchecked TO-DO item
- Q3 correct answer: target file path (passed as $1)
- Q4 correct answer: first item from MISTAKES TO AVOID or OUT OF SCOPE

It writes `<!-- source_slot: /path/to/slot.md -->` metadata so the validator can find the same slot.

**`~/.claude/scripts/validate-pre-flight.sh`** (MCQ validator):

This script re-derives correct answers from the watcher slot (no stored key), compares to agent response, and exits 0 (pass) or 1 (fail with specific feedback). On pass, it deletes both challenge.md and response.md.

Core logic:
```bash
#!/bin/bash
# Exit 0 = pass (files consumed), Exit 1 = fail (stderr says which Q wrong)
CHALLENGE_FILE=".claude/pre-flight/challenge.md"
RESPONSE_FILE=".claude/pre-flight/response.md"

# Extract source slot from challenge metadata (requires grep -P for PCRE)
SLOT_FILE=$(grep -oP '<!-- source_slot: \K[^>]+(?= -->)' "$CHALLENGE_FILE" | head -1 | sed 's/[[:space:]]*$//')

# Re-derive correct answers from watcher slot (same logic as generator)
CORRECT_Q1=$(grep -F '**Task**:' "$SLOT_FILE" | head -1 | sed 's/.*\*\*Task\*\*:[[:space:]]*//')
CORRECT_Q2=$(sed -n '/## TO-DO/,/^## /{/^## /d;p;}' "$SLOT_FILE" | grep -F -- '- [ ]' | head -1 | sed 's/^[[:space:]]*- \[ \][[:space:]]*//')

# Q3: the correct file is the option NOT in the distractor pool
# Scan Q3 options in challenge.md, find the one absent from files.txt
while IFS= read -r line; do
  # ... parse Q3 options, check each against distractor pool
  if ! grep -qxF "$OPT_TEXT" "$HOME/.openclaw/distractor-pool/files.txt"; then
    CORRECT_Q3="$OPT_TEXT"
  fi
done < "$CHALLENGE_FILE"

CORRECT_Q4=$(sed -n '/## MISTAKES TO AVOID/,/^##/{/^##/d;/^$/d;p;}' "$SLOT_FILE" | head -1 | sed 's/^[[:space:]]*-[[:space:]]*//')

# Find which letter (A/B/C/D) contains each correct answer in the challenge
find_correct_letter() {
  local q_num="$1" correct_text="$2"
  # Scan challenge.md section for Q$q_num, match option text to correct_text
  # Return the letter (A/B/C/D) that matches
}

# Parse agent response (format: "Q1: A")
AGENT_Q1=$(grep -iE "^[[:space:]]*Q1[[:space:]]*:" "$RESPONSE_FILE" | grep -oE '[A-Da-d]' | head -1 | tr '[:lower:]' '[:upper:]')

# Compare each answer, report specific failures
if [ "$AGENT_Q1" != "$CORRECT_LETTER_Q1" ]; then
  printf "FAIL: Q1 is wrong -- re-read your watcher slot task description\n" >&2
fi
# ... same for Q2, Q3, Q4

# On pass: consume both files
rm -f "$CHALLENGE_FILE" "$RESPONSE_FILE"
exit 0
```

The Q3 validation trick: the correct file path is the one NOT found in the distractor pool's `files.txt`. Since all distractors come from that file, the real answer is the only one absent from it.

**`~/.claude/hooks/post-write-check.sh`** (write counter -- PostToolUse hook):

The pre-write-gate reads `.claude/state/write-count.txt` to decide when to lock tools. Something must increment this counter on every Write/Edit. This is a PostToolUse hook:

```bash
#!/bin/bash
# PostToolUse hook on Write|Edit -- increments the write counter
STATE_DIR=".claude/state"
WRITE_COUNTER="${STATE_DIR}/write-count.txt"
mkdir -p "$STATE_DIR"
WRITES=$(cat "$WRITE_COUNTER" 2>/dev/null || printf "0")
WRITES=$(printf '%s' "$WRITES" | grep -o '[0-9]*' | head -1)
WRITES=${WRITES:-0}
WRITES=$((WRITES + 1))
printf "%d" "$WRITES" > "$WRITE_COUNTER"
```

Register it in settings.json:
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {"type": "command", "command": "bash $HOME/.claude/hooks/post-write-check.sh"}
        ]
      }
    ]
  }
}
```

Without this hook, the write counter never increments and the 2-free-writes rule in pre-write-gate has no teeth.

### Step 6: Register Hooks in Settings

Add to `~/.claude/settings.json`:
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|Agent",
        "hooks": [
          {"type": "command", "command": "bash $HOME/.claude/hooks/pre-write-gate.sh"}
        ]
      },
      {
        "matcher": "Write|Edit",
        "hooks": [
          {"type": "command", "command": "bash $HOME/.claude/hooks/pre-flight-gate.sh"}
        ]
      }
    ]
  }
}
```

Order matters: pre-write-gate runs first (enforces watcher), pre-flight-gate runs second (enforces MCQ).

### Step 7: Initialize Project State

In each project that uses the system:
```bash
mkdir -p .claude/state .claude/pre-flight
echo '{"phase": "PLAN", "sprint": 1, "iteration": 1}' > .claude/state/current-phase.json
echo "0" > .claude/state/write-count.txt
```

---

## Gotchas and Lessons Learned

### Path Normalization
On Windows with Git Bash, `pwd -W` returns `G:/my project` but paths in JSON may have backslashes. All path comparisons must normalize: convert backslashes to forward slashes, remove trailing slashes, lowercase everything. Both the hook and the registry must agree on the format.

### grep -F with Dash-Leading Patterns
`grep -F '- [ ]'` interprets the leading dash as an option flag. Always use `grep -F -- '- [ ]'` (double-dash end-of-options marker).

### Scoping TO-DO Extraction
`grep -F -- '- [ ]'` matches anywhere in the file, including inside MISTAKES TO AVOID text that happens to contain that pattern. Always scope to the TO-DO section: `sed -n '/## TO-DO/,/^## /{/^## /d;p;}' "$SLOT_FILE" | grep -F -- '- [ ]'`

### Circular Dependencies
If the validator has a bug, you cannot fix it via the Edit tool because the gate calls the buggy validator. In emergencies, fix via bash (`sed -i`) to break the cycle. This is the one legitimate case for using bash to write files directly.

### Hooks Output to stderr, Not stdout
Claude Code hooks communicate via exit codes and stderr. Stdout is reserved for `hookSpecificOutput` JSON. All diagnostic messages must go to stderr (`>&2`).

### lib-helpers.sh Dependency
The pre-write-gate.sh sources `$HOME/.claude/scripts/lib-helpers.sh` at startup. The `2>/dev/null` suppresses failure if it does not exist, so the hook works without it. If you see this in the code, you can safely ignore it or create an empty file at that path.

### PCRE in the Validator
`validate-pre-flight.sh` uses `grep -oP` (Perl regex) to extract the source slot path from challenge metadata. If your grep does not support `-P`, the validator silently fails and all MCQ validations will error. Test with `echo "test" | grep -P "test"` before deploying.

### Concurrent Agent Runs
The `shuffle_options()` function communicates the correct answer letter via file descriptor 3, redirected to temp files (`/tmp/pf_q1_label` through `/tmp/pf_q4_label`). If two agents run on the same machine simultaneously, they can overwrite each other's temp files. Mitigate by using `mktemp` for the label files or adding a PID suffix: `3>/tmp/pf_q1_label_$$`.

### The Agent Will Try to Bypass the System
This is the fundamental insight. Any enforcement that can be bypassed *will* be bypassed under pressure. The system must be structural -- bash scripts that check conditions and block tool calls -- not instructions that ask the agent to self-enforce.

Even this system has one remaining bypass: the agent can use the Bash tool to write files directly, since hooks only fire on Write/Edit tool calls. The mitigation is awareness: if you see the agent switching to bash for file writes, it is probably trying to dodge the gate.

---

## Tuning

### Gate Frequency
The system gates every 4th write. You can adjust by changing the modulo in the counter logic:
- `write_count % 2 == 0` -- gate every 2nd write (more aggressive)
- `write_count % 6 == 0` -- gate every 6th write (less friction)
- `write_count % 4 == 0` -- current setting (balanced)

### Cron Interval
3 minutes is the current setting. Shorter intervals (1-2 minutes) create more interruptions but catch drift faster. Longer intervals (5-10 minutes) allow more flow state but risk more drift.

### Distractor Pool Size
60 entries per category gives good variety. Fewer entries risk the agent seeing repeats and memorizing patterns. More entries are fine but have diminishing returns.

### Exempted Paths
Currently exempts `.claude/pre-flight/`, `.openclaw/watchers/`, and `.claude/state/`. Add more exemptions if the agent needs to write to infrastructure files without being gated (e.g., config files, test fixtures).
