# Sprint 31a Contract — Multilane Foundation (isolation mechanism + hard guarantees)

**Split from**: sprint-31-contract.md (the thrice-validated master). 31a = the part that must WORK and
not deadlock or lose state. 31b (awareness sweep + advisory) depends on 31a and builds after it.
**Phase target**: PLAN(done via master) -> NEGOTIATE(this) -> BUILD -> EVALUATE -> COMPLETE
**Sprint id**: 31a

## Goal
Up to 5 concurrent instances in one folder, each with CORRECTLY ISOLATED harness state — no cross-lane
writes, no cross-lane gate deadlock, no state loss under concurrency. Lane 1 = today's flat layout (zero
migration). The turn packet shows the correct lane's BASIC status. (Exhaustive awareness sweep + sibling
briefing + advisory file-claim are deferred to 31b.)

## Acceptance criteria (full text in master; IDs partitioned here)
### Probe (BUILD GATE)
- AC1: session_id probe — confirm `.session_id` in PreToolUse/PostToolUse/UserPromptSubmit/Stop + sub-agent
  behavior; record findings; concrete named fallback (CLAUDE_SESSION_ID). Nothing else builds until recorded.

### resolve_instance + registry v2
- AC2: resolve_instance(payload) exports LANE/STATE_DIR/CONTRACTS_DIR/PREFLIGHT_DIR/EVIDENCE_DIR/MUSTDO_FILE/
  WORKING_DIR; lane 1 = flat, lanes 2-5 = subdirs.
- AC3: reads session_id from PASSED payload; never re-reads stdin.
- AC4: registry v2 list keyed by session_id; helpers claim/find/activate/release under registry_lock.
- AC5: per-project lane numbering; concurrent same-cwd claims get DISTINCT lanes (lock serializes).
- AC6: 6th concurrent instance refused with a clear "5 lanes in use" message.

### Claim timing
- AC7: new session first seen via read-only PreToolUse does NOT claim.
- AC8: first UserPromptSubmit claims exactly one lane.
- AC37: pre-claim default = read-only flat (lane 1); MUST NOT write lane state or claim before first prompt.

### Namespacing mechanism (the part that makes isolation REAL)
- AC32a: payload-carrying hooks read stdin once and call resolve_instance BEFORE any state read.
- AC32b: STATIC GUARD — zero literal `.claude/state|contracts|pre-flight|evidence/` READ forms remain
  outside resolve_instance (excludes exemption-matching + BLOCKED-message text). Every read uses a resolved var.
- AC9: with 2 lanes, each hook reads/writes ONLY its lane paths (lane 1 flat, lane 2 lane-2/).
- AC10: per-lane sprint numbers — lane 2 contracts in .claude/contracts/lane-2/.
- AC11: memory hot working files per-lane (working/lane-N/); core/semantic/decisions shared; episodic _laneN-tagged.
- AC14-basic: the turn packet leads with [LANE N] and shows that lane's OWN phase/sprint (2-lane assertion;
  the EXHAUSTIVE all-channel sweep is 31b/T20).

### Watcher pool via session key
- AC12: watcher enforcement = "does MY session's entry exist+active+cron?" — no project-path matching.
- AC13: each project independently supports 5 watchers; cross-project independence (no global-pool exhaustion).

### No-stdin contexts + subprocess threading (build-blockers)
- AC34: on-session-end.sh converted to read stdin once + extract session_id; release removes ONLY that entry.
- AC35: session_id THREADED as arg/env to bash subprocess helpers (generate-pre-flight-challenge.sh,
  create-evidence-checkpoint.sh, validate-pre-flight.sh); they resolve lane from it, never project-path match.

### Lane-aware contract gate (fixes the deadlock)
- AC36: contract gate (pre-write-gate ~174) + contract reads use ${CONTRACTS_DIR}; lane 2 gated on lane-2's
  contract, never lane-1's. Flat-only contract does NOT satisfy lane 2.

### Concurrency on shared writables
- AC27: lane-activity.jsonl appends serialized (lock/atomic) — 5 concurrent appenders lose zero lines.
- AC28: shared MANIFEST no lost updates under concurrent session-end (per-lane count or lock).
- AC29: instance_release under registry_lock; two simultaneous Stops leave exactly survivors.

### Orphan state + liveness
- AC30: stale-prune keys off last_seen heartbeat (refreshed in on-prompt-submit each turn), not just claimed_at.
- AC31: pruned/released lane-N dirs cleaned/quarantined so a reclaim starts CLEAN.

### Backward compat / migration
- AC24: single instance = lane 1 = flat; NO lane-N dir created; Sprint 29 suite still 11/11.
- AC25: v1 registry migrated to v2 once; legacy slots mapped under synthetic key (legacy-slot-N), preserved.
- AC26: all modified shell files pass bash -n; Windows/MSYS-safe; additive (no FAIL/gate logic removed).

## TDD (functional — real hooks, real multi-lane sandboxes; MUST fail first)
- T1(AC1) probe findings recorded. T2(AC2/3) resolve_instance lane1-flat vs lane2-dirs, stdin not consumed.
- T3(AC5/6) two sessions -> lanes 1,2; 6th refused. T4(AC7/8/37) read-only no-claim; first prompt claims;
  pre-claim writes nothing. T5(AC9/10) post-write-check A(flat)/B(lane-2) isolation + lane-2 contract path.
- T-basic-packet(AC14-basic) 2-lane turn packets each show own lane/phase only.
- T-guard(AC32b) grep finds zero literal-path reads. T-ns(AC32a) STATE_DIR set before first read.
- T-watcher(AC12) session B passes iff B's own entry active+cron. T-cap(AC13) two projects independent 5 each.
- T25(AC34) Stop B removes only B (real stdin). T26(AC35) pre-flight gen with lane-2 session arg -> lane-2 source.
- T27(AC36) lane-2 with only lane-2 contract -> gate PASSES; flat-only -> lane2 not satisfied (no deadlock).
- T15(AC27) 5 concurrent appenders -> wc -l == 5. T16(AC29) concurrent release -> survivors exact.
  T17(AC28) concurrent session-end -> no lost MANIFEST update. T18(AC30) heartbeat survive/prune. T19(AC31) reclaim clean.
- T13(AC24) single session flat-only, no lane dirs, Sprint 29 11/11. T14(AC25) v1->v2 migrate, legacy preserved.

## Done (31a) = AC1 recorded + all 31a ACs pass + all 31a TDD green + literal-path guard clean +
independent verifier (real 2-3 lane sandbox; attempts cross-lane WRITE + contract-gate deadlock) returns PASS.
