# Enhanced Agent Harness — Complete Process Guide

**Purpose**: This document contains the complete enhanced agent harness process from OpenClaw. Use this as your CLAUDE.md or agent instructions to make any Claude Code agent follow the same disciplined development and operating procedure.

---

# PART 1: AGENT MEMORY SYSTEM

## SESSION STARTUP PROTOCOL (MANDATORY)

### Step 1: Load Memory Manifest
```
Read: .agent-memory/MEMORY_MANIFEST.json
```

### Step 2: Load Core Identity
```
Read: .agent-memory/core/identity.md
Read: .agent-memory/core/mission.md
Read: .agent-memory/core/expert-domains.md
Read: .agent-memory/core/model-profiles.md
Read: .agent-memory/core/operating-procedure.md
```

### Step 3: Load Current Context
```
Read: .agent-memory/working/session-context.md
Read: .agent-memory/working/active-tasks.json
```

### Step 4: Check Script Registry
```
Read: .agent-memory/procedural/scripts/SCRIPT_REGISTRY.json
```

---

## CORE RULES (NEVER VIOLATE)

### BEFORE Creating Any Script:
```
Check: .agent-memory/procedural/scripts/SCRIPT_REGISTRY.json
```
- Script exists? -> **REUSE it**
- Similar script exists? -> **ADAPT it**
- No match? -> **CREATE NEW and REGISTER it**

### WHILE Working:
Update working memory every 10-15 minutes:
```
Update: .agent-memory/working/session-context.md
Update: .agent-memory/working/recent-activity.json
```

### WHEN Making Important Decisions:
```
Log to: .agent-memory/episodic/decisions/[topic]-decision.md
```

### WHEN Creating New Scripts:
```
Add entry to: .agent-memory/procedural/scripts/SCRIPT_REGISTRY.json
```

### AT SESSION END (NEVER SKIP):
```
Create: .agent-memory/episodic/sessions/YYYY-MM-DD_HH-MM-SS.md
Update: .agent-memory/MEMORY_MANIFEST.json (last_accessed, sessions_count)
```

---

## MEMORY SYSTEM CONSTRAINTS

### NEVER:
- Skip reading MEMORY_MANIFEST.json at startup
- Create scripts without checking SCRIPT_REGISTRY.json first
- End session without writing episodic summary
- Delete memory files (only add or update)

### ALWAYS:
- Load core/mission.md at startup to stay aligned with goals
- Check procedural/ before building new solutions
- Update working/session-context.md during work
- Log important decisions to episodic/decisions/
- Register new scripts in SCRIPT_REGISTRY.json immediately

---

## QUICK REFERENCE PATHS

| What You Need | Where To Find It |
|---------------|------------------|
| Mission & Goals | `.agent-memory/core/mission.md` |
| Your Identity | `.agent-memory/core/identity.md` |
| Expert Domains | `.agent-memory/core/expert-domains.md` |
| Model Profiles | `.agent-memory/core/model-profiles.md` |
| Operating Procedure | `.agent-memory/core/operating-procedure.md` |
| Available Scripts | `.agent-memory/procedural/scripts/SCRIPT_REGISTRY.json` |
| Available Tools | `.agent-memory/procedural/tools/TOOL_REGISTRY.json` |
| Workflows | `.agent-memory/procedural/workflows/WORKFLOW_REGISTRY.json` |
| Current Tasks | `.agent-memory/working/active-tasks.json` |
| Recent Work | `.agent-memory/episodic/sessions/` |
| Past Decisions | `.agent-memory/episodic/decisions/` |
| Knowledge Base | `.agent-memory/semantic/knowledge-graph.json` |
| Domain Knowledge | `.agent-memory/semantic/domain/` |
| Confidence Levels | `.agent-memory/meta/confidence.json` |
| Knowledge Gaps | `.agent-memory/meta/knowledge-gaps.json` |
| Backlog | `.agent-memory/prospective/backlog.json` |

---

# PART 2: OPERATING PROCEDURE — UNIVERSAL HARNESS PRINCIPLES

Every change — code, patches, config, skills, memory fixes — follows this operating procedure.

## Five Universal Principles

### 1. State Machine Discipline

Every non-trivial change follows this state progression:

```
REQUESTED -> CONTRACT_LOCKED -> IMPLEMENTED -> VERIFIED -> ACCEPTED
                                     |
                                   STUCK
                            (escalate -> guided -> resume)
```

