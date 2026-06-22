# Sprint 35 Contract — Beast-Mode Foundation (toggle + curated capture/init)

## Scope (what will be built)
Pillars 1 (toggle) and 2 (capture/init) of beast-mode. `beast-on` / `beast-off`
exact-match toggle with the agreed truth table and harness-superset rule; project
memory initialization into mempalace wing `harness_infra` (curated drawers + KG
facts), idempotent, no CMD windows. Recall/surfacing/uptake are NOT in this sprint.

## Locked NEGOTIATE decisions
- **N1 — Pack boundary:** the deliverable is (a) a deterministic **pack-plan
  emitter** (curated file list + the exact KG facts to add, as data) and (b) the
  wiring that drives the mempalace writes once on `beast-on` via the MCP/CLI path.
  The plan-emitter is unit-testable without the server; the real writes are
  exercised in the integration test (C-series) against a disposable wing.
- **N2 — KG granularity:** seed conservatively — **one fact per settled feature**
  already in MEMORY.md (~10–15 facts), each linked to its dossier drawer via
  `source_drawer_id`. No finer granularity this sprint.
- **N3 — Test isolation:** pack integration tests use wing `harness_infra_test`
  and delete it on teardown; pack test SKIPS loudly if the MCP server is
  unreachable (toggle tests remain a hard PASS bar).

## Files
1. **`lib-helpers.sh`** — add `beast_is_on [dir]`, `beast_enable [dir]`,
   `beast_disable [dir]`; default dir resolved by project root via existing
   `find_project_state_dir`. Atomic flag write/delete; tolerate missing dir.
2. **`on-prompt-submit.sh`** — after the existing `---`/`===` handling, add
   exact-match handling for `beast-off` (check FIRST) and `beast-on`:
   - `beast-on` → if `harness_is_disabled`, `harness_enable` first and print the
     exact notice `[HARNESS RE-ENABLED — beast mode requires active gates]`;
     `beast_enable`; trigger the one-time pack if wing not yet initialized;
     banner `[BEAST MODE ON — {project}]`.
   - `beast-off` → `beast_disable`; banner `[BEAST MODE OFF]`; harness untouched.
   - extend `---` handling → also `beast_disable` (clear beast flag).
   - `===` unchanged re: beast (harness on only; beast stays off).
3. **`beast-pack-plan.sh`** (new) — emits the deterministic pack plan: the curated
   source file list (per manifest) and the KG facts (subject/predicate/object/
   valid_from) to add. Pure, no MCP calls, no side effects; output is stable text.
4. **`docs/applying fussion ideas/seed-manifest.md`** (new) — the curated source
   list (INCLUDE: `…/projects/G--harness-infra/memory/*`, `.agent-memory/core/*`,
   `.agent-memory/semantic/domain/*`, `.agent-memory/episodic/decisions/*`,
   `.claude/reports/*`; EXCLUDE: `.agent-memory/episodic/sessions/*`, raw scripts,
   hook source).
5. **`_install/` mirror** — copy the changed `lib-helpers.sh`, `on-prompt-submit.sh`,
   `beast-pack-plan.sh` into the matching `_install/{scripts,hooks}` paths.
6. **`tests/test-beast-toggle.sh`** (new) — pure-bash, sandboxed `HARNESS_STATE_DIR`,
   pipes prompt JSON through the LIVE `on-prompt-submit.sh`.
7. **`tests/test-beast-pack.sh`** (new) — runs the pack for real into
   `harness_infra_test`, queries mempalace, asserts, cleans up; SKIPs if server down.

## Acceptance criteria (verifier checks ALL; default FAIL)
**Toggle (live hook):**
- C1. `beast-on` (harness on) → `beast-mode.flag` present; banner has `BEAST MODE ON`.
- C2. `beast-on` (harness disabled) → `harness-disabled.flag` removed AND
  `beast-mode.flag` present; banner contains the EXACT string
  `[HARNESS RE-ENABLED — beast mode requires active gates]` (per D2) AND
  `BEAST MODE ON`.
- C3. `beast-off` → `beast-mode.flag` removed; `harness-disabled.flag` still absent.
- C4. `---` while in beast mode → `harness-disabled.flag` present AND
  `beast-mode.flag` removed.
- C5. `===` after that `---` → `harness-disabled.flag` removed AND `beast-mode.flag`
  still absent (no auto-resume).
- C6. Exact-match only: `beast-on please` does NOT toggle; whitespace-padded
  `  beast-on  ` DOES.
- C7. `beast-off` never triggers the ON path (no prefix collision).
**Helpers / resolution:**
- C8. `beast_*` helpers exist; called from a cwd ≠ project root, the flag lands in
  the PROJECT's `.claude/state/`, not cwd.
**Pack (real mempalace, disposable wing):**
- C9. After pack, wing `harness_infra_test` has > 0 drawers (was 0).
- C10. Wing-scoped semantic search for a seeded concept returns a match under the
  agreed cutoff.
- C11. `kg_stats` shows > 0 entities and > 0 facts; `kg_query` on a seeded entity
  returns a typed fact with `valid_from`.
- C12. Exclusions: no packed drawer's `source_file` is under
  `episodic/sessions/`, raw scripts, or hook source.
- C13. Idempotent: second pack run does not duplicate drawers/facts.
- C14. Pack uses the MCP/CLI path — no spawned interactive terminal; legacy
  auto-capture hook remains absent from `settings.json`.
**Non-regression / hygiene:**
- C15. `tests/test-killswitch.sh` still passes unchanged.
- C16. Beast OFF + harness ON → normal packet, no beast injection.
- C17. `_install` copies byte-equivalent to live for every changed file.
- C18. `bash -n` clean on all modified/added `.sh`; MSYS-safe (`tr` not `sed`
  backslash, `\r`-stripped, no here-strings, read loops tolerate no trailing NL).
- C19. `beast-pack-plan.sh` is pure: produces identical output on repeat runs and
  performs zero writes.
**Evidence / separation:**
- C20. Both test scripts written TDD-FIRST and shown to FAIL before implementation
  (evidence captured in progress notes); PASS after.
- C21. An independent verifier sub-agent re-runs both scripts from scratch (not
  reading builder notes) and returns PASS on C1–C19.

## TDD (functional, tests reality)
Write `tests/test-beast-toggle.sh` and `tests/test-beast-pack.sh` FIRST. They must
FAIL before the toggle/helpers/initializer exist (no flag transitions; empty
wing). The toggle test drives the REAL hook; the pack test writes to and reads
from the REAL mempalace (disposable wing). No criterion is satisfied by source
inspection or mere file existence.

## Out of scope
Recall injection, the deterministic surfacing scan, tripwire/dossier capture at
birth events, the reconcile-gate, adversarial framing, the A/B tripwire behavioral
test (sprints 36–37). No edits to any existing sprint/spec/contract file.

## Revision: 1 (accepted after sceptical self-review in sprint-35-proposal.md).
