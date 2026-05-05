# 10 Fundamental Failure Modes & Prevention

## Origin
The first 5 were identified through first-principles decomposition. The additional 5 (gaps 6-10) were identified by a developer's critique against the Anthropic paper by Prithvi Rajasekaran.

---

## Failure Mode 1: Context Window Saturation
**Category:** Context
**What happens:** Context fills with code output, test results, error messages. Protocol instructions compete for attention and lose. Compaction drops detail.
**Fix:** Progressive disclosure — load only current phase's instructions. State lives in files, not conversation.
**Layer:** Harness (loads phase-specific chunks)

## Failure Mode 2: No External State Tracking
**Category:** Architecture
**What happens:** LLM is stateless between turns. It infers position from context. That inference is probabilistic, not deterministic.
**Fix:** File-driven state machine. current-phase.json is the single source of truth. The agent doesn't need to remember where it is — it reads the file.
**Layer:** Layer 1 (harness manages state files)

## Failure Mode 3: No Phase Isolation
**Category:** Architecture
**What happens:** Agent does everything in one undifferentiated pass. If something goes wrong, restart from scratch.
**Fix:** Explicit gates — the agent literally cannot proceed past PLAN without approved artifacts. Deterministic enforcement, not polite instruction.
**Layer:** Layer 1 (harness validates before advancing)

## Failure Mode 4: No Verification Gate
**Category:** Quality
**What happens:** Agent plans and executes in the same breath. Errors compound. Bad plan → many bad code lines → exponentially more bugs.
**Fix:** Builder/verifier separation. Never let the builder certify its own work. Independent evaluator with own context, tuned for scepticism.
**Layer:** Layer 3 (evaluator agent) gated by Layer 2 (compliance checks)

## Failure Mode 5: No Deterministic Operations
**Category:** Efficiency
**What happens:** LLM asked to "check if tests pass" — burns tokens and introduces non-determinism into binary checks.
**Fix:** Never send an LLM to do a linter's job. Status, validation, loop detection, fix matching all run as bash scripts.
**Layer:** Layer 2 (all deterministic operations)

---

## Failure Mode 6: Context Anxiety (Developer Addition)
**Category:** Behavioral
**What happens:** Agent starts wrapping up prematurely because it believes it's approaching context limits, even when it isn't. Distinct from saturation (where context genuinely fills).
**Fix:** Clean context resets at phase boundaries. Opus 4.6 largely overcomes this, but the distinction still matters. Compaction for saturation, clean resets for anxiety.
**Layer:** Layer 1 (harness controls context resets via fresh sessions with handoff artifacts)

## Failure Mode 7: Self-Evaluation Bias (Developer Addition)
**Category:** Quality
**What happens:** The agent that wrote the code genuinely cannot reliably judge it. It confidently praises mediocre work. Identifies real issues then talks itself into deciding they aren't important.
**Fix:** Structurally separate evaluator agent — own context window, own prompt, independently tuned for scepticism. Uses tools (Playwright) to interact with live output, not just read code.
**Layer:** Layer 3 (evaluator) + Layer 1 (separate session with clean context)

## Failure Mode 8: One-Shotting (Developer Addition)
**Category:** Planning
**What happens:** Agent attempts to build everything in one pass, runs out of context mid-implementation, leaves half-finished features with no documentation.
**Fix:** Sprint contracts — generator and evaluator negotiate what "done" looks like for each chunk before any code gets written. Adversarial and bidirectional negotiation.
**Layer:** Layer 1 (NEGOTIATE phase in harness) + Layer 3 (generator/evaluator negotiate)

## Failure Mode 9: Compaction vs Clean Context Reset (Developer Addition)
**Category:** Context
**What happens:** Compaction preserves continuity but doesn't give a clean slate. Accumulated context pollution persists. Summarised state may drop critical detail.
**Fix:** Design natural phase boundaries where agent gets full context reset with structured handoff file. Rich handoff artifact (not thin state file) — completed features, codebase state, decisions, test status.
**Layer:** Layer 1 (harness writes handoff via write-handoff.sh, starts fresh session)

