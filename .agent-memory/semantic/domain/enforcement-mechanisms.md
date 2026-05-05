# Enforcement Mechanisms — Hard vs Soft

## The Core Problem
Instruction decay under context pressure. When context fills up, the agent stops attending to protocol instructions because more recent, more salient information demands attention. The protocol is still in context — the agent just stops following it.

**Clinical analogy:** A trainee therapist reads a session protocol. The client says something unexpected. The trainee follows that thread. 40 minutes later, they realise they never assessed risk or reviewed homework. The protocol was in their head — they just stopped attending to it under pressure.

**The fix in clinical training is NOT "read the protocol harder."** It's structured fidelity checks — someone observing with a checklist, tapping them on the shoulder at transition points.

---

## Influences That Shaped This Architecture

These real-world workflows directly informed the harness design:

- **Boris Tane's plan-annotation workflow:** Developer annotates plan.md directly, agent reads annotations and updates plan, code only proceeds after plan approval. A concrete instance of the Plan gate pattern.
- **RIPER framework** (Research → Innovate → Plan → Execute → Review): Actually blocks the agent from writing code until it's past Research and Plan phases. Deterministic enforcement of phase isolation, not hopeful instruction.
- **Pedro Sant'Anna's academic workflow:** Agents communicate through standardised files on disk (JSON, CSV, logs) — not through hidden conversational state. Every step is inspectable and rerunnable. The direct inspiration for the file-driven state machine.
- **Anthropic's Prithvi Rajasekaran paper:** Three-agent Planner-Generator-Evaluator architecture with sprint contracts. Evaluator independently tuned for scepticism. Context resets with handoff artifacts.

---

## Soft Enforcement (Advisory — Degrades Under Pressure)

**What it is:** Instructions in markdown files that the LLM reads and (hopefully) follows.

**Characteristics:**
- Works when context is fresh
- Degrades as context fills with code output, test results, error messages
- Agent can choose to ignore under context pressure
- No feedback mechanism when skipped
- Relies on LLM attention and instruction following

**Examples:**
- "You MUST check known-fixes.md before attempting any fix"
- "ALWAYS re-read the skill file at step 3"
- "NEVER skip a phase"
- Checkpoint instructions asking agent to write compliance artifacts

**Why it fails:** The agent produces plausible compliance artifacts without actually performing the check. Writing "I checked known-fixes.md and found no matching patterns" when it never opened the file.

---

## Hard Enforcement (Deterministic — Works Regardless)

**What it is:** Bash scripts, Claude Code hooks, and harness logic running outside the LLM.

**Characteristics:**
- Binary pass/fail (exit code 0 or 1)
- Runs regardless of agent's context state
- Cannot be ignored or faked
- Provides immediate, concrete feedback
- Uses "dumb sensors": grep, curl, exit codes, file existence, git history

**Examples:**
- `[ -f .claude/state/step-1-analysis.md ]` — file exists or doesn't
- `grep -q "## Acceptance Criteria" plan.md` — section present or not
- `pytest; echo $?` — tests pass or fail
- `git log --name-only -10 | sort | uniq -c` — loop detection

**Why it works:** The agent cannot fake a grep result or an exit code. The check runs in the real environment, not in the LLM's context.

---

## Harness Enforcement (Structural — Agent Doesn't Participate)

**What it is:** The outer loop that controls what the agent sees, when sessions start/stop, and whether the agent can proceed.

**Characteristics:**
- Agent doesn't decide transitions
- Agent doesn't choose what instructions to load
- Agent doesn't control its own context
- Infrastructure decides based on Layer 2 results

**Examples:**
- Phase transitions: agent writes marker → harness validates → harness advances (or blocks)
- Instruction loading: harness copies current phase file to active-instructions.md
- Known-fix injection: harness greps registry and writes matches into agent's prompt
- Blocking: harness writes agent-blocked.md and refuses to start next iteration

---

## Translation Protocol

Every "the agent must..." in a protocol should be analysed:

| Original Instruction | Enforcement Type | Translated To |
|---------------------|-----------------|---------------|
| "Agent must check known-fixes.md" | Soft → Hard | Harness injects matching fixes into prompt |
| "Agent must re-read skill file at step 3" | Soft → Harness | Harness loads phase-3 instructions at transition |
| "Agent must not skip phases" | Soft → Harness | Harness validates before advancing |
| "Agent must follow TDD" | Soft → Hard + Harness | Three-layer: (A) Bash hook collects test execution evidence, (B) validate-tdd.sh checks red→green cycle, (C) harness independently runs tests at BUILD→EVALUATE gate |
| "Agent must stop when stuck" | Soft → Hard | Loop detector blocks after 4 repeats |
| "Agent must document decisions" | Soft (keep) | Genuine writing task — LLM appropriate |
| "Agent must plan creatively" | Soft (keep) | Genuine judgment — LLM appropriate |

---

## The Five Protocol Fidelity Mechanisms

### 1. Inline Checkpoints (upgraded from soft to hard)
- **Old (soft):** "Write your answers to checkpoint-1.md"
- **New (hard):** Harness validates outputs of each step (file exists? contains required sections?)

### 2. Negative Loop Detector (hard)
- Git history analysis + test failure patterns
- BLOCKS execution (exit 1), doesn't just advise
- Two paths: known fix injected, or agent paused for human

### 3. Known-Fixes Registry (hard injection)
- **Old (soft):** "Agent must check known-fixes.md"
- **New (hard):** pre-phase-start.sh greps registry, writes matches to injected-context.md
- On test failure: on-test-failure.sh hook auto-searches and injects

### 4. Protocol Re-Injection (harness)
- Skills broken into phase-specific chunks
- Harness loads only current phase's instructions
- Agent never sees full 200-line skill — only current 30-line chunk

### 5. Evaluator Protocol Compliance (split hard + soft)
- Layer 2 script checks deterministic compliance BEFORE evaluator loads
- Evaluator (Layer 3) judges code quality — the stuff that needs LLM judgment
- Protocol compliance is a hard gate — sprint fails regardless of code quality

### 6. TDD Execution Evidence Gate (hard + harness)
- **Old (soft — fails):** "Agent must follow TDD and run tests first"
- **New (hard — works):** Three-layer detection and enforcement:

**Layer 2 — Evidence Collection (PostToolUse/Bash hook):**
- Hook fires on every Bash tool call during BUILD phase
- Pattern-matches command against known test runners (pytest, npm test, jest, vitest, cargo test, go test, etc.)
- Captures: timestamp, command, exit code, output summary
- Parses output for genuine framework markers (pytest's `=== X passed ===`, Jest's `Tests: X passed`, etc.)
- Flags suspicious runs (no recognised framework output) 
- Writes all evidence to `.claude/state/tdd/tdd-events.jsonl`

**Layer 2 — TDD Cycle Validation (`validate-tdd.sh`):**
- Called at BUILD→EVALUATE transition by `evaluate-protocol-compliance.sh`
- Checks four things deterministically:
  1. Test files exist (file glob on `*test*`, `*spec*`, `__tests__/`)
  2. Test execution evidence exists (tdd-events.jsonl has TEST_RUN entries)
  3. Red→green transition proven by timestamps (at least one exit≠0 BEFORE final exit=0)
  4. No suspicious test runs without framework markers
- Any failure → exit 1 → back to BUILD with specific error message

**Layer 1 — Independent Test Execution (`run-project-tests.sh`):**
- Harness runs project test suite ITSELF at BUILD→EVALUATE gate
- Auto-detects test runner from project config (package.json, pytest.ini, Cargo.toml, etc.)
- Agent does not participate — exit code is the truth
- If exit ≠ 0 → failure output written to phase-feedback.md, stays in BUILD
- This is the nuclear backstop: even if all evidence is gamed, the harness runs tests independently

**Layer 3 — Test Quality (evaluator judgment):**
- "Did tests run and pass?" is Layer 2 (deterministic)
- "Are tests actually testing anything meaningful?" is Layer 3 (judgment)
- A trivial `assert True` passes Layer 2 but should fail Layer 3
- Test coverage and assertion quality are genuine LLM judgment calls

**Why it works:** The agent cannot fake an exit code. The harness runs the real tests in the real environment. Framework markers in output are generated by the framework, not the agent. Timestamps prove temporal ordering. Five independent signals, each catching a different evasion.
