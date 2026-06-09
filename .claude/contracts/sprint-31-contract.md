# Sprint 31 Contract — Multilane Workers

**Phase target**: PLAN -> NEGOTIATE -> BUILD -> EVALUATE -> COMPLETE
**Spec**: .claude/specs/multilane-workers-spec.md
**Principle**: preserve "no surprises" awareness meticulously — it has its own AC block (F).

## A. Probe (BUILD GATE)
- AC1: A probe captures raw stdin of PreToolUse, PostToolUse, UserPromptSubmit, Stop, and a
  spawned sub-agent call; a findings file records whether `.session_id` is present in EACH
  event and whether a sub-agent reports its own id or the parent's. No further build until
  recorded. If session_id is absent anywhere, the spec's env-var fallback is added for that path.

## B. resolve_instance + registry v2 (lib-helpers.sh)
- AC2: `resolve_instance(payload)` returns/exports LANE, STATE_DIR, CONTRACTS_DIR, PREFLIGHT_DIR,
  EVIDENCE_DIR, MUSTDO_FILE, WORKING_DIR. Lane 1 => flat paths; lanes 2-5 => lane-N subdirs.
- AC3: resolve_instance reads session_id from the PASSED payload and never re-reads stdin.
- AC4: Registry v2 = list keyed by session_id. Helpers: instance_claim_lane,
  instance_find_by_session, instance_activate_watcher, instance_release (all under registry_lock).
- AC5: Per-project lane numbering: claim picks lowest free lane (1-5) among entries with the
  same project; two concurrent claims (same cwd) get DISTINCT lanes (lock serializes).
- AC6: 6th concurrent instance for a project is refused with a clear "5 lanes in use" message.

## C. Lazy claim
- AC7: A new session_id seen FIRST via a read-only PreToolUse does NOT claim a lane.
- AC8: A new session_id's first UserPromptSubmit DOES claim a lane (and only one).

## D. Namespacing across hooks
- AC9: With 2 active lanes, each hook writes/reads ONLY its lane's paths — lane 1 to flat,
  lane 2 to lane-2/ (asserted by driving real hooks with two session_ids).
- AC10: Per-lane sprint numbers — lane 2 contracts live in .claude/contracts/lane-2/.
- AC11: Memory: working hot files go to working/lane-N/ for lane 2+; core/semantic/decisions
  stay shared; episodic session file for lane 2 is _lane2-tagged.

## E. Watcher pool = per-project via session key
- AC12: Watcher enforcement asks "does MY session_id's entry exist + active + cron?" — no
  project-path matching in the enforcement path.
- AC13: Each project independently supports 5 watchers; a second project is unaffected by
  the first's usage (no global 5-cap exhaustion).

## F. Situational-awareness preservation (THE SPINE)
- AC14: With 3 lanes active (distinct session_ids, distinct phases/sprints), each lane's turn
  packet contains its OWN lane number and NONE of another lane's phase/sprint/step.
- AC15: Every BLOCKED message emitted to lane N references only lane-N paths (no bare/foreign paths).
- AC16: The pre-flight challenge served to lane N is built from lane N's must-do file and
  includes a lane-identity anchor question.
- AC17: On claim, lane N receives the "you are LANE N; siblings X,Y; do not touch theirs"
  briefing exactly once.
- AC18: CLAUDE.md gains a lane pointer; the injected lane paths are authoritative (a test
  confirms the turn packet tells the model to use lane-N paths over CLAUDE.md defaults).

## G. Shared-codebase advisory (never blocking)
- AC19: post-write-check appends {session_id,lane,path,ts} to per-project lane-activity log.
- AC20: When lane 2 writes a file lane 1 (active) already touched, a WARNING is injected and
  the operation is NOT blocked (exit 0). Single-lane projects get no such warnings.

## H. Lifecycle / release
- AC21: Stop for session B removes ONLY B's entry; A's entry remains.
- AC22: A Stop carrying a session_id with no entry (e.g. a sub-agent) does not remove any
  parent entry (structural fix of the sub-agent-release bug).
- AC23: Entries with claimed_at > 4h are pruned on startup; dead cron_job_ids cleared.

## I. Backward compatibility / migration
- AC24: A single instance resolves to lane 1 = flat; NO lane-N directory is created; behavior
  matches pre-Sprint-31 (regression of the existing single-lane suites, incl. Sprint 29 11/11).
