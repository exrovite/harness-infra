# Sprint 4 Contract: Pre-Flight Gate Frequency Reduction (LOCKED — Rev 3)

## Revision Notes
Rev 3 fixes: added slot file lookup logic (step 2), clarified MCQ-pass insertion point (step 8), added mkdir -p for counter directory, added eval criterion for last_step persistence.
Rev 2 fixes: corrected write numbering (fires on writes 1, 5, 9, 13 = 3 free between each gate), added corrupt JSON handling, specified sentinel value for all-checked case.

## Deliverable

### D1: Counter Logic in pre-flight-gate.sh
Modify `~/.claude/hooks/pre-flight-gate.sh` to add write counting and step-change detection.

**Counter state file**: `.claude/pre-flight/gate-counter.json`
```json
{"write_count": 0, "last_step": "Step 1: ..."}
```

**Logic (inserted after exemptions check, before MCQ check):**
1. Read gate-counter.json via jq. If file missing OR jq parse fails: initialize write_count=0, last_step=""
2. Look up the active slot file: `SLOT_NUM=$(jq --arg proj "$CURRENT_PROJECT" '[.watchers[] | select(.status == "active" and .project != null and ((.project | gsub("\\\\";"/") | sub("/$";"") | ascii_downcase) == $proj))] | .[0].slot' "$WATCHER_REGISTRY" 2>/dev/null)` then `SLOT_FILE="$HOME/.openclaw/watchers/slot-${SLOT_NUM}.md"` (reuses CURRENT_PROJECT and WATCHER_REGISTRY from the existing watcher check above line 45)
3. Extract current step: `sed -n '/## TO-DO/,/^## /{/^## /d;p;}' "$SLOT_FILE" | grep -F -- '- [ ]' | head -1 | sed 's/^[[:space:]]*- \[ \][[:space:]]*//'` (note: `## TO-DO` pattern matches both `## TO-DO` and `## TO-DO LIST` since sed range start is a substring match)
4. If no unchecked items: current_step = "(no unchecked steps remain)"
5. If current_step != last_step: reset write_count to 0, update last_step, **proceed to MCQ check**
6. If write_count % 4 == 0: **proceed to MCQ check**
7. Otherwise: increment write_count, save counter file (`mkdir -p .claude/pre-flight` before write), **exit 0** (allow without MCQ)
8. At the MCQ validation-pass exit (line 63-65: `if [ $VALIDATE_EXIT -eq 0 ]; then exit 0`): before the `exit 0`, insert counter increment and save (`mkdir -p .claude/pre-flight` before write)

**Write cycle** (counter starts at 0):
- Counter 0: gate fires (write 1). After MCQ pass, counter becomes 1.
- Counter 1: free (write 2). Counter becomes 2.
- Counter 2: free (write 3). Counter becomes 3.
- Counter 3: free (write 4). Counter becomes 4.
- Counter 4: gate fires (write 5). After MCQ pass, counter becomes 5.
- Pattern: gate on writes 1, 5, 9, 13... (3 free writes between each gate)

**Sentinel value**: When all TO-DO items are checked, last_step is set to "(no unchecked steps remain)". Counter continues working normally.

**Corrupt file handling**: If gate-counter.json exists but jq fails to parse it, treat as missing -- re-initialize to write_count=0, last_step="".

**What stays the same**: All exemptions, MCQ generation, MCQ validation, distractor pool, watcher format.

## Verification Criteria

| # | Criterion | Method |
|---|-----------|--------|
| 1 | Gate fires on write 1 (counter = 0) | Delete counter file, attempt write, verify blocked |
| 2 | Gate allows write 2 (counter = 1) | After MCQ pass, next write passes freely |
| 3 | Gate allows writes 3 and 4 (counter = 2, 3) | Third and fourth writes pass freely |
| 4 | Gate fires on write 5 (counter = 4) | Fifth write blocks with MCQ |
| 5 | Counter persists in gate-counter.json with write_count and last_step | Read file, check JSON fields |
| 6 | Step change resets counter to 0 and fires gate | Change watcher TO-DO, verify gate fires |
| 7 | Step change updates last_step in counter file | Read counter after step change, verify new step |
| 8 | All existing exemptions work (pre-flight/, watchers/, state/) | Test each exempted path |
| 9 | MCQ still works when gate fires | Full generate + validate cycle |
| 10 | Hook exits 0 when no active watcher | Remove watcher, verify exit 0 |
| 11 | Hook passes bash -n | bash -n |
| 12 | Missing counter file treated as write 1 (gate fires) | Delete counter, verify blocked |
| 13 | Corrupt counter file treated as missing (re-initialized) | Write invalid JSON, verify gate fires and file re-created |
| 14 | All TO-DO checked: last_step = "(no unchecked steps remain)", counter works | Check all items, verify counter increments |

## Scope
- **IN**: pre-flight-gate.sh modifications only
- **OUT**: generator, validator, distractor pool, watcher format, pre-write-gate.sh, cron interval
