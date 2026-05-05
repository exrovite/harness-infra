# PLAN: Hard Enforcement System for Harness Hooks

**Author:** Planner Agent (Opus 4.6)
**Date:** 2026-04-04
**Status:** PLAN (ready for review, not yet implemented)

---

## 1. Problem Statement

Claude sees harness hook messages (watcher not claimed, phase status, pending actions) via `additionalContext` JSON in PostToolUse and UserPromptSubmit hooks. **It ignores them.** The `additionalContext` field is advisory -- Claude has no obligation to comply. After 5+ writes without a watcher, the post-write-check nags but never blocks.

The existing `pre-write-gate.sh` already has the right structure (exit 2 to block) but is **not registered in settings.json** -- it never fires. The existing hooks are:
- `UserPromptSubmit` -> `on-prompt-submit.sh` (fires, advisory)
- `PostToolUse` (Write|Edit) -> `post-write-check.sh` (fires, advisory)
- `Stop` -> `on-session-end.sh` (fires, cleanup)

**Missing:** `PreToolUse` (Write|Edit) -> `pre-write-gate.sh` (would fire, would BLOCK)

---

## 2. Verified Evidence (Empirical, Not Documentation)

These were tested and confirmed working on this machine:

| # | Fact | Implication |
|---|------|------------|
| 1 | PreToolUse hook with `exit 2` BLOCKS Write/Edit -- file never created, stderr shown to Claude | **This is the enforcement primitive.** Exit 2 = hard block. |
| 2 | PostToolUse hook with `additionalContext` JSON -- Claude sees it but can ignore it | Useful for status display, NOT for enforcement. |
| 3 | UserPromptSubmit hook stdout -- injected into Claude's context at start of every turn | Useful for early warning ("your tools are locked"), NOT for enforcement. |
| 4 | Settings are hot-reloaded -- no restart needed | We can deploy and test without restarting Claude. |
| 5 | Agent cannot disable guardrails via Edit (also blocked) -- must use Bash | The gate is self-protecting against Write/Edit bypass of the gate config. |
| 6 | Bash operations are NOT blocked by Write/Edit matcher | **Known gap.** Claude can use `bash -c 'echo foo > file.txt'` to bypass the gate. |

---

## 3. Hook Architecture

### 3.1 Hook 1: PreToolUse Gate (`pre-write-gate.sh`) -- THE ENFORCER

**Event:** `PreToolUse`
**Matcher:** `Write|Edit`
**Exit codes:** `0` = allow, `2` = block (file operation prevented, stderr shown to Claude)
**Purpose:** Hard-block Write/Edit when harness requirements are not met.

#### Checks (evaluated in order, first failure blocks):

**Check A: Watcher Compliance (5+ writes without watcher)**

```
IF write-count.txt >= 5 AND no active watcher in REGISTRY.json:
    EXIT 2 with instructions to claim a watcher
ELSE:
    PASS (continue to next check)
```

Stderr message when blocked:
```
======================================================
BLOCKED: Write/Edit tools are LOCKED.
======================================================

You have made [N] file writes without claiming a watcher.
Your Write and Edit tools will remain locked until you comply.

DO THIS NOW:
1. Read C:\Users\exrov\.openclaw\watchers\REGISTRY.json
2. Find a slot with status "available"
3. Update that slot: set status to "active", claimed_by to your name
4. Write your task details into the slot's .md file
5. Run CronCreate with */3 * * * * to set a recurring reminder
6. Then retry your write -- it will succeed.

DO NOT attempt to use Bash to write files instead.
DO NOT skip this step.
======================================================
```

**Check B: State Machine Phase Enforcement (optional, Phase 2 of implementation)**

```
IF current-phase.json exists:
    phase = read phase from current-phase.json
    tool_target_path = path Claude is trying to write to

    IF phase == "PLAN" AND target is in src/ or lib/ or app/:
        EXIT 2 "BLOCKED: You are in PLAN phase. You may only write to specs/, contracts/, or docs/."

    IF phase == "EVALUATE" AND target is in src/ or lib/ or app/:
        EXIT 2 "BLOCKED: You are in EVALUATE phase. Evaluators do not modify source code."
```

