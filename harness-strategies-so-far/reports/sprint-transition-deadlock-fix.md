# Sprint Transition Deadlock Fix — Breaking Circular Gate Dependencies

## What This Document Is

A complete analysis of how three independent gate scripts created a circular deadlock that permanently locked agents when transitioning from a COMPLETE phase to a new sprint. Covers the root cause, why each gate contributed, the three-file fix, and why the fix does not weaken any existing enforcement.

If you are maintaining the harness or debugging a similar lockout, this document explains exactly what went wrong and what was changed.

---

## The Problem

An agent finishes sprint 3. All criteria pass independent verification. The phase advances to COMPLETE. The agent then receives a new task — a one-line CSS fix — and needs to start sprint 4.

The agent changes `current-phase.json` to `{"phase": "BUILD", "sprint": 4}` (writing to `.claude/state/` is always exempt). It then tries to write a sprint contract. Three gates block it in a cycle:

```
Agent tries to write sprint-4-proposal.md
    |
    v
pre-flight-gate.sh: BLOCKED — phase-feedback.md contains FAIL
    (from sprint 3 verification — stale but still present)
    |
    "Fix the failure first, then write phase-complete-marker.md"
    |
    v
Agent tries to spawn a verification sub-agent to clear the feedback
    |
    v
pre-write-gate.sh: BLOCKED — BUILD requires contract for sprint 4
    (no contract exists yet — agent was trying to write one)
    |
    "Complete NEGOTIATE phase first"
    |
    v
Agent tries Bash workaround to write the contract
    |
    v
pre-bash-gate.sh: BLOCKED — phase-feedback.md contains FAIL
    "Cannot bypass Write/Edit hooks via shell commands"
    |
    v
... back to start. Agent is permanently locked.
```

Every gate requires another gate to be resolved first. The agent correctly escalated per the stuck protocol.

---

## Why It Happened

Each gate was designed in isolation for a valid purpose. None is buggy on its own. The deadlock emerged from their interaction at a specific state transition.

### Gate 1: Phase-Feedback FAIL Block (`pre-flight-gate.sh`)

**Purpose**: When phase validation fails, block ALL code writes until the agent addresses the failure. Prevents agents from ignoring failed tests and continuing to pile on code.

**The flaw**: The exemption list was too narrow:
```bash
# BEFORE (only 2 exemptions)
if printf '%s' "$TARGET_NORM" | grep -qF '.claude/state/'; then exit 0; fi
if printf '%s' "$TARGET_NORM" | grep -qF '.openclaw/watchers/'; then exit 0; fi
```

`.claude/contracts/` was not exempt. The agent needed to write a contract to advance past the stale feedback, but couldn't write a contract because of the stale feedback. `.claude/specs/`, `.agent-memory/`, and other infrastructure paths were also missing.

**Key insight**: Phase-feedback's purpose is to block *source code* writes, not *harness infrastructure* writes. Contracts, specs, and memory files are phase-transition infrastructure — blocking them prevents the agent from doing the exact work needed to clear the block.

### Gate 2: Contract Gate Agent Block (`pre-write-gate.sh`)

**Purpose**: In BUILD phase, block all writes until a sprint contract exists. Without a contract, the agent has no scope boundary and will drift indefinitely.

**The flaw**: The Agent tool was subject to the contract gate. Spawning a sub-agent does not write files — the sub-agent's *own* Write/Edit calls go through the same hooks independently. Blocking Agent here prevented the agent from spawning a verification sub-agent to clear the phase-feedback.

**Key insight**: The contract gate's concern is scope drift in *code writes*. Agent spawning is a coordination action, not a file write. The spawned agent gets its own gating — blocking the spawn is redundant and creates deadlocks.

### Gate 3: Bash Bootstrap Exemptions (`pre-bash-gate.sh`)

**Purpose**: Prevent agents from bypassing Write/Edit hooks by using `python3 -c`, `echo >`, `sed -i`, etc. via the Bash tool. Apply the same enforcement as Write/Edit.

**The flaw**: The bootstrap exemption list (paths always allowed via Bash) did not include `.claude/contracts/` or `.claude/specs/`:
```bash
# BEFORE (5 exemptions, contracts/specs missing)
if printf '%s' "$COMMAND" | grep -qiF '.openclaw/watchers/'; then exit 0; fi
if printf '%s' "$COMMAND" | grep -qiF '.claude/state/'; then exit 0; fi
if printf '%s' "$COMMAND" | grep -qiF '.claude/pre-flight/'; then exit 0; fi
if printf '%s' "$COMMAND" | grep -qiF '.agent-memory/'; then exit 0; fi
if printf '%s' "$COMMAND" | grep -qiF 'agentwiki/'; then exit 0; fi
```

This closed the last escape route. Even if the agent tried to write the contract via Bash, the phase-feedback FAIL block in pre-bash-gate.sh would catch it.

---

## The Fix

Three edits, one per file. Each is minimal and targeted.

