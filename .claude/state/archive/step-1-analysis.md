# Step 1 Analysis: Pre-Flight Gate Frequency Reduction

## Codebase Structure
- `~/.claude/hooks/pre-flight-gate.sh` — the hook to modify (93 lines)
- No existing counter mechanism — gate fires on every Write/Edit
- Exemptions already handle pre-flight/, watchers/, state/ paths
- Watcher slot has TO-DO checklist with `- [ ]` and `- [x]` items

## Identified Issues
1. Gate fires on EVERY non-exempt Write/Edit — too much friction for sustained coding
2. Agents preemptively answer challenges, then get blocked again (wasted effort)
3. No concept of "current step" tracking — gate cannot detect step changes

## Applicable Patterns
1. Write counter from pre-write-gate.sh (.claude/state/write-count.txt) — proven pattern for counting writes
2. Step tracking: extract first `- [ ]` from watcher TO-DO, compare to saved value to detect step changes
3. Counter state file: simple text file with current count and last-known step
4. Modular change: all logic added to pre-flight-gate.sh only, no other scripts touched
