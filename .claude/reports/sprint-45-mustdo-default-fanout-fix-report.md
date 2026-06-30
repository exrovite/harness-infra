# Sprint 45 Report — Multi-session must-do OWNERSHIP deadlock: default per-session fan-out

**Date:** 2026-07-01
**Status:** BUILT, TDD-green (fanout 9/0 + gate 4/0 + session-aware 23/0 + session-owned 10/0 + default-on
11/0 + pack 25/0 + killswitch 22/0), mirrored 5/5, independently validated PASS.
**Trigger:** the user hit a live deadlock — two sessions in one project (PCW, Sprint 96) ping-ponging
`[MUST-DO OWNERSHIP] BLOCKED … authored by a different session … Send '+++pack'`. Each `+++pack` archived
the other's must-do file and re-stamped it, so the other session then read its file as foreign → rebuilt →
loop. The agent even said *"The must-do.md already has my session tag!"* yet was still blocked.

## Root cause
The must-do **file** ownership (Sprint 37 stamp + "foreign → +++pack") fanned out the owned file ONLY by
**LANE** (`mustdo_file_for_dir`, `lib-helpers.sh`), and multilane is **opt-in** via `.claude/multi-lane.json`.
Agents never enable it, so every parallel session was LANE=1 → every session resolved to the SAME
`must-do.md` → they fought over one stamp → deadlock. The *summary* side had been fixed this way (per-
`session_id` files) but the must-do **file** side never was. (The design doc said ownership should ride the
per-project watcher pool — `slot-N ↔ must-do-N.md` — but that was wired to LANE, which collapses without
multilane.)

## The fix (default, no opt-in)
1. **`mustdo_file_for_dir` fans out BY DEFAULT** (`lib-helpers.sh`). For a flat session it returns the
   session's OWN file: (a) any must-do file already **stamped by me** (stable across roster changes), else
   (b) assigned by my **ordinal among the project's ACTIVE watcher sessions, sorted by slot** → `must-do.md`
   (1st), `must-do-2.md`, `must-do-3.md`, … Slots are uniquely assigned under registry lock, so the initial
   assignment is race-free; concurrent sessions never land on the same file. Explicit multilane and the
   no-session-id back-compat path are preserved. Result memoised per (DIR, session).
2. **`HARNESS_SESSION_ID`** is set once per hook from the payload `.session_id` (pre-write-gate,
   pre-bash-gate, on-prompt-submit, post-write-check), so the resolver and every reader agree on the owned
   file.
3. **The system now TELLS each agent its own file** (the user's key ask — agents won't infer it):
   - `on-prompt-submit` BUILD packet always injects: *"YOUR must-do file is '<file>' — yours alone … NEVER
     read, clear, or overwrite another session's must-do file; to (re)build yours send '+++pack'."*
   - The `[MUST-DO OWNERSHIP]` block (pre-write-gate + pre-bash-gate) now names `YOUR OWN must-do file is:
     <file>` and states each session owns exactly one.
4. **Bug found mid-fix (pre-write-gate line 379):** `[ -n "$MUST_DO_MD" ] && [ -f "$MUST_DO_MD" ] || …find|head -1`
   clobbered a validly-resolved owned file (`must-do-2.md`) with the first existing file (`must-do.md`)
   whenever the owned file didn't exist yet — re-creating the deadlock at the gate even after the resolver
   was fixed. Changed to only scan when the resolver returned nothing. (Also silenced a phantom
   `No such file` stderr from a reader loop over the not-yet-authored owned file.)

## Proof
- `tests/test-mustdo-default-fanout.sh` **9/0** (resolver: solo→must-do.md; two sessions→must-do.md +
  must-do-2.md; stamp-stable across roster shift; leftover reclaim; back-compat; multilane).
- `tests/test-mustdo-fanout-gate.sh` **4/0** (END-TO-END: CONTROL reproduces the deadlock when B has no
  own file; FIX — B with its own watcher is NOT ownership-blocked by A's must-do.md, via BOTH pre-write
  and pre-bash; B resolves must-do-2.md).
- Regression: session-aware 23/0, session-owned 10/0, default-on 11/0, pack 25/0, killswitch 22/0,
  killswitch-resolve 7/0, nested-root 12/0, no-autocreate 6/0, fresh-folder 8/0; `bash -n` clean.
- **Independent validator: PASS** (A–E) — reproduced in its own sandboxes; adversarial probes confirmed
  slot-driven (not alphabetical) assignment, `sort_by(.slot)` honored regardless of JSON order, 3 sessions
  → must-do.md/-2/-3, and **20-way concurrent resolves stayed consistent with zero collisions**. Live↔
  `_install` byte-identical on all 5 files.

## One line
Every concurrent session now gets — and is explicitly TOLD — its own must-do file (`must-do.md`,
`must-do-2.md`, …) by default off the watcher pool, so sessions stop overwriting each other's grounding and
the `+++pack` ownership deadlock is gone — proven by an end-to-end gate test and an independent agent.
