# PROJECT SCOPE: Harness Infrastructure Controller — Full PC Deployment

**Created**: 2026-04-04
**Status**: DRAFT — Pending 5 verification loops + Adewale approval
**Methodology**: Enhanced Agent Harness (contract-first, evidence-first, builder/verifier separation)

---

## 1. OBJECTIVE

Deploy the three-layer deterministic agent harness across Adewale's Windows 10 PC so that every AI model (Claude Opus 4.6, GPT-5.4/Codex, MiniMax M2.7, Gemma 3 4B, DeepSeek V3.2, Gemini 3 Pro) operates under:

- State machine discipline (REQUESTED -> CONTRACT_LOCKED -> IMPLEMENTED -> VERIFIED -> ACCEPTED)
- Builder/verifier separation (builder CANNOT self-certify)
- Evidence-first verification (dumb sensors: grep, curl, exit codes — not LLM opinions)
- Automatic escalation (3 same errors OR 5min no progress -> STUCK -> stop + notify)
- Deterministic guards (bash scripts check compliance, not markdown instructions)

**Governing rule**: Never use Layer 3 (LLM) for something Layer 2 (scripts) can do. Never use Layer 2 for something Layer 1 (harness) should control.

---

## 2. WHAT ALREADY EXISTS

Located in `G:\harness infra\.agent-memory\`:

| Component | Path | Status |
|-----------|------|--------|
| Core Identity | `.agent-memory/core/identity.md` | Complete |
| Mission | `.agent-memory/core/mission.md` | Complete |
| Expert Domains (7 lenses) | `.agent-memory/core/expert-domains.md` | Complete |
| Model Profiles (failure taxonomies) | `.agent-memory/core/model-profiles.md` | Complete |
| Operating Procedure (full protocol) | `.agent-memory/core/operating-procedure.md` | Complete |
| Memory Manifest | `.agent-memory/MEMORY_MANIFEST.json` | Complete |
| Working Memory (session context, active tasks) | `.agent-memory/working/` | Complete |
| Episodic Memory (sessions, decisions) | `.agent-memory/episodic/` | Complete |
| Procedural Memory (script/tool/workflow registries) | `.agent-memory/procedural/` | Structure exists, registries need population |
| Semantic Memory (knowledge graph, domain knowledge) | `.agent-memory/semantic/` | Partial — domain docs exist, knowledge graph needs updating |
| Meta Memory (confidence, knowledge gaps) | `.agent-memory/meta/` | Structure exists |
| Prospective Memory (backlog) | `.agent-memory/prospective/` | Structure exists |
| CLAUDE.md (project-level) | `CLAUDE.md` | Complete — points to .agent-memory |
| Enhanced Agent Harness document (11 parts) | `enhanced-agent-harness.md` | Complete — reference document |
| Harness Big Idea (evolution through pushback) | `Harness big idea.txt` | Complete — reference document |
| Integration Blueprint | `making th enhanced agent harnes...txt` | Complete — reference document |
| Watcher System | `C:\Users\exrov\.openclaw\watchers\` | Complete — 5 slots |

**What does NOT exist yet**: All enforcement scripts, hooks, agent definitions, settings.json, per-project template, and init-project.sh. The entire bash enforcement layer is designed but not built.

---

## 3. THREE-LAYER ARCHITECTURE — COMPLETE BUILD MANIFEST

### 3.1 LAYER 1 — THE HARNESS (Session Lifecycle, Outside the LLM)

Controls what the agent sees, when sessions start/stop, and whether the agent proceeds. The agent does not participate in these decisions.

**Location**: `C:\Users\exrov\.claude\scripts\` (global, built once)

| # | Script | Purpose | Inputs | Outputs | Dependencies |
|---|--------|---------|--------|---------|-------------|
| 1 | `run-harness.sh` | **Outer loop** — drives the state machine (PLAN -> NEGOTIATE -> BUILD -> EVALUATE -> COMPLETE). Invokes Claude sessions per phase. Manages iteration count, checks for blocked state, constructs prompts from files. | `current-phase.json` | Phase transitions, session invocations | All other Layer 1 scripts |
| 2 | `run-claude-safe.sh` | **Retry wrapper** — wraps every `claude` invocation. Takes prompt via FILE (stdin pipe, not command-line args — avoids shell length limits). Exponential backoff: attempt 1 waits 60s, attempt 2 waits 120s, attempt 3 waits 240s. Max 3 retries. On each failure: notify via Telegram with exit code and retry count. On final failure: write handoff artifact, notify, set agent-blocked, exit 1. | Prompt file path, permission mode | Exit code 0 (success) or 1 (all retries failed), handoff on failure | `write-handoff.sh`, `notify.sh` |
| 3 | `startup-recovery.sh` | **Crash recovery** — runs at harness start. Detects stale artifacts from crashed sessions. Cleans lockfile, kills orphaned dev server, writes fresh handoff. | Disk state | Clean state, fresh handoff | `write-handoff.sh`, `notify.sh` |
| 4 | `telegram-poll.sh` | **Notification daemon** — long-polls Telegram Bot API for your replies. Writes replies to `human-response.md`. Has heartbeat file so harness can detect if daemon dies. Triggers `resume-on-reply.sh` if agent was timed out. | Telegram Bot Token, Chat ID | `human-response.md`, heartbeat file | Telegram Bot (optional) |
| 5 | `wait-for-human.sh` | **Timeout + state save** — blocks until `human-response.md` appears or timeout (default 30min). On timeout: saves state, **dynamically generates** `resume-on-reply.sh` (a runtime artifact, NOT a build deliverable — it's a small bash script that calls `run-harness.sh` when human eventually responds), notifies. Sends reminders every 10min. | Timeout in minutes | Human response or timeout with state save | `write-handoff.sh`, `notify.sh` |
| 6 | `notify.sh` | **Telegram/WhatsApp bridge** — sends messages via Telegram Bot API (simple curl). Transport-agnostic: swap API endpoint for WhatsApp/Twilio. | Message text | Telegram message sent | Telegram Bot Token (optional — degrades gracefully to file-only) |
| 7 | `check-budget.sh` | **Cost/time circuit breaker** — checks elapsed time against MAX_HOURS (default 4) and estimated cost against MAX_COST_USD (default 50). Cost estimated as: iteration_count × $4 per iteration (integer arithmetic, no `bc`). Time tracked via unix timestamps in `session-start-time.txt`. On limit: write handoff, notify, exit 1 (hard stop). Called by run-harness.sh at start of every iteration. | `session-start-time.txt`, `current-phase.json`, env vars MAX_COST/MAX_HOURS | Exit code 0 (within budget) or 1 (limit reached) | `write-handoff.sh`, `notify.sh` |
| 8 | `git-checkpoint.sh` | **Auto-commit at state transitions** — stages all changes and commits with harness-prefixed message at every phase boundary. Only commits if there are actual changes. | Phase name, sprint number | Git commit | Git |
| 9 | `write-handoff.sh` | **Rich handoff artifact** — generates structured context document from disk state. Internal schema: `## Completed Features` (git log --oneline since session start), `## Current Codebase State` (find src/ file list), `## Files Modified This Session` (git diff --name-only HEAD~5), `## Architectural Decisions Made` (cat progress-notes.md), `## Known Issues / Deferred Work` (cat deferred.md), `## Active Sprint Contract` (cat current contract), `## Test Status` (validate.sh --summary), `## What To Do Next` (pointer to active-instructions.md). Used at session boundaries, crash recovery, and sprint transitions. | Phase label | `handoff-artifact.md` | Git, state files |
| 10 | `ensure-dev-server.sh` | **Pre-evaluator server check** — detects project type (package.json/requirements.txt), starts dev server if not running, waits up to 60s for HTTP response. Blocks evaluation if server won't start. | Project root | Dev server running, PID file | Node/Python (project-dependent) |
| 11 | `init-project.sh` | **One-command project setup** — creates `.claude/` structure with minimal CLAUDE.md, state/, state/evaluation-results/, specs/, contracts/, protocols/, evidence/ directories. Creates empty `known-fixes.md`, `features.json` (empty features array), `tests.json` (empty tests array), `claude-progress.txt`. Creates `.gitattributes` (`* text=auto eol=lf`) and `.editorconfig` (`end_of_line = lf`) for CRLF enforcement. Initializes `current-phase.json` (`{"phase":"PLAN","sprint":0,"iteration":0}`). For `.agent-memory/` projects, **copies** (NOT symlinks) operating-procedure.md — symlinks require admin on Windows Home, copy is functionally equivalent since the file is read-only during harness operation. | Project root | Project ready for harness | None |

