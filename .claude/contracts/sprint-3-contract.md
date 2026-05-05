# Sprint 3 Contract: Pre-Flight Gate System (LOCKED — Rev 2)

## Revision Notes
Rev 2 fixes: removed challenge-key.txt (cheating vector), added "none" fallback, defined response.md format, specified stdin JSON parsing, added missing verification criteria, stated build order.

## Build Order
D1 (distractor pool) -> D2 (generator) -> D3 (validator) -> D4 (hook) -> D5 (templates) -> D6 (registry)

## Deliverables

### D1: Distractor Pool
- Location: `C:\Users\exrov\.openclaw\distractor-pool\`
- Files: `tasks.txt`, `steps.txt`, `files.txt`, `constraints.txt`
- Each file: 50+ entries, one per line, no duplicates within file
- Content: plausible, diverse, domain-appropriate

### D2: Challenge Generator Script
- File: `~/.claude/scripts/generate-pre-flight-challenge.sh` (Layer 2)
- Reads active watcher slot for this project (finds slot via REGISTRY.json project match, same normalization as pre-write-gate.sh)
- Accepts target file path as argument ($1)
- Extracts from watcher slot: task description (`**Task**:` line), first unchecked `- [ ]` item, `## MISTAKES TO AVOID` or `## OUT OF SCOPE` content
- **"None" fallback**: if `## MISTAKES TO AVOID` and `## OUT OF SCOPE` are missing or empty, Q4 correct answer is "None identified for this task"
- Picks 3 random distractors per question via `shuf -n 3` from distractor pool
- Randomizes correct answer position per question (A/B/C/D varies)
- Writes `.claude/pre-flight/challenge.md` with:
  - 4 questions, each with 4 labeled options (A/B/C/D)
  - A metadata block at the top: `<!-- source_slot: [slot path] -->` (so validator knows which slot to re-derive from)
- **No answer key file** — correct answers are re-derived at validation time

### D3: Validation Script
- File: `~/.claude/scripts/validate-pre-flight.sh` (Layer 2)
- Reads `.claude/pre-flight/response.md` for agent's answers
- **Expected response.md format**:
  ```
  Q1: B
  Q2: A
  Q3: D
  Q4: C
  ```
  (One line per question, format `Q[n]: [A|B|C|D]`, whitespace-tolerant)
- **Re-derives correct answers** (no stored key):
  1. Reads `<!-- source_slot: ... -->` from challenge.md to find watcher slot
  2. Extracts correct content from watcher slot (task, current step, scope, mistakes)
  3. For each question in challenge.md, scans which option (A/B/C/D) contains the correct content
  4. Compares against agent's answer
- On pass: deletes response.md AND challenge.md (consumed), exits 0
- On fail: exits 1, stderr says which question(s) wrong (e.g. "FAIL: Q2 is wrong — re-read your watcher slot")
- On missing response.md: exits 1, stderr says "No response file found"
- On missing challenge.md: exits 1, stderr says "No challenge file found"

### D4: Pre-Flight Gate Hook
- File: `~/.claude/hooks/pre-flight-gate.sh` (PreToolUse on Write|Edit)
- **Exemptions** (these paths bypass the gate entirely):
  - Writes to `.claude/pre-flight/` directory
  - Writes to `$HOME/.openclaw/watchers/` directory
  - Writes to `.claude/state/` directory (phase markers, progress notes)
- **No watcher fallback**: if no active watcher exists for this project, the gate does NOT fire (pre-write-gate.sh already handles that enforcement)
- **Flow**:
  1. Check exemptions — if exempt, exit 0
  2. Check if watcher is active for this project — if not, exit 0 (let pre-write-gate handle it)
  3. Extract target file path from stdin JSON (`tool_input.file_path`)
  4. Check if `.claude/pre-flight/response.md` exists
  5. If exists: call validate-pre-flight.sh — if passes, exit 0 (write proceeds)
  6. If no response or validation fails: call generate-pre-flight-challenge.sh with target file path, then exit 2 with block message
- Block message tells agent: "Read .claude/pre-flight/challenge.md and write your answers to .claude/pre-flight/response.md in format Q1: A, Q2: B, etc."
- Registered in settings.json as PreToolUse hook on Write|Edit
- Must appear AFTER pre-write-gate.sh in settings.json hook array (hook ordering)

### D5: Watcher Slot Template Update
- Update all 5 slot .md files to include new sections:
  - `## SCOPE` (after Task line)
  - `## OUT OF SCOPE` (after SCOPE)
  - `## MISTAKES TO AVOID` (after OUT OF SCOPE)
- Existing fields (`**Status**`, `**Task**`, `## TO-DO`, `## REMINDER`, `## COMPLETION CRITERIA`) unchanged

### D6: Registry Updates
- SCRIPT_REGISTRY.json: add generate-pre-flight-challenge.sh (Layer 2), validate-pre-flight.sh (Layer 2), pre-flight-gate.sh (hook)
- Settings.json: add PreToolUse hook entry for pre-flight-gate.sh on Write|Edit, positioned after pre-write-gate.sh

## Verification Criteria

| # | Criterion | Method |
|---|-----------|--------|
| 1 | All 4 distractor pool files exist with 50+ lines each | `wc -l` on each file |
| 2 | No duplicates within any pool file | `sort \| uniq -d` returns empty |
| 3 | Generator produces valid challenge.md from mock watcher slot | Run with test fixture, check 4 questions with A/B/C/D |
| 4 | challenge.md contains `<!-- source_slot: ... -->` metadata | grep for metadata line |
| 5 | Correct answer in challenge.md matches watcher slot content | Cross-reference each Q |
| 6 | Correct answer position varies across multiple generations | Generate 5 times, check positions differ |
| 7 | Generator handles missing MISTAKES TO AVOID (uses "None identified") | Test with slot lacking that section |
| 8 | Validator exits 0 on correct answers + deletes challenge.md and response.md | Run with correct answers, check files gone |
| 9 | Validator exits 1 on wrong answers + says which Q is wrong | Run with wrong answers |
| 10 | Validator exits 1 on missing response.md | Run without response.md |
| 11 | Validator re-derives answers from watcher slot (no key file exists) | Confirm no challenge-key.txt anywhere |
| 12 | Hook passes bash -n syntax check | `bash -n` |
| 13 | Hook exempts `.claude/pre-flight/` writes | Test with pre-flight path |
| 14 | Hook exempts watcher slot writes | Test with watcher path |
| 15 | Hook exempts `.claude/state/` writes | Test with state path |
| 16 | Hook blocks when no response exists | Test without response.md |
| 17 | Hook extracts target file from stdin JSON | Test with mock JSON input |
| 18 | Hook gracefully handles no active watcher (exits 0, defers to pre-write-gate) | Test with no watcher claimed |
| 19 | Hook appears after pre-write-gate.sh in settings.json | Inspect array ordering |
| 20 | Hook coexists with post-write-check.sh (no conflicts) | Verify both hooks fire without error |
| 21 | Watcher slot templates have all 3 new sections | grep for section headers in all 5 slots |
| 22 | SCRIPT_REGISTRY.json has 3 new entries (32 total) | `jq '.scripts + .hooks \| length'` |
| 23 | All new scripts pass bash -n | `bash -n` on each |
| 24 | Distractors differ across 2 consecutive challenge generations | Generate twice, diff distractors |

## Scope Boundaries
- **IN**: D1-D6 above
- **OUT**: Modifying pre-write-gate.sh logic, changing cron interval, changing watcher claiming flow, LLM-based validation, modifying post-write-check.sh