- AC25: A v1 registry is migrated to v2 once on startup, preserving any existing active watcher.
- AC26: All modified shell files pass `bash -n`; Windows/MSYS-safe (tr -d CR, no sed backslash
  subs, temp files not here-strings); changes additive (no FAIL/gate logic removed).

## TDD Tests (FUNCTIONAL — real hooks, real multi-lane sandboxes; MUST fail before build)
Each test builds a throwaway repo sandbox, crafts distinct session_id payloads, and drives the
REAL hooks/helpers; asserts on resulting files and injected output.
- T1 (AC1): run probe; assert findings file lists session_id presence per event.
- T2 (AC2/AC3): resolve_instance(payload) -> lane 1 flat; a lane-2 payload -> lane-2 dirs; calling
  it does not consume stdin (feed payload as arg, stdin empty, still resolves).
- T3 (AC5/AC6): two session_ids same project -> lanes 1 and 2; a 6th -> refused message.
- T4 (AC7/AC8): read-only PreToolUse with new session -> no entry; then UserPromptSubmit -> entry.
- T5 (AC9/AC10): drive post-write-check for session A (lane1) and B (lane2); assert A's counter/
  state in flat, B's in lane-2/; B's contract path is lane-2.
- T6 (AC14): drive on-prompt-submit for A (BUILD/sprint5) and B (PLAN/sprint1); assert A's packet
  shows lane1 BUILD sprint5 and NOT PLAN/sprint1; B's shows lane2 PLAN sprint1 and NOT A's.
- T7 (AC15): force a gate block on lane 2; assert the message contains lane-2 paths and no flat path.
- T8 (AC16): generate pre-flight for lane 2; assert questions derive from must-do-1.md + identity Q.
- T9 (AC17): first claim for lane 2 emits the sibling briefing once; second turn does not repeat it.
- T10 (AC20): lane 1 writes foo.js, then lane 2 writes foo.js -> warning injected, exit 0;
  single-lane control -> no warning.
- T11 (AC21/AC22): Stop session B removes only B; Stop unknown session removes nothing.
- T12 (AC23): seed claimed_at>4h -> startup prune removes it.
- T13 (AC24): single session end-to-end -> flat paths only, NO lane-2..5 dirs; Sprint 29 suite still 11/11.
- T14 (AC25): v1 registry on disk -> startup migrates to v2, prior watcher preserved.

## Rev 2 (2026-06-06) — gaps closed after independent concept validation
Validator confirmed the scope is faithful and decisions sound, but FAILed on three additive
gaps: incomplete awareness enumeration, shared-write concurrency, orphaned lane state. Added:

### J. Concurrency on shared writable surfaces
- AC27: `lane-activity.jsonl` (per-project, SHARED across lanes) appends are serialized — under
  `registry_lock` or a proven-atomic single-writer append. TEST: 5 concurrent appenders lose zero lines.
- AC28: Shared MANIFEST must not lose updates under concurrent multi-lane session-end — either move
  `sessions_count` per-lane (like recent-activity) or update MANIFEST under lock. TEST: two concurrent
  session-ends -> no lost update.
- AC29: `instance_release` runs under `registry_lock`. TEST: two SIMULTANEOUS Stops (A and B) leave
  exactly the surviving entries (no clobber).

### K. Orphaned lane state + liveness
- AC30: stale-prune keys off a `last_seen` heartbeat (refreshed each turn), NOT just `claimed_at`, so a
  live long-running lane (legit >4h build) is NOT evicted. TEST: recent last_seen survives; old prunes.
- AC31: when a lane entry is pruned/released, its `lane-N/` state dirs are cleaned or quarantined so a
  re-claiming instance starts CLEAN (no inherited phase/contract). TEST: prune lane 2, reclaim -> fresh state.

### L. EXHAUSTIVE orientation-channel coverage (strengthens block F — the spine)
- AC32: Awareness is exhaustive. EVERY injected orientation channel is lane-scoped: turn packet,
  pre-flight challenge, block messages, 3-min cron reminder, watcher-self-check.md, injected-context.md,
  active-instructions.md, strategy-loop-state.json, harness-test-result.json, evidence-checkpoint brief,
  [MUST-DO ACTIVE] summary. TEST (the key adversarial one): with lane 2 active and DISTINCT lane-1
  markers seeded into the FLAT version of ALL these files, drive lane 2's turn and assert ZERO lane-1
  marker appears in ANY injected channel (proves no flat-default reads).
