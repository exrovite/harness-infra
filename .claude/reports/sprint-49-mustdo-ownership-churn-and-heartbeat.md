# Sprint 49 Report — Fix must-do ownership churn (greedy resolver) + full heartbeat coverage

**Date:** 2026-07-01
**Status:** BUILT, TDD-green (ownership-churn 7/0 + full regression 18 suites / 0 fail), mirrored 4/4,
independently validated PASS (A–G, all 4 FAIL-critical invariants).
**Trigger:** the user showed a live PCW session stuck in a gate loop — *pre-flight regenerates ("my slot was
reset") → must-do gate says "no grounding yet"* — repeating. Real cause visible in the live registry:
`d2248c13` held **slot 2** but grounded first (claimed 13:13); `2f081509` held **slot 1** (claimed later,
13:21).

## Root causes (two)
1. **Ordinal-by-slot assignment collided with existing ownership.** The Sprint-45 resolver assigned the
   owned must-do file by ordinal = slot order. So the lower-slot session `2f081509` was handed `must-do.md`
   — which the higher-slot `d2248c13` had already grounded. `d2248c13`'s grounding was orphaned → its next
   resolution returned a non-existent file → "no grounding yet" → the loop.
2. **Heartbeat coverage was too thin.** `last_seen` was only refreshed by `on-prompt-submit` (turn start)
   and `post-write-check` (successful Write/Edit). A Bash-heavy turn — or one where writes are being
   *blocked* — produced no heartbeat, so a busy agent could go stale and get its watcher + summary reaped
   mid-work (Sprints 47/48), which reset its slot and wiped its grounding.

## The fix
**Greedy, ownership-aware resolver** (`mustdo_file_for_dir`, `lib-helpers.sh`):
- pass-3: a file already **stamped by me** is mine (stable across roster churn).
- pass-4: else claim the **lowest-numbered file NOT owned by a LIVE peer** (unstamped / mine / dead-owner),
  with ties among concurrent unstamped sessions broken by **rank in slot order**. This never collides with
  a live peer's grounded file and never orphans mine; dead owners' files are reclaimable.
- `session_is_live` hardened: an **active watcher with no timestamp is treated as LIVE** (fail-safe — don't
  steal its file or reap it; matches `watcher_reap_stale`, which skips no-timestamp entries).

**Full heartbeat coverage:** `watcher_touch_session` now fires **early in `pre-write-gate`, `pre-bash-gate`,
and `pre-flight-gate`** (before any blocking) — so *any* tool attempt (Write/Edit/Bash, even a blocked one)
keeps the watcher alive. A busy agent can no longer be reaped mid-work.

## Proof
- `tests/test-mustdo-ownership-churn.sh` **7/0**: the exact reported case (lower-slot new session avoids a
  live peer's grounded `must-do.md` → `must-do-2.md`); grounded session stays stable; two new sessions fan
  out distinctly; dead-owner reclaim; a Bash command refreshes the heartbeat; session is live afterward.
- Full regression **18 suites, 0 fail** (fanout, fanout-gate, summary-lane, session-scoping, watcher-reap,
  isolation, session-aware/owned, default-on, pack, perproject, killswitch, nested/fresh). `bash -n` clean.
  (`test-mustdo-fanout-gate`'s CONTROL was updated: it asserted the *old* collision — now B is correctly
  never routed to a live peer's file even without a watcher, so it gets the author-your-own gate, not the
  foreign-ownership block.)
- **Independent validator: PASS (A–G)** — reproduced in its own sandboxes; confirmed slot-order (not
  array-order) assignment, dead-owner reclaim + no-timestamp fail-safe, stability under a third session,
  and that all three gate hooks refresh a stale session's `last_seen`. Live↔`_install` byte-identical (4/4).

## One line
The must-do file assignment is now greedy and ownership-aware (never steals a live peer's grounded file,
never orphans yours) and every tool attempt heartbeats — so a busy multi-session project stops churning
through pre-flight/must-do gates.
