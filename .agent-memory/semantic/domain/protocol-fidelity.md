# Protocol Fidelity Enforcement

## The Problem: Instruction Decay Under Context Pressure

When a skill file loads (200 lines of protocol), the agent reads it with full attention. Then it starts working. Each tool call, file read, and code generation step adds to context. The 200-line protocol competes with 500 lines of code, 300 lines of test results, 150 lines of errors. The protocol is still technically in context, but the agent stops attending to it.

This is **instruction dilution** — distinct from:
- **Context saturation** (compaction drops detail)
- **Context anxiety** (agent rushes to finish)

The protocol is there. The agent just stops following it.

---

## Five Mechanisms for Protocol Fidelity

### Mechanism 1: Inline Protocol Checkpoints (Hard Enforcement)

**Old (soft — fails):**
```markdown
### CHECKPOINT 1
Before proceeding, re-read this skill file.
Answer these questions in state/checkpoint-1.md:
- What step am I on?
- What does step 2 require?
```
Problem: Agent produces plausible answers without actually re-reading.

**New (hard — works):**
The harness validates the OUTPUTS of each step, not the agent's claim about what it did:
- Did `step-1-analysis.md` get written? (`[ -f step-1-analysis.md ]`)
- Does it contain required sections? (`grep -q "## Identified Issues"`)
- Does it reference the right patterns? (structural check)

The validation script runs — not the agent's self-assessment.

---

### Mechanism 2: Negative Loop Detector (Hard Enforcement)

**What it detects:**
- Same files modified 4+ times in 10 commits (git history)
- Same test failures repeating across runs (test result analysis)

**What it does (BLOCKS, doesn't advise):**
1. If known fix exists → writes fix to `next-fix.md`, agent sees "apply this"
2. If no known fix → writes `agent-blocked.md`, notifies human, PAUSES

**Implementation:** Bash script analysing git log and test output. Exit code 1 = blocked. The agent cannot proceed while blocked — the harness checks `agent-blocked.md` at each iteration.

---

### Mechanism 3: Known-Fixes Registry (Hard Injection)

**The principle:** The agent NEVER searches known-fixes.md. The infrastructure does.

**How it works:**
1. `pre-phase-start.sh` extracts domain keywords from product spec
2. Script greps `known-fixes.md` for matching symptoms
3. Matches written to `injected-context.md`
4. Harness includes `injected-context.md` in agent's prompt
5. On test failure: `on-test-failure.sh` hook auto-searches and injects
6. If match → fix in `next-fix.md` → agent sees "apply this fix"
7. If no match → agent attempts own solution, documents for registry

**Registry format (with structured verification):**
```markdown
## FIX-002: API route ordering in FastAPI
- **Symptom**: 422 error on parameterised routes
- **Root cause**: Specific routes defined after /{param} catch-all
- **Fix**: Move specific routes ABOVE parameterised routes
- **File**: src/api/routes.py

## Verify
- type: file_contains
  file: src/api/routes.py
  pattern: "@app.get\(\"/reorder\"\)"
  before_pattern: "@app.get\(\"/{.*}\"\)"
```

**Verification uses structured format — NEVER eval:**
Three check types only: `file_exists`, `file_contains` (with optional ordering), `test_passes` (allowlisted commands)

---

### Mechanism 4: Protocol Re-Injection (Harness Enforcement)

**The principle:** Never load the full skill file. Load only the current phase's chunk.

**Structure:**
```
.claude/skills/my-workflow/
  SKILL.md              # Overview only — 20 lines max
  phases/
    phase-1-research.md    # Only research instructions
    phase-2-plan.md        # Only planning instructions
    phase-3-execute.md     # Only execution instructions
    phase-4-review.md      # Only review instructions
    phase-5-verify.md      # Only verification instructions
  references/
    known-fixes.md
    patterns.md
```

**At each phase transition:**
The harness (not the agent) copies the next phase file to `active-instructions.md`. The agent reads only that file. The newest, most salient instructions in context are always the current phase's.

---

### Mechanism 5: Evaluator Protocol Compliance Check (Split Hard + Soft)

**Layer 2 (deterministic, before evaluator loads):**
- Required files exist?
- No negative loops detected?
- Tests pass?
- Known fixes applied?
All binary. `evaluate-protocol-compliance.sh` runs first.

**Layer 3 (evaluator judgment, after compliance passes):**
- Does the code do what the contract specified?
- Does the UI make sense?
- Is the architecture sound?
Genuine judgment calls that need an LLM.

**Hard gate:** A sprint can produce working code and STILL fail evaluation because protocol compliance failed. That's intentional. Bypassing the protocol — even when output is okay — erodes reliability.

---

## How These Mechanisms Interact

```
Session Start
  ↓
[Harness loads phase instructions] — Mechanism 4
  ↓
Agent works on current phase
  ↓
Agent writes to files
  ↓
[Hook fires on Write/Edit] — checks for phase-complete-marker
  ↓
[validate-phase.sh runs] — Mechanism 1 (checks outputs, not claims)
  ↓
If FAIL → feedback injected, agent continues
If PASS → [harness advances phase]
  ↓
[pre-phase-start.sh] — Mechanism 3 (inject known fixes)
  ↓
[Next phase instructions loaded] — Mechanism 4
  ↓
During BUILD: [detect-loop.sh via hook] — Mechanism 2
  ↓
Before EVALUATE: [evaluate-protocol-compliance.sh] — Mechanism 5
  ↓
Evaluator runs (Layer 3 judgment only)
```

Every mechanism operates at Layer 1 or Layer 2. The LLM never participates in its own compliance checking.