- AC33: the 3-min cron reminder text for lane N references lane N's watcher and asks "which lane". TEST
  asserts the CronCreate prompt content is lane-correct.

### Corrections to Rev 1 ACs
- AC1 (amended): the env-var fallback is a NAMED variable (`CLAUDE_SESSION_ID`, or whatever the probe
  finds Claude Code actually sets) — the build gate's escape hatch is concrete, not undefined.
- AC18 (amended, honest testability): the testable claim is that lane N's turn packet CONTAINS an
  explicit instruction "use .claude/state/lane-N/ paths, not the CLAUDE.md defaults" (a hook output).
  The unprovable "model prefers injection" wording is dropped — we test the instruction is emitted.

### Rev 2 TDD additions (functional)
- T15 (AC27): 5 concurrent appenders to lane-activity.jsonl -> `wc -l` == 5 (no interleave loss).
- T16 (AC29): two concurrent instance_release calls -> exactly the surviving entries remain.
- T17 (AC28): two concurrent session-end MANIFEST updates -> no lost update (count correct / per-lane).
- T18 (AC30): entry with recent last_seen survives prune; entry with stale last_seen pruned.
- T19 (AC31): prune lane 2 then reclaim -> lane-2 state dirs start clean.
- T20 (AC32): lane 2 active, ALL flat orientation files seeded with lane-1 markers -> drive
  on-prompt-submit for lane 2 -> assert NO lane-1 marker in any injected channel (the spine test).

## Rev 3 (2026-06-06) — awareness grounded in the REAL hooks (2nd validation)
2nd validator read the actual on-prompt-submit.sh and found AC32's channel list was built from the
plan doc, not the code: it OMITTED live channels (ralph-mode.json, build-iteration.json,
cron-paused.json, the compute_pending_gates PENDING string, context-snapshot.md, strategy-ack.md)
and INCLUDED two files the hook never injects (injected-context.md, active-instructions.md — those
are CLAUDE.md startup reads). A code audit confirmed it.

### Reframe — the real leak vector is LITERAL paths, not the list (more robust than a hand-list)
All orientation reads should use ${STATE_DIR}; if resolve_instance sets STATE_DIR before the first
read, every one is lane-correct automatically. The audit found some reads hardcode `.claude/state/`
instead of ${STATE_DIR} — those always hit lane-1 flat and leak. So AC32 is replaced by:
- AC32a: resolve_instance sets STATE_DIR, CONTRACTS_DIR, PREFLIGHT_DIR, EVIDENCE_DIR, MUSTDO_FILE,
  WORKING_DIR at the TOP of every hook, BEFORE any state read.
- AC32b (STATIC GUARD): a grep across all hooks/scripts finds ZERO literal `.claude/state/` (or
  `.claude/contracts|pre-flight|evidence`) ORIENTATION reads outside resolve_instance — every read
  goes through the resolved var. This converts the audit's hardcoded reads and prevents future drift.
- AC32c (SPINE TEST T20, corrected seed set from the audit): seed a DISTINCT lane-1 marker into the
  FLAT copy of EVERY state file the hooks read — audited ground truth:
  current-phase, phase-feedback, phase-complete-marker, ralph-mode, build-iteration, cron-paused,
  strategy-loop-state, strategy-ack, evidence-checkpoint, evidence-verdict, evidence-remediation,
  harness-test-result, test-output, next-fix, must-do-summary(.md / -step.txt), must-do-injection-log,
  watcher-self-check, context-snapshot, progress-notes, stuck-report, unverified-writes, write-count,
  gate-counter.json + the watcher slot file (the compute_pending_gates PENDING string). Drive lane-2's
  turn -> assert ZERO lane-1 marker in any injected/echoed output.
- AC32d: startup-read orientation files the model is told (by CLAUDE.md) to read — injected-context.md,
  active-instructions.md, context-snapshot.md, active-tasks.json, working/session-context.md — are
  ALSO lane-namespaced; CLAUDE.md's lane pointer makes the model read the lane copies. (Reads, not
  turn-injections — reclassified from the Rev 2 list.)

### Missing tests added (Rev 3)
- T21 (AC33): cron reminder content for lane N references lane N's watcher + "which lane" — assert the
  CronCreate prompt string is lane-correct (closes the Rev 2 AC33-without-a-test gap).
