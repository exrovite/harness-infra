# Enforcement Stack Report — Enhanced Agent Harness

**Date**: 2026-04-13
**System**: Enhanced Agent Harness (Claude Code hooks, bash scripts, deterministic enforcement)
**Platform**: Windows 10 / Git Bash (MSYS2)

---

## Overview

The harness enforces agent behavior through Claude Code hooks — bash scripts that fire on specific tool events. These are not instructions that the agent can ignore. They are deterministic gates that block tool execution at the platform level. If a hook exits non-zero, the tool call is rejected before it reaches the filesystem.

All enforcement is configured in `~/.claude/settings.json` via the `hooks` section. The hooks are organized by event type:

| Event | When It Fires | Scripts |
|-------|--------------|---------|
| **PreToolUse** (Write\|Edit\|Agent) | Before any file write or agent spawn | `pre-write-gate.sh` |
| **PreToolUse** (Write\|Edit) | Before any file write (after pre-write-gate) | `pre-flight-gate.sh` |
| **PreToolUse** (Bash) | Before any shell command | `pre-bash-gate.sh` |
| **PostToolUse** (Write\|Edit) | After every file write | `post-write-check.sh` |
| **PostToolUse** (Bash) | After every shell command | `collect-test-evidence.sh` |
| **PostToolUse** (Agent) | After every sub-agent spawn | `agent-call-tracker.sh` |
| **UserPromptSubmit** | Start of every agent turn | `on-prompt-submit.sh` |
| **Stop** | When session ends | `on-session-end.sh` |

Hooks run top-to-bottom within each event. PreToolUse hooks are blocking gates (exit 2 = reject). PostToolUse hooks are observers and state updaters. UserPromptSubmit injects context into the agent's prompt.

---

## Layer 1: Phase Gate

**Hook**: `pre-write-gate.sh` (lines 21–75)
**Mirror**: `pre-bash-gate.sh` (lines 77–102)
**Fires**: Every Write, Edit, Agent call, and file-writing Bash command
**Applies to**: All projects with `.claude/state/current-phase.json`

### What It Does
Enforces the state machine: PLAN → NEGOTIATE → BUILD → EVALUATE → COMPLETE. Only the BUILD phase allows source code writes. In all other phases, writes to source files are blocked.

### What It Blocks
- PLAN: "Source code writes are not allowed. Write your spec to `.claude/specs/`."
- NEGOTIATE: "Source code writes are not allowed. Write your sprint contract."
- EVALUATE: "Spawn an independent verifier — don't write code yourself."
- COMPLETE: "Start a new sprint if more work is needed."