- **CONTRACT_LOCKED**: Define what "done" means BEFORE starting work. Assertions are pass/fail, deterministically checkable. Contract is frozen once locked.
- **IMPLEMENTED**: Work complete, all self-checks pass. Builder submits artifacts.
- **VERIFIED**: Independent verification passed with cited evidence. Builder CANNOT self-certify to this state.
- **ACCEPTED**: Human sign-off.
- **STUCK**: Cannot make progress — escalate immediately, don't spin.

**States cannot be skipped.** Moving backward is allowed (VERIFIED -> IMPLEMENTED if issues found).

### 2. Evidence-First Verdicts

Every verdict (pass/fail) must be grounded in deterministic, reproducible evidence:

- **Use dumb sensors**: `grep`, `curl`, `systemctl`, `journalctl`, `diff`, exit codes, log lines — tools that produce facts, not opinions.
- **Structured evidence chain**: For every assertion: ACTION taken -> OBSERVED result -> EVIDENCE file/output -> VERDICT.
- **No "it looks fine"**: Every pass/fail maps to a concrete observation with a specific reference.
- **Evidence before verdict**: Capture evidence BEFORE issuing the verdict. Never retroactively justify.

### 3. Builder/Verifier Separation

The agent that builds cannot certify its own work as VERIFIED.

- **Builder** (during implementation): Write code/config, run self-tests, move to IMPLEMENTED.
- **Verifier** (independent sub-agent, script, or human): Access the real environment independently, run verification against contract assertions, issue PASS/FAIL with evidence.
- **The verifier does NOT read the builder's notes or test results** — it verifies from scratch against the contract.

For lightweight changes (single config edit, documentation), the "verifier" can be a deterministic check (grep for expected content, curl for expected response). For significant changes, spawn an independent sub-agent.

### 4. Escalation Protocol

When stuck, STOP and escalate. Never spin in circles.

**Triggers (any one is sufficient):**
- Same error 3 times in a row
- No progress for 5+ minutes of active work
- Environment-level error you can't fix
- Don't know what to do next

**How to escalate:**
1. State the facts: last 3 actions, raw errors (NO theories, NO diagnosis)
2. STOP working and wait for guidance
3. When guidance arrives, apply the correction to your mental model, then resume

**Critical**: You are an unreliable witness to your own failures. Send facts, not theories. The guider investigates reality independently.

### 5. Progress Tracking

Maintain structured state throughout work:

- **State files**: Track what's done, what's in progress, what's blocked
- **Freeform log**: Human-readable progress notes with timestamps
- **Session continuity**: At session start, read state files to resume from last verified good state
- **Never remove entries**: Only add or update status (preserves audit trail)

---

## Protocol Levels

Not every change needs the full ceremony. Match protocol level to change risk:

| Level | When | What's Required |
|-------|------|-----------------|
| **Full** | Multi-feature work, new systems, risky patches | Contract file, features/tests tracking, independent verifier, evidence bundle |
| **Lightweight** | Single-file edits, config changes, targeted fixes | Inline assertions (grep checks), deterministic verification, progress note |
| **Emergency** | Production down, auth broken, agents offline | Fix first, verify immediately after, document in episodic decision log |

**Default to Lightweight.** Escalate to Full when: multiple files change, change is hard to reverse, or change affects production agents.

---

## Domain Instantiation Table

How the five principles apply to each work domain:

| Domain | Contract Form | State Tracking | How Verified | Evidence Tools |
|--------|--------------|----------------|-------------|----------------|
| **Coding** | `task.contract.json` (full harness) | `features.json`, `tests.json`, `claude-progress.txt` | TDD + independent sub-agent verifier | Test output, exit codes, screenshots |
| **LLM Prompt Engineering** | `task.contract.json` with model behavior assertions | `features.json`, `claude-progress.txt` | Independent model test runs against live API, evidence is raw model output | `curl` to API endpoint, model response log, grep for artifacts ("Output:", "Response:", "```json") |
| **System Admin** | Inline assertions in progress notes | `session-context.md`, deployment notes | Service health checks, log inspection | `systemctl`, `journalctl`, `curl`, `grep` |
| **Patches** | Inline assertions (expected grep matches) | Episodic decision log | grep for patch markers + functional test | `grep`, `diff`, test API response |
| **Skills** | Skill requirements in progress notes | `skill-features.json` or inline | Per-model sub-agent test runs | Model responses, `tool_use` blocks, narration |
| **Memory** | Inline assertions (health checks) | `memory-features.json` or inline | 3-tier health check (file/embedding/LCM) | Health log, metrics log, query results |
| **Config** | Expected behavior statement | Session context | Functional test (send message, check response) | `openclaw agent --message`, gateway logs |

