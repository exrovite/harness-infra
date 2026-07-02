# Sprint 50 — All audit findings fixed (2026-07-02)

Goal (user): "fix all found errors making sure the harness still works properly at the end.
ensure beast mode does what it is meant to do."
Findings: `.claude/reports/audit-2026-07-01-remaining-problems.md`. Contract:
`.claude/contracts/sprint-50-contract.md`. Criteria: `evaluation-criteria-sprint-50.md` (AC1-AC18).

## What was fixed (all mirrored live ↔ _install, bash -n clean)

**Deadlock cluster**
- A1 (`pre-write-gate.sh` watcher admin lock): now exempts the Agent tool and all harness-state
  paths (.claude/state, watchers, pre-flight, contracts, specs, agent-memory, evidence, agentwiki,
  .lavish-axi). Source writes stay locked. The packet's "ALWAYS WRITABLE" promise is now true (A4).
- A3 (must-do summary gate): Agent tool / empty-target calls are exempt — verifier subagents can
  always be spawned.
- A2 (`beast-protocol-gate.sh`): Bash is only gated when the command can WRITE; read-only commands
  pass silently; Bash writes to `protocol-ack.*` / `.claude/state/` / `.beast/` / `.agent-memory/`
  pass (the gate's own escape hatch — closes the self-deadlock that trapped the audit session).
- B1: `.claude/evidence/` added to the phase gate, strategy-loop, must-do (both arms), and
  default-on exemption lists in pre-write-gate (pre-flight-gate already had it).
- A5 (`write-count`): PER-SESSION (`write-count.<sid>.txt`) across post-write-check, both gates and
  the packet — every session genuinely gets its 2 free writes; the 1100+ cumulative counter no
  longer pre-locks new sessions. Interaction fix: `startup-recovery.sh` phantom-cron clearing now
  spares the CURRENT session and any session with a fresh heartbeat (found live: the per-session
  counter made every first write run startup-recovery, which wiped the just-recorded cron).

**Enforcement integrity**
- B3 (`generate-pre-flight-challenge.sh` / `validate-pre-flight.sh`): answer labels moved to a
  sidecar `answer-key` file the agent is never pointed at; challenge.md carries NO key (verified
  live on this session's own MCQ). Distractors that appear verbatim in the question's source file
  are filtered out. Validator reads the sidecar (challenge-comment fallback for old challenges) and
  consumes it on PASS.
- C3 (`validate-pre-flight.sh` hardening): `last_reset` is stamped when the 5-strike hardening
  arms (it was never set → the unblock path was unreachable); a fresh verification-ledger entry now
  UN-hardens and resets the counter.
- B2 (`pre-bash-gate.sh`): detects `dd/truncate of=`, `git apply`, `patch -`/`patch <`, `perl -e`
  writes, `rsync src dst`. (`>>` was already caught — the audit overcounted that one.)

**Robustness**
- B4 (`on-prompt-submit.sh`): staged packet trimming — over the 2000-char cap the must-do echo is
  shrunk to 200 chars, then dropped, then WARNINGS dropped; hard tail-cut only as last resort, so
  BLOCKED BY / ACTIONS are no longer silently lost.
- C4 (`build-mustdo-pack.sh`): grounding list is newline-separated and space-safe (one link per
  existing path — "docs/must do/x file.md" works); legacy word-split fallback kept.

**Beast mode does what it's meant to do**
- D1 (`beast-wins-extract.sh`): report REQUESTS are no longer counted as validations (that was 10
  of 16 stored "wins"); noise filter also drops /goal command echoes and Stop-hook system lines;
  negation catches "I don't think it has worked". `.beast/validated-wins.jsonl` regenerated:
  16 noisy entries → 3 genuine validations (pre-sprint copy in `.claude/evidence/`).
- A2 above stops the gate from firing on reads. All beast suites remain in the regression run.

**Hygiene**
- C1/E4: `REGISTRY.json` pruned — legacy `.instances[]` (12 zombie rows), `max_lanes_per_project`,
  and `available` placeholder rows removed (pre-sprint copy in `.claude/evidence/`).
  `startup-recovery.sh` stale/orphan reaps now REMOVE entries instead of recreating placeholders.
- E1/E2/E3: phase advanced through NEGOTIATE→BUILD Sprint 50 properly (contract + criteria +
  spec); ~17 dead artifacts moved to `.claude/state/archive/`; `backlog.json` and
  `knowledge-gaps.json` regenerated to reflect reality (only D3/D4/D6/D8 + optional bridge remain).
- Repaired two pre-existing red suites: `test-preflight-session-keyed.sh` (rewritten to fake-HOME
  sandbox — it predated Sprint 47's session-keyed slot lookup) and
  `test-headroom-last30days-integration.sh` A10 (step label `[10/10]` → `[10/1x]`, install grew to
  11 steps).

## TDD evidence
- `tests/test-audit-fixes-sprint50.sh`: RED 12/30 before fixes (`.claude/evidence/sprint50-tdd-red.txt`),
  GREEN 30/30 after (`sprint50-tdd-green.txt`). All [keep] anti-regression assertions passed on BOTH runs.
- Baseline before any change: `.claude/evidence/sprint50-baseline.txt` (45 suites; 2 pre-existing reds,
  both repaired). Post-fix full regression: `sprint50-postfix.txt`.

## Dispositions (AC18 — documented, not code-fixed)
- **A6 headless `claude -p`**: machine-level GLM env (`ANTHROPIC_API_KEY`) hijacks headless auth.
  Workaround (proven this sprint): `env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_BASE_URL claude -p ...`.
  Fixing it in the GLM launcher is out of scope (user's GLM setup must stay untouched).
- **Audit C2 "phantom crons"**: CronCreate jobs are session-only and die with their session; a
  reaped registry entry removes the id with it. No orphan process exists — the audit finding is
  downgraded to cosmetic. (startup-recovery's cron clearing remains, now liveness-aware.)
- **Audit B5 fallback**: project-level watcher counting only runs when no session id exists
  (tests / non-session callers) — by design; all live sessions use session-keyed lookups.
- **cron_pause churn**: the pause suppresses the printed reminder; the CronCreate job still firing
  each interval is a scheduler property hooks cannot change. Recorded in knowledge-gaps.json.
- **ralph-mode.json**: left in `.claude/state/` — it is user-controlled and the gate (correctly)
  refuses agent moves of it. Remove manually if unwanted.
- **D3/D4/D6/D8** beast backlog: unchanged, tracked in the regenerated backlog.json.
- **Audit C5 note**: startup-recovery loop word-splitting left as-is — the iterated tokens are
  `slot|timestamp` pairs that cannot contain spaces; registry stale-lock PID check not added
  (mkdir-lock has no PID file; 10s timeout is the accepted design).
- **Audit AC8 correction**: hardening DID block (audit overcalled); the real bug was that it could
  never UNBLOCK — fixed as described.

## BUILD iteration 2 (after independent verifier FAIL — the process worked)
The first verifier run returned FAIL with four findings, all fixed:
1. **AC7 was reported built but was NOT in the file** — the staged-trimming edit had been silently
   lost in a gate-block shuffle (blocked by the cron gate mid-retry, never re-applied). Now
   genuinely implemented in on-prompt-submit.sh (verified by grep + new AC7a-c tests, 33/33 suite).
   This false completion claim is exactly what builder/verifier separation exists to catch.
2. **Two suites went red from intentional behavior changes**: test-beast-wins-extract.sh updated to
   the new D1 semantics (report-request EXCLUDED); test-fresh-folder-no-claude.sh updated to the
   per-session counter filename. Assertions modernized, no tests removed.
3. **startup-recovery.sh loops** converted to `while IFS= read -r` process-substitution (AC10).
4. **Evidence quality**: the earlier regression logs piped through `tail`, masking exit codes, and
   "2 pre-existing reds" undercounted — ralph-loop had 2 more (test 7 asserted a message string
   that never shipped and pre-dated the auto-transition feature; test 41 asserted an 800-char cap
   superseded by the 2000-char contract cap in Sprint 21). Both cases modernized and now GREEN —
   ralph-loop 36/0. Final sweep with REAL exit codes: 43 suites, 0 failures
   (`.claude/evidence/sprint50-final-sweep.txt`; earlier "46" counted duplicated log headers).

## BUILD iteration 3 (residual B1, found live during COMPLETE prep)
Writing the sweep evidence via Bash in EVALUATE was blocked: `pre-bash-gate.sh`'s bootstrap
exemption list lacked `.claude/evidence/` (the audit's B1 fix covered pre-write-gate and
pre-flight-gate only). Added the exemption (+ AC4c test), mirrored to _install — the harness no
longer blocks its own evidence pipeline in verification phases.

## Verification
Independent verifier (adversarial, default-FAIL): first run FAIL (4 findings above), re-verified
after fixes — verdict in `.claude/state/evidence-verdict.json`.

## Sprint 51 addendum — install pack shipped complete + Linux-ready (2026-07-02)
Committed+pushed through 9fcece3. Verified by independent verifier (3 rounds, PASS AC1-AC8):
- CRLF purged from shipped files (validate-pre-flight.sh, claude-hr.sh, settings.json,
  REGISTRY-template.json) + .gitattributes pins eol=lf so Windows checkouts can't regress it.
- install.sh: hard jq prerequisite check; npm/uv/git/GLM steps guarded; chmods everything.
- REGISTRY-template.json was v1.0.0 with THIS machine's old watcher claims baked in (leaked
  project names, seeded fresh installs with phantom watchers) -> clean v3 empty pool.
- post-write-check.sh:158 hardcoded C:\Users\<user> path -> ~/.openclaw/watchers/ (caught by the
  verifier's drive-letter scan).
- Completeness: full live<->_install parity; justified exceptions only (headroom-supervisor.sh
  machine copy vs shipped glm.enabled-gated template; pack-only glm-setup.sh). Windows-only
  commands exist solely inside uname-guarded branches. Full 43-suite sweep: zero failures.