### 3.2 LAYER 2 — DETERMINISTIC GUARDS (Scripts, No LLM)

Binary pass/fail checks. File existence, grep, line counts, exit codes, git history analysis. No LLM judgment.

**Location**: `C:\Users\exrov\.claude\scripts\` (global, built once)

| # | Script | Purpose | What It Checks | Outputs |
|---|--------|---------|----------------|---------|
| 12 | `validate-phase.sh` | **Phase validation** — runs deterministic checks per phase. Phase 1 (Research): output file exists, contains required sections. Phase 2 (Plan): plan file exists, has acceptance criteria, line count check for over-specification. Phase 3 (Execute): all tests pass, no loops detected. | File existence, required sections (grep), line counts (wc) | Exit code 0 (pass) or 1 (fail) + specific failure message |
| 13 | `detect-loop.sh` | **Negative loop detector** — checks git log for same files modified 4+ times in 10 commits. Checks test results for repeating failures. If loop + known fix exists: injects fix to `next-fix.md`. If loop + no known fix: blocks agent, notifies, waits for human. **Blocks execution, does not advise.** | Git history (`git log --name-only`), test result files | Exit code 0 (no loop) or 1 (loop detected) + fix injection or block |
| 14 | `validate-state-transition.sh` | **State machine enforcement** — validates that state transitions follow allowed paths (REQUESTED->CONTRACT_LOCKED->IMPLEMENTED->VERIFIED->ACCEPTED, with STUCK entry from any state). Prevents skipping states. | `current-phase.json`, requested transition | Exit code 0 (valid) or 1 (invalid transition) |
| 15 | `verify-fix-applied.sh` | **Structured fix verification (NO eval)** — reads `## Verify` section from known-fix entries. Interprets structured format: `file_exists`, `file_contains` (with optional `before_pattern` for ordering), `test_passes` (allowlisted commands only with timeout). Diffs actual code, never trusts commit messages. | Fix file with structured verify section | Exit code 0 (fix verified) or 1 (fix not applied) |
| 16 | `evaluate-protocol-compliance.sh` | **Protocol compliance gate** — **called by `run-harness.sh` at the start of the EVALUATE phase**, runs BEFORE evaluator agent loads. Checks: all required state files exist, no negative loops, all tests pass, known-fix application verified. Binary pass/fail on each. If fail: harness returns to BUILD phase with feedback. Sprint cannot reach evaluator until all pass. | State files, git history, test suite | Exit code 0 (all pass) or 1 (compliance failure) |

### 3.3 LAYER 3 — AGENT DEFINITIONS (LLM, Within Constraints)

Genuine judgment calls only. Everything scriptable has already been handled by Layers 1-2.

