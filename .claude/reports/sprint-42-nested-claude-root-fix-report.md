# Sprint 42 Report — Stop the harness creating nested `.claude` project roots

**Date:** 2026-06-28
**Status:** BUILT, TDD-green (12/12 + 22/22 + 7/7), mirrored, independently validated PASS.
**Trigger:** the user found `.claude` roots appearing all over PCW (`src/.claude`, `.claude/state/.claude`,
…), which fragmented the kill-switch/state so a `---`/`beast-on` at the project root never reached the
`src/` subtree (a stale disabled flag sat in `src/.claude/state/`).

## Root cause
Several harness scripts created `.claude` using **cwd-relative** paths instead of resolving the project
root, and one of them **auto-runs**:
- **`init-project.sh`** was entirely cwd-relative (`mkdir -p .claude/...`, writes `CLAUDE.md`,
  `known-fixes.md`, `current-phase.json`) with **no guard** against a parent project. It is auto-invoked
  by `post-write-check.sh` and `on-session-end.sh`. Running with cwd ≠ the true root built a whole new
  `.claude` tree there — a false root.
- **`pre-flight-gate.sh` / `agent-call-tracker.sh`** did bare `mkdir -p .claude/pre-flight` and wrote
  counters/`verification-ledger.jsonl` to a cwd-relative `.claude/state`.
- **~7 more hooks/scripts** did `mkdir -p "$STATE_DIR"` with the cwd-relative default `.claude/state`.
- `find_project_state_dir` then walks **up to the nearest** `.claude`, so any nested one became the
  authoritative root for its subtree — permanent fragmentation.

## The fix (TDD-first)
1. **`init-project.sh` ancestor guard** — before creating anything, walk up from the parent of cwd; if any
   ancestor (stopping at `$HOME`, so the global `~/.claude` install never counts) already has a `.claude`,
   **refuse and exit** without creating. This stops every *full* nested root.
2. **Project-root resolution for state writes** — `pre-flight-gate.sh` and `agent-call-tracker.sh` resolve
   `PF_BASE`/`STATE_DIR` via `find_project_state_dir`; `on-test-failure.sh`, `on-stuck-detected.sh`,
   `pre-phase-start.sh`, `check-budget.sh`, `create-evidence-checkpoint.sh`, `detect-loop.sh`,
   `ensure-dev-server.sh` got a uniform "resolve `STATE_DIR` to the project root" snippet.
3. **Sweep**: no hook now creates `.claude`/state at a cwd-relative path without resolving the root.

## Proof
- `tests/test-nested-root-guard.sh` **12/12**: guard refuses nested roots from subdirs / inside
  `.claude/state` / `.claude/specs`; a genuinely fresh project still inits; the global `~/.claude` never
  blocks a project under `$HOME`; root re-init is idempotent; auto-firing hooks create no nested `.claude`
  from a subdir; pre-flight hooks have no bare cwd-relative mkdir.
- Regression: `test-killswitch.sh` 22/0, `test-killswitch-resolve.sh` 7/0; `bash -n` clean on all 10 files.
- **Independent validator: PASS** — reproduced the guard in its own sandboxes, confirmed fresh/HOME
  projects still init, confirmed the pre-existing `test-preflight-session-keyed` 0/4 is NOT caused by this
  change (identical with the pre-change hook; that suite doesn't even invoke `pre-flight-gate.sh`), and
  caught the `agent-call-tracker` `STATE_DIR` gap which is now fixed.
- Live↔`_install` byte parity on all 10 changed files.

## Not done / follow-up
- **Cleaning PCW's existing nested roots** (`src/.claude`, `.claude/state/.claude`, etc.) is a separate
  one-time cleanup (destructive) — to be done on request. The fix stops *new* ones; the old ones remain
  until removed.
- `pre-flight-gate.sh` reassigns `STATE_DIR` cwd-relative inside one read-only block (line ~123); its
  *writes* go through `PF_BASE`, so it creates nothing — a correctness nicety, not a root-creator.

## One line
The harness was minting new `.claude` project roots wherever a hook happened to run from a subdirectory;
now `init-project.sh` refuses to nest inside an existing project and every state-writer resolves the true
project root — proven by TDD and an independent agent.