### Exemptions
Infrastructure paths are always writable: `.claude/state/`, `.claude/specs/`, `.claude/contracts/`, `.openclaw/watchers/`, `.agent-memory/`, `.claude/pre-flight/`, `agentwiki/`. Markdown files (`.md`) are allowed in all phases. The Agent tool is exempt (spawning sub-agents doesn't write files directly).

---

## Layer 2: Contract Gate

**Hook**: `pre-write-gate.sh` (lines 77–107)
**Fires**: Every Write, Edit, and file-writing Bash command during BUILD phase
**Applies to**: All projects in BUILD phase

### What It Does
Requires a sprint-specific contract file before any code can be written during BUILD. The contract is the scope boundary — without it, work drifts.

### What It Blocks
If `.claude/contracts/sprint-{N}-contract.md` does not exist for the current sprint number: "BUILD phase requires a contract for sprint N. You MUST complete the NEGOTIATE phase first."

### Exemptions
Same infrastructure paths as Layer 1. The Agent tool is exempt to prevent deadlocks (verifier sub-agents need to spawn during BUILD even if contract details are being finalized).

---

## Layer 3: Strategy Loop Breaker

**Hook**: `pre-write-gate.sh` (lines 109–224) — block gate
**Mirror**: `pre-bash-gate.sh` (lines 115–196)
**Detection**: `detect-strategy-loop.sh` — called by `on-prompt-submit.sh`
**Logging**: `collect-test-evidence.sh` — logs failures with fingerprints
**Fires**: Detection runs every prompt. Block gate runs every write.
**Applies to**: All projects

### What It Does
Detects when an agent is repeating the same failing approach and escalates in two tiers:

**Detection** (3-signal conjunction — all 3 must fire):
1. Same output fingerprint repeating (3+ consecutive failures with identical error hash)
2. Consecutive command failures without success (3+ in a row)
3. Same files edited between failures (same file churned in 3+ failure entries)

**Tier 1 — Nudge** (injected into prompt via `on-prompt-submit.sh`):
- "You appear to be repeating the same failing approach."
- Lists must-do files with "mistake" files marked as PRIORITY
- 60-second cooldown between nudge increments

**Tier 2 — Block** (hard gate in `pre-write-gate.sh` and `pre-bash-gate.sh`):
- All source code writes blocked
- Agent must write `strategy-ack.md` with:
  - `## New Approach` section header
  - 150+ characters describing the new strategy
  - Reference to at least one must-do file basename (if must-do folder exists)
- On valid ack: block clears, state resets, failure log truncated

### Reset Conditions
- Output fingerprint changes (different error = different problem)
- Churn files change (editing different files = new approach)
- Success entry logged (a test passed)
- `agent-blocked.md` exists (external block takes priority)

---

## Layer 4: Must-Do Summary Gate

**Hook**: `pre-write-gate.sh` (lines 226–365)
**Injection**: `on-prompt-submit.sh` (lines 75–90)
**Fires**: Every Write/Edit when project has a must-do folder
**Applies to**: Projects with `docs/must do/`, `docs/must-do/`, or `.claude/must-do/` containing `.md` files

### What It Does
Forces the agent to read required process documents and write a summary before any code. The summary proves comprehension and is injected into every subsequent prompt so the agent sees it while working.

### What It Blocks
Source code writes are blocked until `.claude/state/must-do-summary.md` exists and meets all criteria:
- At least 200 characters long
- References at least one must-do file by basename
- Not stale (if watcher step has changed, summary must be refreshed within 5 minutes)

### Prompt Injection
When the summary exists, it is truncated to 800 chars and injected as `[MUST-DO ACTIVE] {summary text}` into every agent prompt via `on-prompt-submit.sh`. This keeps the process requirements visible during execution, not just at the entry gate.

### Staleness Detection
Tracks the current watcher step in `must-do-summary-step.txt`. When the agent moves to a new checklist item, the summary is considered stale and must be refreshed — unless it was modified within the last 5 minutes.

---

## Layer 5: Evidence Checkpoint System

**Hook**: `pre-write-gate.sh` (lines 367–428) — block gate
**Mirror**: `pre-bash-gate.sh` (lines 198–233)
**Trigger**: `post-write-check.sh` (lines 219–290) — counter + trigger
**Builder**: `create-evidence-checkpoint.sh` — builds the verifier brief
**Injection**: `on-prompt-submit.sh` (lines 92–96)
**Fires**: Periodically (every N writes) when must-do summary exists
**Applies to**: Projects with a must-do folder AND must-do summary

### What It Does
Periodic mid-execution verification. After every N writes (default 15, configurable), the harness assembles a checkpoint brief containing:

1. **Must-do source files** — the actual process documents (up to 3000 chars each), read directly by the harness. The builder agent does not control what the verifier sees.
2. **Must-do summary** — what the agent declared it would do
3. **Watcher checklist** — the agent's step-by-step plan with checked/unchecked items
4. **Modified files** — what the agent has actually touched
5. **Agent-provided paths** — files the agent claims contain evidence (from previous FAIL cycles)
6. **Verifier instruction** — tells the sub-agent exactly what to check and how to report

All source code writes are blocked until a verifier sub-agent reads the brief, checks each declared phase for evidence, and writes a verdict.

### Trigger Conditions
- **Write count**: fires when checkpoint counter reaches threshold (default 15). Only triggers when no checkpoint is already pending.
- **Step change**: fires immediately when the watcher checklist step changes (catches agents that check off items without doing the work). **Replaces stale checkpoints** — if a pending checkpoint exists from a previous step or session, it is cleared along with its verdict, remediation plan, and agent-provided paths, then a new checkpoint is built for the current work. This prevents agents from being blocked by checkpoints for work they're no longer doing.

### Verdict Handling
- **PASS**: checkpoint, verdict, and paths files cleared. Counter resets. Writes resume.
- **FAIL**: writes stay blocked. Verifier findings shown (phase name + what's missing). Agent can:
  1. Produce the missing evidence, then delete the verdict file to re-verify
  2. Write file paths to `evidence-paths.json` if evidence exists elsewhere, then delete verdict to re-verify
- **No verdict yet**: writes blocked with instruction to spawn a verifier sub-agent

### Bug Fixes (Sprint 15)

The checkpoint system was completely inert from initial deployment until sprint 15 — `create-evidence-checkpoint.sh` failed silently on every invocation due to three MSYS/Windows-specific bugs:

1. **MSYS sed crash**: `sed 's/\\/\\\\/g; s/"/\\"/g'` used for JSON escaping crashes on Git Bash with "unknown option to 's'". Fix: removed sed entirely — jq `--arg` handles JSON escaping natively.
2. **Windows command-line length limit (exit 126)**: Must-do source files (32KB+) passed as `--argjson` shell arguments exceeded the OS argument limit. Fix: write large values to temp files, use jq `--slurpfile`/`--rawfile` to read them.
3. **Subshell pipe problem**: `grep | while` runs the while-loop in a subshell — temp file modifications don't persist after the pipe. Fix: process substitution `< <(grep ...)` keeps the loop in the main shell.

### Remediation Gate (Sprint 17)

When a verifier returns FAIL, the agent previously could write new evidence files immediately without consulting the must-do documentation — producing the same low-quality work. The remediation gate forces a documentation-review step:

**On FAIL verdict, `.claude/evidence/` writes are conditionally blocked.** The agent must:
1. Read the must-do documentation (enforced indirectly — the plan must reference it)
2. Write a remediation plan to `.claude/state/evidence-remediation.md`
3. The plan is validated against three criteria:
   - **Length**: 200+ characters
   - **Phase reference**: must mention at least one failed phase name from the verdict's `findings[].phase`
   - **Document reference**: must mention at least one must-do file basename

Only when all three criteria pass does `.claude/evidence/` become writable again. The agent then produces evidence and deletes the verdict file to trigger re-verification.

**Injection states** (via `on-prompt-submit.sh`):
- FAIL without valid plan: "Writes blocked. Read must-do docs and write remediation plan."
- FAIL with valid plan: "Remediation accepted. Produce evidence, delete verdict, spawn verifier."

On PASS or new checkpoint, stale `evidence-remediation.md` is automatically cleared.

### Verdict File Injection (Sprint 18)

Verifier sub-agents weren't writing verdicts to file because the instruction was buried in the checkpoint brief's `instruction` field, which they only see if they read the brief. Sprint 18 added explicit verdict file path and JSON format to three independent channels:

1. **Prompt injection** (`on-prompt-submit.sh`): both builder and verifier see the verdict path and format every turn
2. **Block message** (`pre-write-gate.sh`): shown when writes are blocked pending verification
3. **Checkpoint brief** (`create-evidence-checkpoint.sh`): the `instruction` field (unchanged, but now reinforced)

Verdict format: `{"verdict":"PASS|FAIL","findings":[{"phase":"X","evidence_file":"path|null","quality":"substantive|insufficient|null","note":"details"}],"summary":"text"}`

### Configuration
- `checkpoint-config.json`: `{"interval": N}` (0 = disabled, default 15)
- Projects without must-do folder: system is completely dormant

---

## Layer 6: Pre-Flight MCQ Gate

**Hook**: `pre-flight-gate.sh`
**Generator**: `generate-pre-flight-challenge.sh`
**Validator**: `validate-pre-flight.sh`
**Fires**: Every Write/Edit (after pre-write-gate passes)
**Applies to**: All projects with a watcher claimed

### What It Does
Generates a multiple-choice quiz derived from the agent's watcher slot content. The agent must answer correctly before each write is allowed. Questions test:

1. **Q1**: What is your current task? (from watcher slot Task field)
2. **Q2**: Which step are you currently on? (from first unchecked TO-DO item)
3. **Q3**: What file should this edit target? (from the actual file path being written)
4. **Q4**: What should you avoid? (from MISTAKES TO AVOID / OUT OF SCOPE sections)
5. **Q5**: Have you done work that needs independent verification? (tracks verification debt)

Distractors are drawn from `~/.openclaw/distractor-pool/` (4 files, 60 entries each, randomized). Correct answers are shuffled — no fixed position.

### What It Blocks
If the agent answers any question wrong: "PRE-FLIGHT CHECK FAILED" with specifics.

If Q5 "yes" counter exceeds 5 without spawning a verifier: hard block requiring an Agent tool call with verification language before continuing.

### Must-Do Integration
When a must-do folder exists, additional questions (Q6, Q7, ...) are generated — one per must-do file, testing whether the agent can identify the file's purpose from its content.

### Phase Feedback Hard Block
If `phase-feedback.md` contains "FAIL", the pre-flight gate blocks all source code writes regardless of MCQ answers. The agent must fix the validation failure first.

---

## Layer 7: Bash Bypass Gate

**Hook**: `pre-bash-gate.sh`
**Fires**: Every Bash tool call
**Applies to**: All projects with harness state

### What It Does
Detects file-writing patterns in shell commands and applies the same enforcement as Write/Edit gates. Prevents agents from bypassing all PreToolUse Write/Edit hooks by writing files through `python3 -c`, `echo >`, `tee`, `sed -i`, `cat <<EOF >`, `cp`, `mv`, or `node -e fs.writeFileSync`.

### Detection Patterns
1. Python/node/ruby with file I/O keywords (`open`, `write`, `Path`, `fs.`)
2. `tee` command
3. `sed -i` (in-place editing)
4. Shell redirects to project-relative paths (`echo/printf/cat ... > file`)
5. Heredoc writes (`<< ... >`)
6. `cp`/`mv` to project-relative destinations

### Enforcement Applied
When a file-writing pattern is detected, the gate applies (in order):
1. Phase gate (only BUILD allows writes)
2. Phase feedback block (FAIL = blocked)
3. Strategy loop block (same ack requirement)
4. Evidence checkpoint block (same verifier requirement, including remediation gate — FAIL verdict conditionally blocks `.claude/evidence/` writes until valid remediation plan exists)
5. Watcher/cron enforcement (same claim requirement)

### Bootstrap Exemptions
Critical paths are always writable via Bash to prevent catch-22 deadlocks: `.openclaw/watchers/`, `.claude/state/`, `.claude/pre-flight/`, `.claude/contracts/`, `.claude/specs/`, `.agent-memory/`, `agentwiki/`. Without these, agents couldn't claim watchers or update harness state to unblock themselves.

---

## Layer 8: Watcher/Cron Enforcement

**Hook**: `pre-write-gate.sh` (lines 430–496)
**Mirror**: `pre-bash-gate.sh` (lines 235–256)
**Self-check**: `post-write-check.sh` (lines 39–80)
**Fires**: Every Write, Edit, Agent call, and file-writing Bash command after 2 writes
**Applies to**: All projects

### What It Does
After 2 free writes, all further Write/Edit/Agent tools are locked until the agent has BOTH:
1. A watcher slot claimed for THIS specific project (project path must match)
2. A 3-minute cron reminder registered in the watcher registry

### What It Blocks
- No watcher: "Write/Edit/Agent tools are LOCKED after N writes. You need BOTH a watcher AND a cron reminder FOR THIS PROJECT."
- Watcher but no cron: "Watcher is claimed but NO CRON REMINDER is set up. Without the cron, you will forget your to-do list and drift."

### Project Scoping
The gate normalizes project paths (lowercase, forward slashes, no trailing slash) and matches against watcher registry entries. A watcher for Project A does not unlock Project B.

### Self-Check Prompt
After 5+ writes without a watcher, `post-write-check.sh` creates `watcher-self-check.md` prompting the agent to ask itself: "Am I doing a multi-step task? Could I drift? Should I claim a watcher?"

---

## Layer 9: Phase Validation

**Hook**: `post-write-check.sh` (lines 177–217)
**Validator**: `validate-phase.sh`
**Fires**: When agent writes `phase-complete-marker.md`
**Applies to**: All projects

### What It Does
When an agent declares a phase complete by writing the marker file, the hook runs `validate-phase.sh` which checks whether the phase's requirements are actually met:

- **PLAN**: spec file exists in `.claude/specs/`
- **NEGOTIATE**: contract file exists in `.claude/contracts/`
- **BUILD**: tests pass, implementation exists
- **EVALUATE**: verifier has been spawned and produced a verdict

### What Happens on Failure
Writes `phase-feedback.md` with "FAIL" and the validation output. This triggers the Phase Feedback Hard Block in Layer 6 (pre-flight gate), blocking all source code writes until the agent fixes the issue.

### What Happens on Success
Logs the phase transition to `transitions.jsonl` (append-only). The agent can then advance to the next phase.

---

## Layer 10: TDD Enforcement (Phantom TDD Detection)

**Hook**: `post-write-check.sh` (lines 140–175)
**Detection**: 5 signals tracked via `tdd-events.jsonl`
**Fires**: During BUILD phase when TDD is required (`tdd-config.json`)
**Applies to**: Projects with TDD enabled

### What It Does
Detects "phantom TDD" — when agents claim to follow Test-Driven Development but actually don't. Tracks:

1. **Test file writes**: Detects test file naming patterns (`test_*.py`, `*.test.js`, `*_spec.rb`, etc.) and directory patterns (`tests/`, `__tests__/`, `spec/`)
2. **Test execution**: Tracks whether tests were actually run after being written
3. **Failure-first**: Checks whether tests failed before implementation (the core TDD requirement)
4. **Implementation timing**: Detects if implementation was written before or after tests

### Enforcement
When phantom TDD is detected, the agent is blocked from continuing until genuine TDD evidence exists.

---

## Layer 11: Prompt Injection (Context Awareness)

**Hook**: `on-prompt-submit.sh`
**Fires**: Start of every agent turn (before the agent sees the user's message)
**Applies to**: All projects

### What It Injects
A single line prepended to every prompt containing:

1. **Harness state**: `[HARNESS STATE] Phase: BUILD | Sprint: 19 | Iter: 0 | Writes: 530 | Watcher: claimed (4 active)`
2. **Lock warning** (if tools locked): "You MUST claim a watcher using Bash before you can Write/Edit any files."
3. **Pending items**: phase feedback, next-fix, watcher self-check
4. **Must-do summary** (if exists): `[MUST-DO ACTIVE] {truncated summary}`
5. **Evidence checkpoint** (if pending) — three distinct states:
   - **No verdict yet**: "Writes blocked until verified. If you are the builder: spawn a verifier sub-agent. If you are the verifier: read `.claude/state/evidence-checkpoint.json`. Write your verdict to `.claude/state/evidence-verdict.json` as JSON: `{verdict, findings, summary}`."
   - **FAIL without valid remediation plan**: "Writes blocked. Read must-do docs and write remediation plan to `.claude/state/evidence-remediation.md` (200+ chars, reference failed phases and docs)."
   - **FAIL with valid remediation plan**: "Remediation accepted. Produce evidence in `.claude/evidence/`, then delete verdict file and spawn a new verifier."
6. **Strategy loop nudge/block** (if detected): Tier 1 nudge with file list, or Tier 2 block warning

This ensures the agent is always aware of its current state and obligations. Sub-agents in the same project directory trigger the same hook, so injections reach them without the builder controlling the prompt. The verdict format is included in the checkpoint injection so verifier sub-agents know exactly where and how to write their verdict — they don't need to find the instruction buried in the checkpoint brief.

---

## Layer 12: Session Lifecycle

**Startup**: `startup-recovery.sh` (called by `post-write-check.sh` on first write)
**Shutdown**: `on-session-end.sh` (Stop hook)
**Applies to**: All projects

### Startup Recovery
On first write of a new session:
- Clears stale artifacts: `phase-complete-marker.md`, `agent-blocked.md`
- Resets strategy loop state: clears `bash-failure-log.jsonl`, `strategy-ack.md`, resets `strategy-loop-state.json`
- Cleans stale watchers: any watcher claimed > 4 hours ago for this project is reset to available
- Clears phantom cron references: removes `cron_job_id`/`cron_interval` from active watchers (crons die with sessions)
- Auto-removes stale `phase-feedback.md` (> 2 hours old)

### Session End
On Stop event:
- Writes session summary to `.agent-memory/episodic/sessions/`
- Updates `MEMORY_MANIFEST.json` with session count and timestamp
- Writes `active-tasks.json` for next session resume
- Processes wiki dropbox if entries exist

---

## Layer 13: File Write Tracking

**Hook**: `post-write-check.sh` (lines 125–138)
**Fires**: Every Write/Edit
**Applies to**: All projects

### What It Does
Logs every file write (excluding harness infrastructure paths) to `unverified-writes.jsonl` with timestamp and file path. This provides:

1. An audit trail of what the agent has modified
2. Input to the pre-flight Q5 verification debt tracker
3. Data for the evidence checkpoint's modified files list
4. Evidence for the strategy loop breaker's file churn detection

---

## Layer 14: Agent Call Tracking

**Hook**: `agent-call-tracker.sh` (PostToolUse on Agent)
**Fires**: After every sub-agent spawn
**Applies to**: All projects

### What It Does
Tracks sub-agent spawns for the pre-flight Q5 verification ledger. When a sub-agent is spawned with verification language (verify, review, evaluate, validate, audit, assess), the Q5 "no verification needed" counter resets. This prevents agents from accumulating unlimited verification debt.

---

## Enforcement Stack Order (Write/Edit)

When an agent calls Write or Edit, gates fire in this exact order:

```
1. allow-claude-dir.sh     — filesystem permission helper
2. pre-write-gate.sh       — ALL blocking gates:
   a. Phase gate            — only BUILD allows code writes
   b. Contract gate         — BUILD requires sprint contract
   c. Strategy loop block   — blocked if looping, needs ack
   d. Must-do summary gate  — needs summary before code
   e. Evidence checkpoint   — needs verifier PASS
   f. Watcher/cron gate     — needs watcher + cron after 2 writes
3. pre-flight-gate.sh      — MCQ comprehension test
   a. Phase feedback block  — blocks if validation failed
   b. MCQ generation        — quiz from watcher slot
   c. MCQ validation        — check answers
   d. Verification debt     — force verifier after 5 skips
```

If ANY gate returns exit 2, the write is rejected. The agent sees the error message and must address it before retrying.

---

## Enforcement Stack Order (Bash)

When an agent calls Bash, the gate fires only if a file-writing pattern is detected:

```
1. pre-bash-gate.sh        — pattern detection + blocking:
   a. File-write detection  — grep for write patterns
   b. Bootstrap exemptions  — harness paths always allowed
   c. Phase gate            — only BUILD allows code writes
   d. Phase feedback block  — blocks if validation failed
   e. Strategy loop block   — same as Write/Edit
   f. Evidence checkpoint   — same as Write/Edit
   g. Watcher/cron gate     — same as Write/Edit
```

Non-file-writing Bash commands (ls, git, npm test, etc.) pass through unblocked.

---

## Projects Without Must-Do Folders

These layers still apply to ALL projects:

| Layer | Enforcement |
|-------|------------|
| Phase gate | Only BUILD allows code writes |
| Contract gate | BUILD needs sprint contract |
| Strategy loop breaker | Detects repeated failures, nudge → block |
| Watcher/cron gate | Must claim watcher + cron after 2 writes |
| Pre-flight MCQ | Task awareness quiz (Q1–Q5) |
| Bash bypass gate | Prevents shell-based Write/Edit bypass |
| Phase validation | Checks phase completion requirements |
| Session lifecycle | Startup recovery, session summaries |
| File write tracking | Audit trail of all modifications |
| Prompt injection | State + lock warnings every turn |

These layers are **additional** for projects WITH must-do folders:

| Layer | Enforcement |
|-------|------------|
| Must-do summary gate | Must read process docs and write summary |
| Must-do prompt injection | Summary visible every turn |
| Must-do MCQ questions | Additional Q6+ testing process comprehension |
| Evidence checkpoint | Periodic mid-execution verification |
| Strategy loop must-do ref | Ack must reference must-do file basenames |

---

## Design Principles

1. **Hard over soft**: Bash scripts block tool calls deterministically. Markdown instructions degrade under token pressure.
2. **Layer discipline**: Layer 1 (harness lifecycle) controls Layer 2 (deterministic guards) controls Layer 3 (LLM judgment). Never use a higher layer for something a lower layer can do.
3. **Builder/verifier separation**: The agent that does the work cannot verify its own work. Verifiers are independent sub-agents that test from scratch.
4. **Harness-controlled context**: The harness assembles what the verifier sees. The builder cannot filter, summarize, or editorialize the evidence.
5. **Iterative feedback**: FAIL is not a dead end. The system tells the agent exactly what's missing and provides a path to unblock.
6. **Bootstrap safety**: Infrastructure paths are always writable to prevent catch-22 deadlocks where the agent can't fix what's blocking it.
7. **Project scoping**: Watchers, path matching, and enforcement are all scoped to the specific project directory. Work in Project A doesn't affect enforcement in Project B.
8. **Zero impact without opt-in**: Must-do enforcement, evidence checkpoints, and TDD detection only activate when the project has the relevant configuration. Projects without these are still protected by the universal layers.
