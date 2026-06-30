# Sprint 44 Report — The REAL fresh-folder `.claude` creator: `startup-recovery.sh`

**Date:** 2026-06-30
**Status:** BUILT, TDD-green (8/8 fresh-folder + 6/6 + 12/12 + 22/22 + 7/7), mirrored 4/4, independently validated PASS.
**Trigger:** after Sprints 42/43 the user reported the harness **STILL** created a `.claude` when Claude wrote
a file in a new folder — and rightly pushed: *"Have you functionally tested that?"* I had not tested the
full hook chain; my earlier tests covered a subset and missed the actual culprit.

## What I missed (and how I found it)
Sprints 42/43 fixed `find_project_state_dir` and the state-WRITING hooks, and my tests passed — but they
only exercised ~6 hooks. I wrote a **full-chain** test (`test-fresh-folder-no-claude.sh`) that fires EVERY
wired hook in a fresh folder, then a **standalone diagnostic** that runs each suspect alone. The diagnostic
was decisive: of all the gates and hooks, exactly **one** created `.claude` in a fresh folder —
**`startup-recovery.sh`**.

## Root cause
`startup-recovery.sh` has a "No previous state found — Starting fresh" branch that does
`mkdir -p "$STATE_DIR"` + writes `current-phase.json` (cwd-relative `.claude/state`). It is invoked by
`post-write-check.sh` (first write of a session) and `run-harness.sh` (startup). It had **no project-root
resolution and no guard**, so running it in a non-project folder minted `.claude`. A second creator
surfaced via the same script: `startup-recovery` calls **`write-handoff.sh`**, which also wrote a
cwd-relative `.claude/state/handoff-artifact.md` — so from a subdir it made a *nested* `.claude` too.

## The fix (TDD-first, defense-in-depth)
1. **`startup-recovery.sh`** — before any creation, resolve `STATE_DIR` to an existing project root via
   `find_project_state_dir` (which stops at `$HOME`); if there is no project, **`exit 0`** (create
   nothing). When a root IS found, **`export HARNESS_STATE_DIR`** so child scripts
   (`write-handoff.sh`, `notify.sh`, …) write into the real project's state instead of a cwd-relative
   nested `.claude`.
2. **`run-harness.sh`** — the explicit launcher now calls `init-project.sh` (opt-in) *before*
   `startup-recovery.sh`, since recovery no longer auto-bootstraps. (init-project still refuses to nest.)
3. **`post-write-check.sh`** — hardened the Sprint-43 guard: `exit 0` on *no project root* regardless of
   lane (previously an exact-match `= ".claude/state"` could let a multilane `STATE_DIR` slip past),
   while still preserving real multilane lane dirs.
4. **`write-handoff.sh`** — its own resolve-or-`exit 0` guard (defense-in-depth for any direct/future
   caller).

Net: **no harness hook or script auto-creates `.claude` in a non-project folder by any path.** The harness
is opt-in per folder; explicit `init-project.sh` / `run-harness.sh` still bootstrap normally.

## Proof
- `tests/test-fresh-folder-no-claude.sh` **8/8**: full wired chain in a fresh folder creates nothing;
  `startup-recovery` standalone creates nothing; `post-write-check` first-write path bootstraps nothing;
  `write-handoff` creates nothing; **explicit `init-project` still creates `.claude` (opt-in preserved)**;
  `startup-recovery` in a real-project subdir makes no nested `.claude`; real project still records its
  write.
- Regression: `test-no-autocreate-claude` 6/0, `test-nested-root-guard` 12/0, `test-killswitch` 22/0,
  `test-killswitch-resolve` 7/0; `bash -n` clean on all 4 changed files.
- **Independent validator: PASS** — reproduced the literal scenario (prompt → pre-write → file write →
  post-write → session-end), folder ended with only `x.txt` and no `.claude`/`.agent-memory`; confirmed
  real project still records writes, explicit init still creates, `run-harness` bootstraps, and
  live↔`_install` byte parity on all 4 files.

## Honest note
Sprints 42 and 43 were real fixes but **incomplete** because I tested a subset of hooks, not the whole
chain — `startup-recovery` (a transitively-invoked script, not a directly-wired hook) was never in the
test. The lesson encoded here: the fresh-folder test now runs the ENTIRE wired chain plus the
transitively-invoked scripts, so this class of bug can't hide in an untested path again.

## One line
The real culprit was `startup-recovery.sh`'s "start fresh" auto-init (and its `write-handoff` child);
both now resolve an existing project root or do nothing, so writing a file in a new folder creates no
`.claude` — proven by a full-chain functional test and an independent agent.
