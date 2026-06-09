● Good — option 2 it is. Here's the full design, end to end, then the concrete change list.

  A. The data model
  One global file stays (~/.openclaw/watchers/REGISTRY.json), but it changes from a fixed array of 5 slots into a list of active instances, keyed by 
  session_id:
  {
    "version": "2.0.0",
    "max_lanes_per_project": 5,
    "instances": [
      {
        "session_id": "c836c5fa-…",        // unique per Claude Code launch — the real key
        "project": "g:/harness infra",      // ONLY for lane-numbering, the fairness cap, and display
        "lane": 1,                          // 1–5, assigned per-project
        "status": "active",
        "claimed_by": "Claude",
        "claimed_at": "2026-06-…",
        "cron_job_id": "abc123",
        "cron_interval": "*/3 * * * *",
        "todo_path": ".claude/state/lane-1/watcher.md"
      }
    ]
  }

  The critical change: enforcement is keyed by session_id, not by matching the project path. The gate asks "does my session's entry exist and is it
  active with a cron?" — session_id is globally unique, so there's no pwd/backslash/case normalization in the enforcement path. That's the whole class of  historical watcher bugs gone. The project field still exists, but only to (a) number lanes within a project, (b) enforce the 5-per-project cap, (c)
  show you a readable dashboard.

  B. The zero-migration trick — lane 1 is today

  Lane 1 uses the existing flat paths. Lanes 2–5 use subdirs.

  ┌────────────┬─────────────────────────┬──────────────────────────────────┐
  │            │  Lane 1 (1st instance)  │ Lanes 2–5 (concurrent instances) │
  ├────────────┼─────────────────────────┼──────────────────────────────────┤
  │ State      │ .claude/state/          │ .claude/state/lane-2/ …          │
  ├────────────┼─────────────────────────┼──────────────────────────────────┤
  │ Contracts  │ .claude/contracts/      │ .claude/contracts/lane-2/ …      │
  ├────────────┼─────────────────────────┼──────────────────────────────────┤
  │ Pre-flight │ .claude/pre-flight/     │ .claude/pre-flight/lane-2/ …     │
  ├────────────┼─────────────────────────┼──────────────────────────────────┤
  │ Must-do    │ docs/must do/must-do.md │ must-do-1.md … must-do-4.md      │
  └────────────┴─────────────────────────┴──────────────────────────────────┘

  So a project running one instance behaves exactly as it does today — no migration, no new directories, zero behavior change. Subdirs only appear when a  2nd+ instance shows up. This is what makes the whole thing safe to roll out harness-wide.

  C. Lifecycle of an instance

  1. First hook fires with a session_id. A new helper resolve_instance extracts it and looks it up in the registry.
  2. Not found → auto-claim a lane. Under the registry mkdir-lock: list active entries for this same project, find the lowest free lane number (1–5),
  write a new entry. Because both same-folder instances share an identical cwd, they group correctly; the lock serializes the two claims so they can't
  both grab lane 1. If all 5 are taken → block with "this project already has 5 active lanes."
  3. Every subsequent hook looks up session_id → gets its lane → sets STATE_DIR=.claude/state/lane-N (or flat for lane 1). One chokepoint, every hook
  inherits it.
  4. Watcher activation (the existing "claim a watcher for multi-step work") now just fills in cron_job_id + writes the lane's watcher.md to-do — found
  by session_id, no slot hunting.
  5. Release on Stop — on-session-end removes the entry whose session_id == mine. A sub-agent's Stop carries a different session_id, so it physically
  cannot release the parent's entry. That structurally fixes the sub-agent-kills-parent-watcher bug we fought before.
  6. Stale entries age out in startup-recovery by claimed_at > 4h, keyed by session — no project-scoping fragility.

  D. The concrete change list (file by file)

  1. lib-helpers.sh — the heart:
    - extract_session_id (read .session_id from the hook payload)
    - resolve_instance → returns/sets LANE, STATE_DIR, CONTRACTS_DIR, PREFLIGHT_DIR, MUSTDO_FILE (lane 1 = flat, else subdir)
    - instance_claim_lane, instance_find_by_session, instance_activate_watcher, instance_release
    - keep registry_lock/unlock; retire check_watcher_for_project (replaced by session lookup)
  2. pre-write-gate.sh / pre-bash-gate.sh — call resolve_instance at top; swap the "count watchers matching project" enforcement for the session lookup;
  update the claim-instruction block messages (now "activate your instance's watcher", no slot number to pick); all the
  .claude/state|contracts|pre-flight paths come from the resolved vars; the release-guard keys off the session entry.
  3. pre-flight-gate.sh / generate-pre-flight-challenge.sh / validate-pre-flight.sh — challenge + response read/write ${PREFLIGHT_DIR}; the must-do
  questions read ${MUSTDO_FILE} for this lane.
  4. post-write-check.sh — counters + the Sprint 29 auto-resolve all key off ${STATE_DIR}; the lane resolution at top.
  5. on-prompt-submit.sh — resolve lane; inject [LANE 3 | watcher active | step …] and the lane's paths into the turn packet so the instance can't stray
  into another lane.
  6. on-session-end.sh — release the entry by session_id.
  7. startup-recovery.sh — stale-prune the registry by age; clear dead cron_job_ids; (one-time) migrate a v1 registry to v2.
  8. create-evidence-checkpoint.sh — checkpoint + must-do source files come from the lane's dirs/file.
  9. Registry file — v1 → v2 format + a small migration shim that reads both.
  10. CLAUDE.md / docs — document lanes, the must-do file naming, and the per-project cap.

  E. Step 0 — the probe (de-risks everything)

  Before writing any of the above, a throwaway capture hook dumps the raw stdin of PreToolUse, PostToolUse, UserPromptSubmit, Stop, and a sub-agent call,  and confirms:
  - session_id is present in every event (the auto-claim depends on it), and
  - whether a spawned sub-agent reports its own session_id or the parent's.

  That answer decides the one real open question: if sub-agents get their own id, they must either skip lane logic or inherit the parent's lane (via a
  parent_session → lane note) so a verifier sub-agent doesn't burn a lane or write to the wrong namespace. This is AC #1 — nothing else gets built until
  the probe passes.

  F. What you get

  - Up to 5 concurrent instances per project, each with isolated phase/contracts/pre-flight/evidence/must-do — they can't confuse each other's work.
  - 5 lanes per project, every project — no global pool to exhaust; the fairness cap stops one project hogging.
  - Single global dashboard — one REGISTRY.json shows every active instance across all projects.
  - Two old bugs killed for free — project-path matching and sub-agent watcher-release, both gone because the key is now session_id.
  - Zero migration — lane 1 is exactly today's layout.

  The main risk is entirely in the sub-agent/session_id behavior, which the probe settles first.

  Want me to scope this as a sprint now — spec + contract with the probe as AC #1 — and where does it sit relative to the Sprint 30 kill-switch?