- T22 (AC11): drive on-session-end/post-write-check for lane 2 -> working hot files land in
  working/lane-2/; core/semantic/decisions untouched (shared); episodic file _lane2-tagged.
- T23 (AC12): pre-write-gate for session B passes iff B's OWN entry is active+cron — NOT because
  another session in the same project holds one (two-session drive).
- T24 (AC13): two DIFFERENT projects each reach 5 lanes independently; project A's 5 do not reduce
  project B's available lanes (no global-pool exhaustion).

## Rev 4 (2026-06-06) — build-blockers from 3rd validation (code-grounded)
3rd validator audited the hooks and found three build-blockers (one a real deadlock) plus 4 weak ACs.
B/C confirmed closed; T21-T24 confirmed present. Closed here:

### M. No-stdin contexts + subprocess session threading
- AC34: on-session-end.sh (Stop hook) — currently reads NO stdin — is converted to read stdin once and
  extract `.session_id`; instance_release removes ONLY that session's entry. (Load-bearing: the
  structural sub-agent-kills-parent fix; AC21/AC22 depend on it.) TEST T25.
- AC35: session_id is THREADED as an explicit argument/env var to every bash-invoked subprocess helper
  that runs with empty stdin — generate-pre-flight-challenge.sh, create-evidence-checkpoint.sh,
  validate-pre-flight.sh — and those scripts resolve their lane from it, NEVER from project-path
  matching. (Without this the pre-flight generator reintroduces the exact bug the sprint kills.) TEST T26.

### N. Lane-aware contract gate (fixes a real deadlock)
- AC36: the contract GATE (pre-write-gate.sh ~174) and ALL contract reads (on-prompt-submit ~128/362/393)
  use ${CONTRACTS_DIR} — a lane-2 BUILD agent is gated against lane-2's contract, never lane-1's. A
  flat-only contract does NOT satisfy lane 2; a lane-2 contract DOES. TEST T27. (Today this literal flat
  read would DEADLOCK lane 2 in BUILD.)
- AC32c (amended): T20's seed set ALSO includes a flat lane-1 CONTRACT file and a flat
  .claude/pre-flight/gate-counter.json; assert neither leaks into a lane-2 turn.

### Amendments to earlier ACs (precision)
- AC32a (reworded): only PAYLOAD-CARRYING hooks (PreToolUse, PostToolUse, UserPromptSubmit, Stop) read
  stdin once and call resolve_instance before any state read. No-stdin contexts (startup-recovery operates
  registry-wide; subprocess helpers get session_id via AC35) are explicitly out of the "top of hook" rule.
- AC30 (pinned): last_seen is refreshed in on-prompt-submit.sh each turn (named writer).
- AC32b (clarified): the static guard targets READ forms only; it explicitly EXCLUDES the two non-read
  literal categories — exemption substring matching (grep -qF '.claude/state/') and BLOCKED-message TEXT —
  which legitimately contain the literal.
- AC25 (amended): legacy v1 watchers have NO session_id; migration maps each to a v2 entry under a
  synthetic key (legacy-slot-N) so existing active watchers are preserved.

### Pre-claim default (resolves the d2/d7 timing concern)
- AC37: before a lane is claimed (a tool call BEFORE the session's first UserPromptSubmit), hooks resolve
  to a READ-ONLY default (lane 1 / flat) and MUST NOT write lane-scoped state or claim; the claim happens
  only at first UserPromptSubmit. TEST: a PreToolUse before any prompt neither creates a registry entry
  nor writes a lane-N dir.

### Rev 4 TDD additions
- T25 (AC34): drive on-session-end with a real Stop payload for session B -> only B's entry removed.
- T26 (AC35): invoke generate-pre-flight-challenge.sh with a lane-2 session arg -> challenge built from
  lane-2's must-do/dirs, with NO project-path matching used.
- T27 (AC36): lane-2 BUILD with only a lane-2 contract present -> contract gate PASSES; with only a flat
  contract -> lane 2 is NOT satisfied (proves no cross-lane gate + no deadlock).
- T28 (AC37): PreToolUse with a brand-new session_id BEFORE any prompt -> no registry entry, no lane dir.

## Done = AC1 probe recorded + all ACs (1-37, AC32 -> AC32a-d) pass + all TDD (T1-T28) green + the AC32b
static literal-path guard clean + independent verifier (real multi-lane sandbox, actively attempting
cross-lane contamination AND a cross-lane contract-gate deadlock) returns PASS.