**Location**: `C:\Users\exrov\.claude\agents\` (global, built once)

| # | Agent | Role | Key Constraints | Context |
|---|-------|------|-----------------|---------|
| 17 | `planner.md` | **Planner** — expands user brief into product-level spec with evaluation criteria. Stays HIGH-LEVEL: what gets built and why, feature scope, user stories, quality dimensions. Does NOT specify granular implementation details (prevents speculative planning cascades, Failure Mode #10). | Cannot write implementation details. Output capped at ~100 lines. Defines evaluation criteria the Evaluator will use. | Own session, clean context |
| 18 | `generator.md` | **Generator (Builder)** — implements features per sprint contract. TDD-first (write tests that fail, then implement). Writes progress notes to disk. Negotiates sprint contracts with evaluator before coding. Can ONLY move to IMPLEMENTED — never VERIFIED or ACCEPTED. | Cannot self-certify. Cannot modify task.contract.json after lock. Cannot write/edit verification scripts. Must follow TDD (tests first, must fail before implementation). ONE feature at a time. | Own session with compaction. Reads handoff artifact at sprint boundaries. |
| 19 | `evaluator.md` | **Evaluator** — has TWO distinct roles invoked at different phases: **(a) CONTRACT REVIEW** during NEGOTIATE phase — reviews Generator's sprint proposal for quality, feasibility, and alignment with product spec; approves or rejects with feedback. **(b) IMPLEMENTATION VERIFICATION** during EVALUATE phase — grades quality with tools (Playwright, curl, etc.), tuned for SCEPTICISM. Does NOT read builder's code, notes, or test results — verifies from scratch against contract. Default: fail if in doubt. Checks both code quality AND protocol compliance. | Cannot read builder's progress notes during verification. Cannot use builder's terminal. Must interact with LIVE output during verification. Adversarial framing: "Your job is to FIND PROBLEMS." Protocol compliance is a hard gate. | Own CLEAN session for each invocation — separate context from generator |
| 20 | `cross-examiner.md` | **Cross-Examiner (Layer 6 Doubt Protocol)** — invoked by `run-harness.sh` ONLY after evaluator issues PASS. Gets its own separate session. Reads ONLY the `evidence/` bundle and `verification.result.json` — CANNOT read builder's code, progress notes, or evaluator's reasoning. Prompt MUST contain: "Assume the verifier MISSED something. What could still be wrong? Does the evidence actually show what the verifier claims?" Can override PASS to FAIL if evidence is inconsistent with verdicts. If overridden: harness returns to BUILD with cross-examiner's concerns as feedback. | Cannot read builder's code/notes. Cannot read evaluator's session. Only reads evidence bundle. Must cite specific evidence file + line for every concern. Can only override PASS→FAIL, never FAIL→PASS. | Own CLEAN session — sees only evidence/ directory and verification.result.json |

### 3.4 HOOKS AND HARNESS-INTERNAL SCRIPTS

There are two types of hooks in this system:

**Claude Code hooks** — registered in `settings.json`, triggered by Claude Code's hook system:

| # | Hook | Trigger | Purpose |
|---|------|---------|---------|
| 21 | `post-write-check.sh` | PostToolUse (filtered to Write/Edit/str_replace) | Detects `phase-complete-marker.md` writes. Triggers `validate-phase.sh`. If validation passes: advances phase, loads next instructions to `active-instructions.md`. If fails: writes feedback, agent keeps working. |
| 25 | `on-session-end.sh` | Stop (fires when Claude session ends) | Writes session summary to `.agent-memory/episodic/sessions/`. Updates `MEMORY_MANIFEST.json` with session count and last_accessed. Saves final state to `progress-notes.md`. Ensures no orphaned state. |

**Harness-internal scripts** — called by `run-harness.sh` at specific points, NOT registered in settings.json:

| # | Script | Called By | When | Purpose |
|---|--------|----------|------|---------|
| 22 | `pre-phase-start.sh` | `run-harness.sh` | Before each phase begins | Extracts domain keywords from product spec (`grep -oP '(?<=## )\w+' product-spec.md`), uses keywords to grep `known-fixes.md` for matching symptoms (`grep -B1 -A10 -iE "$KEYWORDS" known-fixes.md`), writes matches to `injected-context.md`. Agent sees fixes as briefing material — never searches itself. |
| 23 | `on-stuck-detected.sh` | `run-harness.sh` | When STUCK triggers fire (3 same errors, 5min stall, or agent writes STUCK marker) | **Dual-path logic**: (1) Runs `detect-loop.sh` to check git history. (2) **If loop detected AND known fix exists**: writes fix directly to `next-fix.md` with header "MANDATORY FIX — DO NOT IMPROVISE", notifies Telegram "Loop detected, known fix injected." (3) **If loop detected AND NO known fix**: writes `agent-blocked.md` with facts (file name, repeat count), notifies Telegram "Loop detected, no known fix, agent PAUSED", blocks until `human-response.md` appears. Human response becomes `next-fix.md`. |
| 24 | `on-test-failure.sh` | `run-harness.sh` | When `validate-phase.sh` or test suite returns non-zero | **Search algorithm**: reads `known-fixes.md` line by line, extracts `**Symptom**:` fields, greps failure output for each symptom (case-insensitive). **If match found**: reads the next 10 lines (fix block), writes to `next-fix.md` with header "KNOWN FIX FOUND — APPLY EXACTLY", notifies Telegram. **If no match**: logs "No known fix matched", agent proceeds with own approach. Does NOT block on no-match. |

### 3.5 SETTINGS.JSON

**Location**: `C:\Users\exrov\.claude\settings.json` (global)

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "\"C:/Program Files/Git/bin/bash.exe\" \"$HOME/.claude/hooks/post-write-check.sh\""
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "\"C:/Program Files/Git/bin/bash.exe\" \"$HOME/.claude/hooks/on-session-end.sh\""
          }
        ]
      }
    ]
  }
}
```

**CRITICAL for Windows**: Hook commands MUST use explicit path to `bash.exe` (not just `bash`) because Claude Code's hook executor may use PowerShell or cmd.exe. The path `C:/Program Files/Git/bin/bash.exe` is the default Git for Windows installation. If Git is installed elsewhere, adjust path. Phase A must verify this path exists and Phase I test #51 must confirm hooks actually fire in bash.

Key design decision: hooks fire on Write/Edit ONLY, not every tool use. On a session with 200+ tool uses, this is ~30 hook invocations instead of 200+.

---

## 4. PER-PROJECT STRUCTURE

