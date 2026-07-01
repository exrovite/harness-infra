# Phase Complete — Sprint 37 (Session-Aware Must-Do File-Exists Branch)

BUILD + EVALUATE complete. All contract criteria met (C1-C21 + migration C22-C24).

- Sprint 37 functional suite: 23/23 (live hooks, real mktemp + HARNESS_STATE_DIR sandboxes).
- Regression green: mustdo-session-owned 10/10, mustdo-default-on 11/11, mustdo-pack 25/25,
  killswitch 22/22; full test dir otherwise green.
- bash -n clean; live <-> _install byte parity = 0 on all 7 changed files.
- Independent strict validator: VERDICT PASS (own sandboxes, default-FAIL) — reproduced all 13
  headline behaviors incl. foreign-stamp block + migration legacy-pack block; confirmed
  copy-not-move (no deletion); no regressions; no deviations from agreement.
- Verdict: .claude/evidence/sprint-37-independent-validation.md
- Report: .claude/reports/sprint-37-session-aware-mustdo-report.md

Mechanism: hook-written first-line stamp `<!-- mustdo-session: <id> -->`; 3-arm routing in the
file-exists branch (no-stamp seed / mine / foreign); snapshot-then-write by COPY to
docs/must do/history/<base>.<cksum>.md (idempotent); migration = unstamped agent-pack signature
treated as foreign so PRE-EXISTING leftover files in project folders no longer free-pass a new
session, while plain human lists stay shared seeds.

Three pre-existing, unrelated suite failures (preflight-session-keyed, headroom-last30days,
ralph-loop) confirmed NOT caused by this sprint via HEAD-revert causality checks.
