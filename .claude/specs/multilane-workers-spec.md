# Multilane Workers — Product Spec (Sprint 31)

## Problem
The harness is single-tenant per project: phase, contracts, pre-flight, evidence,
must-do, counters, and the global 5-slot watcher pool all assume ONE Claude Code
instance per project folder. A second instance in the same folder clobbers state.
The watcher pool is also a GLOBAL cap of 5 across all projects, so concurrent
projects starve each other.

Goal: run up to 5 concurrent Claude Code instances in the SAME project folder,
each isolated so none confuses its work with another's — WITHOUT diluting the
harness's core property: the model is always aware of where it is, what it is
doing, what is next, and why it is blocked. No surprises.

## Core model (decisions locked)
- **Identity = session_id** (Claude Code stamps every hook). Enforcement keys off
  session_id, never project-path matching. (Kills the project-match bug class.)
- **Global registry, v2**, `~/.openclaw/watchers/REGISTRY.json`: a list of active
  instances keyed by session_id; `project` retained only for lane-numbering, the
  per-project cap, and the readable dashboard. One file = one global view + one lock.
- **Lane 1 == today's flat layout. Lanes 2-5 == subdirs.** Zero migration; a single
  instance behaves exactly as now. Subdirs appear only when a 2nd instance arrives.
- **Lazy claim at first UserPromptSubmit** of a session (not on arbitrary read
  hooks). Read-only/sub-agent tool calls do not burn a lane.
- **Per-project cap of 5**; a 6th instance is blocked with a clear message.

## Namespacing (lane N; lane 1 = flat)
- state:      .claude/state/            | .claude/state/lane-N/
- contracts:  .claude/contracts/        | .claude/contracts/lane-N/   (per-lane sprint numbers)
- pre-flight: .claude/pre-flight/       | .claude/pre-flight/lane-N/
- evidence:   .claude/evidence/         | .claude/evidence/lane-N/
- must-do:    docs/must do/must-do.md   | docs/must do/must-do-(N-1).md
- memory:     working/ hot files per-lane (working/lane-N/{session-context.md,
              recent-activity.jsonl,active-tasks.json}); core/semantic/decisions
              SHARED; episodic session files tagged _laneN; MANIFEST shared (atomic_write).

## The chokepoint
New helper `resolve_instance(payload)` in lib-helpers.sh, called at the TOP of every
hook AFTER stdin is read once:
- extract `.session_id` from the already-read payload (NEVER re-cat stdin)
- look up session_id -> lane; if absent and event == UserPromptSubmit -> claim (locked)
- export LANE, STATE_DIR, CONTRACTS_DIR, PREFLIGHT_DIR, EVIDENCE_DIR, MUSTDO_FILE,
  WORKING_DIR (lane 1 = flat, else subdir)
Because every hook resolves the SAME lane for a session within a turn, every injected
message is mutually consistent — lane 3 can never be shown lane 2's contract.

## Situational-awareness preservation (the spine — own AC block)
Every orientation channel becomes lane-stamped and self-only:
- Turn packet leads with `[LANE N]` and shows ONLY lane N's phase/sprint/watcher/step.
- Pre-flight MCQ is built from lane N's watcher + must-do file, and adds a lane-identity
  anchor question.
- Every BLOCKED message references only lane-N paths.
- 3-min reminder points at lane N's watcher; evidence/PASS/feedback all name the lane.
- On claim, lane N gets a one-time briefing: "You are LANE N. Siblings X,Y are other
  live instances; their lane-*/must-do-* are NOT yours — never read/write them."
- CLAUDE.md gains a one-line pointer; the runtime injection is AUTHORITATIVE over the
  bare paths in CLAUDE.md.

## Shared-codebase surprise (advisory, never blocking)
Lane isolation separates harness STATE, not source files. To prevent silent clobber:
- post-write-check appends each lane's edited file path to a per-project
  `.claude/state/lane-activity.jsonl` (session_id, lane, path, ts).