Created by `init-project.sh` (script #11). Each project gets:

```
project-root/
├── .claude/
│   └── CLAUDE.md                      # Minimal — points to active instructions
├── .agent-memory/                     # OR this, for memory-equipped projects
│   └── (full memory system)
├── task.contract.json                 # Per task — locked at creation
├── features.json                      # Feature tracking with status
├── tests.json                         # Test registry with pass/fail
├── claude-progress.txt                # Human-readable progress log
├── evidence/                          # Verification evidence bundle
│   ├── screenshot-001.png
│   ├── stdout.txt
│   ├── stderr.txt
│   ├── exit-codes.json
│   ├── dom-snapshot.html
│   ├── network-log.json
│   ├── environment.json
│   ├── file-hashes.json
│   └── calibration-result.json
└── verification.result.json           # Verifier output (structured)
```

**Per-project state directory** (created automatically by harness):

```
.claude/state/                         # OR .agent-memory/working/ for memory projects
├── current-phase.json                 # {"phase": "BUILD", "sprint": 2, "iteration": 5}
├── progress-notes.md                  # What agent has learned/decided/built
├── handoff-artifact.md                # Rich context for session transitions
├── active-instructions.md             # Current phase only (loaded by harness)
├── injected-context.md                # Known-fixes relevant to current work
├── next-fix.md                        # Mandatory fix to apply (from loop detector)
├── human-response.md                  # Your Telegram/WhatsApp replies
├── agent-blocked.md                   # Pause marker
├── harness.lockdir/                   # Concurrency protection (mkdir-based atomic lock, contains pid file)
├── session-start-time.txt             # For budget circuit breaker
├── dev-server.pid                     # Orphan cleanup
├── telegram-poll-heartbeat            # Daemon liveness
├── negotiate-attempts.txt             # Contract negotiation retry counter (managed by run-harness.sh NEGOTIATE phase)
├── eval-attempts-sprint-N.txt         # Per-sprint evaluation retry counter (managed by run-harness.sh EVALUATE phase)
├── phase-complete-marker.md           # Agent writes this; harness validates
└── evaluation-results/                # (managed by run-harness.sh EVALUATE phase)
    └── sprint-N-evaluation.md         # Evaluator findings per sprint (PASS.md or FAIL.md)
```

**Per-project protocol files**:

```
.claude/protocols/                     # OR .agent-memory/procedural/
└── known-fixes.md                     # Project-specific known-fix registry
```

**Per-project specs and contracts** (created during work):

```
.claude/specs/
├── product-spec.md                    # Planner output (high-level)
└── evaluation-criteria.md             # What evaluator grades against

.claude/contracts/
├── sprint-1-proposal.md               # Generator's proposed contract
├── sprint-1-contract.md               # Approved contract (locked)
├── sprint-1-feedback.md               # If rejected during negotiation
└── ...
```

---

## 5. STATE MACHINE — HARNESS-ENFORCED TRANSITIONS

```
REQUESTED -> CONTRACT_LOCKED -> IMPLEMENTED -> VERIFIED -> ACCEPTED
                                     |
                                   STUCK
                            (escalate -> guided -> resume)
```

**Mapped to harness phases in run-harness.sh**:

| State Machine State | Harness Phase | Who Acts | What Happens |
|-------------------|---------------|----------|-------------|
| REQUESTED | PLAN | Planner agent | Expands brief to product spec + evaluation criteria |
| CONTRACT_LOCKED | NEGOTIATE | Generator proposes, Evaluator reviews | Sprint contract negotiated. **Max 3 attempts** (tracked in `negotiate-attempts.txt`). On 3rd failure: harness notifies Telegram, pauses, waits for human. Human can reply: "skip" (use last proposal as contract), or guidance text (injected into next negotiation round, counter resets to 0). |
| IMPLEMENTED (building) | BUILD | Generator agent | TDD-first implementation. Loop detector active. Known-fix injection active. |
| IMPLEMENTED (checking) | EVALUATE | Layer 2 scripts THEN Evaluator agent THEN Cross-Examiner | **Sequence**: (1) `evaluate-protocol-compliance.sh` runs — if FAIL, return to BUILD immediately (hard gate, evaluator never loads). (2) Calibration gate: harness renames a required file or injects known-bad assertion, invokes evaluator, checks `calibration-result.json` — if evaluator misses planted failure, discard all results and re-run with fresh session. (3) Evaluator 7-layer verification (Layer 3). (4) If PASS: Cross-Examiner doubt protocol (Layer 6) — can override PASS→FAIL. (5) Evidence archived immutably BEFORE verdict written. **Max 3 evaluation attempts** per sprint (tracked in `eval-attempts-sprint-N.txt`). On 3rd failure: notify Telegram, pause, wait for human. Human can reply: "accept" (ship as-is), "skip" (move to next sprint), or guidance text (inject, reset counter, return to BUILD). |
| VERIFIED | COMPLETE | Human (via Telegram or manual) | Final sign-off. Git checkpoint. Session summary. |
| STUCK | BLOCKED | Harness auto-detects (see triggers below) | Stop working, send facts not theories, wait for guidance |

**STUCK detection triggers (any ONE is sufficient — enforced by `on-stuck-detected.sh`)**:
- **Error Loop**: Same error type 3 times in a row (detected by `detect-loop.sh` via git history)
- **Progress Stall**: No progress for 5+ minutes of active work (detected by checking modification timestamp on `progress-notes.md` — if `$(date +%s) - $(stat -c %Y progress-notes.md)` exceeds 300 seconds, stall detected)
- **Environment Error**: Environment-level error agent can't fix (e.g., port not listening, service down)
- **Explicit Confusion**: Agent doesn't know what to do next (agent writes STUCK marker to `claude-progress.txt`)
| ACCEPTED | DONE | Harness | All sprints passed. Handoff written. Notify. |

**Transition rules (enforced by `validate-state-transition.sh`)**:
- States CANNOT be skipped
- Builder can ONLY move to IMPLEMENTED — never VERIFIED or ACCEPTED
- Moving backward is allowed (VERIFIED -> IMPLEMENTED if issues found)
- STUCK can be entered from any active state
- STUCK exits to the state it came from after guidance received
- "Done" is COMPUTED from evidence, not typed by the agent

---

## 6. 7-LAYER VERIFICATION PROTOCOL

Runs when task reaches IMPLEMENTED. Independent verifier executes all 7 layers:

| Layer | Name | What Happens | Enforcement |
|-------|------|-------------|-------------|
| 1 | Evidence Before Verdict | Verifier NEVER reads builder's code or claims. Operates only in real environment. | Evaluator agent definition prohibits reading builder files |
| 2 | Structured Evidence Chain | For every assertion: ACTION -> OBSERVED -> EVIDENCE file -> VERDICT | Evaluator must write structured results to `verification.result.json` |
| 3 | Adversarial Framing | "Your job is to FIND PROBLEMS. You succeed when you catch a failure." | Baked into `evaluator.md` prompt |
| 4 | Calibration Gate | Plant deliberate failure before real verification. If verifier misses it -> discard ALL results. | **Owned by `run-harness.sh` EVALUATE phase**: before invoking evaluator agent, harness renames a required file or injects a known-bad assertion. After evaluator runs, harness checks `calibration-result.json` to confirm the planted failure was caught. If missed: discard all results, re-run with fresh evaluator session. |
| 5 | Independent Environment | Verifier gets own fresh environment, not builder's | Separate Claude session with clean context |
| 6 | Cross-Examination | Second prompt: "Assume the verifier MISSED something." Can override PASS to FAIL. | `cross-examiner.md` agent, separate session |
| 7 | Immutable Evidence Archive | All evidence saved BEFORE verdict issued. Anyone can re-examine independently. | Evidence written to `evidence/` before `verification.result.json` |

**Evidence bundle** (required after verification):

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

---

## 7. ENVIRONMENT VERIFICATION PACKS

Each environment type has specific verification steps the evaluator must follow:

| Environment | Key Steps |
|------------|-----------|
| **windows-desktop** | Launch via Session 1 wrapper (not SSH), screenshot desktop, `Get-Process`, verify window title, walk UIS on visible desktop, capture exit code |
| **docker-live** | `docker ps \| grep <container>`, health check via curl, Playwright DOM snapshot + screenshot, verify CSS/elements, network requests |
| **prod-web** | HTTP status 200 via curl, Playwright screenshot, DOM snapshot, SSL cert check, content verification, network log |
| **api-live** | curl with expected body, verify HTTP status + JSON schema, test error handling, verify auth, log request/response pairs |
| **cli-local** | Run with expected args, capture exit code, verify output patterns, check output files, test error cases, verify help/usage |

---

## 8. PROTOCOL LEVELS

Not every change needs full ceremony. Match protocol to risk:

| Level | When | Required |
|-------|------|----------|
| **Full** | Multi-feature work, new systems, risky patches | Contract file, features/tests tracking, independent verifier, evidence bundle, 7-layer protocol |
| **Lightweight** | Single-file edits, config changes, targeted fixes | Inline assertions (grep checks), deterministic verification, progress note |
| **Emergency** | Production down, auth broken, agents offline | Fix first, verify immediately after, document in episodic decision log |

**Default to Lightweight. Escalate to Full when**: multiple files change, change is hard to reverse, or change affects production agents.

---

## 9. KNOWN-FIXES REGISTRY FORMAT

Structured format with NO `eval`. Scripts interpret, not execute:

```markdown
## FIX-NNN: [Short description]
- **Symptom**: [Exact error text or pattern that scripts can grep for]
- **Root cause**: [Why this happens]
- **Fix**: [What to do]
- **File**: [Which file(s) to change]
- **Verified**: [Date last confirmed working]

## Verify
- type: file_exists
  file: [path]

- type: file_contains
  file: [path]
  pattern: [regex]
  before_pattern: [optional — for ordering checks]

- type: test_passes
  command: [allowlisted command only: pytest, npm test, cargo test, python -m unittest]
```

Three verification types only — NO `eval`, NO arbitrary shell execution:

- **`file_exists`**: checks `[ -f "$file" ]` — binary pass/fail
- **`file_contains`**: checks `grep -q "$pattern" "$file"` — with optional `before_pattern` for ordering (verifies pattern appears on an earlier line number than before_pattern, e.g., specific route defined before catch-all)
- **`test_passes`**: runs ONLY allowlisted commands (`pytest`, `npm test`, `cargo test`, `python -m unittest`) with 120s timeout. Command base must match allowlist or check is SKIPPED.

`verify-fix-applied.sh` parses this format line-by-line using case statements — no eval, no arbitrary execution.

---

## 10. TASK CONTRACT SCHEMA

Created before ANY implementation. Locked immediately. Builder CANNOT modify.

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
  "uis": ["Step 1: ...", "Step 2: ...", "Step 3: ..."]
}
```

---

## 11. 10 FUNDAMENTAL FAILURE MODES ADDRESSED

| # | Failure Mode | Category | How This Architecture Fixes It |
|---|-------------|----------|-------------------------------|
| 1 | Context Window Saturation | Context | Progressive disclosure — phase-specific instruction loading. Agent only sees current phase. |
| 2 | No External State Tracking | Architecture | File-driven state machine. `current-phase.json` is truth. Agent reads file, doesn't infer. |
| 3 | No Phase Isolation | Architecture | Explicit gates. Harness validates before advancing. Agent writes marker, harness decides. |
| 4 | No Verification Gate | Quality | Builder/verifier separation. 7-layer protocol. Evaluator in own clean session. |
| 5 | No Deterministic Operations | Efficiency | Everything scriptable is bash. Tests, linting, validation, loop detection — all Layer 2. |
| 6 | Context Anxiety (distinct from saturation) | Behavioral | Agent rushes to finish prematurely because it *believes* it's approaching limits, even when it isn't. Fix: clean context resets at sprint boundaries via `write-handoff.sh`. Evaluator always gets fresh context. Within sprints, Opus 4.6's automatic compaction handles most pressure. The fix is structural (new session) not instructional ("don't rush"). |
| 7 | Self-Evaluation Bias | Quality | Agent confidently praises its own mediocre work. Fix: structurally separate evaluator in own clean session. Evaluator CANNOT read builder's code, notes, or test results — verifies from scratch. Adversarial framing ("your job is to FIND PROBLEMS"). Calibration gate plants deliberate failure to test evaluator catches it. Evaluator tuned for scepticism over multiple calibration rounds. |
| 8 | One-Shotting | Planning | Agent attempts to build everything in one pass, runs out of context, leaves half-finished features. Fix: sprint contracts negotiated per feature BEFORE coding. Generator and evaluator agree what "done" looks like for each chunk. Max 3 negotiation attempts, then escalate to human. |
| 9 | Compaction vs Clean Reset | Context | Compaction preserves continuity but accumulates context pollution. Fix: compaction within sprints (Opus 4.6 handles this well). Clean context resets between sprints via `write-handoff.sh` — fresh session with rich handoff artifact, not carried-over polluted context. Evaluator ALWAYS gets clean context. |
| 10 | Speculative Planning Cascades | Planning | Planner specifies granular technical details upfront, gets something wrong, errors cascade into implementation exponentially. Fix: planner stays at product context and high-level technical design. ~100 line cap on spec enforced by `validate-phase.sh` line count check. Generator figures out the implementation path as it works. |

---

## 12. MODEL PROFILES & COMPENSATION STRATEGIES

Each model has a documented failure taxonomy. Agent definitions adapt per model.

| Model | Role in Harness | Key Compensations |
|-------|----------------|-------------------|
| **Claude Opus 4.6** | Primary reasoning, planning, complex tasks | Trust inference. Clean context resets at sprint boundaries. |
| **GPT-5.4 / Codex** | Browser automation, literal execution | Explicit decision trees. "VERIFY after every action" loops. Numbered steps. |
| **MiniMax M2.7** | Summarisation, cheap processing | Narration points every 30s. Version lock checkpoint. Reality check protocol. |
| **Gemma 3 4B** | Local content generation, NL routing | Anti-commentary directive. Multi-turn `<start turns>` format. temp=1.0, top_k=64, repeat_penalty=1.0, max_tokens=2000. |
| **DeepSeek V3.2** | Quick experiments | Fast, free, local. |
| **Gemini 3 Pro** | Creative research | Different perspective. |

Model-specific agent variants: Base `SKILL.md` targets Opus. `SKILL-codex.md` and `SKILL-minimax.md` adapt per model. Three-layer model means a new model only needs a Layer 3 profile — Layers 1-2 are model-agnostic.

---

## 13. INTEGRATION: .agent-memory ↔ ENFORCEMENT SCRIPTS

The `.agent-memory/` system is the **protocol layer** (rules, identity, knowledge). The `~/.claude/scripts/` are the **enforcement layer** (deterministic execution). They integrate as follows:

| .agent-memory Component | Enforcement Script Integration |
|------------------------|-------------------------------|
| `core/operating-procedure.md` | Defines the state machine that `run-harness.sh` enforces |
| `core/model-profiles.md` | Informs agent definition variants in `~/.claude/agents/` |
| `core/expert-domains.md` | Guides which expert lenses to apply during troubleshooting |
| `working/session-context.md` | Updated by harness at session boundaries via `write-handoff.sh` |
| `working/active-tasks.json` | Tracks tasks that `run-harness.sh` cycles through |
| `procedural/scripts/SCRIPT_REGISTRY.json` | Must contain entries for all 16 scripts + 4 agents + 5 hooks/harness-internal scripts (25 total) |
| `procedural/workflows/WORKFLOW_REGISTRY.json` | Must contain workflow for full harness cycle |
| `episodic/decisions/` | `run-harness.sh` logs phase transitions here (e.g., `BUILD-to-EVALUATE-2026-04-04.md`); `on-stuck-detected.sh` logs escalation decisions here |
| `episodic/sessions/` | Session summary written at end by `on-session-end.sh` hook |
| `semantic/domain/three-layer-architecture.md` | Documents the Layer 1/2/3 split |
| `semantic/domain/enforcement-mechanisms.md` | Documents soft vs hard vs harness enforcement |
| `semantic/domain/failure-modes.md` | Documents all 10 failure modes |
| `semantic/domain/protocol-fidelity.md` | Documents instruction decay and re-injection pattern |
| `meta/confidence.json` | Updated as scripts are tested and verified |
| `prospective/backlog.json` | Contains build order and dependencies for this scope |

---

## 14. WINDOWS ADAPTATION NOTES

This system is designed for bash scripts on Windows 10 Home (10.0.19045) using Git Bash. Critical platform-specific considerations:

### 14.1 Tool Dependencies (must verify/install in Phase A)

| Tool | Required By | How to Install | Verification |
|------|------------|----------------|-------------|
| Git Bash | All scripts | Bundled with Git for Windows | `bash --version` |
| `jq` | All scripts that parse JSON (run-harness.sh, check-budget.sh, validate-state-transition.sh) | `winget install jqlang.jq` or download binary to PATH | `jq --version` |
| `curl` | notify.sh, telegram-poll.sh, ensure-dev-server.sh | Bundled with Git Bash | `curl --version` |
| `grep` | All Layer 2 scripts | Bundled with Git Bash (GNU grep) | `grep --version` |
| Claude Code CLI | run-claude-safe.sh, run-harness.sh | Installed via npm or standalone | `claude --version` |
| Node.js | ensure-dev-server.sh, Playwright MCP | `winget install OpenJS.NodeJS` | `node --version` |
| Playwright | evaluator.md (live app testing) | `npx playwright install chromium` | `npx playwright --version` |

**Note**: `bc` is NOT required. All arithmetic uses bash `$(( ))` integer arithmetic. Budget calculations use integer cents, not floating-point dollars.

### 14.2 Path Handling

| Context | Path Format | Notes |
|---------|------------|-------|
| Inside scripts | `$HOME/.claude/scripts/...` | Use `$HOME`, never hardcode `C:\Users\exrov` |
| settings.json hooks | `bash $HOME/.claude/hooks/...` | Claude Code resolves `$HOME` on Windows |
| Git Bash terminal | `~/.claude/...` | Tilde expands to `C:\Users\exrov` in Git Bash |
| Claude Code hooks | Test empirically | Hook executor may use PowerShell or cmd — must verify bash is invoked |

**Rule**: Always use `$HOME/.claude/` in scripts, never hardcoded Windows paths. Test hook execution from Claude Code (not just Git Bash terminal) in Phase I.

### 14.3 Line Ending Handling (CRITICAL)

Git Bash's GNU grep may fail on files with CRLF line endings when matching `$` anchors or multiline patterns. All harness state files MUST use LF line endings.

| Mitigation | Where Applied |
|-----------|---------------|
| `git config core.autocrlf input` | Set globally — Git converts CRLF to LF on commit |
| Scripts MUST write files with `printf`, NEVER `echo` | `printf "%s\n" "$content" > file` always produces LF. `echo` may produce CRLF depending on system config. This is a HARD RULE for all harness scripts. |
| Add `.gitattributes` with `* text=auto eol=lf` | Per-project, created by init-project.sh |
| Add `.editorconfig` with `end_of_line = lf` | Per-project, created by init-project.sh |

### 14.4 Background Process Management

Git Bash's `nohup` does NOT reliably survive terminal closure on Windows. The Telegram polling daemon requires special handling:

| Approach | Reliability | Notes |
|----------|------------|-------|
| `bash script.sh &` | Works while terminal is open | Daemon dies when Git Bash terminal closes |
| `nohup bash script.sh &` | Unreliable on Windows | SIGHUP handling differs |
| `start /b bash script.sh` | Windows-native, more reliable | Use `cmd /c start /b` from Git Bash |

**Decision**: The harness runs in a Git Bash terminal that stays open. Telegram daemon runs as `&` background job within that terminal. If the terminal closes, the daemon dies and the harness's heartbeat monitor will detect this on next startup. This is acceptable because:
- The harness itself needs the terminal open to run
- Crash recovery handles daemon restart
- Telegram is optional — harness works without it

**Dev server backgrounding**: `ensure-dev-server.sh` must also handle Windows backgrounding. Use `bash -c "npm run dev &" &` or `cmd /c "start /b npm run dev"` depending on reliability. The script must write PID to `dev-server.pid` for cleanup by `startup-recovery.sh`. Heartbeat: the script checks `curl -s http://localhost:PORT` to confirm server is alive — this is portable and works identically on Windows and Unix.