But there is a crucial part to this we have maintained a system that keeps the model awware of what it is doing what its comingin a way that leaves no 
  room for surrises we need to maintain this in a metuclous way. does this make sense                                                                    
  
● Yes — and that's the most important thing you've said in this whole discussion. The harness's real product isn't the gates; it's that the model always 
  knows exactly where it is, what it's doing, what's next, and why it's blocked — never a surprise. Multilane must not dilute that by even 1%. In fact
  multilane raises the bar, because now there are siblings that could create confusion. Let me show how each awareness surface stays airtight, and name
  the one genuinely new surprise-surface honestly.

  The awareness surfaces, and how each stays lane-correct
  Every channel that keeps the model oriented today must become lane-stamped and self-only:

  ┌─────────────────────────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │        Awareness channel (today)        │                                         Multilane requirement                                          │
  ├─────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Turn packet ([HARNESS] Phase…) every    │ Leads with [LANE 3] and shows only lane 3's phase/sprint/watcher/step. Never another lane's.           │
  │ prompt                                  │                                                                                                        │
  ├─────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Pre-flight MCQ (restate                 │ Generated from lane 3's own watcher + must-do file. Add an anchor question — "Which lane are you?" —   │
  │ task/step/target/scope)                 │ so the model re-affirms identity every gated write.                                                    │
  ├─────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Gate block messages ("GATES AHEAD",     │ Every path is lane-qualified: "write .claude/contracts/lane-3/sprint-N-contract.md". No bare paths     │
  │ claim instructions)                     │ that could mean another lane.                                                                          │
  ├─────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ 3-min watcher reminder                  │ Points at lane 3's watcher.md, asks "which lane, which step."                                          │
  ├─────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ Evidence brief / PASS reminder / phase  │ All read/write the lane's dirs; messages name the lane.                                                │
  │ feedback                                │                                                                                                        │
  └─────────────────────────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────┘

  The resolve_instance chokepoint is what guarantees this: because every hook computes the same lane for a given session_id within a turn, every injected  message in that turn is mutually consistent. There is no path where lane 3 is shown lane 2's contract — the namespace is resolved once, at the top,
  identically everywhere.

  The new awareness requirement multilane adds

  Today the model only needs to know about itself. With siblings, "no surprises" means it must also know two new facts up front, or it will be surprised:
  1. "You are not alone." The moment a lane is claimed, the very first injection tells it: "You are LANE 3. Lanes 1 and 2 are other live instances in
  this folder. Their lane-1/, lane-2/, must-do.md, must-do-1.md are NOT yours — never read or write them." So when it later sees sibling subdirs, that's
  expected, not a surprise.
  2. The honest hard part — the shared codebase. Lane isolation cleanly separates harness state (phase, contracts, must-do, evidence). It does not
  separate the actual source files — all 5 lanes edit the same repo. That's the one place multilane introduces a real new surprise: two lanes editing
  foo.js at once. The harness can't make that disappear while everyone shares one folder, so "no surprises" demands we surface it loudly rather than hide  it:
    - The turn packet lists sibling lanes and their declared scope ("lane 2 is working in src/api/"), so each model knows where the others are operating.    - Optionally a lightweight advisory file-claim (a lane notes the files it's actively editing; another lane touching the same file gets a warning
  injection — not a hard lock, but no silent clobber).
    - And the discipline that you assign each lane a non-overlapping area of the code when you launch them.

  That second point is the only thing in this whole design that can't be made invisible — so the right move is the harness one: make it visible and
  reminded, never silent.

  Making "no surprises" testable, not aspirational

  To maintain it meticulously, I'd put it in the contract as its own acceptance-criteria block, e.g.:

  - AC: with 3 lanes active, the turn packet for each lane contains its own lane number and none of another lane's phase/sprint/step (asserted by a real
  3-lane sandbox).
  - AC: every BLOCKED message emitted to lane N references only lane-N paths.
  - AC: the pre-flight challenge served to lane N is built from lane N's must-do file and includes the lane-identity question.
  - AC: on claim, lane N receives the "you are lane N, siblings are X,Y, do not touch theirs" briefing exactly once.
  - AC: if two lanes edit the same file, the second receives a concurrent-edit warning injection (if we adopt the advisory claim).

  That way "the model is never surprised" stops being a hope and becomes something the verifier checks in a multi-lane sandbox.

  So yes — it makes complete sense, and it's the spine of the sprint, not a footnote. When I scope it, "situational-awareness preservation" gets its own
  section in the spec and its own ACs, and the independent verifier will specifically try to make a lane see the wrong context and confirm it can't.

  The one decision your point surfaces: for the shared-codebase surprise, do you want (a) awareness-only (siblings + their scope shown, you assign
  non-overlapping work), or (b) awareness + an advisory file-claim that actively warns on concurrent edits? That's the only open question your "no
  surprises" principle forces.