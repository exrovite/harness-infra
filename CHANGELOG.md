# Harness Infrastructure — Changelog

The master harness that controls all AI models on this machine through three-layer deterministic
enforcement (Layer 1 harness/hooks · Layer 2 deterministic guards · Layer 3 LLM agents). Live config
lives in `~/.claude/{hooks,scripts}`; the distributable **install pack** is `_install/` and is kept
**byte-identical** to the live harness (except intentional install-time differences like the GLM
supervisor). Every change is TDD-first and verified by an independent default-FAIL sub-agent before commit.

---

## Multi-session correctness (Sprints 42–46) — 2026-06-28 → 2026-07-01

This run hardened the harness for **multiple Claude sessions working the same (or a new) project at once**.
The through-line: a per-session mechanism at the *gate* is not enough — the parts the agent *perceives*
(directory creation, injected packet, every message) must be per-session too, or agents collide.

### Sprint 42 — stop creating **nested** `.claude` roots (`2cdd536`)
`init-project.sh` created `.claude` cwd-relative with no guard and is auto-invoked by other hooks, so a
hook firing from a subdirectory minted a whole new `.claude` tree → a false project root that fragmented
the kill-switch/state. **Fix:** ancestor guard in `init-project.sh` (refuse to create `.claude` if an
ancestor below `$HOME` already has one) + project-root resolution in 9 state-writing hooks. Test:
`test-nested-root-guard.sh` 12/0.

### Sprint 43 — stop creating `.claude` in **new / non-project** folders (`430ab59`)
`find_project_state_dir` treated the global `~/.claude` install as a project root, and hooks fell back to
a cwd-relative `.claude/state` and `mkdir`'d it. **Fix:** the resolver now stops the walk at `$HOME`
(the global install is never a project), and every state-writer `exit 0`s when no project root resolves —
the harness is now **opt-in per folder**. Test: `test-no-autocreate-claude.sh` 6/0.

### Sprint 44 — the *real* fresh-folder creator: `startup-recovery.sh` (`3884d08`)
Found by a full-chain test: of every wired hook, only `startup-recovery.sh` (invoked transitively by
`post-write-check`/`run-harness`) auto-created `.claude` in a fresh folder, and its child
`write-handoff.sh` did too. **Fix:** both resolve an existing project root or do nothing; `startup-recovery`
exports the resolved root to children; `run-harness` calls `init-project` first (explicit opt-in). Test:
`test-fresh-folder-no-claude.sh` 8/0.

### Sprint 45 — default per-session must-do **FILE** fan-out (`88834aa`)
Two sessions deadlocked: both owned the single `docs/must do/must-do.md`, each saw the other's ownership
stamp as "foreign", each `+++pack` archived the other's and re-stamped → ping-pong. The fan-out that was
meant to prevent this was wired to opt-in multilane that agents never enable. **Fix:** `mustdo_file_for_dir`
fans out **by default** — each session owns a distinct file (`must-do.md`, `must-do-2.md`, …) by its
ordinal among the project's active watcher sessions (a file already stamped by me wins, for stability).
The packet and every block message now **name the agent's own file**. Threaded via `HARNESS_SESSION_ID`.
Tests: `test-mustdo-default-fanout.sh` 9/0, `test-mustdo-fanout-gate.sh` 4/0 (end-to-end).

### Sprint 46 — per-session must-do **SUMMARY** lane (`819bab3`)
The gate already keyed the summary per-session, but the packet **injection** read the shared
`must-do-summary.md` (another session's content) and every message told the agent to write the shared file,
so agents read and overwrote each other's summaries. **Fix:** the injection now shows only
`must-do-summary.<session_id>.md` (nothing if not authored yet — never a peer's), and every authoring/block
message names the session's own lane. Test: `test-mustdo-summary-lane.sh` 6/0.

**Net:** N sessions can now share a project — each gets, and is explicitly told, its own must-do file and
its own summary lane; and running the harness in a brand-new folder creates nothing until you opt in.

---

## Earlier foundations (condensed — see `.claude/reports/` and `docs/` for detail)

- **Beast-mode intuition layer (Sprints 35–41).** Per-project `.beast/lessons.jsonl`; global PreToolUse
  recall (`beast-recall-hook`), in-work interjection (`beast-watch-hook`), reconcile-gate; mempalace
  semantic recall; validated-protocol surfacing + enforced independent-check gate (`beast-protocol-gate`).
- **Must-do system (Sprints 13, 19, 34, 37 + pack builder).** `docs/must do/` grounding gate, session-aware
  ownership stamping, non-destructive history archive, automated `+++pack` builder.
- **Kill-switch (Sprint 33/35).** `---`/`===` per-project on/off, resolved by project root
  (cwd-independent); `beast-on`/`beast-off` toggles; the flag check sits at the top of every gate.
- **Per-project watcher pool (Sprint 31a).** Each project gets up to 5 of its own watchers; global-unique
  slots; registry locking.
- **Pre-flight MCQ gate, phantom-TDD enforcement, evidence checkpoints, contract/phase gates, memory
  hardening (atomic writes, append-only JSONL).**
- **Integrations shipped in `_install`:** lavish-axi (HTML review loop), headroom (token compression, incl.
  opt-in GLM dual-proxy), Arbor (research agent), Codex/oh-my-codex harness, Agent Wiki.

---

## Conventions

- **Live ↔ `_install` parity** is verified on every change (byte-identical for hooks; `_install` may lead
  on intentional install-time pieces like the GLM supervisor).
- **TDD-first**, then an **independent default-FAIL verifier** reproduces in its own sandboxes before commit.
- MSYS/Git Bash safe (`pwd -W`, no subprocess-per-line loops, temp files not here-strings).
- Full per-sprint write-ups live in `.claude/reports/`.