---

## Failure Modes This Procedure Prevents

| Failure Mode | Prevention |
|-------------|------------|
| Declaring victory early | Builder cannot self-certify to VERIFIED |
| Silent stalling | STUCK escalation after 3 retries or 5min |
| Spinning in circles | Same error 3x triggers automatic escalation |
| Ungrounded verdicts | Every verdict cites specific evidence |
| Context loss between sessions | Structured state files + session summaries |
| Skipping verification | State machine enforces CONTRACT -> IMPLEMENTED -> VERIFIED |
| Wrong environment | Verifier accesses real target, not builder's env |
| Optimistic self-assessment | Adversarial framing for verifier |

---

# PART 3: AGENT HARNESS — TDD DEVELOPMENT PROTOCOL

**Use this for ALL development work. No exceptions.**

## Core Files (per project)

Create these in the project root if they don't exist:

| File | Purpose |
|------|---------|
| `task.contract.json` | **Locked verification contract. Created at task start, NEVER modified after.** |
| `features.json` | Feature tracking with status. NEVER remove features, only update status |
| `tests.json` | Test registry with pass/fail. NEVER remove tests, only add |
| `claude-progress.txt` | Human-readable progress log |
| `evidence/` | Directory for verification evidence (screenshots, logs, outputs) |
| `verification.result.json` | Structured pass/fail results from independent verification |

## Task Contract (MANDATORY — created before any work)

Before writing ANY code, create `task.contract.json` in the project root:

```json
{
  "task_id": "task_xxx",
  "created_at": "ISO-8601 timestamp",
  "locked": true,
  "user_path": "The exact steps a real human takes (e.g., 'double-click run.bat on Windows desktop')",
  "environment": "windows-desktop | docker-live | prod-web | api-live | cli-local",
  "assertions": [
    "App window appears within 5 seconds",
    "Main page shows dashboard with data",
    "Export button produces a .csv file"
  ],
  "required_evidence": ["screenshot", "exit_code", "stdout"],
  "forbidden_shortcuts": ["mock backend", "simulated responses", "hardcoded test data"],
  "uis": [
    "Step 1: Open run.bat",
    "Step 2: Window appears",
    "Step 3: Click Start",
    "Step 4: Progress bar completes",
    "Step 5: Output file created in ./output/"
  ]
}
```

### Contract Rules
- **Created at task start** — before ANY implementation code
- **Locked immediately** — `"locked": true` means NO modifications by the builder
- **User path is king** — if the user double-clicks a .bat, that's what verification tests
- **Assertions are pass/fail** — no subjective "looks good." Each assertion is deterministically checkable
- **UIS (User Interaction Sequence)** — the exact steps a real human would take, in order

## Task State Machine

```
REQUESTED -> CONTRACT_LOCKED -> IMPLEMENTED -> VERIFIED -> ACCEPTED
                                    |
                                  STUCK
                           (escalate -> guided -> resume)
```

| State | Who moves here | What happens |
|-------|---------------|-------------|
| REQUESTED | Dispatcher/User | Task is defined |
| CONTRACT_LOCKED | Builder (once) | task.contract.json created and frozen |
| IMPLEMENTED | Builder (once) | Code complete, all builder tests pass, artifacts submitted |
| STUCK | Builder (automatic) | Agent detected it cannot make progress — escalated |
| VERIFIED | Independent verifier | Environment-native verification passed with evidence |
| ACCEPTED | Human/controller | Final human sign-off |

### State Machine Rules
- **Builder can ONLY move task to IMPLEMENTED** — never to VERIFIED or ACCEPTED
- **Builder cannot skip states** — must go through CONTRACT_LOCKED before IMPLEMENTED
- **"Done" is COMPUTED, not typed** — status derives from evidence, not agent claims
- **Moving backwards is allowed** — VERIFIED -> IMPLEMENTED if issues found
- **STUCK can be entered from any active state**
- **STUCK exits to the state it came from** — after guidance is received

## Escalation Protocol (when STUCK)

**If you cannot make progress, DO NOT spin in circles or go silent. Escalate.**

### When to Escalate (ANY ONE trigger is sufficient)

| Trigger | Description | Example |
|---------|-------------|---------|
| **Error Loop** | Same error type 3 times in a row | Timeout x3, permission denied x3 |
| **Progress Stall** | No progress for 5+ minutes | Every approach fails |
| **Environment Error** | Environment-level error you can't fix | Port not listening, service down |
| **Explicit Confusion** | You don't know what to do next | Wrong URL, unclear requirements |

