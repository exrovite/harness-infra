# Spec — Session-Aware Must-Do File-Exists Branch (Sprint 37)

**Phase:** PLAN · **Sprint:** 37 (new — does not modify any prior sprint)
**Agreement of record (verified verbatim):**
`docs/applying fussion ideas/enhancing the must do system/discussion-agreement-session-aware-mustdo.md`

## Problem (evidence-cited)
The must-do summary gate routes on one test — *does a `.md` file exist in `docs/must do/`?*
(`pre-write-gate.sh:383`, resolved at `:374-381`). When a finished agent leaves its must-do file
behind, the next session hits the **file-exists** branch and only has to summarize the *leftover*
list; it is never routed to the **create** branch (`:526-559`) that forces it to author its own
grounding. The per-session summary keying we already shipped sits *downstream* of this branch, so it
does not help. Net effect: the grounding ritual silently becomes a no-op for every agent after the
first.

## Goal
Make the file-exists branch **session-aware** so a leftover file authored by another session stops
satisfying it — **without deleting anything**. Old grounding is archived to `docs/must do/history/`
so the folder keeps a record of what each agent grounded on.

## Approach (WHAT, not full HOW)
A **deterministic session stamp** written into agent-authored must-do files — **by hook/script only,
never by the agent** (the agent cannot reliably know its own `session_id`, and a self-reported stamp
is forgeable). The two existing controlled write points carry the stamp:
- `build-mustdo-pack.sh` (the `+++pack` path) stamps the pack it builds.
- `post-write-check.sh` (PostToolUse) stamps an agent-authored must-do file after the Write.

The gate then resolves the owned file and decides by stamp:

```
owned must-do file ─► stamped?
  ├─ no stamp (human-seeded spec)   ─► SUMMARY branch   (unchanged; zero regression)
  ├─ stamp == THIS session          ─► SUMMARY branch   (it's mine; proceed)
  └─ stamp == ANOTHER session       ─► CREATE branch    (author your own grounding / +++pack)
```

On re-author, the prior session's file is **moved to `docs/must do/history/`** (not deleted). That
subfolder is invisible to resolution because every lookup uses `find -maxdepth 1`.

## Pre-existing files already in folders (migration — added per user)
Files already on disk are all unstamped. An unstamped file is classified by content: if it bears the
`build-mustdo-pack.sh` signature (`current task pack` / `Auto-built by build-mustdo-pack` /
`raw-conversation`) it is a **legacy agent pack** → treated as foreign (force the new session to author
its own; archived to `history/` on re-author). A plain unstamped list has no such signature → it stays
a shared human seed. This closes the migration gap without breaking the human-seed rule below.

## Human-seed semantics (confirmed by user)
An **unstamped** must-do file is a shared/persistent human spec and behaves exactly as today
(summarize-and-proceed). The per-session "build your own" forcing applies **only** to
agent-generated packs. A human editing the file outside Claude triggers no hook, so it stays
unstamped — the distinction is free.

## In scope
- Session stamp emission in `build-mustdo-pack.sh` (new `--session`) and `post-write-check.sh`.
- Thread `session_id` into the `+++pack` handler → `build-mustdo-pack.sh --session`.
- Session-aware routing in the file-exists branch of `pre-write-gate.sh` and its `pre-bash-gate.sh` twin.
- Archive-before-clobber to `docs/must do/history/` at the controlled re-author points.
- Stamp-line skipping in every must-do reader (summary counter, printed list, MCQ generator, injection).
- Functional TDD: new live-hook sandbox suite, failing-first.
- Live ↔ `_install` byte parity.

## Out of scope (explicit)
- **No deletion** of must-do files anywhere (this sprint is archive-only).
- No change to the lane resolver `mustdo_file_for_dir`, the MCQ count logic, the PLAN-entry backstop,
  or summary injection beyond stamp-line skipping.
- No change to projects without a `docs/must do/` folder (default-on create branch untouched).
- No watcher-release/Stop-hook cleanup (deliberately avoided — sub-agents fire Stop).

## Success (high level)
A leftover, foreign-stamped must-do file forces the next session through the create branch; that
session's own pack supersedes it while the old file is preserved under `history/`; human-seeded and
no-session cases are byte-for-byte unchanged; all proven by tests that drive the **live** hooks in
real temp-dir sandboxes. Detailed binary criteria: `evaluation-criteria-sprint-37.md`.
