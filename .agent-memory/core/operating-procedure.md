# Operating Procedure — Enhanced Agent Harness

This is the complete operating procedure. Every change — code, patches, config, skills, memory fixes — follows this procedure. The harness scripts enforce it deterministically.

---

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
- **VERIFIED**: Independent verification passed with cited evidence. Builder CANNOT self-certify.
- **ACCEPTED**: Human sign-off.
- **STUCK**: Cannot make progress — escalate immediately, don't spin.

**States cannot be skipped. The harness enforces this, not instructions.**

### 2. Evidence-First Verdicts

Every verdict must be grounded in deterministic, reproducible evidence:

- **Use dumb sensors**: `grep`, `curl`, `systemctl`, `journalctl`, `diff`, exit codes, log lines — tools that produce facts, not opinions.
- **Structured evidence chain**: For every assertion: ACTION taken -> OBSERVED result -> EVIDENCE file/output -> VERDICT.
- **No "it looks fine"**: Every pass/fail maps to a concrete observation.
- **Evidence before verdict**: Capture evidence BEFORE issuing the verdict.

### 3. Builder/Verifier Separation

The agent that builds CANNOT certify its own work as VERIFIED.

- **Builder**: Write code/tests, run self-tests, move to IMPLEMENTED.
- **Verifier**: Access real environment independently, verify against contract, issue PASS/FAIL with evidence.
- **The verifier does NOT read the builder's notes or test results** — it verifies from scratch.

### 4. Escalation Protocol

When stuck, STOP and escalate. Never spin in circles.

**Triggers (any one sufficient):**
- Same error 3 times in a row
- No progress for 5+ minutes
- Environment-level error you can't fix
- Don't know what to do next

**How to escalate:**
1. State the facts: last 3 actions, raw errors (NO theories, NO diagnosis)
2. STOP working and wait for guidance
3. When guidance arrives, apply correction to mental model, then resume

**Critical: You are an unreliable witness to your own failures. Send facts, not theories.**

### 5. Progress Tracking

- **State files**: Track what's done, in progress, blocked
- **Freeform log**: Human-readable progress notes with timestamps
- **Session continuity**: Read state files at session start, resume from last verified good state
- **Never remove entries**: Only add or update (preserves audit trail)

---

## Protocol Levels

Not every change needs full ceremony. Match protocol to risk:

| Level | When | Required |
|-------|------|----------|
| **Full** | Multi-feature work, new systems, risky patches | Contract file, features/tests tracking, independent verifier, evidence bundle |
| **Lightweight** | Single-file edits, config changes, targeted fixes | Inline assertions (grep checks), deterministic verification, progress note |
| **Emergency** | Production down, auth broken, agents offline | Fix first, verify immediately after, document in episodic decision log |

**Default to Lightweight. Escalate to Full when:** multiple files change, change is hard to reverse, or change affects production agents.

---

## TDD Protocol (Mandatory for All Development)

- Write tests FIRST — before any implementation code (TDD Red phase)
- Tests MUST FAIL before implementation begins — if they pass, the test is wrong
- ONE feature at a time — implement to make tests pass (TDD Green phase)
- Run ALL tests (not just new ones) after completing each feature
- Mark feature "passing" ONLY after ALL tests green
- NEVER remove tests — only add

---

## Harness-Controlled Phase Transitions

The agent NEVER decides "I'm done with this phase." Instead:

1. Agent writes `.claude/state/phase-complete-marker.md` explaining what it completed
2. Harness hook fires (scoped to Write/Edit only)
3. Harness runs `validate-phase.sh` for the current phase
4. If validation FAILS → harness writes feedback, agent keeps working
5. If validation PASSES → harness advances phase, loads next instructions
6. Agent never runs `cat phases/phase-3.md` itself — infrastructure loads it

### Phase Validation (Layer 2 — No LLM)

Each phase has deterministic validation:
- **Research**: Required output file exists, contains mandatory sections, references known-fixes
- **Plan**: Plan file exists, contains acceptance criteria, not over-specified (line count check)
- **Execute**: All tests pass, no negative loops detected
- **Evaluate**: Protocol compliance script passes BEFORE evaluator agent loads

---

## Known-Fix Injection (Layer 2)

**Enforced by:** `pre-phase-start.sh` (hook_002) and `on-test-failure.sh`

The agent NEVER searches known-fixes.md. The harness does:

1. `pre-phase-start.sh` extracts domain keywords from product spec
2. Script greps known-fixes.md for matching symptoms
3. Matching fixes are written to `injected-context.md`
4. Harness includes injected-context.md in the agent's prompt
5. On test failure, `on-test-failure.sh` hook searches known-fixes automatically
6. If match found → fix written to `next-fix.md` → agent sees "apply this fix"
7. If no match → agent blocked, Telegram notification sent

---

## Negative Loop Detection (Layer 2)

**Enforced by:** `detect-loop.sh` (script_011), triggered by `on-stuck-detected.sh` (hook_003)

Deterministic, runs as hook:

1. Check git log for same files modified 4+ times in 10 commits
2. Check test results for same failures repeating
3. If loop detected AND known fix exists → inject fix into `next-fix.md`
4. If loop detected AND no known fix → write `agent-blocked.md`, notify Telegram, PAUSE
5. Agent cannot proceed until human responds or harness clears block

---

## Sprint Contract Negotiation

Before each feature:

1. Generator proposes what it will build and verification criteria
2. Evaluator reviews proposal (separate session)
3. If approved → contract file created, build begins
4. If rejected → feedback file created, re-negotiate
5. Max 3 negotiation attempts → escalate to human

---

## 7-Layer Verification Protocol

When task reaches IMPLEMENTED, independent verifier runs:

| Layer | What | Purpose |
|-------|------|---------|
| 1 | Evidence Before Verdict | Verifier NEVER reads builder's code or claims |
| 2 | Structured Evidence Chain | For every assertion: ACTION → OBSERVED → EVIDENCE → VERDICT |
| 3 | Adversarial Framing | "Your job is to FIND PROBLEMS. You succeed when you catch a failure." |
| 4 | Calibration Gate | Plant deliberate failure. If verifier misses it → discard all results |
| 5 | Independent Environment | Verifier gets own fresh environment |
| 6 | Cross-Examination | Second prompt: "Assume the verifier MISSED something" |
| 7 | Immutable Evidence Archive | Evidence saved BEFORE verdict issued |

### Evidence Bundle (required after verification)

The `evidence/` directory must contain after verification:

```
evidence/
  screenshot-001.png        # UI state captures
  stdout.txt                # Command output
  stderr.txt                # Error output
  exit-codes.json           # Process exit codes
  dom-snapshot.html         # DOM state (for web tasks)
  network-log.json          # HTTP requests/responses
  environment.json          # OS, versions, paths, timestamps
  file-hashes.json          # SHA-256 hashes of key artifacts
  calibration-result.json   # Calibration gate outcome
```

### Environment Verification Packs

Each environment type has specific verification steps:

| Environment | Key Verification Steps |
|------------|----------------------|
| **windows-desktop** | Launch via Session 1 wrapper (not SSH), screenshot desktop, `Get-Process`, verify window title, walk UIS on visible desktop, capture exit code |
| **docker-live** | `docker ps \| grep <container>`, health check via curl, Playwright DOM snapshot + screenshot, verify CSS/elements, network requests, walk UIS |
| **prod-web** | HTTP status 200 via curl, Playwright full-page screenshot, DOM snapshot, SSL cert check, content verification, network log |
| **api-live** | curl with expected body, verify HTTP status + response JSON schema, test error handling (malformed request), verify auth, log all request/response pairs |
| **cli-local** | Run with expected args, capture exit code, verify output patterns, check output files, test error cases (missing args, bad input), verify help/usage |

---

## Task Contract Schema

```json
{
  "task_id": "task_xxx",
  "created_at": "ISO-8601",
  "locked": true,
  "user_path": "Exact steps a real human takes",
  "environment": "windows-desktop | docker-live | prod-web | api-live | cli-local",
  "assertions": ["Pass/fail, deterministically checkable"],
  "required_evidence": ["screenshot", "exit_code", "stdout"],
  "forbidden_shortcuts": ["mock backend", "simulated responses", "hardcoded test data"],
  "uis": ["Step 1: ...", "Step 2: ..."]
}
```

Contract Rules:
- Created at task start — before ANY implementation
- Locked immediately — builder CANNOT modify
- User path is king — verification tests what the user would do
- Assertions are pass/fail — no subjective "looks good"

---

## Domain Instantiation Table

| Domain | Contract Form | State Tracking | How Verified | Evidence Tools |
|--------|--------------|----------------|-------------|----------------|
| **Coding** | `task.contract.json` | `features.json`, `tests.json`, `claude-progress.txt` | TDD + independent verifier | Test output, exit codes, screenshots |
| **LLM Prompt Engineering** | `task.contract.json` with model behavior assertions | `features.json`, `claude-progress.txt` | Independent model test runs against live API | `curl`, model response log, grep for artifacts |
| **System Admin** | Inline assertions in progress notes | `session-context.md` | Service health checks, log inspection | `systemctl`, `journalctl`, `curl`, `grep` |
| **Patches** | Inline assertions (expected grep matches) | Episodic decision log | grep for patch markers + functional test | `grep`, `diff`, test API response |
| **Skills** | Skill requirements in progress notes | `skill-features.json` or inline | Per-model sub-agent test runs | Model responses, `tool_use` blocks |
| **Memory** | Inline assertions (health checks) | `memory-features.json` or inline | 3-tier health check (file/embedding/LCM) | Health log, metrics log |
| **Config** | Expected behavior statement | Session context | Functional test | Gateway logs |

---

## Failure Modes & Prevention

| Failure | Prevention |
|---------|------------|
| Declaring victory early | Builder CANNOT self-certify to VERIFIED |
| Silent stalling | STUCK escalation after 3 retries or 5min |
| Spinning in circles | Same error 3x → automatic escalation |
| Ungrounded verdicts | Every verdict cites specific evidence |
| Context loss | Structured state files + rich handoff artifacts |
| Skipping verification | State machine enforces CONTRACT → IMPLEMENTED → VERIFIED |
| Wrong environment | Verifier accesses real target, not builder's env |
| Optimistic verifier | Adversarial framing + calibration gate |
| Broken verifier | Calibration gate catches verifier bugs |
| Agent guessing after failure | STOP rule — wait for guidance, don't improvise |
| Hook performance degradation | Scoped to Write/Edit only, not every tool use |
| Thin handoff | Rich handoff artifact with git log, files, decisions, tests |
| eval on markdown content | Structured verification format (file_exists, file_contains, test_passes) |
| Infinite wait for human | Timeout with state save and auto-resume script |
| Concurrent harness instances | Lockfile with PID check |
| Session crash | Retry wrapper with exponential backoff + crash recovery routine |
| Cost overrun | Budget circuit breaker on time and estimated cost |

---

## Recovery Protocol

If interrupted or context lost:
1. Read `claude-progress.txt` for last known state
2. Check `features.json` for any `"in_progress"` items
3. Run all tests to find failures
4. Resume from last verified good state

---

*This operating procedure is enforced by the harness scripts in `~/.claude/scripts/`. The agent follows it because the infrastructure makes non-compliance impossible, not because it reads and obeys markdown instructions.*