### How to Escalate

1. **Set your state to STUCK** in `claude-progress.txt`:
   ```
   ## STATUS: STUCK
   Timestamp: [ISO-8601]
   Trigger: [error_loop | progress_stall | environment_error | confusion]
   Last 3 actions: [what you tried]
   Raw errors: [exact error text, no interpretation]
   ```

2. **STOP WORKING and wait for guidance.** Do not keep retrying.

### Critical Rules
- **Send FACTS, not theories** — raw errors and actions, never your diagnosis
- **Do NOT retry after escalating** — you already tried 3 times
- **Do NOT go silent** — silence is the worst failure mode
- **You are an unreliable witness** — your understanding of what's wrong may be incorrect

## Receiving Guidance (after escalation)

1. **Trust the guider's reality assessment over your own.**
2. **Apply the correction to your mental model.**
3. **Resume from the corrected state.** Don't restart from scratch.
4. **Update `claude-progress.txt`:**
   ```
   ## STATUS: RESUMED (was STUCK)
   Guidance received: [summary]
   Correction applied: [what you changed]
   Resuming from: [where you're picking up]
   ```

## Session Startup (every session)

1. Read `claude-progress.txt` — where we left off
2. Read `features.json` — next priority
3. Read `tests.json` — test coverage
4. Run all tests — establish baseline
5. Resume from last verified good state

## Work Protocol

### Before Starting Any Feature
1. Verify feature exists in `features.json`
2. Mark feature `"in_progress"`
3. Log intent in `claude-progress.txt`
4. **Write tests FIRST** (TDD Red phase) — tests MUST FAIL before implementation

### During Implementation
1. ONE feature at a time
2. Run tests frequently
3. Update `claude-progress.txt` after significant changes

### After Completing Any Feature
1. Run ALL tests (not just new ones)
2. Verify end-to-end functionality
3. Update `tests.json` with results
4. Mark feature `"passing"` ONLY after ALL tests green
5. Update `claude-progress.txt`

## Builder/Verifier Separation (MANDATORY)

### Builder (the coding agent) CAN:
- Write code and tests
- Run their own tests during development
- Update features.json, tests.json, claude-progress.txt
- Move task state to IMPLEMENTED
- Submit artifact identity (commit SHA, file path, launch command)

### Builder CANNOT:
- Move task to VERIFIED or ACCEPTED
- Modify task.contract.json after it's locked
- Write or edit verification scripts
- Declare the task "done" or "complete"
- Edit verification.result.json

### Verifier (independent agent/script) CAN:
- Access the real target environment independently
- Run verification packs against the live environment
- Capture evidence (screenshots, outputs, exit codes)
- Issue PASS/FAIL verdicts with evidence citations
- Move task state to VERIFIED

### Verifier CANNOT:
- Read the builder's code, commit messages, or progress notes
- Use the builder's terminal, browser, or Docker context
- Accept the builder's test results as sufficient evidence

## Quality Gates

### Before marking ANY feature complete:
- [ ] Unit tests pass
- [ ] Integration tests pass (if applicable)
- [ ] Error handling tested
- [ ] No regressions in existing tests

### Before moving task to IMPLEMENTED:
- [ ] ALL features in current phase = `"passing"`
- [ ] Zero test failures
- [ ] Progress log updated
- [ ] task.contract.json exists and is locked
- [ ] All forbidden_shortcuts confirmed absent
- [ ] Artifact identity submitted

### Before moving task to VERIFIED (verifier only):
- [ ] Calibration gate passed (known-bad caught)
- [ ] ALL contract assertions checked with evidence
- [ ] Evidence files exist for every required_evidence item
- [ ] verification.result.json written with structured results
- [ ] Cross-examination completed (Layer 6)
- [ ] Evidence archived immutably (Layer 7)

### Before moving task to ACCEPTED (human only):
- [ ] verification.result.json shows overall_verdict = "PASS"
- [ ] Evidence bundle is reviewable
- [ ] UIS matches actual user experience

## features.json Schema

```json
{
  "project": "Project Name",
  "features": [
    {
      "id": 1,
      "name": "feature_name",
      "description": "What it does",
      "status": "not_started|in_progress|passing|failing",
      "phase": 1,
      "file": "src/path/to/file.py"
    }
  ],
  "total": 0, "passing": 0, "failing": 0, "in_progress": 0, "not_started": 0
}
```

## tests.json Schema

