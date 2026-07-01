# Sprint 48 Report — Hard session isolation (liveness-aware) + stale must-do property cleanup

**Date:** 2026-07-01
**Status:** BUILT, TDD-green (session-isolation 12/0 + full regression 17 suites / 0 fail), mirrored 5/5,
independently validated PASS (A–F, both FAIL-critical properties).
**Trigger:** the user asked *"Is it now impossible for another session to write into another session's
must-do property?"* — honest answer was **no** (Sprints 45/46 gave assignment + guidance + detection, but
no hard block; summaries in `.claude/state` were wide open). The user approved a hard block **and** added
the crucial caveat: *"we must also have a way of managing stale properties … otherwise we have all the spots
cleaned and nobody can do anything about it."*

## The two interlocked pieces
A naive hard block would re-create lockout: a must-do file/summary owned by a **dead** session would be
frozen forever. So the block is **liveness-aware**, and stale properties are **actively cleaned** — the same
AC30 heartbeat signal drives both.

### 1. Hard block — you cannot write a *live* peer's must-do property
- `session_is_live(sid)` = has an active watcher whose `last_seen` (else `claimed_at`) is within the stale
  threshold (same signal `watcher_reap_stale` uses → "live" == "not yet reaped").
- `mustdo_cross_session_owner(target)` = the owning session of a target that is a per-session property: a
  summary lane `must-do-summary.<sid>.md` / `-step.<sid>.txt` (the shared `must-do-summary.md` is NOT owned),
  or a must-do file (owner = its stamp; probes cwd must-do dirs for a bare basename).
- `mustdo_peer_write_blocked(target, me)` → block iff the owner is a **different, still-LIVE** session.
- Enforced in **`pre-write-gate.sh`** (Write/Edit) right after the kill-switch — *before* any path exemption
  (summaries live in the always-writable `.claude/state`) — and in **`pre-bash-gate.sh`** for write commands
  (redirect / tee / cp / mv / sed -i / dd / truncate / heredoc / python-open), independent of the existing
  `WRITES_FILES` heuristic so **absolute/`/tmp` paths are also caught**. Pure reads are not gated.
- **No lockout:** own property always writable; a **dead/reaped** owner's property is reclaimable (allowed);
  fail-open when the writer has no session id.

### 2. Stale-property cleanup — dead sessions' summaries are reaped
- `mustdo_reap_stale_summaries([state_dir])` removes `must-do-summary.<sid>.md` (+ `-step.<sid>.txt`) whose
  owner is **not live** and whose file mtime is older than a grace (~300 s, avoids racing a just-started
  session); never the current session's own, never the shared file.
- Wired into **`on-prompt-submit.sh`** (every prompt, on the resolved project state dir) and
  **`startup-recovery.sh`** (on startup) — alongside the watcher reap. So a dead session's summary + must-do
  file both free up within ~20 min (the watcher-reap window), and nobody is ever permanently locked out.

## Proof
- `tests/test-session-isolation.sh` **12/0**: live peer's summary/must-do BLOCKED (Write + Bash, incl.
  absolute path); own + shared + no-session-id ALLOWED; **DEAD peer's property reclaimable** (Write + Bash);
  `session_is_live` fresh/stale/unknown; reap removes only the dead owner, keeps live/own/too-fresh/shared.
- Full regression **17 suites, 0 fail** (session-scoping, watcher-reap, all must-do, killswitch, perproject,
  nested/fresh) — the isolation block causes **no** false-positives. `bash -n` clean on all 5 files.
- **Independent validator: PASS (A–F)** — reproduced in its own sandboxes; confirmed the block is truly
  **liveness-keyed** (the *same* write is BLOCKED when the owner is live, ALLOWED when dead), own files never
  blocked even with a stale own watcher, full takeover after the owner dies, Edit tool + `sed -i` caught,
  runs before the `.claude/state` exemption. Live↔`_install` byte-identical on all 5 files.

## Answer to the original question
**Yes — it is now enforced.** A session physically cannot Write/Edit or `>`-write into another session's
must-do file or summary lane **while that session is alive**. And because the ownership is tied to the
liveness heartbeat, a dead session's property is automatically reclaimable and its orphaned summaries are
reaped — so the isolation never locks the project's agents out.

## One line
Cross-session must-do writes are now hard-blocked while the owner is live, and a dead owner's property is
auto-reclaimed + its summaries reaped — strong isolation with zero lockout.