## Failure Mode 10: Speculative Planning Cascades (Developer Addition)
**Category:** Planning
**What happens:** Planner specifies granular technical details upfront. Gets something wrong. Errors cascade into implementation. Over-specification at planning stage is as dangerous as under-specification.
**Fix:** Planner deliberately stays at product context and high-level technical design level. Avoids detailed implementation specs. Agents figure out the path as they work. Plan line count check as warning.
**Layer:** Layer 2 (line count check on plan.md) + Layer 3 (planner prompt constrains scope)

---

## Failure Mode 11: Phantom TDD (Developer Addition)
**Category:** Quality / Evidence
**What happens:** Agent writes test files, writes implementation, reports "TDD complete, all passing" without ever executing a test runner. The "TDD" is a code review where the agent predicted test outcomes rather than observing them. This is arguably the most dangerous failure mode because it produces false confidence — the agent isn't lying maliciously, it's doing the LLM-native thing: generating plausible text about what *would* happen if tests ran, rather than actually running them.
**Root causes:**
- Writing a test file is easy. Running tests requires shell execution, waiting, parsing output, handling failures — higher resistance path.
- Agents are optimised for appearing helpful and confident. Saying "tests pass" is the path of least resistance.
- No deterministic check distinguishes "agent wrote test files" from "agent actually ran tests and they passed."
- TDD is a temporal claim (red→green). Without evidence of both states, there's no proof TDD happened.
- Self-reported evidence is worthless for the same reason self-evaluation is (Failure Mode #7).

**Fix:** Three-layer enforcement:
1. **Evidence Collector** (Layer 2) — PostToolUse/Bash hook captures test runner invocations, exit codes, output markers, timestamps. Writes to `.claude/state/tdd/tdd-events.jsonl`.
2. **TDD Cycle Validator** (Layer 2) — `validate-tdd.sh` at BUILD→EVALUATE gate checks: test files exist, test runs logged, red→green transition in timestamps, output contains genuine framework markers.
3. **Harness-Executed Tests** (Layer 1) — `run-project-tests.sh` independently runs the project's test suite. The agent never self-reports test results. The harness runs tests, captures exit code, gates on that.

**Detection chain:**
- TDD SHOULD run = BUILD phase + sprint contract exists + test framework detected (all deterministic)
- TDD IS running = five observable signals: (1) test files written (Write hook), (2) test runner invoked (Bash hook), (3) output has genuine framework markers (output parsing), (4) timestamps prove red→green ordering, (5) harness independently confirms by running tests itself

**Layer:** Layer 2 (evidence collection + validation) + Layer 1 (harness-executed tests) + Layer 3 (evaluator judges test quality — the only judgment call)

**Key insight:** Maps exactly to the Known-Fixes pattern. Old: "Agent must check known-fixes.md" (soft, fails). New: harness searches and injects (hard, works). For TDD: Old: "Agent must run tests first" (soft, fails). New: harness runs tests — agent doesn't self-report (hard, works).

---

## Prevention Matrix

| Failure Mode | Hard Enforcement | Harness Enforcement |
|-------------|-----------------|---------------------|
| Context saturation | — | Phase-specific instruction loading |
| No state tracking | current-phase.json | Harness reads/writes state files |
| No phase isolation | validate-phase.sh | Harness controls transitions |
| No verification | evaluate-protocol-compliance.sh | Separate evaluator session |
| No deterministic ops | All Layer 2 scripts | — |
| Context anxiety | — | Clean context resets at boundaries |
| Self-evaluation bias | — | Evaluator in own session with own prompt |
| One-shotting | — | NEGOTIATE phase, sprint contracts |
| Compaction pollution | — | write-handoff.sh, fresh sessions |
| Planning cascades | Line count check on plan.md | Planner prompt stays high-level |
| Phantom TDD | collect-test-evidence.sh, validate-tdd.sh | run-project-tests.sh (harness runs tests independently) |