### 14.5 Signal Handling (trap)

Git Bash's `trap` works for EXIT but is unreliable for SIGTERM, SIGHUP. Scripts that use trap:

| Script | Uses trap | Fallback |
|--------|----------|----------|
| `run-harness.sh` | `trap "rm -f $LOCKFILE; kill $POLL_PID" EXIT` | EXIT works. startup-recovery.sh cleans stale lockfiles on next start. |
| `run-claude-safe.sh` | No trap needed | Exits naturally |
| `telegram-poll.sh` | No trap needed | PID file cleaned by startup-recovery.sh |

**Rule**: Only use `trap ... EXIT`. Never rely on SIGTERM/SIGHUP handlers on Windows. Use startup-recovery.sh as the fallback cleanup mechanism.

### 14.6 File Locking

PID-based lockfile has a race condition window on Windows. Mitigation:

```bash
# Use mkdir for atomic lock creation (works on Windows and Unix)
LOCKDIR=".claude/state/harness.lockdir"
if mkdir "$LOCKDIR" 2>/dev/null; then
  echo $$ > "$LOCKDIR/pid"
  trap "rm -rf $LOCKDIR" EXIT
else
  # Lock exists — check if PID is still alive
  ...
fi
```

`mkdir` is atomic on all platforms. This replaces the simple file-based lock.