- When a lane writes a file another ACTIVE lane touched, inject a WARNING (not a block);
  the turn packet lists sibling lanes' recent files. Visible + reminded, never silent.

## Lifecycle
claim (lazy, locked) -> work (all state lane-namespaced) -> watcher activate (cron +
lane watcher.md, found by session_id) -> release on Stop BY session_id (a sub-agent's
Stop carries a different id, so it cannot release the parent — structurally fixes the
sub-agent-release bug) -> stale entries age out (claimed_at > 4h).

## Step 0 — session_id probe (BUILD GATE, AC #1)
A throwaway capture confirms session_id is present in PreToolUse, PostToolUse,
UserPromptSubmit, Stop, AND whether a spawned sub-agent reports its own session_id or
the parent's. The result fixes sub-agent handling: if sub-agents have their own id they
do NOT claim a lane (transient) and inherit the parent lane via a parent_session->lane
note. NOTHING else is built until the probe passes and its finding is recorded.

## Backward compatibility
- A single instance is lane 1 = flat = exactly today. Zero new dirs, zero behavior change.
- Registry v1 -> v2 migrated once on startup; helpers read both.
- Projects never running a 2nd instance are unaffected.

## Out of scope
- Hard file locking (advisory only). The kill-switch (Sprint 30). Cross-project lane
  sharing. Changing the verifier protocol or the Sprint 29 auto-resolve behavior.

## Success
5 instances in one folder, each with isolated state and correct, self-only awareness;
no lane ever sees another's context; watcher pool is per-project (cap 5); single
instance unchanged; verified in a real multi-lane sandbox by an independent agent that
actively tries to make a lane see the wrong context and cannot.

## Rev 2 hardening (after independent concept validation)

### Awareness must be EXHAUSTIVE — and grounded in the REAL hooks, not the plan doc
"No surprises" requires EVERY orientation surface to be lane-scoped. The robust guarantee is
structural, not a hand-maintained list: resolve_instance sets STATE_DIR before any read, and
EVERY read goes through ${STATE_DIR} — a static grep guard proves ZERO literal `.claude/state/`
orientation reads remain (that literal-path case is the actual leak vector; an audit of
on-prompt-submit.sh found some). The audited ground-truth set the spine test must seed (flat
lane-1 markers) and prove no leak into a lane-2 turn: current-phase, phase-feedback,
phase-complete-marker, ralph-mode, build-iteration, cron-paused, strategy-loop-state, strategy-ack,
evidence-checkpoint/verdict/remediation, harness-test-result, test-output, next-fix,
must-do-summary(+step), must-do-injection-log, watcher-self-check, context-snapshot, progress-notes,
stuck-report, unverified-writes, write-count, gate-counter + watcher slot (the pending-gates string),
plus the turn packet / pre-flight challenge / BLOCKED messages / 3-min cron reminder. Startup-read
files the model is told to open (injected-context.md, active-instructions.md, active-tasks.json,
working/session-context.md) are ALSO lane-namespaced — these are reads, not turn-injections.

### Concurrency on the one shared writable surface
Per-lane state files never collide (not shared). The NEW shared writable is
.claude/state/lane-activity.jsonl (the advisory log) — appends MUST be serialized
(registry_lock or proven-atomic append), never bare append from 5 processes. The shared
MANIFEST must not lose updates: move sessions_count per-lane, or update under lock.
instance_release and instance_claim_lane both run under registry_lock; two simultaneous
Stops must leave exactly the surviving entries.

### Liveness + orphaned state
Stale-prune keys off a last_seen HEARTBEAT refreshed every turn, NOT just claimed_at — a
legitimate >4h build must never be evicted out from under itself. When a lane IS pruned or
released, its lane-N/ dirs are cleaned or quarantined so the next instance to claim lane N
starts CLEAN and cannot inherit a dead predecessor's phase/contract/evidence.

### Concrete probe fallback
If the probe finds session_id absent in any event, the named fallback is the CLAUDE_SESSION_ID
environment variable (or whatever stable per-session id the probe confirms Claude Code sets) —
the build gate's escape hatch is concrete, not "some env var".
