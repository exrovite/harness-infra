# Sprint 31b Contract — Multilane Awareness Hardening + Advisory

**Depends on**: sprint-31a (foundation — resolve_instance, registry v2, lane namespacing). 31b adds the
meticulous "no surprises" awareness sweep across EVERY orientation channel, plus the sibling briefing and
the shared-codebase advisory. Build ONLY after 31a is COMPLETE and verified.
**Split from**: sprint-31-contract.md (thrice-validated master).
**Phase target**: PLAN(done via master) -> NEGOTIATE(this) -> BUILD -> EVALUATE -> COMPLETE
**Sprint id**: 31b

## Goal
With lanes already isolated (31a), guarantee the model is NEVER shown another lane's context through ANY
orientation channel, knows it is not alone, and is warned (never blocked) on concurrent edits to shared
source files. This is the spine: "the model always knows where it is / what's next — no surprises."

## Acceptance criteria (full text in master; IDs partitioned here)
### Exhaustive awareness sweep (THE SPINE)
- AC14 (full): with 3 lanes active (distinct session_ids, distinct phases/sprints), each lane's turn packet
  contains its OWN lane number and NONE of another lane's phase/sprint/step.
- AC15: every BLOCKED message emitted to lane N references only lane-N paths (no bare/foreign paths).
- AC16: the pre-flight challenge served to lane N is built from lane N's must-do file AND includes a
  lane-identity anchor question.
- AC18: CLAUDE.md gains a lane pointer; lane N's turn packet CONTAINS the explicit instruction "use
  .claude/state/lane-N/ paths, not the CLAUDE.md defaults" (testable hook output).
- AC33: the 3-min cron reminder text for lane N references lane N's watcher and asks "which lane".
- AC32c (spine seed set): seed a DISTINCT lane-1 marker into the FLAT copy of EVERY audited orientation
  channel — current-phase, phase-feedback, phase-complete-marker, ralph-mode, build-iteration, cron-paused,
  strategy-loop-state, strategy-ack, evidence-checkpoint/verdict/remediation, harness-test-result,
  test-output, next-fix, must-do-summary(+step), must-do-injection-log, watcher-self-check, context-snapshot,
  progress-notes, stuck-report, unverified-writes, write-count, gate-counter + watcher slot, AND a flat
  lane-1 CONTRACT file. Drive lane-2's turn -> assert ZERO lane-1 marker in ANY injected/echoed output.
- AC32d: startup-read orientation files (injected-context.md, active-instructions.md, context-snapshot.md,
  active-tasks.json, working/session-context.md) are lane-namespaced; CLAUDE.md's lane pointer makes the
  model read the lane copies.

### Sibling awareness ("you are not alone")
- AC17: on claim, lane N receives ONCE the briefing "you are LANE N; siblings X,Y are other live instances;
  their lane-*/must-do-* are NOT yours — never read/write them." Not repeated on later turns.

### Shared-codebase advisory (never blocking)
- AC19: post-write-check appends {session_id,lane,path,ts} to the per-project lane-activity log.
- AC20: when lane 2 writes a file an ACTIVE sibling lane already touched, a WARNING is injected and the
  write is NOT blocked (exit 0); the turn packet lists sibling lanes' recent files; single-lane projects get
  no such warnings.

## TDD (functional — real 3-lane sandboxes driving the real hooks; MUST fail first)
- T6 (AC14 full): drive on-prompt-submit for A(BUILD/sprint5), B(PLAN/sprint1), C(EVALUATE/sprint3) -> each
  packet shows ONLY its own lane/phase/sprint; none contains another's.
- T7 (AC15): force a gate block on lane 2 -> message contains lane-2 paths, no flat/lane-1 path.
- T8 (AC16): generate pre-flight for lane 2 -> questions derive from must-do-1.md + lane-identity Q present.
- T9 (AC17): first claim for lane 2 emits the sibling briefing once; second turn does not repeat it.
- T20 (AC32c — THE adversarial spine test): lane 2 active; seed lane-1 markers in the FLAT copy of EVERY
  channel above PLUS a flat contract and flat gate-counter; drive lane 2's turn -> assert ZERO lane-1 marker
  anywhere in the injected output.
- T21 (AC33): CronCreate prompt content for lane 2 references lane-2 watcher + "which lane".
- T-ac18 (AC18): lane 2 turn packet contains the explicit "use lane-2 paths, not CLAUDE.md defaults" line.
- T10 (AC20): lane 1 writes foo.js, then lane 2 writes foo.js -> WARNING injected, exit 0; single-lane control -> no warning.
- T-ac19 (AC19): a lane write appends a correct {session_id,lane,path,ts} record to lane-activity.

## Done (31b) = all 31b ACs pass + all 31b TDD green + an independent verifier that ACTIVELY attempts to make
a lane observe another lane's context across EVERY enumerated orientation channel (and seeds a flat contract +
flat gate-counter) and CONFIRMS it cannot, returns PASS.