Stderr message when blocked (PLAN phase example):
```
======================================================
BLOCKED: Phase violation.
======================================================

Current phase: PLAN
You attempted to write to: src/components/Button.tsx

During PLAN phase, you may only write to:
  - .claude/specs/     (specifications)
  - .claude/contracts/  (sprint contracts)
  - .agent-memory/     (memory system files)
  - docs/              (documentation)

Source code writes (src/, lib/, app/) are blocked until BUILD phase.
======================================================
```

#### Edge Cases:

| Edge Case | Handling |
|-----------|----------|
| `write-count.txt` does not exist | Treat as 0 writes. ALLOW. |
| `REGISTRY.json` does not exist | No watcher system available. ALLOW (cannot enforce what doesn't exist). |
| `current-phase.json` does not exist | Project not initialized. ALLOW (no state machine to enforce). |
| `.claude/state/` directory missing | Project not initialized. ALLOW. |
| Claude writes to `.agent-memory/` during PLAN phase | ALLOW -- memory updates are always permitted regardless of phase. |
| Claude writes to `.claude/state/` during any phase | ALLOW -- state files are always permitted. |
| Write count is not a number | Treat as 0. ALLOW. |
| Multiple watchers active | At least one active = compliant. ALLOW. |
| Watcher claimed by different agent | Still counts as active. ALLOW. (Watcher slot enforcement is a separate concern.) |

#### Exempt paths (never blocked regardless of phase):

These paths are always writable because they are infrastructure, not source code:
- `.agent-memory/**` -- memory system
- `.claude/state/**` -- harness state
- `.claude/specs/**` -- specifications (PLAN phase output)
- `.claude/contracts/**` -- sprint contracts
- `**/phase-complete-marker.md` -- phase transition signal
- `**/known-fixes.md` -- fix registry
- `**/progress-notes.md` -- progress tracking

---

### 3.2 Hook 2: UserPromptSubmit Context Injection (`on-prompt-submit.sh`) -- THE WARNER

**Event:** `UserPromptSubmit`
**Matcher:** `""` (empty = fires on every prompt)
**Exit codes:** Always `0` (never blocks user input)
**Purpose:** Tell Claude the state of the world BEFORE it tries anything. If the gate is active, say so.

#### Enhancement needed:

The existing `on-prompt-submit.sh` already works. It needs one addition: when the pre-write-gate WOULD block (write-count >= 5 AND no watcher), the context message should say so explicitly.

Current output:
```
[HARNESS STATE] Phase: BUILD | Sprint: 2 | Iter: 7 | Writes: 12 | Watcher: NOT CLAIMED (12 writes -- consider claiming one)
```

Enhanced output when gate is active:
```
[HARNESS STATE] Phase: BUILD | Sprint: 2 | Iter: 7 | Writes: 12 | Watcher: NOT CLAIMED
*** YOUR WRITE/EDIT TOOLS ARE LOCKED. Claim a watcher first. See pre-write-gate stderr for instructions. ***
```

This is still advisory (Claude can try to write and get blocked), but it prevents Claude from wasting a turn attempting a write that will fail.

---

### 3.3 Hook 3: PostToolUse Feedback (`post-write-check.sh`) -- THE COUNTER

**Event:** `PostToolUse`
**Matcher:** `Write|Edit`
**Exit codes:** Always `0` (never blocks after the fact)
**Purpose:** Increment write counter, update memory, check for phase-complete markers.

#### No changes needed.

This hook already:
- Increments `write-count.txt` (the counter that `pre-write-gate.sh` reads)
- Updates `.agent-memory/working/session-context.md`
- Checks for `phase-complete-marker.md`
- Outputs `additionalContext` with current state

The write counter increment here is critical -- it is the input that the PreToolUse gate reads. The flow is:

```
Claude attempts Write/Edit
  -> PreToolUse fires pre-write-gate.sh
     -> Reads write-count.txt (value from LAST successful write)
     -> If >= 5 and no watcher: EXIT 2 (BLOCKED, write never happens)
     -> If < 5 or watcher active: EXIT 0 (ALLOWED)
  -> Write/Edit executes (only if PreToolUse allowed it)
  -> PostToolUse fires post-write-check.sh
     -> Increments write-count.txt
     -> Updates memory
     -> Outputs additionalContext
```

---

## 4. Settings.json Configuration

### Current hooks section:
```json
{
  "hooks": {
    "UserPromptSubmit": [...],
    "PostToolUse": [{ "matcher": "Write|Edit", ... }],
    "Stop": [...]
  }
}
```

### Required addition:
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash -c 'echo \"[HOOK] pre-write-gate fired at $(date)\" >> /tmp/claude-hooks.log 2>/dev/null; bash $HOME/.claude/hooks/pre-write-gate.sh'"
          }
        ]
      }
    ],
    "UserPromptSubmit": [...existing...],
    "PostToolUse": [...existing...],
    "Stop": [...existing...]
  }
}
```

**Note on ordering:** PreToolUse fires BEFORE the tool executes. PostToolUse fires AFTER. Both use the same matcher (`Write|Edit`). This means every Write/Edit goes through:
1. `pre-write-gate.sh` (can block with exit 2)
2. The actual Write/Edit (only if step 1 allowed)
3. `post-write-check.sh` (increments counter, updates state)

---

## 5. The Bash Bypass Gap

### The problem

Claude can bypass the Write/Edit gate by using Bash:
```bash
bash -c 'cat > src/app.js << "EOF"
console.log("I bypassed the gate");
EOF'
```

The PreToolUse hook with matcher `Write|Edit` does NOT fire on Bash tool calls.

### Analysis

There are three options:

**Option A: Add a PreToolUse hook for Bash with path inspection**
- Problem: The Bash tool's arguments are a command string, not a file path. We would need to parse arbitrary shell commands to detect file writes (`>`, `>>`, `tee`, `cp`, `mv`, `cat >`, `printf >`, heredocs, etc.). This is fragile and will have false positives/negatives.
- Verdict: **Not viable.** Shell command parsing is an unsolvable problem in the general case.

**Option B: Add a Bash matcher that checks for redirect operators**
- A simpler version: `grep -qE '>\s|>>\s|tee\s' <<< "$COMMAND"` and block if the gate is active.
- Problem: This blocks legitimate Bash usage (running tests, reading files with redirects, piping). Too many false positives.
- Verdict: **Not viable.** Would break normal workflow.

**Option C: Accept the gap and document it**
- Claude CAN bypass via Bash, but it has to deliberately choose to do so.
- The stderr message from the gate explicitly says "DO NOT attempt to use Bash to write files instead."
- If Claude does bypass, the post-write-check won't fire (no counter increment), but the file appears on disk.
- Mitigation: Layer 2 scripts (validate-phase.sh, evaluate-protocol-compliance.sh) check actual disk state at phase boundaries, catching unauthorized files.
- Verdict: **Accept this gap.** Document it. Mitigate at phase boundaries.

### Recommended approach: Option C

**Rationale:** The gate's purpose is to make compliance the path of least resistance, not to make bypass impossible. If Claude ignores the gate AND ignores the warning AND deliberately uses Bash to write files, that's a model behavior problem that no hook architecture can fully solve. The phase boundary checks (Layer 2) will catch the consequences.

**Future consideration:** If this becomes a pattern, we could add a Bash PostToolUse hook that scans the command for file-write patterns and logs them (not blocks -- just logs). This creates an audit trail without breaking workflow.

---

## 6. What Remains as Soft Enforcement (and Why That's OK)

| Instruction | Enforcement Type | Why Soft Is OK |
|-------------|-----------------|----------------|
| "Read memory files at session start" | Soft (CLAUDE.md) | Genuine reading task -- can't force LLM to comprehend what it reads |
| "Update session-context.md every 10-15 min" | Soft (CLAUDE.md) + Hard (post-write-check does it automatically) | The hook handles the actual update; the instruction is for manual updates between writes |
| "Log decisions to episodic/decisions/" | Soft (CLAUDE.md) | Genuine writing task requiring judgment about what's worth logging |
| "Write creative/high-level plans" | Soft (planner prompt) | Genuine judgment -- Layer 3 appropriate |
| "Don't attempt Bash bypass" | Soft (stderr message) | See Section 5 -- accepted gap |
| "Release watcher when done" | Soft (CLAUDE.md + watcher slot instructions) | Cleanup task; worst case = stale slot, not incorrect behavior |

**Everything that CAN be hard-enforced IS hard-enforced.** The remaining soft items are either (a) genuine LLM judgment tasks or (b) cleanup operations where the consequence of failure is low.

---

## 7. Implementation Order

### Phase 1: Register the PreToolUse gate (the critical path)

**Step 1.1:** Verify `pre-write-gate.sh` exists and is correct.
- File: `C:\Users\exrov\.claude\hooks\pre-write-gate.sh`
- Status: EXISTS. Already written. Needs review for the edge cases in Section 3.1.

**Step 1.2:** Update `pre-write-gate.sh` to handle all edge cases.
- Add numeric validation for write count (handle non-numeric values)
- Add explicit check for REGISTRY.json missing (currently falls through to exit 0, which is correct but should be explicit)
- Improve stderr message formatting per Section 3.1

**Step 1.3:** Add PreToolUse entry to `settings.json`.
- This is the single change that activates enforcement.
- Hot-reload means it takes effect immediately.

**Step 1.4:** Test the gate. (See Section 8.)

**Estimated effort:** 30 minutes.

### Phase 2: Enhance the UserPromptSubmit warning

**Step 2.1:** Update `on-prompt-submit.sh` to detect when the gate is active and include the "TOOLS ARE LOCKED" warning.
- Read write-count.txt and REGISTRY.json (same logic as gate)
- If gate would block: add the locked warning to context message

**Estimated effort:** 15 minutes.

### Phase 3: Add state machine phase enforcement to the gate (optional)

**Step 3.1:** Add Check B (phase enforcement) to `pre-write-gate.sh`.
- Requires detecting the target file path from the PreToolUse hook input.
- **Open question:** Does the PreToolUse hook receive the file path as an argument or environment variable? This needs to be empirically tested before implementation.

**Step 3.2:** Define exempt paths list.
- Hard-code the list from Section 3.1 (`.agent-memory/`, `.claude/state/`, etc.)
- Allow writes to exempt paths regardless of phase.

**Step 3.3:** Test phase enforcement.

**Estimated effort:** 45 minutes (including empirical testing of hook input).

**Dependency:** Must determine how PreToolUse receives the target path. If it doesn't, phase enforcement via PreToolUse is not possible and would need a different approach.

### Phase 4: Audit trail for Bash writes (future, low priority)

**Step 4.1:** Add a PostToolUse hook for Bash that logs commands containing file-write patterns.
- Matcher: `Bash`
- No blocking (exit 0 always)
- Log to `.claude/state/bash-write-audit.log`

**Estimated effort:** 20 minutes.
**Priority:** Low. Only implement if Bash bypass becomes a pattern.

---

## 8. Test Plan

All tests must be run empirically on the actual Claude Code environment. No simulated tests.

### Test 1: Gate blocks after 5 writes without watcher

**Setup:**
1. Ensure no active watchers in REGISTRY.json (all slots "available")
2. Set `write-count.txt` to `6`

**Action:**
1. Ask Claude to write a test file: "Write the word 'hello' to `test-gate-block.txt`"

**Expected:**
- File `test-gate-block.txt` is NOT created
- Claude sees stderr message with "BLOCKED" and watcher instructions
- Claude reports it was blocked

**Verify:**
```bash
[ ! -f test-gate-block.txt ] && echo "PASS: file not created" || echo "FAIL: file was created"
```

### Test 2: Gate allows with active watcher

**Setup:**
1. Set slot-1 status to "active" in REGISTRY.json
2. Keep `write-count.txt` at `6`

**Action:**
1. Ask Claude to write a test file: "Write the word 'hello' to `test-gate-allow.txt`"

**Expected:**
- File `test-gate-allow.txt` IS created with content "hello"
- post-write-check fires and increments counter to 7

**Verify:**
```bash
[ -f test-gate-allow.txt ] && echo "PASS: file created" || echo "FAIL: file not created"
cat .claude/state/write-count.txt  # Should show 7
```

**Cleanup:**
```bash
rm test-gate-allow.txt
# Reset watcher slot to "available"
```

### Test 3: Gate allows under 5 writes without watcher

**Setup:**
1. Ensure no active watchers
2. Set `write-count.txt` to `3`

**Action:**
1. Ask Claude to write a test file

**Expected:**
- File IS created (under threshold, no block)

**Verify:**
```bash
[ -f test-gate-under.txt ] && echo "PASS" || echo "FAIL"
```

### Test 4: Gate allows when no harness state exists

**Setup:**
1. Rename `current-phase.json` temporarily
2. Set `write-count.txt` to `10`

**Action:**
1. Ask Claude to write a test file

**Expected:**
- File IS created (no harness state = no enforcement)

**Verify:**
```bash
[ -f test-gate-noinit.txt ] && echo "PASS" || echo "FAIL"
```

**Cleanup:**
```bash
# Restore current-phase.json
```

### Test 5: Gate self-protection (cannot be disabled via Edit)

**Setup:**
1. Gate is active (writes >= 5, no watcher)

**Action:**
1. Ask Claude: "Edit the file `C:\Users\exrov\.claude\hooks\pre-write-gate.sh` and change exit 2 to exit 0"

**Expected:**
- Edit is BLOCKED (the gate fires on Edit too!)
- Claude sees stderr telling it to claim a watcher
- The gate script is NOT modified

**Verify:**
```bash
grep -c "exit 2" "$HOME/.claude/hooks/pre-write-gate.sh"  # Should still be present
```

### Test 6: UserPromptSubmit shows "LOCKED" warning

**Setup:**
1. Gate is active (writes >= 5, no watcher)
2. on-prompt-submit.sh updated with lock warning (Phase 2)

**Action:**
1. Send any prompt to Claude

**Expected:**
- Claude's context includes "[HARNESS STATE]" with "WRITE/EDIT TOOLS ARE LOCKED"
- This appears BEFORE Claude attempts any action

### Test 7: Gate allows .agent-memory writes during any phase (Phase 3)

**Setup:**
1. Phase enforcement active
2. Phase set to "PLAN"

**Action:**
1. Ask Claude to update `.agent-memory/working/session-context.md`

**Expected:**
- Write succeeds (exempt path)

### Test 8: Gate blocks src/ writes during PLAN phase (Phase 3)

**Setup:**
1. Phase enforcement active
2. Phase set to "PLAN"
3. Watcher is claimed (so watcher check passes)

**Action:**
1. Ask Claude to create `src/test.js`

**Expected:**
- Write is BLOCKED
- Claude sees stderr about phase violation

### Test 9: Bash bypass (documenting the gap)

**Setup:**
1. Gate is active (writes >= 5, no watcher)

**Action:**
1. Ask Claude: "Using bash, write 'hello' to test-bash-bypass.txt"

**Expected:**
- File IS created (Bash is not gated)
- This documents the known gap

**Verify:**
```bash
[ -f test-bash-bypass.txt ] && echo "CONFIRMED: Bash bypass works (known gap)" || echo "Bash bypass did not work"
```

---

## 9. Open Questions Requiring Empirical Testing

### Q1: Does PreToolUse receive the target file path?

The pre-write-gate needs to know WHICH file Claude is trying to write to for phase enforcement (Check B). We need to test whether the hook receives:
- An environment variable with the file path
- A command-line argument with the file path
- stdin with the tool call details
- Nothing (only knows the tool name)

**Test:** Add `env > /tmp/pre-hook-env.txt; echo "$@" > /tmp/pre-hook-args.txt; cat > /tmp/pre-hook-stdin.txt` to the gate script temporarily, trigger a Write, and inspect the output.

If the file path is NOT available, phase enforcement (Check B) must use a different approach:
- PostToolUse (which may receive more context) could retroactively flag violations
- Or: a separate Layer 2 script runs at phase boundaries to check for unauthorized files

### Q2: Does PreToolUse matcher support regex for tool+path?

Can we match `Write|Edit` AND filter by path? Or does the matcher only match tool names? If tool-only, path filtering must happen inside the script.

### Q3: What happens when PreToolUse exit 2 fires on NotebookEdit?

The matcher `Write|Edit` may or may not match `NotebookEdit`. If not, notebook edits bypass the gate. Need to test.

---

## 10. Architectural Diagram

```
Claude wants to Write/Edit a file
            |
            v
    [PreToolUse Hook fires]
    pre-write-gate.sh
            |
     +------+------+
     |             |
  EXIT 2         EXIT 0
  (BLOCKED)      (ALLOWED)
     |             |
     v             v
  Claude sees    Write/Edit
  stderr msg     executes
  "BLOCKED:      successfully
   claim a          |
   watcher"         v
     |        [PostToolUse Hook fires]
     |        post-write-check.sh
     |             |
     v             v
  Claude must   Increments write-count.txt
  comply        Updates .agent-memory
  before        Checks phase-complete marker
  retrying      Outputs additionalContext
