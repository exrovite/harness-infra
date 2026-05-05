# Three-Layer Architecture

## Origin
This architecture emerged from the "Harness Big Idea" conversation, where a developer iteratively pushed back on soft enforcement until the three-layer model crystallised. The key insight: **the word MUST in a markdown file has zero binding force on an LLM. A bash script that checks exit codes does.**

---

## Layer 1 — The Harness (Deterministic, Outside the LLM)

**What it does:**
- Controls session lifecycle: start, stop, restart, context reset
- Manages phase transitions via hooks and validation scripts
- Decides what the agent sees (loads `active-instructions.md`)
- Blocks progression when validation fails
- Handles notification/communication (Telegram/WhatsApp — optional)
- Runs the Ralph-style outer loop (`run-harness.sh`)
- Budget/time circuit breaker
- Crash recovery and startup routine
- Concurrency protection (lockfile)
- Git auto-commit at phase boundaries

**Key principle:** The agent NEVER decides phase transitions. The agent writes a marker. The harness validates. The harness advances (or doesn't).

**Scripts (11):** run-harness, run-claude-safe, startup-recovery, telegram-poll, wait-for-human, notify, write-handoff, check-budget, git-checkpoint, ensure-dev-server, init-project

**Hooks (3):** post-write-check (scoped to Write/Edit), pre-phase-start, on-stuck-detected

---

## Layer 2 — Deterministic Guards (Bash Scripts, No LLM)

**What it does:**
- Phase validation: file existence, required sections (grep), line counts
- Negative loop detection: git history analysis, repeating test failures
- Known-fix matching: symptom grep against registry, auto-injection
- Test execution: test suite, linting, type checking
- Protocol compliance: all binary pass/fail checks
- Fix verification: structured checks (file_exists, file_contains, test_passes) — NO eval

**Key principle:** Every check is deterministic. File exists or doesn't. Grep matches or doesn't. Test passes or doesn't. Exit code 0 or 1. No LLM judgment needed.

**Scripts (4):** detect-loop, validate-phase, evaluate-protocol-compliance, verify-fix-applied

**Note:** `validate.sh` is a project-specific test runner created per-project (not a harness infrastructure script). It is referenced in workflows but not registered in SCRIPT_REGISTRY.json.

---

## Layer 3 — The Agents (LLM, Within Constraints)

**What it does:**
- Planner: expands brief into high-level product spec
- Generator: implements features, writes code, follows TDD
- Evaluator: judges quality, usability, architecture using tools (Playwright, curl)
- Cross-examiner: Layer 6 doubt protocol

**Key principle:** Only genuine judgment calls belong here. Everything else belongs in Layer 1 or 2.

---

## The Rule

```
Never use Layer 3 for something Layer 2 can do.
Never use Layer 2 for something Layer 1 should control.
```

### Decision Tree

When you need to add a new check or control:

1. **Can a bash script check this?** (file exists? grep matches? exit code?) → Layer 2
2. **Does it control session flow?** (start/stop? what agent sees? phase transitions?) → Layer 1
3. **Does it require genuine judgment?** (is this code good? does the UX make sense?) → Layer 3

### Examples

| Check | WRONG Layer | RIGHT Layer | Why |
|-------|------------|-------------|-----|
| "Does the plan file exist?" | Layer 3 (ask LLM) | Layer 2 (`[ -f plan.md ]`) | Binary check |
| "Are tests passing?" | Layer 3 (ask LLM) | Layer 2 (`pytest; echo $?`) | Deterministic |
| "Is the agent stuck in a loop?" | Layer 3 (ask LLM) | Layer 2 (git history analysis) | Pattern matching |
| "Load the next phase's instructions" | Layer 3 (agent reads) | Layer 1 (harness loads) | Session control |
| "Should we advance to the next phase?" | Layer 3 (agent decides) | Layer 1 (harness validates) | Transition control |
| "Is this architecture sound?" | Layer 2 (grep check) | Layer 3 (evaluator judgment) | Genuine judgment |
| "Does the UX make sense?" | Layer 2 (file check) | Layer 3 (evaluator + Playwright) | Genuine judgment |

---

## Global vs Per-Project Split

### Global (`~/.claude/`) — Built Once
All Layer 1 and Layer 2 scripts. Agent definitions. Hook configurations. Apply to every project.

### Per-Project (`project/.claude/`) — Created by init-project.sh
State files, specs, contracts, known-fixes. Project-specific.

### Memory-Equipped (`project/.agent-memory/`)
For agents with full memory systems. operating-procedure.md contains the enhanced harness. Replaces the thinner `.claude/state/` tracking.
