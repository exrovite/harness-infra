# Sprint 3 Proposal: Pre-Flight Gate System

## What Will Be Built

### Deliverable 1: Distractor Pool
Create `C:\Users\exrov\.openclaw\distractor-pool\` with four text files:
- `tasks.txt` — 50+ plausible task descriptions
- `steps.txt` — 50+ plausible step descriptions
- `files.txt` — 50+ plausible file paths
- `constraints.txt` — 50+ plausible constraints/out-of-scope items

### Deliverable 2: Pre-Flight Challenge Generator Script
`~/.claude/scripts/generate-pre-flight-challenge.sh` (Layer 2)
- Reads the active watcher slot to extract: task, current step, mistakes to avoid
- Accepts target file path as argument (from hook)
- Picks 3 random distractors per question from pool via `shuf`
- Randomizes correct answer position (A/B/C/D)
- Writes challenge to `.claude/pre-flight/challenge.md`
- Writes answer key derivation logic (not stored — re-computed at validation)

### Deliverable 3: Pre-Flight Validation Script
`~/.claude/scripts/validate-pre-flight.sh` (Layer 2)
- Reads `.claude/pre-flight/response.md` for agent answers
- Re-derives correct answers from watcher slot + challenge.md position mapping
- Validates exact A/B/C/D match per question
- On pass: deletes response.md (consumed), exits 0
- On fail: exits 1 with specific feedback ("Q2 is wrong")

### Deliverable 4: Pre-Flight Gate Hook
`~/.claude/hooks/pre-flight-gate.sh` (PreToolUse on Write|Edit)
- Exempts writes to `.claude/pre-flight/` directory
- Checks for valid, passing response — if none, generates challenge and blocks (exit 2)
- Integrates with existing pre-write-gate.sh (runs after watcher check passes)
- Registered in settings.json

### Deliverable 5: Watcher Slot Template Update
Update slot template files to include SCOPE, OUT OF SCOPE, MISTAKES TO AVOID sections.

### Deliverable 6: Registry Updates
- SCRIPT_REGISTRY.json updated with new scripts + hook
- Settings.json updated with new PreToolUse hook entry

## How Success Is Verified

For each deliverable, an independent sub-agent will verify:

1. **Distractor pool**: All 4 files exist, each has 50+ lines, no duplicates within a file
2. **Challenge generator**: Given a mock watcher slot, produces valid challenge.md with 4 questions, 4 options each, correct answers derived from slot content
3. **Validation script**: Given correct answers → exit 0 + response deleted. Given wrong answers → exit 1 + specific feedback. Given missing response → exit 1.
4. **Gate hook**: bash -n syntax passes. Exempts pre-flight directory. Blocks when no response exists. Allows when valid response exists.
5. **Watcher template**: New sections present in slot template files
6. **Registry**: New components registered, total count accurate

## Scope Boundaries
- IN: The 6 deliverables above
- OUT: Modifying existing pre-write-gate.sh logic, changing cron interval, modifying the watcher claiming flow, any LLM-based validation
