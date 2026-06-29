# Sprint 43 Report — Stop the harness creating `.claude` in non-project / new folders

**Date:** 2026-06-29
**Status:** BUILT, TDD-green (6/6 + 12/12 + 22/22 + 7/7), mirrored 11/11, independently validated PASS.
**Trigger:** after Sprint 42 (which stopped *nested* `.claude` inside an existing project), the user found
that **running the harness in a brand-new / non-project folder STILL created a `.claude` there.**

## Root cause (different path from Sprint 42)
Sprint 42 fixed *nested* roots (a `.claude` inside an existing project). This is the **"no project at
all"** case, and it had two compounding defects:

1. **`find_project_state_dir` treated the global `~/.claude` as a project root.** Walking up from any
   folder, it returned the first `.claude` it hit. For a folder **under `$HOME`** with no project of its
   own, that was the global `C:/Users/exrov/.claude` — so hooks wrote into (and polluted) the global
   state. Proven live: from a fresh temp dir it returned `C:/Users/exrov/.claude/state`.
2. **State-writing hooks fell back to a cwd-relative `.claude/state` and `mkdir`'d it.** For a folder
   **not under `$HOME`** (e.g. `G:/newfolder`), resolution returned empty and the hooks used their
   `${HARNESS_STATE_DIR:-.claude/state}` default, then `mkdir -p "$STATE_DIR"` / `atomic_write` — minting
   a `.claude` in the user's folder on the first write/event.

A hook must **never create a `.claude` root**; only `init-project.sh` (explicit / guarded) should.

## The fix (TDD-first)
1. **`find_project_state_dir` stops at `$HOME`** (`lib-helpers.sh`): compute `_home` via `cd "$HOME" &&
   pwd -W`; the walk-up `break`s when `$d == $_home` *before* testing `$d/.claude`, so the global install
   is never returned. A real project under `$HOME` (`$HOME/proj/.claude`) still matches — that dir
   ≠ `$HOME`.
2. **State-writing hooks/scripts `exit 0` when no project resolves** (create nothing):
   - `post-write-check.sh` — only the bare lane-1 default `".claude/state"` is root-resolved; if no root,
     `exit 0` (explicit `HARNESS_STATE_DIR` and multilane lane dirs untouched).
   - GROUP A (uniform snippet): `on-stuck-detected.sh`, `on-test-failure.sh`, `pre-phase-start.sh`,
     `check-budget.sh`, `create-evidence-checkpoint.sh`, `detect-loop.sh`, `ensure-dev-server.sh` —
     `if [ -n "$_r" ]; then STATE_DIR="$_r"; else exit 0; fi`.
   - GROUP B: `agent-call-tracker.sh`, `pre-flight-gate.sh` — `[ -n "$_pf_root" ] || exit 0`.

Net effect: the harness is now effectively **opt-in per folder** — it only acts where a `.claude` already
exists (an existing project, found before the walk reaches `$HOME`). A scratch/new folder stays clean; to
enable the harness there you run `init-project.sh` explicitly.

## Proof
- `tests/test-no-autocreate-claude.sh` **6/6**: no-project folder under HOME → empty; isolated no-project
  folder → empty; real project still resolves to its root; running the auto-firing hooks from a
  no-project folder creates **no** `.claude`; `HARNESS_STATE_DIR` override honored.
- Regression: `test-nested-root-guard.sh` 12/0, `test-killswitch.sh` 22/0, `test-killswitch-resolve.sh`
  7/0; `bash -n` clean on all 11 changed files.
- **Independent validator: PASS** — reproduced in its own mktemp sandboxes (incl. a sandbox directly
  under the real `$HOME`, the exact bug scenario): 0 `.claude` created by any hook; `find_project_state_dir`
  never emits the global; real projects still resolve and hooks still write into `<root>/.claude/state`;
  live `G:/harness infra` resolves to its own root. It flagged then dismissed a path-form false-alarm
  (feeding a non-`pwd -W` arg) as a test artifact the runtime never produces.
- Live↔`_install` byte parity on all 11 files.

## Not done / follow-up
- `on-prompt-submit.sh` is intentionally **left alone**: its only state-creating sites are the kill-switch
  toggles (`---`/`===`/`beast-on`, explicit user actions) and a `$ralph` branch guarded by an existing
  sprint contract — none fire on an ordinary request in a fresh folder. Changing it risks the
  well-tested kill-switch/beast toggle logic. (Minor: typing a toggle token in a *bare* folder could
  still touch a cwd-relative flag — explicit user action, not the reported bug.)
- `harness_disabled_resolved` (kill-switch walk) has its own walk-up and could still treat the global
  `~/.claude` as a root; harmless today (no global flag), but worth the same `$HOME` stop for symmetry.
- Existing stray `.claude` roots already on disk (e.g. PCW) remain until the one-time cleanup is run.

## One line
A harness hook must never create a project root: `find_project_state_dir` now stops at `$HOME` (the global
`~/.claude` is the install, not a project) and every state-writer exits instead of falling back to a
cwd-relative `.claude` — so running the harness in a new/non-project folder creates nothing. Proven by TDD
and an independent agent.