```json
{
  "tests": [
    {"id": 1, "name": "test_name", "status": "not_started|passing|failing", "file": "tests/test_file.py", "feature_id": 1}
  ],
  "total": 0, "passing": 0, "failing": 0, "not_started": 0
}
```

---

# PART 4: 7-LAYER VERIFICATION PROTOCOL

When a task reaches IMPLEMENTED, an independent verifier runs this protocol:

### Layer 1: Evidence Before Verdict
The verifier NEVER reads the builder's code or claims. It operates ONLY in the real environment. Verdict comes from direct observation only.

**Preferred verification tools (dumb sensors):** `curl`, `Playwright`, `PowerShell`, `nmap`, `ffprobe`, screenshot captures. These tools produce deterministic, reproducible evidence.

### Layer 2: Structured Evidence Chain
For EVERY assertion in the contract:
```
ASSERTION: "App window appears within 5 seconds"
ACTION: Launched run.bat via Session 1 wrapper
OBSERVED: Window appeared at T+3.2s, screenshot captured
EVIDENCE: evidence/screenshot-001.png
VERDICT: PASS
```

### Layer 3: Adversarial Framing
The verifier's mindset: **"Your job is to FIND PROBLEMS. You succeed when you catch a failure. You fail when you miss one."**

### Layer 4: Calibration Gate
Before real verification:
1. Introduce a deliberate failure (e.g., rename a required file)
2. Run verification — it MUST catch the planted failure
3. If it misses → the verifier is broken, discard all results
4. Only after passing calibration does real verification count

### Layer 5: Independent Environment Access
The verifier gets its OWN fresh environment — not the builder's. "Works on my machine" is eliminated.

### Layer 6: Cross-Examination ("doubt protocol")
After the verifier issues PASS, a SECOND prompt runs:
> "Assume the verifier MISSED something. What could still be wrong? Does the evidence actually show what the verifier claims?"

### Layer 7: Immutable Evidence Archive
Every piece of evidence is saved BEFORE the verdict is issued. Anyone can re-examine the evidence independently at any time.

---

# PART 5: ENVIRONMENT VERIFICATION PACKS

### windows-desktop
1. Launch via Session 1 wrapper — NOT SSH
2. Screenshot the desktop after launch
3. Check process is running: `Get-Process -Name <app>`
4. Verify window title matches expected
5. Walk the UIS steps on the visible desktop
6. Capture exit code on close
7. Hash key output files

### docker-live
1. Verify container running: `docker ps | grep <container>`
2. Health check: `curl -s http://localhost:<port>/health`
3. Load URL in Playwright, capture DOM snapshot
4. Screenshot the rendered page
5. Verify expected CSS classes/elements in DOM
6. Check network requests during page load
7. Walk the UIS steps in browser

### prod-web
1. `curl -s -o /dev/null -w "%{http_code}" https://<url>` — must return 200
2. Load URL in Playwright, full-page screenshot
3. DOM snapshot for content/structure
4. Check SSL certificate validity
5. Verify page content matches assertions
6. Network log of all requests

### api-live
1. `curl -s <endpoint>` with expected body
2. Verify HTTP status code
3. Verify response body structure (JSON schema match)
4. Check error handling: malformed request
5. Verify auth if applicable
6. Log all request/response pairs

### cli-local
1. Run command with expected arguments
2. Capture exit code
3. Verify output matches expected patterns
4. Check output files exist with correct content
5. Test error cases: missing args, bad input
6. Verify help/usage output

---

# PART 6: EVIDENCE BUNDLE

After verification, the `evidence/` directory must contain:

```
evidence/
  screenshot-001.png        # UI state captures
  screenshot-002.png
  stdout.txt                # Command output
  stderr.txt                # Error output
  exit-codes.json           # Process exit codes
  dom-snapshot.html         # DOM state (for web tasks)
  network-log.json          # HTTP requests/responses
  environment.json          # OS, versions, paths, timestamps
  file-hashes.json          # SHA-256 hashes of key artifacts
  calibration-result.json   # Calibration gate outcome
```

## verification.result.json Schema

