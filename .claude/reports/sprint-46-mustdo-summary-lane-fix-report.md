# Sprint 46 Report — Per-session must-do SUMMARY lane (stop agents overwriting each other's summary)

**Date:** 2026-07-01
**Status:** BUILT, TDD-green (summary-lane 6/0 + full must-do suite 88/0), mirrored 3/3, independently
validated PASS.
**Trigger:** immediately after Sprint 45 (must-do FILE fan-out) the user saw an agent about to overwrite a
peer's SUMMARY: *"A summary file already exists (the other session's). Let me read it first, then overwrite
with mine."* — *"no you should not overwrite the agent summary, you should have your lane for the summary."*

## Root cause
The gate already keyed the summary per-session (`must-do-summary.<session_id>.md`, `pre-write-gate.sh:461`),
but two agent-facing surfaces still pointed at the SHARED scratch:
1. **The packet INJECTION** (`on-prompt-submit.sh`) read `${STATE_DIR}/must-do-summary.md` — the shared
   file, which holds whatever session wrote last. So an agent's `[MUST-DO ACTIVE]` injection showed
   ANOTHER session's summary → the agent read it and tried to overwrite it.
2. **Every authoring/block message** told the agent to "Write .claude/state/must-do-summary.md" (the shared
   file), reinforcing the collision.
(The per-session snapshot prevented actual data loss, but the shared scratch was confusing and the agent
should never touch it.)

## The fix (each session writes + sees its OWN lane)
1. **Injection is per-session** (`on-prompt-submit.sh`): reads `must-do-summary.${HARNESS_SESSION_ID}.md`
   (+ its per-session step file). With a session id but no own summary yet → injects NOTHING (never a
   peer's). Falls back to the shared file only when there is no session id (back-compat).
2. **Every authoring/block message names the session's OWN lane** — packet action, and the pre-write-gate
   `no_file` / `stale_step` / long-help blocks + pre-bash-gate blocks now print
   `.claude/state/must-do-summary.<session_id>.md` and say *"write THAT exact file — never the shared
   must-do-summary.md or another session's."*
3. Nothing else needed: the gate already validates the per-session summary and writes the per-session step
   file (`pre-write-gate.sh:587`, keyed by `CUR_SESSION`); `post-write-check` still snapshots the shared
   file for back-compat, so an agent that writes either path is covered.

## Proof
- `tests/test-mustdo-summary-lane.sh` **6/0**: with a shared scratch holding A's summary, session B's
  packet does NOT leak A's summary; B's packet names B's own lane; after B authors it, B sees B's and not
  A's; A sees A's and not B's (isolated both directions).
- Full must-do regression **88/0** (summary-lane 6, session-aware 23, session-owned 10, default-on 11,
  pack 25, default-fanout 9, fanout-gate 4) + killswitch 22/0, killswitch-resolve 7/0, nested-root 12/0,
  no-autocreate 6/0, fresh-folder 8/0; `bash -n` clean.
- **Independent validator: PASS** (A–F) — reproduced in its own sandboxes; no summary leaked into any
  packet in either direction; gate still allows a valid per-session summary; back-compat (no session id →
  shared) intact; live↔`_install` byte-identical on all 3 files.

## Not changed (deliberate)
The generic "GATES AHEAD" forward-hint still prints the bare shared path — it is a non-binding preview, not
the authoring/block instruction (which are all lane-correct). Threading the session id through that helper
in `lib-helpers.sh` would add risk to a validated fix for no functional gain.

## One line
Each session now writes AND sees only its OWN must-do summary lane (`must-do-summary.<session_id>.md`); the
packet never injects a peer's summary and every message names the session's own file — so agents stop
reading and overwriting each other's summaries.