### Fix 1: `pre-flight-gate.sh` — Expand phase-feedback FAIL exemptions

**Location**: `~/.claude/hooks/pre-flight-gate.sh`, lines 28-34

**Before**: Two individual `if` checks for `.claude/state/` and `.openclaw/watchers/`.

**After**: A loop over all 7 infrastructure path patterns:
```bash
if [ -f "$PHASE_FB" ] && grep -qF "FAIL" "$PHASE_FB" 2>/dev/null; then
  # Allow writes to harness infrastructure paths (needed for phase transitions)
  for FB_PAT in '.claude/state/' '.openclaw/watchers/' '.claude/contracts/' \
                '.claude/specs/' '.claude/pre-flight/' '.agent-memory/' 'agentwiki/'; do
    if printf '%s' "$TARGET_NORM" | grep -qiF "$FB_PAT"; then
      exit 0
    fi
  done
  # Block source code writes until feedback is addressed
  ...
  exit 2
fi
```

**What changed**: Added `.claude/contracts/`, `.claude/specs/`, `.claude/pre-flight/`, `.agent-memory/`, `agentwiki/` to exemptions. Refactored from individual `if` blocks to a loop for maintainability.

**What didn't change**: Non-infrastructure paths (source code, config files, test files) are still blocked when phase-feedback contains FAIL. The `exit 2` at the end is untouched.

### Fix 2: `pre-write-gate.sh` — Exempt Agent tool from contract gate

**Location**: `~/.claude/hooks/pre-write-gate.sh`, lines 82-85

**Added**:
```bash
# Agent tool spawns subagents — they get their own Write/Edit gating independently.
# Blocking Agent here creates deadlocks (can't spawn verifier without contract).
CG_TOOL=$(printf '%s' "$INPUT_DATA" | jq -r '.tool_name // ""' 2>/dev/null)
if [ "$CG_TOOL" = "Agent" ]; then exit 0; fi
```

**What changed**: When no contract exists and the tool is Agent, allow (exit 0) instead of blocking.

**What didn't change**: Write and Edit tools are still blocked when no contract exists (they fall through to the path exemption checks and then the block message at line 96). Only Agent — which doesn't write files itself — is exempt.

### Fix 3: `pre-bash-gate.sh` — Add contract/spec paths to bootstrap exemptions

**Location**: `~/.claude/hooks/pre-bash-gate.sh`, lines 70-71

**Added**:
```bash
if printf '%s' "$COMMAND" | grep -qiF '.claude/contracts/'; then exit 0; fi
if printf '%s' "$COMMAND" | grep -qiF '.claude/specs/'; then exit 0; fi
```

**What changed**: Bash commands targeting `.claude/contracts/` or `.claude/specs/` paths are now exempt from the file-write detection gates, matching the Write/Edit exemptions in pre-write-gate.sh.

**What didn't change**: Bash commands targeting source code paths are still detected and blocked when phase-feedback FAIL is active or when no watcher is claimed.

---

## Why Independent Verification Is Not Weakened

This is the critical question. The harness enforces a builder/verifier separation: the agent that writes code cannot declare its own work verified. An independent sub-agent must check. Does exempting Agent from the contract gate weaken this?

**No. The two gates serve different purposes and operate independently.**

There are two separate gate sections in `pre-write-gate.sh`:

| Gate | Line range | When it fires | What it protects | Agent exempt? |
|------|-----------|---------------|-----------------|---------------|
| **Phase gate** | 25-75 | Non-BUILD phases (PLAN, NEGOTIATE, EVALUATE, COMPLETE) | Prevents code writes outside BUILD | Yes — **pre-existing** (line 28) |
| **Contract gate** | 79-105 | BUILD phase without a contract | Prevents scope drift | Yes — **new** (line 85) |

Independent verification is enforced by the **phase gate**, not the contract gate:

1. **EVALUATE phase** (line 59-62) blocks all Write/Edit — the builder cannot write code during evaluation. This is untouched.
2. **Agent was already exempt from the phase gate** (line 26-28) — this is how verification sub-agents could always be spawned during EVALUATE. This is pre-existing behavior, not new.
3. **Spawned sub-agents go through the same hooks** — when a sub-agent tries to Write/Edit, it runs in the same project directory, sees the same `current-phase.json`, and gets gated by the same scripts. The exemption is for *spawning*, not for the sub-agent's *writes*.

The contract gate's purpose is scope drift prevention: "don't write source code without a contract defining what you're building." It has nothing to do with verification. Exempting Agent from the contract gate means "you can spawn helpers even without a contract" — those helpers still can't write source code (they hit the same contract gate on their own Write/Edit calls).

```
Parent agent in BUILD (no contract):
  |
  +-- tries Write(src/app.js)     --> BLOCKED by contract gate (line 96)
  +-- tries Edit(src/app.js)      --> BLOCKED by contract gate (line 96)
  +-- tries Agent("verify X")     --> ALLOWED by contract gate (line 85)
       |
       Sub-agent starts:
         +-- tries Write(src/app.js) --> BLOCKED by contract gate (line 96)
         +-- tries Read(src/app.js)  --> ALLOWED (reads are never gated)
```