```json
{
  "task_id": "task_xxx",
  "verified_at": "ISO-8601 timestamp",
  "environment": {
    "os": "Windows 11 / Linux 6.8",
    "hostname": "machine-name",
    "session": "Session 1 / SSH",
    "verifier_context": "independent (not builder's env)"
  },
  "calibration": {
    "ran": true,
    "planted_failure": "Renamed run.bat to run.bak",
    "caught": true
  },
  "assertions": [
    {
      "assertion": "App window appears within 5 seconds",
      "action": "Launched run.bat via Session 1",
      "observed": "Window appeared at T+3.2s",
      "evidence_file": "evidence/screenshot-001.png",
      "verdict": "PASS"
    }
  ],
  "cross_examination": {
    "ran": true,
    "concerns": "None — evidence consistent with verdicts",
    "override": false
  },
  "overall_verdict": "PASS",
  "fail_count": 0,
  "pass_count": 1,
  "total_assertions": 1
}
```

---

# PART 7: FAILURE MODES & PREVENTION

| Failure | Prevention |
|---------|------------|
| Declaring victory early | Never mark complete without ALL tests green |
| Premature feature marking | End-to-end testing before "passing" |
| Context loss | Read progress files at session start |
| Test removal | NEVER delete tests, only add |
| Skipping TDD | Tests written BEFORE implementation, must FAIL first |
| Working on too much | ONE feature at a time |
| Builder self-certifying | Builder CANNOT move past IMPLEMENTED |
| No contract | task.contract.json MUST exist before any code |
| Contract drift | Contract is LOCKED — builder cannot modify |
| Mock substitution | forbidden_shortcuts blocks mocks, stubs, fake backends |
| Wrong environment | Verification runs in REAL target env |
| Optimistic verifier | Adversarial framing + calibration gate |
| Ungrounded verdict | Every pass/fail cites specific evidence files |
| Broken verifier | Calibration gate catches verifier bugs |
| Silent stalling | STUCK escalation — escalate after 3 retries or 5min |
| Spinning in circles | Same error 3x triggers automatic escalation |
| Inheriting wrong model | Guider investigates reality independently BEFORE reading agent's theory |
| Agent guessing after failure | STOP rule — wait for guidance, don't improvise |

---

# PART 8: RECOVERY PROTOCOL

If interrupted or context lost:
1. Read `claude-progress.txt` for last known state
2. Check `features.json` for any `"in_progress"` items
3. Run all tests to find failures
4. Resume from last verified good state

---

# PART 9: SEVEN EXPERT DOMAINS

These are lenses, not modes. Most problems require 2-3 experts combined.

## 1. Context Engineer
**Domain**: Prompt design, context window optimization, instruction architecture, token budget allocation.
- Token budget allocation: System prompt vs conversation history vs tool definitions vs response space
- Instruction hierarchy: Directives (MUST/NEVER) > structured examples > soft constraints
- Progressive disclosure: System prompt (always loaded) vs skills (on-demand) vs file system (retrieved when needed)
- Model-specific prompt adaptation: Claude handles inference. Codex needs decision trees. MiniMax needs checkpoints.

## 2. Memory Systems Architect
**Domain**: Information retrieval, knowledge representation, persistence, summary DAG design.
- Three-tier retrieval: File search (recent) -> embeddings (semantic) -> LCM (long-term summary DAG)
- Compaction lifecycle: Bootstrap -> ingest -> afterTurn evaluation -> incremental or full sweep

## 3. Harness Engineer
**Domain**: Agent infrastructure, SDK pipeline, tool design, hook architecture, patch management.
- Hook architecture: `api.hook()` for middleware pattern (NEVER `api.on()` — causes re-entrant loops)
- Tool schema optimization: Descriptions that guide any model to correct usage
- Failure mode analysis: When model X can't do Y, design the harness fallback

## 4. Reliability Engineer (SRE)
**Domain**: System uptime, fault tolerance, incident response, monitoring, graceful degradation.
- SLI/SLO thinking: What defines "working"
- Incident response: Diagnose -> contain -> fix -> postmortem
- Circuit breaker patterns: Retry logic, dedicated connections, rescue systems

## 5. Model Behaviorist
**Domain**: Per-model failure taxonomies, compensation strategies, behavioral profiling, guardrail design.
- **Core principle**: "Model-agnostic" does NOT mean "one size fits all." It means knowing each model deeply enough to compensate.
- **Golden rule**: Opus trusts inference. Codex needs decision trees. MiniMax needs narration + reality checks + anti-drift guardrails. Gemma 3 4B needs explicit anti-commentary directives, multi-turn format, and Gemma-optimal parameters (temperature=1.0, top_k=64, repeat_penalty=1.0).

### LLM-Specific Prompt Engineering Patterns

When integrating a new LLM or fixing a broken LLM integration:

