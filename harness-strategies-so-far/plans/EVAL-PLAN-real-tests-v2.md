# Real End-to-End Evaluation Plan v2

## Principle: Every test verifies an OBSERVABLE FILE ON DISK. No "watch and observe" tests.

## PRECONDITIONS
- Set write-count to 1 before starting (avoid startup-recovery side effects)
- All tests run in G:\harness infra which has .claude/ and .agent-memory/

---

## TEST GROUP 1: Hook Trigger Path

### H1: Write-count increments
- Pre: set write-count.txt to "5"
- Action: Write a file (real Write tool)
- Check: write-count.txt contains "6"

### H2: Activity log appended
- Pre: count lines in recent-activity.jsonl
- Action: Write a file
- Check: line count increased by 1, last line is valid JSON with "ts" and "phase" fields

### H3: Session-context reflects current state
- Pre: set current-phase.json to {"phase":"BUILD","sprint":2,"iteration":7}
- Action: Write a file
- Check: session-context.md contains "Phase: BUILD" AND "Sprint: 2"

### H4: Hash gate prevents redundant writes
- Pre: record session-context.md.hash content
- Action: Write a file WITHOUT changing phase
- Check: hash file content is identical (no redundant rewrite)

### H5: Watcher self-check triggers at 5+ writes
- Pre: set write-count.txt to "4", delete watcher-self-check.md if exists
- Action: Write a file (count becomes 5)
- Check: watcher-self-check.md EXISTS and contains "multi-step task"

### H6: Watcher self-check does NOT trigger under 5 writes
- Pre: set write-count.txt to "1", delete watcher-self-check.md
- Action: Write a file (count becomes 2)
- Check: watcher-self-check.md does NOT exist

### H7: Negative scoping — Read/Bash do NOT fire hook
- Pre: record write-count.txt value
- Action: Do a Read operation (read a file), then a Bash operation
- Check: write-count.txt is UNCHANGED (hook only fires on Write/Edit)

---

## TEST GROUP 2: Phase Validation (real hook trigger, not manual script call)

### V1: Phase validation blocks when requirements missing
- Pre: set phase to PLAN, delete product-spec.md
- Action: Write phase-complete-marker.md (real Write tool)
- Check: phase-feedback.md EXISTS and contains "FAIL" and "does not exist"
- Check: phase-complete-marker.md was DELETED by hook

### V2: Phase validation passes and logs transition
- Pre: set phase to NEGOTIATE, create valid product-spec.md with "## Acceptance Criteria"
- Action: Write phase-complete-marker.md
- Check: transitions.jsonl has new line with "phase_complete"
- Check: phase-complete-marker.md was DELETED by hook

---

## TEST GROUP 3: State Machine Enforcement

### SM1: Valid transition accepted
- Action: run validate-state-transition.sh REQUESTED CONTRACT_LOCKED
- Check: exit code 0

### SM2: Invalid skip rejected
- Action: run validate-state-transition.sh REQUESTED IMPLEMENTED
- Check: exit code 1, stderr contains "not an allowed transition"

### SM3: STUCK from any active state
- Action: run validate-state-transition.sh BUILD STUCK
- Check: exit code 0 (STUCK allowed from any active state)

### SM4: ACCEPTED is terminal
- Action: run validate-state-transition.sh ACCEPTED BUILD
- Check: exit code 1, stderr contains "terminal"

---

## TEST GROUP 4: Loop Detection (real git history)

### LD1: No loop detected on normal repo
- Pre: clean git history (< 4 repeated files)
- Action: run detect-loop.sh
- Check: exit code 0, no agent-blocked.md created

### LD2: Loop detected on repeated file modifications
- Pre: create 5 commits modifying same file
- Action: run detect-loop.sh
- Check: exit code 1, either next-fix.md OR agent-blocked.md exists

### LD3: Known fix injected when loop matches
- Pre: add known-fix entry matching the repeated file, create 5 commits
- Action: run detect-loop.sh
- Check: next-fix.md exists and contains "MANDATORY FIX"

---

## TEST GROUP 5: Known-Fix Injection

### KF1: on-test-failure matches symptom and injects fix
- Pre: create known-fixes.md with symptom "cannot find module", create test-output.txt containing "cannot find module foo"
- Action: run on-test-failure.sh test-output.txt
- Check: next-fix.md exists and contains "KNOWN FIX FOUND"

### KF2: on-test-failure does NOT inject on non-matching symptom
- Pre: create test-output.txt containing "unrelated error"
- Action: run on-test-failure.sh test-output.txt
- Check: next-fix.md does NOT exist

---

## TEST GROUP 6: Recovery

### RC1: Recovery detects missed session-end
- Pre: set write-count to 10, delete today's session files
- Action: run startup-recovery.sh
- Check: recovery session file exists with "RECOVERY" in name/content
- Check: sessions.jsonl has new "session_recovery" entry
- Check: write-count.txt reset to 0

### RC2: Recovery updates MANIFEST
- Pre: record sessions_count
- Action: run startup-recovery.sh (with stale write-count)
- Check: sessions_count incremented by 1

---

## TEST GROUP 7: Session End (user verifies after exiting)

### SE1: User exits cleanly, checks session file
- How: type /exit in Claude Code
- Verify: ls .agent-memory/episodic/sessions/ — new file exists
- Verify: jq .sessions_count .agent-memory/MEMORY_MANIFEST.json — incremented
- Verify: cat .agent-memory/working/active-tasks.json — contains current phase

---

## TEST GROUP 8: Cross-Session Persistence (user verifies)

### CS1: Memory survives restart
- How: close and reopen Claude Code in same project
- Verify: ask Claude "what phase were we in?" — it should answer from current-phase.json
- Verify: ask Claude "what was I working on?" — it should answer from progress-notes.md

### CS2: Recovery fires after hard close
- How: close terminal with X button, reopen Claude Code, do one Write
- Verify: ls .agent-memory/episodic/sessions/ — recovery file exists

---

## EXECUTION ORDER
1. Groups 1-6: Run NOW in this session (real hook triggers + script calls)
2. Group 7: User verifies after exiting this session
3. Group 8: User verifies after reopening