**PID liveness check on Windows**: Use `kill -0 $PID 2>/dev/null` — returns 0 if process exists, 1 if not. Works in Git Bash on Windows. A lockdir is **stale** if: (1) PID file exists inside it AND (2) `kill -0 $(cat lockdir/pid)` returns non-zero (process dead). On stale detection: `rm -rf` the lockdir and proceed. If `rm -rf` fails (Windows file handle issue), retry after 1s; if still fails, abort with error.

### 14.7 Claude Code Hook Execution

Claude Code hooks invoke shell commands. On Windows, this may use `cmd.exe`, PowerShell, or Git Bash depending on configuration. **Must test in Phase I**:

1. Create a minimal hook that writes a marker file
2. Trigger a Write/Edit operation in Claude Code
3. Verify the marker file was created
4. Check which shell executed the hook (examine process tree)
5. If not bash: adjust settings.json to explicitly invoke `bash` (e.g., `"command": "C:/Program Files/Git/bin/bash.exe ~/.claude/hooks/post-write-check.sh"`)

### 14.8 Playwright on Windows Home

Playwright requires a Chromium browser. Windows Home does not include Docker Desktop easily. Options:

| Approach | Effort | Notes |
|----------|--------|-------|
| `npx playwright install chromium` | Low | Downloads Chromium binary. Works on Windows Home. |
| Use system Edge/Chrome | Low | Playwright can use installed browsers via `channel: 'msedge'` |
| Skip Playwright for CLI-only projects | Zero | Only needed when evaluator tests web UI |