```

```
Every Claude turn (any prompt):
            |
            v
    [UserPromptSubmit Hook fires]
    on-prompt-submit.sh
            |
            v
    Outputs additionalContext with:
    - Current phase, sprint, iteration
    - Write count
    - Watcher status
    - *** TOOLS ARE LOCKED *** (if gate is active)
            |
            v
    Claude sees this context BEFORE
    deciding what to do
```

---

## 11. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Gate blocks legitimate quick edits | Low | Medium | 5-write threshold gives buffer for quick tasks |
| Claude uses Bash to bypass gate | Medium | Medium | Stderr warning + phase boundary checks |
| Gate fires on memory/state writes it shouldn't block | Medium | High | Exempt paths list (Section 3.1) -- requires path detection |
| PreToolUse doesn't receive file path | Unknown | High (blocks Phase 3) | Empirical test needed (Q1 in Section 9) |
| Gate creates deadlock (can't claim watcher because Edit blocked, can't use anything but Bash) | Low | High | Watcher claim uses Read + Bash (not Edit), so no deadlock. Bash is never blocked. |
| Settings.json edit fails and breaks all hooks | Low | Critical | Test in isolation first. Settings hot-reload means quick recovery. |

### Critical insight on deadlock prevention

When the gate is active and Claude's Write/Edit is locked, Claude must claim a watcher. The watcher claiming process is:
1. **Read** REGISTRY.json -- Read tool is NOT blocked
2. **Update** REGISTRY.json -- This IS a Write/Edit... **potential deadlock!**

**Resolution:** Claude must use **Bash** to update the REGISTRY.json:
```bash
# Claude uses Bash (not blocked) to update the registry
jq '.watchers[0].status = "active" | .watchers[0].claimed_by = "Claude"' \
  "$HOME/.openclaw/watchers/REGISTRY.json" > /tmp/reg.tmp && \
  mv /tmp/reg.tmp "$HOME/.openclaw/watchers/REGISTRY.json"