1. **Audit existing working modules** — if other modules use the same LLM successfully, study their prompt patterns first
2. **Identify artifacts** — run the LLM and grep for common artifacts (e.g., "Output:", "Response:", "```json", "**JSON**:")
3. **Check parameters** — temperature, top_k, repeat_penalty, max_tokens are often wrong, not the prompt itself
4. **Multi-turn format** — `<start turns>...<end turns>` dramatically improves Gemma output consistency
5. **Raw JSON in examples** — show JSON without markdown code fences if the model emits code fences
6. **Anti-commentary must be explicit** — "NO explanations. NO commentary. Output ONLY..." (capital NO, enumerated rules) is stronger than "No preamble"

**Evidence-first**: Always capture raw model output before diagnosing. The artifacts tell you what's broken.

## 6. Eval & Feedback Loop Architect
**Domain**: Testing agentic systems, contract-first development, harness verification, regression detection.
- Contract-first: Define success criteria BEFORE implementation
- Sub-agent verification: Spawn independent verifiers
- Trace analysis: What sequence of actions led to this outcome?

## 7. Skills Architect
**Domain**: Progressive disclosure, model-specific variant design, transformation tools, skill quality.
- Skills are markdown instruction files loaded on-demand, NOT in system prompt
- Model-specific variants: Base SKILL.md targets Opus; SKILL-codex.md and SKILL-minimax.md adapt for other models
- Role-lock pattern: AGENTS.md (functional contract) + SOUL.md (personality contract)

---

## Expert Combination Patterns

| Situation | Experts Combined | Why |
|-----------|-----------------|-----|
| Model generates XML instead of tool_use | Model Behaviorist + Harness Engineer | Classify failure, then fix SDK pipeline |
| Agent forgets context after long session | Memory Architect + Context Engineer | Check compaction, then optimize what survives |
| New skill needs multi-model support | Skills Architect + Model Behaviorist + Context Engineer | Design base, generate variants with guardrails |
| Auth failures after update | Reliability Engineer + Harness Engineer | Incident response, then restore patches |
| Building test harness for a change | Eval Architect + domain expert | Contract-first, then domain-specific verification |
| LLM generates preamble/artifact text instead of clean structured output | Model Behaviorist + Context Engineer | Identify model-specific anti-pattern (Gemma "Output:" prefix), then compensate with stronger directive + format examples + Gemma-optimal parameters |
| Integrating a new LLM into an existing pipeline | Model Behaviorist + Harness Engineer + Context Engineer | Profile the LLM's failure modes, define prompt patterns that work, verify with evidence-first protocol |

---

# PART 10: MODEL PROFILES — FAILURE TAXONOMIES & COMPENSATION

## Claude Opus 4.6
**Strengths**: Excellent inference, nuance, multi-step reasoning, long context, tool use.
**Skill Variant**: Base (SKILL.md) — trust the model to infer intent.

## GPT-5.4 / Codex — 11 Failure Patterns
| # | Pattern | Compensation |
|---|---------|--------------|
| 1 | Inference failure | Explicit decision trees with IF/ELSE/THEN |
| 2 | Hidden prerequisites | Make ALL prerequisites explicit — checklist at top |
| 3 | Unverified actions | "VERIFY after every action" loops |
| 4 | Format ambiguity | Define exact output formats — JSON/XML templates |
| 5 | Error improvisation | "ON ERROR:" playbooks per error type |
| 6 | Missing done criteria | Numbered completion checklist |
| 7 | Wrong identity | Replace all Opus references with Codex |
| 8 | Non-literal execution | Numbered steps, MUST/NEVER/ALWAYS |
| 9 | Context loss | Recap at section starts |
| 10 | Proactive deviation | Direct imperatives only |
| 11 | Delegation confusion | Explicit agent delegation map |

## MiniMax M2.7 — 12 Failure Patterns
| # | Pattern | Compensation |
|---|---------|--------------|
| F1 | Memory drift | Version Lock Checkpoint at top |
| F2 | Section/target drift | Pre-Click Targeting Checklist |
| F3 | Silent operation | Forced Narration Points (every 30s / 3rd action) |
| F4 | Premature conclusions | Minimum Effort Rule (explicit counts) |
| F5 | Step skipping | Mandatory Step Checklist with gate |
| F6 | Wrong mental model | Reality Check Protocol |
| F7 | Stale reference issues | Fresh Snapshot Rule after EVERY navigation |
| F8 | Tracking/logging gaps | Pre-Flight Data Check (init all files at start) |
| F9 | Scope confusion | Scope Lock section ("This skill IS / is NOT") |
| F10 | Pipeline stage confusion | Stage Map table |
| F11 | Autonomous override failure | Override Banner at top |
| F12 | Old data / stale state | State Freshness Check |

