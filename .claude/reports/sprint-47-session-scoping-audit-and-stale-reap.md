# Sprint 47 Report — Whole-harness session-scoping audit + intelligent stale-slot reap (AC30)

**Date:** 2026-07-01
**Status:** BUILT, TDD-green (session-scoping 7/0 + watcher-reap 11/0 + full regression 16 suites / 0 fail),
mirrored 10/10, independently validated PASS (A–G).
**Trigger:** a GLM 5.2 session (its own task on `prompt-assembly.js`) was being forced to answer **Image
Studio** pre-flight questions — because the challenge was keyed to a **stale sibling's watcher (slot-1)**.
The user asked to *"audit the whole harness for these types of bugs … fix them all so everything is
pointing to its own sessions,"* and to *"intelligently clear stale slots."*

## The bug class (Category A): resolve-by-first-watcher
Across the harness, **8 sites** derived the agent's task/step/challenge/checklist from
`[watchers for this project][0].slot` — the project's FIRST active watcher — never the session's own. With
concurrent sessions (or a stale leftover), a session got someone else's task:
`generate-pre-flight-challenge.sh`, `pre-flight-gate.sh` (step), `pre-write-gate.sh` (stale-step),
`on-prompt-submit.sh` (`check_watcher_for_project`), `agent-call-tracker.sh`, `create-evidence-checkpoint.sh`,
and `compute_pending_gates`'s `ACTIVE_SLOT`. Compounding it (Category B), the **watcher-CLAIM gate counted
project watchers**, so a 2nd session was never forced to claim its own slot — which is *why* GLM rode slot-1.

## The fix — everything points to its own session
1. **`watcher_slot_for_session <sid> [reg]`** (new, `lib-helpers.sh`): the canonical "MY own active watcher
   slot" resolver (session_id is globally unique). Every one of the 8 sites now routes through it (or an
   inline session-scoped `jq`), keyed off **`HARNESS_SESSION_ID`** — now set by every gate hook from the
   payload `.session_id` (pre-write, pre-bash, pre-flight, on-prompt-submit, post-write-check,
   agent-call-tracker; and inherited by `create-evidence-checkpoint` as a child). `check_watcher_for_project`
   gained an optional session arg (defaults to `HARNESS_SESSION_ID`).
2. **Per-session CLAIM gate**: `compute_pending_gates` and the inline claim gates in pre-write/pre-bash/
   pre-flight now require **THIS session's own** watcher (+cron), so every concurrent session claims its
   own slot. Back-compat: when no session id is present (tests/session-less callers), the old project-count
   path is used.

## Intelligent stale-slot clearing (AC30 — the harness's own documented TODO)
`startup-recovery` literally said *"claimed_at is NOT refreshed (no heartbeat yet — that's AC30) … add a
last_seen heartbeat, then this can safely tighten."* Implemented:
- **Heartbeat** `watcher_touch_session <sid>`: stamps `last_seen`; called from `on-prompt-submit` (every
  prompt) and `post-write-check` (every write). Because each session runs a `*/3` reminder cron, an alive
  session refreshes at least every ~3 min (the cron fires while idle) — so a stale heartbeat reliably means
  the session is **gone**. `watcher_claim_pp` stamps `last_seen` at claim.
- **Reap** `watcher_reap_stale [secs] [reg]`: frees active watchers whose `last_seen` (else `claimed_at`) is
  older than the threshold (default **1200s / 20 min** ≈ many missed crons), registry-locked, **never** its
  own watcher, and resets the freed `slot-N.md` (sibling of the registry) to available. Called from
  `on-prompt-submit` (so any live session's cron self-cleans the shared pool within ~20 min) and
  `startup-recovery` (the legacy 4h/72h `claimed_at` reaps remain as the fallback for pre-heartbeat entries).

Result: stale slots that used to linger up to 72h now clear in ~20 min, freeing the slot + the per-project
cap — while an active session (even idle, even mid-long-turn under the threshold) is never reaped.

## Proof
- `tests/test-session-scoping.sh` **7/0** incl. T4 end-to-end: session B's pre-flight challenge is derived
  from B's slot (prompt-assembly), NOT slot-1 (Image Studio) — the reported bug.
- `tests/test-watcher-reap.sh` **11/0**: heartbeat refreshes; touch no-ops for unknown session; stale
  (heartbeat + legacy claimed_at) reaped; fresh kept; **own watcher protected even when stale**; claim
  stamps last_seen; freed slot file reset.
- Full regression **16 suites, 0 fail** (perproject-watchers 6, perproject-gate 7, all mustdo 88, killswitch
  22+7, nested/fresh/no-autocreate 26). `bash -n` clean on all 10 changed files.
- **Independent validator: PASS (A–G)** — reproduced in its own sandboxes with reversed registry order
  (proving session-keyed, not array-first): two sessions never share a slot; the claim gate fires for a
  watcher-less 2nd session; the challenge keys to the correct slot; a session never reaps its own or a fresh
  watcher; 76/0 regression; live↔`_install` byte-identical on all 10 files. (Its one non-blocking note — the
  freed slot-file path — was then fixed to derive from the registry dir.)

## One line
Every per-session artifact (pre-flight challenge, current step, evidence checklist, claim gate) now resolves
THIS session's own watcher, and stale watchers self-clear within ~20 min via a last_seen heartbeat — so
concurrent sessions each work their own task and dead slots don't pile up.
