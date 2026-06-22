# Sprint 37 — Independent Strict Validation: Session-Aware Must-Do File-Exists Branch

**Validator:** independent sub-agent (default-FAIL). Did NOT read progress notes or builder report.
**Method:** fresh `mktemp` sandboxes driving the LIVE hooks/scripts via stdin JSON + `HARNESS_STATE_DIR`.
**Date:** 2026-06-22

## VERDICT: PASS

All 13 required behaviors reproduced with my own evidence, including the two FAIL-gating
headlines (behavior 1 foreign-stamp block, behavior 12 legacy-pack migration). No must-do file
deleted (copy-not-move confirmed). Live ↔ `_install` byte parity intact. All suites green.

## Behaviors 1–13 (observed rc / evidence)

| # | Behavior | Result | Observed |
|---|----------|--------|----------|
| 1 | Foreign-stamp BLOCK (stamp SESS_A, valid summary SESS_B, src write SESS_B) | PASS | rc=2, "[MUST-DO OWNERSHIP] BLOCKED ... authored by a different session" |
| 2 | Own-stamp allowed (stamp SESS_A, summary SESS_A, src write SESS_A) | PASS | rc=0 |
| 3 | Human seed: plain unstamped + valid summary → rc0; + NO summary → rc2 (ordinary summary gate) | PASS | rc=0 / rc=2 "[EVIDENCE GATE] BLOCKED ... write .claude/state/must-do-summary.md" |
| 4 | No deadlock: under foreign stamp, write targeting must-do.md itself | PASS | rc=0 |
| 5 | History via pack: `build-mustdo-pack.sh --own --session SESS_B --no-transcript` | PASS | old `UNIQUE_MARKER_XYZ123` now in `history/must-do.3577407436.md`; new must-do.md first line `<!-- mustdo-session: SESS_B \| built: pack -->` |
| 6 | History via gate (manual write to foreign must-do.md, diff session) | PASS | rc=0; old `MARKER_GATE_456` copied to `history/must-do.3992253050.md` |
| 7 | Idempotent history: repeat #6 identical content | PASS | exactly 1 file in `history/` after two attempts |
| 8 | No-session back-compat (no session_id, stamped file, shared summary) | PASS | rc=0 (ownership inert) |
| 9 | Kill-switch superset (foreign stamp + harness-disabled.flag) | PASS | rc=0 |
| 10 | Bash mirror (pre-bash-gate): foreign stamp+summary → rc2; own stamp → rc0 | PASS | rc=2 ownership block / rc=0 |
| 11 | Stamp inert to readers: stamped must-do.md, src write no summary | PASS | "Files listed" prints `docs/ref-one.md` only; `grep -c mustdo-session` of output = 0 |
| 12 | MIGRATION legacy agent pack (UNstamped + `current task pack`/`Auto-built by build-mustdo-pack`/`raw-conversation`) | PASS | rc=2, ownership BLOCKED (treated as foreign leftover) |
| 13 | MIGRATION plain human list (UNstamped, no signature) + valid summary | PASS | rc=0 (stays shared seed, NOT foreign) |

### Extra independent confirmations
- **Copy-not-move (N1/C12):** after gate snapshot, original must-do.md still present AND still
  contains `ORIG_MARKER` (gate only copies; never writes/deletes); history copy present. No orphan.
- **C14 history invisible:** populated `history/` ignored by resolution; root file resolves, rc=0.

## Suite counts (run myself from `G:\harness infra`)
- `test-mustdo-session-aware.sh` — **23 passed, 0 failed**
- `test-mustdo-session-owned.sh` — **10 passed, 0 failed**
- `test-mustdo-default-on.sh` — **11 passed, 0 failed**
- `test-mustdo-pack.sh` — **25 passed, 0 failed**
- `test-killswitch.sh` — **PASS=22 FAIL=0**

## bash -n (live, 7 changed files) — all clean
pre-write-gate.sh · pre-bash-gate.sh · post-write-check.sh · on-prompt-submit.sh ·
lib-helpers.sh · build-mustdo-pack.sh · generate-pre-flight-challenge.sh — all OK.

## Live ↔ `_install` byte parity (diff per file) — all empty
- hooks/pre-write-gate.sh — OK
- hooks/pre-bash-gate.sh — OK
- hooks/post-write-check.sh — OK
- hooks/on-prompt-submit.sh — OK
- scripts/lib-helpers.sh — OK
- scripts/build-mustdo-pack.sh — OK
- scripts/generate-pre-flight-challenge.sh — OK

## REGRESSIONS / BREAKAGE
None observed. No-folder regression confirmed: a sandbox with no `docs/must do/` + a BUILD source
write still hits the default-on create branch (rc=2, "This project has no must-do grounding yet"),
unchanged.

## DEVIATIONS FROM AGREEMENT
None. Mechanism matches the agreement verbatim: hook/script-only deterministic stamp; gate routing
(no stamp → summary; own stamp → summary; foreign stamp → create); archive-to-`history/` by copy,
never delete; `find -maxdepth 1` keeps `history/` out of resolution; unstamped plain human list stays
a shared seed while unstamped legacy agent packs are treated as foreign (the user-added migration
rule, C22-C24). pre-bash-gate twin mirrors pre-write-gate.