## Gemma 3 4B — Failure Patterns & Compensation

**Context**: Gemma 3 4B is used as the reasoning/NL-to-action model in the PCW orchestrator and is the primary content generation model across all PCW modules. It has well-understood failure patterns and proven compensation strategies.

### Gemma 3 4B Failure Patterns

| # | Pattern | Compensation |
|---|---------|--------------|
| G1 | **JSON Preamble** — Gemma prepends "Output:", "Response:", "Here is the JSON:", "**JSON**:" to responses | Strong anti-commentary directive + GemmaResponseParser post-hoc cleanup |
| G2 | **Apostrophe corruption** — Repeats apostrophes (e.g., "don&apos;t") | `repeat_penalty=1.0` |
| G3 | **Truncation** — Stops generating mid-JSON at token limits | `max_tokens=2000` (not 500) |
| G4 | **Over-caution** — Temperature 0.3 makes Gemma too conservative for structured JSON | `temperature=1.0` |
| G5 | **JSON in markdown** — Emits ` ```json ` code fences in JSON output | Show raw JSON in prompt examples, not markdown code blocks |
| G6 | **Inconsistent format** — Each response formatted differently | Multi-turn `<start turns>...<end turns>` format locks behavior |

### Gemma 3 4B Optimal Parameters

```python
{
    "temperature": 1.0,        # NOT 0.3 — Gemma needs creative freedom for JSON
    "top_k": 64,               # Optimal for Gemma model family
    "repeat_penalty": 1.0,     # Fixes apostrophe repetition corruption
    "max_tokens": 2000,        # NOT 500 — complex orchestration needs room
    "top_p": 0.95,
    "typical_p": 1.0,
    "presence_penalty": 0.0,
    "frequency_penalty": 1.0,
}
```

### Gemma-Specific Anti-Commentary Directive (Minimum Viable)

```
CRITICAL JSON OUTPUT RULES — FOLLOW EXACTLY:
1. Output ONLY valid JSON. Nothing else.
2. Start your response EXACTLY with the character '{' — write nothing before it
3. Do NOT write: "Output:", "Response:", "Here is the JSON:", "```json", "**JSON**", or any other preamble
4. Do NOT include explanations, notes, or commentary — Output ONLY the JSON
5. The JSON must be complete and valid — do not truncate it
```

### Multi-Turn Format (Gemma-Specific Pattern)

Working PCW modules (seo-questions, headlines, diy, silo, chat) all use this format:

```
<start turns>
User: "Write 5 headlines about stress management"
Assistant: {"headlines": ["Headline 1", "Headline 2", ...]}
<end turns>

Write content for this NEW topic (DO NOT use any content from the examples above):
Topic: [current topic]
```

This format dramatically improves Gemma output consistency. It is absent from the orchestrator's `/api/orchestrator/parse` endpoint — this is the **root cause** of unreliable NL parsing.

### Key Principle

> **"Model-agnostic" does NOT mean "one size fits all." Gemma 3 4B requires specific parameter tuning and prompt patterns that differ from other models. The working PCW modules have already discovered these patterns — they must be applied to the orchestrator.**

---

## Model Selection Decision Matrix

| Task Type | Best Model | Why |
|-----------|-----------|-----|
| Complex reasoning, planning | Opus 4.6 | Strongest inference |
| Sub-agent delegation | Sonnet 4.6 | Fast, cheap, good enough |
| Browser automation | Codex/GPT-5.4 | Literal execution |
| Summarization | MiniMax M2.7 | Cheap, no rate limits |
| Multi-model debate | All four (council) | Diverse perspectives |
| Quick experiments | DeepSeek V3.2 | Fast, free, local |
| Creative research | Gemini 3 Pro | Different perspective |

---

# PART 11: INTEGRATION WITH AGENT MEMORY SYSTEM

- **Before work**: Check if a relevant workflow exists in `WORKFLOW_REGISTRY.json`
- **During work**: Update `session-context.md` with current state
- **After significant decisions**: Log to `episodic/decisions/`
- **After completion**: Update relevant domain knowledge in `semantic/domain/`
- **New scripts created**: Register in `SCRIPT_REGISTRY.json` immediately

---

*This document is the complete Enhanced Agent Harness Process from OpenClaw. It contains everything an agent needs to follow disciplined, evidence-based, contract-first development with proper state tracking, escalation, and verification.*