**Decision**: Install Chromium via Playwright for web projects. For CLI-only projects, evaluator uses exit codes and stdout instead of Playwright. `ensure-dev-server.sh` should detect project type and skip server start for CLI projects.

---

## 15. BUILD ORDER & DEPENDENCIES

Organized into build phases. Each phase depends on the previous.

### Phase A: Prerequisites & Foundation
1. Verify ALL required tools on Windows (each must return version or clear error):
   - `bash --version` (Git Bash — note install path, e.g. `C:/Program Files/Git/bin/bash.exe`)
   - `jq --version` (if missing: `winget install jqlang.jq` or download binary from github.com/jqlang/jq/releases)
   - `curl --version` (bundled with Git Bash)
   - `claude --version` (Claude Code CLI — if missing, install via npm or standalone)
   - `grep -P "test" <<< "test"` (verify PCRE support — if fails, use `grep -E` fallback in all scripts)
   - `git config --global core.autocrlf input` (enforce LF on commit)
   - `node --version` (for Playwright/dev servers — optional for CLI-only projects)
2. Create `C:\Users\exrov\.claude\` directory structure: `scripts/`, `agents/`, `hooks/`
3. Create `settings.json` with hook registrations (scoped to Write/Edit, using explicit bash.exe path from step 1)

### Phase B: Layer 1 Core Scripts (Harness Lifecycle)
Build order matters — later scripts depend on earlier ones:

4. `notify.sh` (no dependencies — standalone Telegram sender)
5. `write-handoff.sh` (depends on: git, state file conventions)
6. `check-budget.sh` (depends on: `notify.sh`, `write-handoff.sh`)
7. `wait-for-human.sh` (depends on: `notify.sh`, `write-handoff.sh`)
8. `git-checkpoint.sh` (depends on: git)
9. `run-claude-safe.sh` (depends on: `notify.sh`, `write-handoff.sh`)
10. `telegram-poll.sh` (depends on: `notify.sh`, Telegram Bot Token)
11. `startup-recovery.sh` (depends on: `write-handoff.sh`, `notify.sh`)
12. `ensure-dev-server.sh` (depends on: curl)
13. `init-project.sh` (depends on: directory structure conventions)

### Phase C: Layer 2 Deterministic Guards
14. `detect-loop.sh` (depends on: git, `notify.sh`)
15. `validate-phase.sh` (depends on: file conventions from Phase B)
16. `validate-state-transition.sh` (depends on: state machine definition)
17. `verify-fix-applied.sh` (depends on: known-fixes format)
18. `evaluate-protocol-compliance.sh` (depends on: `detect-loop.sh`, `validate-phase.sh`, `verify-fix-applied.sh`)

### Phase D: Layer 3 Agent Definitions
19. `planner.md` (depends on: understanding of high-level spec format)
20. `generator.md` (depends on: TDD protocol, sprint contract format)
21. `evaluator.md` (depends on: 7-layer verification protocol, evidence bundle format)
22. `cross-examiner.md` (depends on: evidence bundle format)

### Phase E: Hooks
23. `post-write-check.sh` (depends on: `validate-phase.sh`)
24. `pre-phase-start.sh` (depends on: known-fixes format)
25. `on-stuck-detected.sh` (depends on: `detect-loop.sh`, `notify.sh` — note: `wait-for-human.sh` is called by the harness AFTER this hook fires, not by the hook itself)
26. `on-test-failure.sh` (depends on: known-fixes format, `notify.sh`)
27. `on-session-end.sh` (depends on: `.agent-memory/` structure for session summaries)

### Phase F: Outer Loop Assembly
28. `run-harness.sh` (depends on: ALL of the above — this is the final assembly that wires everything together. Note: listed as script #1 in Section 3.1's table for logical ordering, but built LAST because it orchestrates all other scripts)

### Phase G: Per-Project Template
29. `init-project.sh` refinement — test on a real project (must create: state/, state/evaluation-results/, specs/, contracts/, protocols/, evidence/)
30. CLAUDE.md template finalization (minimal — points to active-instructions.md, sets 4 universal constraints)
30b. `known-fixes.md` template creation (structured format with `## Verify` section, three check types: file_exists, file_contains, test_passes)

### Phase H: Integration & Registry Updates

**Must cross-reference Section 13 (Integration Table) to ensure all `.agent-memory/` integration points are covered.**

31. Register all 16 scripts + 4 agents + 5 hooks (25 total) in `.agent-memory/procedural/scripts/SCRIPT_REGISTRY.json` using schema:
```json
{
  "scripts": [
    {
      "id": "script_001",
      "name": "run-harness.sh",
      "layer": 1,
      "type": "harness|guard|agent|hook",
      "path": "$HOME/.claude/scripts/run-harness.sh",
      "purpose": "Outer loop driving state machine",
      "dependencies": ["all"],
      "tested": false,
      "last_verified": null
    }
  ],
  "total": 25
}
```
32. Register full harness cycle workflow in `.agent-memory/procedural/workflows/WORKFLOW_REGISTRY.json` using schema:
```json
{
  "workflows": [
    {
      "id": "workflow_001",
      "name": "harness-full-cycle",
      "phases": ["PLAN","NEGOTIATE","BUILD","EVALUATE","COMPLETE"],
      "scripts_per_phase": {
        "PLAN": ["run-harness.sh","planner.md","pre-phase-start.sh"],
        "NEGOTIATE": ["run-harness.sh","generator.md","evaluator.md"],
        "BUILD": ["run-harness.sh","generator.md","detect-loop.sh","on-stuck-detected.sh","on-test-failure.sh"],
        "EVALUATE": ["evaluate-protocol-compliance.sh","evaluator.md","cross-examiner.md"],
        "COMPLETE": ["git-checkpoint.sh","on-session-end.sh","write-handoff.sh"]
      },
      "gate_conditions": {
        "PLAN_to_NEGOTIATE": "validate-phase.sh phase 1 passes",
        "NEGOTIATE_to_BUILD": "sprint-N-contract.md exists",
        "BUILD_to_EVALUATE": "phase-complete-marker.md written + validate-phase.sh passes",
        "EVALUATE_to_COMPLETE": "verification.result.json overall_verdict=PASS"
      }
    }
  ]
}
```
33. Update `.agent-memory/semantic/knowledge-graph.json` with three-layer architecture nodes and relationships
34. Create/update 4 domain knowledge files in `.agent-memory/semantic/domain/`: three-layer-architecture.md, enforcement-mechanisms.md, failure-modes.md, protocol-fidelity.md
35a. Cross-reference Section 13 integration requirements: update `meta/confidence.json` as scripts pass tests, ensure `episodic/decisions/` logging is wired, verify `prospective/backlog.json` reflects remaining work

### Phase I: Testing & Calibration

