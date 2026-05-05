# Evaluation Criteria: Pre-Flight Gate Frequency Reduction

## Criteria

### Counter Logic
- [ ] Gate fires on write 1 (first non-exempt write, counter = 0)
- [ ] Gate allows writes 2, 3, and 4 without MCQ (counter = 1, 2, 3)
- [ ] Gate fires again on write 5 (counter = 4, divisible by 4)
- [ ] Counter increments correctly across writes
- [ ] Counter persists in .claude/pre-flight/gate-counter.json

### Step Change Detection
- [ ] Gate fires immediately when first unchecked TO-DO item changes
- [ ] Counter resets to 0 on step change
- [ ] After step change, counter file last_step field reflects the new step value
- [ ] Step extracted from watcher slot TO-DO section (handles both ## TO-DO and ## TO-DO LIST headers)

### Preservation
- [ ] All existing exemptions still work (pre-flight/, watchers/, state/)
- [ ] MCQ generation still works when gate fires
- [ ] MCQ validation still works when gate fires
- [ ] Hook still exits 0 when no watcher is active
- [ ] Hook passes bash -n syntax check

### Edge Cases
- [ ] Missing counter file initializes correctly (treated as write 1)
- [ ] Corrupt counter file (invalid JSON) re-initializes correctly
- [ ] All TO-DO items checked: step = "(no unchecked steps remain)", counter still works
