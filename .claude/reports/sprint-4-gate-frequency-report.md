# Sprint 4 Report: Pre-Flight Gate Frequency Reduction

## Why This Change Was Made

### The Origin: Agent Drift Problem
We observed that AI agents bluff through the watcher system. They fill in the minimum required content to claim a watcher slot without genuine comprehension, then drift during implementation -- ignoring watcher reminders 3-4 times before complying. The watcher enforces *process rhythm* (checking in every 3 minutes) but not *knowledge*.

### Sprint 3: The Pre-Flight Gate
To solve this, Sprint 3 built a Pre-Flight Gate -- a multiple-choice quiz that fires before every Write/Edit. The MCQ is dynamically generated from the agent's own watcher slot content (task, current step, target file, constraints). There is no stored answer key; correct answers are re-derived from the watcher at validation time. Wrong answers come from a rotating distractor pool (240 entries across 4 categories) so agents cannot memorize patterns.

This worked -- agents had to prove they understood what they were doing before every code change. But it created a new problem.

### The New Problem: Too Much Friction
The gate fired on *every* non-exempt Write/Edit. During a typical implementation, an agent makes dozens of writes. Answering 4 MCQ questions before each one added massive overhead:

1. **Wasted time**: Agents spent more time answering quizzes than writing code
2. **Preemptive answering**: Agents tried to answer challenges before they were generated, then got blocked again because Q3 (target file) requires the actual tool call context
3. **Diminishing returns**: The re-grounding value is highest on write 1. By write 3 of the same step, the agent clearly knows what it is doing -- the quiz adds friction without insight

The observation was clear: **gate every write, but most of that gating is wasted on writes where the agent is already grounded**.

### The Insight: Gate Frequency Should Match Re-Grounding Value
Re-grounding value is high in two situations:
1. **First write** -- the agent just started, needs to prove comprehension
2. **Step change** -- the agent moved to a new step, context has shifted

Between these events, consecutive writes to the same step have low re-grounding value. The agent proved it knows the task; let it work.

## What Sprint 4 Built

### Write Counter with Step-Change Reset
A counter in `~/.claude/hooks/pre-flight-gate.sh` that fires the MCQ gate on:

| Write # | Counter | Gate Fires? | Why |
|---------|---------|-------------|-----|
| 1 | 0 | Yes | First write -- prove comprehension |
| 2 | 1 | No | Agent just passed MCQ, let it work |
| 3 | 2 | No | Still on same step |
| 4 | 3 | No | Still on same step |
| 5 | 4 | Yes | Periodic re-grounding (4 % 4 == 0) |
| 6 | 5 | No | Just re-grounded |
| ... | ... | ... | Pattern repeats |

**Step change override**: If the first unchecked TO-DO item in the watcher changes (agent ticked off a step and moved to the next), the counter resets to 0 and the gate fires immediately -- regardless of where in the 4-write cycle the agent was. This ensures re-grounding whenever the work context shifts.

### Counter State File
State persists in `.claude/pre-flight/gate-counter.json`:
```json
{"write_count": 5, "last_step": "Step 2: BUILD -- implement counter logic"}
```

### Single File Changed
Only `~/.claude/hooks/pre-flight-gate.sh` was modified (93 to 153 lines). Nothing else changed -- the MCQ generator, validator, distractor pool, watcher format, and all exemptions are untouched.

### Implementation Details
- **Lines 54-68**: Read counter file, initialize if missing or corrupt JSON
- **Lines 70-74**: Look up active watcher slot file via REGISTRY.json
- **Lines 76-85**: Extract current step (first unchecked TO-DO item) from watcher slot
- **Lines 87-103**: Decision logic -- step change resets counter, modulo-4 fires gate, otherwise free write
- **Lines 104-108**: Save counter state before MCQ check (ensures corrupt files are re-created)
- **Lines 121-125**: After MCQ pass, increment counter and save

### Edge Cases
- **Missing counter file**: initialize to write_count=0, gate fires (treated as write 1)
- **Corrupt JSON**: re-initialize, re-create file with valid JSON, gate fires
- **All TO-DO items checked**: sentinel value `(no unchecked steps remain)`, counter continues normally
- **Both `## TO-DO` and `## TO-DO LIST` headers**: handled by sed substring matching

## How It Was Verified

### Enhanced Agent Harness Protocol
This change followed the full protocol: PLAN, NEGOTIATE, BUILD, EVALUATE.

- **Spec**: `.claude/specs/pre-flight-frequency-spec.md`
- **Evaluation Criteria**: `.claude/specs/evaluation-criteria-sprint4.md`
- **Contract**: `.claude/contracts/sprint-4-contract.md` (Rev 3, locked after 2 independent agent reviews)
- **3 independent agent reviews**: 2 during NEGOTIATE (contract validation), 1 during EVALUATE (implementation verification)

### Contract Revisions
- **Rev 1**: Initial draft
- **Rev 2**: Fixed off-by-one in write numbering, added corrupt JSON handling, specified sentinel value
- **Rev 3**: Added explicit slot file lookup jq command (Rev 2 falsely assumed a variable existed), clarified MCQ-pass insertion point (Rev 2 was ambiguous about which `exit 0`), added `mkdir -p` for counter directory

### Verification Results
14 criteria tested by independent agent -- all passed:

| # | Criterion | Result |
|---|-----------|--------|
| 1 | Gate fires on write 1 (counter = 0) | PASS |
| 2 | Gate allows write 2 (counter = 1) | PASS |
| 3 | Gate allows writes 3 and 4 (counter = 2, 3) | PASS |
| 4 | Gate fires on write 5 (counter = 4) | PASS |
| 5 | Counter persists with write_count and last_step | PASS |
| 6 | Step change resets counter and fires gate | PASS |
| 7 | Step change updates last_step in counter file | PASS |
| 8 | All exemptions work (pre-flight/, watchers/, state/) | PASS |
| 9 | MCQ still works when gate fires | PASS |
| 10 | Hook exits 0 when no active watcher | PASS |
| 11 | Hook passes bash -n syntax check | PASS |
| 12 | Missing counter file treated as write 1 | PASS |
| 13 | Corrupt counter file re-initialized and re-created | PASS |
| 14 | All TO-DO checked: sentinel works, counter works | PASS |

One fix was applied during evaluation: criterion 13 initially failed because the corrupt counter file was re-initialized in memory but not re-written to disk until MCQ pass. Fixed by adding a counter save before the MCQ check on all gate-fire paths.

## Impact
- **75% reduction in gate friction** -- agents answer MCQ once every 4 writes instead of every write
- **Step-change detection preserved** -- agents still get re-grounded when work context shifts
- **No loss of comprehension enforcement** -- the first write and periodic checks still require proof of understanding
- **Two-system pipeline intact** -- watcher (process rhythm) + pre-flight gate (knowledge enforcement) still complement each other
