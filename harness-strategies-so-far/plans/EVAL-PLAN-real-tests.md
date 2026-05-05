# Real End-to-End Evaluation Plan

## Principle: Every test MUST verify an OBSERVABLE OUTCOME on disk or in Claude's behavior. No code review tests. No "the script looks correct" tests.

---

## CATEGORY 1: Hook Trigger Path (testable from this session)

These verify that Write/Edit operations actually trigger hooks and hooks actually update files.

### Test H1: Write-count increments on each Write
**Method**: Record write-count.txt, do a Write, check write-count.txt again
**Pass criteria**: Number increased by exactly 1
**Fake version to avoid**: "write-count.txt exists" (that's not a test)

### Test H2: recent-activity.jsonl gets a new line on each Write
**Method**: Record line count, do a Write, check line count
**Pass criteria**: Line count increased by exactly 1, last line contains current timestamp and correct phase

### Test H3: session-context.md reflects current state after Write
**Method**: Change current-phase.json to BUILD sprint 2, do a Write, read session-context.md
**Pass criteria**: session-context.md says "Phase: BUILD" and "Sprint: 2"

### Test H4: session-context.md does NOT rewrite when unchanged (hash gate)
**Method**: Record session-context.md.hash, do a Write WITHOUT changing phase, check hash
**Pass criteria**: Hash file unchanged, session-context.md modification time unchanged

### Test H5: Watcher self-check triggers after 5 writes
**Method**: Set write-count to 4, do a Write (makes 5), check for watcher-self-check.md
**Pass criteria**: watcher-self-check.md exists with self-assessment questions

### Test H6: Watcher self-check does NOT trigger for quick edits (< 5 writes)
**Method**: Reset write-count to 0, do a Write, check for watcher-self-check.md
**Pass criteria**: watcher-self-check.md does NOT exist

### Test H7: Phase validation blocks on missing research output
**Method**: Write phase-complete-marker.md while in PLAN phase with no product-spec.md
**Pass criteria**: phase-feedback.md created with failure message, marker deleted

### Test H8: Phase transition logged to transitions.jsonl on success
**Method**: Create valid product-spec.md with required sections, write phase-complete-marker.md
**Pass criteria**: transitions.jsonl gets new entry with phase_complete event

---

## CATEGORY 2: Session End Hook (testable by exiting this session)

### Test S1: Session summary written on clean exit
**Method**: User types /exit. Check .agent-memory/episodic/sessions/ for new file.
**Pass criteria**: New session file exists with today's date, contains phase/progress/files sections
**How user verifies**: After exiting, run: ls .agent-memory/episodic/sessions/

### Test S2: MANIFEST updated on clean exit
**Method**: Record sessions_count before exit. Exit cleanly. Check sessions_count.
**Pass criteria**: sessions_count incremented by 1, last_accessed updated
**How user verifies**: Run: jq '{sessions_count, last_accessed}' .agent-memory/MEMORY_MANIFEST.json

### Test S3: active-tasks.json written on clean exit
**Method**: Exit cleanly. Check active-tasks.json.
**Pass criteria**: Contains current phase and "resume_action" field
**How user verifies**: Run: cat .agent-memory/working/active-tasks.json

---

## CATEGORY 3: Recovery (testable by simulating crash then reopening)

### Test R1: Recovery detects missed session-end
**Method**: Set write-count > 0, delete today's session files, run startup-recovery.sh
**Pass criteria**: Recovery session file created with "RECOVERY" in content

### Test R2: Recovery updates MANIFEST
**Method**: Record sessions_count, run recovery, check sessions_count
**Pass criteria**: Incremented by 1

### Test R3: Recovery resets write counter
**Method**: Set write-count to 10, run recovery, check write-count
**Pass criteria**: Write-count is 0

---

## CATEGORY 4: Cross-Session Persistence (requires user to open new session)

### Test P1: Memory files survive session restart
**Method**: User closes Claude, reopens in same project
**Pass criteria**: current-phase.json, progress-notes.md, session-context.md all still exist with correct content
**How user verifies**: Open Claude, ask it "what phase am I in?" — it should read current-phase.json and answer correctly

### Test P2: Claude reads memory at startup
**Method**: Set current-phase.json to BUILD sprint 3. Close and reopen Claude.
**Pass criteria**: Claude's first response references BUILD phase or sprint 3 without being told
**How user verifies**: Open Claude, ask "where did we leave off?" — answer should come from memory files

### Test P3: Claude reads active-tasks.json for resume context
**Method**: Write specific resume action to active-tasks.json. Reopen Claude.
**Pass criteria**: Claude references the resume action
**How user verifies**: Ask Claude "what should I do next?"

---

## CATEGORY 5: Claude Following Protocol (requires real task in real project)

### Test C1: Claude follows state machine on multi-step task
**Method**: Give Claude a real coding task in a real project. Observe if it goes through PLAN first.
**Pass criteria**: Claude writes product-spec.md before writing any code
**How user verifies**: Give task, watch Claude's first actions

### Test C2: Claude claims watcher on sustained work
**Method**: Give Claude a task requiring 5+ file writes. Check watcher registry.
**Pass criteria**: A watcher slot is claimed with task to-do list
**How user verifies**: After Claude writes several files, check: cat C:\Users\exrov\.openclaw\watchers\REGISTRY.json

### Test C3: Claude spawns independent verifier at EVALUATE phase
**Method**: Let Claude reach EVALUATE phase. Observe if it uses Agent tool.
**Pass criteria**: Sub-agent spawned that checks work without reading progress notes
**How user verifies**: Watch Claude's tool calls during evaluation

### Test C4: Claude escalates when stuck (doesn't spin)
**Method**: Give Claude a task that will fail (e.g., work with non-existent API). Watch behavior.
**Pass criteria**: After 3 failures, Claude writes STUCK to progress file and stops
**How user verifies**: Observe if Claude stops and reports facts

---

## WHAT MAKES THIS DIFFERENT FROM MY PREVIOUS FAKE TESTS

| Fake Test | Real Test |
|-----------|-----------|
| "Script exists" | "Hook fires and file on disk changes" |
| "Script has correct code" | "Output file contains correct data" |
| "Manually ran script, got exit 0" | "Triggered via Claude Code Write, checked disk" |
| "Simulated state by writing JSON" | "Observed Claude's actual behavior in real session" |
| "Checked file count" | "Read file content and verified accuracy" |
| "Script handles edge case in code" | "Created the edge case and verified behavior" |

---

## EXECUTION ORDER

1. Run Category 1 tests now (H1-H8) — these are real hook trigger tests
2. Run Category 3 tests now (R1-R3) — these test recovery
3. Category 2 (S1-S3) — user verifies after this session ends
4. Category 4 (P1-P3) — user verifies by reopening project
5. Category 5 (C1-C4) — user verifies by giving real task to Claude in another project
