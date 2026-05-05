# Product Spec: Pre-Flight Gate Frequency Reduction

## Problem
The pre-flight gate fires on every Write/Edit, which is too much friction. Agents spend excessive time in the block-answer-retry cycle. The re-grounding value is highest on the first write and diminishes on consecutive writes to the same step.

## Solution
Add a write counter to pre-flight-gate.sh that only fires the MCQ on:
1. **Write 1** — first non-exempt write (always gated, counter = 0)
2. **Every 4-write cycle** — periodic re-grounding (gate fires when counter is 0, 4, 8, 12... i.e. 3 free writes between each gate)
3. **Step changes** — when the watcher checklist advances (first unchecked item changes)

Between gated writes, the hook exits 0 (allows freely).

In human terms: write 1 is gated, writes 2-4 are free, write 5 is gated, writes 6-8 are free, write 9 is gated, etc.

## Counter Mechanism
- State file: `.claude/pre-flight/gate-counter.json`
- Tracks: `write_count` (int), `last_step` (string — first unchecked TO-DO item)
- If all TO-DO items are checked, `last_step` = `(no unchecked steps remain)`
- On each non-exempt Write/Edit:
  1. Read counter file (if missing or corrupt JSON, initialize write_count=0, last_step="")
  2. Extract current step from watcher slot TO-DO section
  3. If step changed from `last_step`: reset counter to 0, update last_step, fire gate
  4. If `write_count % 4 == 0`: fire gate
  5. Otherwise: increment counter, allow write
- Counter file lives in `.claude/pre-flight/` (already exempt from the gate)

## What Changes
- **pre-flight-gate.sh** — add counter logic between exemptions check and MCQ check
- **Nothing else** — generator, validator, distractor pool, watcher format all unchanged