The chain of enforcement is preserved at every level.

---

## How the Deadlock Flow Works After the Fix

```
Agent finishes sprint 3 → phase is COMPLETE
Agent receives new task → changes phase to BUILD sprint 4
    |
    v
Agent tries to write sprint-4-proposal.md
    |
    v
pre-flight-gate.sh: phase-feedback.md has FAIL?
    → Yes, but target is .claude/contracts/ → EXEMPT → exit 0     [FIX 1]
    |
    v
pre-write-gate.sh: BUILD, no contract for sprint 4?
    → Yes, but target is .claude/contracts/ → EXEMPT → exit 0     [existing]
    |
    v
Contract written. Agent writes sprint-4-contract.md same way.
    |
    v
Agent resumes BUILD with contract → all gates pass normally.
```

Alternative flow if the agent needs to spawn a verifier first:
```
Agent tries to spawn verification sub-agent
    |
    v
pre-write-gate.sh: BUILD, no contract, tool is Agent?
    → EXEMPT → exit 0                                             [FIX 2]
    |
    v
Sub-agent verifies, clears phase-feedback.
Agent writes contract. Proceeds normally.
```

---

## The Underlying Design Principle

**Infrastructure paths must always be writable.** The purpose of every gate in the harness is to control *source code* writes — the files that make up the user's product. Infrastructure paths (`.claude/state/`, `.claude/contracts/`, `.claude/specs/`, `.openclaw/watchers/`, `.agent-memory/`, `.claude/pre-flight/`, `agentwiki/`) are the agent's own operational state. Blocking them creates catch-22 deadlocks where the agent cannot perform the administrative actions needed to clear a block.

Every gate should ask: "Is this a source code write?" If no, allow. The exemption lists across all three gates should be consistent — the same set of infrastructure paths, everywhere.

### Exemption consistency after fix

| Path pattern | pre-write-gate (phase) | pre-write-gate (contract) | pre-flight-gate (feedback) | pre-bash-gate (bootstrap) |
|-------------|----------------------|--------------------------|--------------------------|--------------------------|
| `.claude/state/` | Yes | Yes | Yes | Yes |
| `.openclaw/watchers/` | Yes | Yes | Yes | Yes |
| `.claude/contracts/` | Yes | Yes | **Yes** (added) | **Yes** (added) |
| `.claude/specs/` | Yes | Yes | **Yes** (added) | **Yes** (added) |
| `.claude/pre-flight/` | Yes | Yes | **Yes** (added) | Yes |
| `.agent-memory/` | Yes | Yes | **Yes** (added) | Yes |
| `agentwiki/` | Yes | Yes | **Yes** (added) | Yes |

The fix brought two lagging gates into alignment with the exemptions already present in the others.

---

## Conditions That Trigger This Deadlock

All three must be true simultaneously:
1. `phase-feedback.md` exists and contains "FAIL" (stale from a previous sprint)
2. Agent has transitioned to BUILD for a new sprint (no contract yet)
3. Agent has not waited 2+ hours (the stale feedback auto-clear threshold in `startup-recovery.sh`)

This is most likely to happen when:
- An agent finishes a sprint, gets verified, moves to COMPLETE
- Receives a follow-up task immediately (within the same session)
- The phase-feedback from the previous sprint's evaluation was not cleaned up

The stale feedback auto-clear (2-hour threshold) would eventually resolve it, but forcing an agent to wait 2 hours for a one-line fix is not acceptable.

---

## Files Modified

| File | Lines changed | What changed |
|------|--------------|-------------|
| `~/.claude/hooks/pre-flight-gate.sh` | 28-34 | Expanded phase-feedback FAIL exemptions from 2 paths to 7, refactored to loop |
| `~/.claude/hooks/pre-write-gate.sh` | 82-85 | Added Agent tool exemption to contract gate (3 new lines) |
| `~/.claude/hooks/pre-bash-gate.sh` | 70-71 | Added `.claude/contracts/` and `.claude/specs/` to bootstrap exemptions (2 new lines) |

**Total**: 8 lines added, 4 lines removed. No new files. No behavioral change for source code enforcement.

## Verification

An independent sub-agent verified all 5 contract criteria:

1. **Phase-feedback exemptions complete** — all 7 infrastructure paths present in the loop (PASS)
2. **Agent exempt from contract gate** — explicit check on tool_name == "Agent", exits 0 (PASS)
3. **Bash bootstrap exemptions complete** — `.claude/contracts/` and `.claude/specs/` added (PASS)
4. **No regression: source code still blocked** — non-exempt paths still hit exit 2 when FAIL active (PASS)
5. **No regression: contract gate still enforces Write/Edit** — only Agent exempt, Write/Edit still blocked (PASS)