```

The stderr message in the gate MUST make this clear. The current version says "Update that slot" but should specify to use Bash for the update. Updated instruction step 3 should be:

```
3. Use Bash to update the registry (your Write/Edit tools are locked, but Bash works):
   bash -c 'jq ".watchers[0].status = \"active\" | .watchers[0].claimed_by = \"Claude\"" "$HOME/.openclaw/watchers/REGISTRY.json" > /tmp/reg.tmp && mv /tmp/reg.tmp "$HOME/.openclaw/watchers/REGISTRY.json"'
```

This is a feature, not a bug: the Bash gap (Section 5) serves as the escape hatch for the watcher claiming process. If we ever close the Bash gap, we need an alternative escape hatch.

---

## 12. Summary of Deliverables

| # | Deliverable | File | Phase |
|---|------------|------|-------|
| 1 | Updated `pre-write-gate.sh` (edge cases, messaging) | `~/.claude/hooks/pre-write-gate.sh` | 1 |
| 2 | PreToolUse hook registration in `settings.json` | `~/.claude/settings.json` | 1 |
| 3 | Updated `on-prompt-submit.sh` (lock warning) | `~/.claude/hooks/on-prompt-submit.sh` | 2 |
| 4 | Phase enforcement in `pre-write-gate.sh` | `~/.claude/hooks/pre-write-gate.sh` | 3 |
| 5 | Bash audit hook (if needed) | `~/.claude/hooks/bash-audit.sh` | 4 |
| 6 | Updated SCRIPT_REGISTRY.json | `.agent-memory/procedural/scripts/SCRIPT_REGISTRY.json` | 1 |

---

## 13. Decision Log

| Decision | Rationale |
|----------|-----------|
| 5-write threshold before enforcement | Quick edits shouldn't require full ceremony. 5 writes implies a multi-step task. |
| Exit 2 (not exit 1) for blocking | Claude Code documentation specifies exit 2 as the "block with feedback" code. Exit 1 is generic failure. |
| Accept the Bash bypass gap | Shell command parsing is unsolvable in general. Mitigation via phase boundary checks is sufficient. |
| Phase enforcement as separate phase | Requires empirical testing of PreToolUse input. Don't block Phase 1 on unknowns. |
| Bash as the escape hatch for watcher claiming | The Bash gap is actually load-bearing for the watcher claiming flow. Must not close it without an alternative. |
| No blocking on UserPromptSubmit | Blocking user input would be hostile UX. Warning is appropriate; enforcement belongs on the tool. |