**Individual script tests (Layer 1 — 10 core scripts; run-harness.sh tested separately in end-to-end #61)**:
35. Test `notify.sh` — sends message; when Telegram unavailable (no token/no network), degrades gracefully (no crash, returns 0)
36. Test `write-handoff.sh` — generates complete handoff with all 8 sections from disk state
37. Test `run-claude-safe.sh` — retries on failure, exponential backoff (60→120→240s), final block writes handoff
38. Test `ensure-dev-server.sh` — starts Node server, starts Python server, handles already-running, fails cleanly if no project
39. Test `startup-recovery.sh` — cleans stale lockfile, kills orphaned PID, writes fresh handoff
39a. Test `check-budget.sh` — fires at time limit, fires at cost limit, returns 0 when within budget
39b. Test `wait-for-human.sh` — blocks until human-response.md appears; times out correctly; generates resume-on-reply.sh on timeout
39c. Test `telegram-poll.sh` — writes heartbeat file; writes human-response.md on message receipt (or skip if no Telegram configured)
39d. Test `git-checkpoint.sh` — commits when changes exist; no-op when no changes; correct message format
39e. Test `init-project.sh` — creates all required directories and files (verified in structural test #57)

**Individual script tests (Layer 2)**:
40. Test each Layer 2 script individually with known inputs/outputs
41. Test `detect-loop.sh` with deliberately repeated file modifications — verify it blocks
42. Test `verify-fix-applied.sh` with structured verify format — all three check types

**Integration tests**:
43. Test phase transitions end-to-end (PLAN -> NEGOTIATE -> BUILD -> EVALUATE -> COMPLETE)
44. Test known-fix injection with planted symptoms — verify fix appears in `next-fix.md`
45. Test evaluator calibration gate (plant deliberate failure, verify evaluator catches it)
46. Test cross-examiner doubt protocol (evaluator passes, cross-examiner finds planted gap)
47. Test crash recovery (kill harness mid-session, verify clean restart with fresh handoff)
48. Test budget circuit breaker (set low time/cost limits, verify hard stop with state save)
49. Test concurrency protection (run two harness instances, verify mkdir-based lockdir blocks second)
50. Test on-session-end hook (verify episodic summary written, MEMORY_MANIFEST updated)

**Windows-specific tests**:
51. Test Claude Code hook execution — trigger Write/Edit, verify bash hook fires correctly
52. Test CRLF handling — create file with CRLF, verify grep patterns still match
53. Test PATH resolution — verify `claude`, `jq`, `bash` all accessible from hook context
54. Test Playwright availability — verify Chromium installed and evaluator can screenshot

**Structural verification** (confirm artifacts exist and are well-formed):
55. Verify all 4 agent definitions load correctly — planner, generator, evaluator, cross-examiner contain required sections
56. Verify all 5 hooks/harness-internal scripts execute — trigger each one and confirm expected output file created
57. Verify init-project.sh creates all required directories (state/, state/evaluation-results/, specs/, contracts/, protocols/, evidence/) and files (CLAUDE.md, known-fixes.md, current-phase.json)
58. Verify SCRIPT_REGISTRY.json is valid JSON, contains 25 entries (16 scripts + 4 agents + 5 hooks), all paths resolve to existing files
59. Verify WORKFLOW_REGISTRY.json is valid JSON, phase-to-script mapping matches actual scripts, gate conditions reference real validators
60. Verify domain knowledge docs exist in `.agent-memory/semantic/domain/` — all 4 files present and non-empty
60a. Cross-reference integrity: every script in WORKFLOW_REGISTRY exists in SCRIPT_REGISTRY; every Phase H integration from Section 13 is satisfied

**End-to-end**:
61. Full harness run on a trivial project (simple CLI tool through ALL phases: PLAN -> NEGOTIATE -> BUILD -> EVALUATE -> COMPLETE/ACCEPTED)

### Phase J: Documentation & Session End
62. Write episodic decision log for architectural choices made during build
63. Write session summary
64. Update MEMORY_MANIFEST.json

---

## 16. TOTAL COMPONENT COUNT

| Category | Count |
|----------|-------|
| Layer 1 Scripts (Harness) | 11 |
| Layer 2 Scripts (Deterministic Guards) | 5 |
| Layer 3 Agent Definitions | 4 |
| Hooks | 5 (post-write-check, pre-phase-start, on-stuck-detected, on-test-failure, on-session-end) |
| Configuration Files | 1 (settings.json) |
| Per-Project Templates | 2 (CLAUDE.md, known-fixes.md) |
| Registry Updates | 3 (script, workflow, knowledge graph) |
| Domain Knowledge Docs | 4 (architecture, enforcement, failure modes, protocol fidelity) |
| **Total components to build** | **35** |
| Testing scenarios | **33** (10 Layer 1 + 3 Layer 2 + 8 integration + 4 Windows + 7 structural + 1 end-to-end) |
| **Total work items** | **70+** |

---

## 17. WHAT THIS SCOPE DOES NOT COVER (EXPLICIT EXCLUSIONS)

- **Telegram Bot creation** — documented how to use it, but creating the bot via BotFather is a manual step Adewale does himself
- **WhatsApp/Twilio integration** — architecture supports it, but not building it in this scope
- **Multi-model orchestration** — architecture is ready for it, but this scope builds for single-model (Opus 4.6) first
- **Playwright MCP setup** — evaluator uses it, but MCP server configuration is a separate setup task
- **Specific project deployments** — this builds the infrastructure; deploying to specific projects is subsequent work
- **VS Code extension for blocked-state UI** — mentioned as possible alternative to Telegram; not in scope
- **Model-specific agent variants** (e.g., generator-codex.md, evaluator-minimax.md, SKILL-codex.md, SKILL-minimax.md) — architecture supports them, model profiles document them, but this scope builds only the 4 base agents targeting Opus 4.6. Variants are added per model as they're integrated.

---

## 18. SUCCESS CRITERIA

The deployment is complete when:

1. All 16 scripts exist in `C:\Users\exrov\.claude\scripts\` and are executable
2. All 4 agent definitions exist in `C:\Users\exrov\.claude\agents\`
3. All 5 hooks exist in `C:\Users\exrov\.claude\hooks\`
4. `settings.json` is configured with Write/Edit-scoped hooks
5. `init-project.sh` successfully sets up a new project with all required directories and files
6. `run-harness.sh` drives a trivial task through all 5 states (REQUESTED -> ACCEPTED)
7. Loop detector catches a deliberately planted negative loop
8. Known-fix injection works: planted symptom -> fix appears in `next-fix.md`
9. Evaluator calibration gate catches a deliberately planted failure
10. Budget circuit breaker fires at configured limits
11. Crash recovery restores clean state after simulated crash
12. All scripts registered in `SCRIPT_REGISTRY.json`
13. All workflows registered in `WORKFLOW_REGISTRY.json`
14. Domain knowledge docs written in `.agent-memory/semantic/domain/`

---

*This scope document is the CONTRACT for the full Harness Infrastructure deployment. It must pass 5 independent verification loops before implementation begins.*
