# Sprint 35 — Evaluation Criteria (Beast-Mode Foundation)

Scope under test: toggle (D1, D2) + one-time curated bulk-pack / project
initialization (D3, D4). Every criterion is **functional** — verified by
exercising the REAL hook and the REAL mempalace, not by inspecting source or
checking file existence. The independent verifier runs the tests from scratch
and does NOT read the builder's notes.

## A. Toggle — exercised through the live hook
Tests pipe a real prompt JSON into the real `on-prompt-submit.sh` in a sandboxed
state dir (`HARNESS_STATE_DIR`), exactly as `tests/test-killswitch.sh` does.

- **A1** Prompt exactly `beast-on` (harness already ON) → `beast-mode.flag` exists
  afterward; banner contains `BEAST MODE ON`.
- **A2** Prompt exactly `beast-on` while harness is DISABLED
  (`harness-disabled.flag` present) → after the hook, `harness-disabled.flag` is
  GONE and `beast-mode.flag` exists; banner contains the EXACT re-enable notice
  string `[HARNESS RE-ENABLED — beast mode requires active gates]` AND
  `BEAST MODE ON`.
- **A3** Prompt exactly `beast-off` → `beast-mode.flag` is gone;
  `harness-disabled.flag` is still absent (harness untouched); banner `BEAST MODE OFF`.
- **A4** Prompt exactly `---` while in beast mode → BOTH `harness-disabled.flag`
  present AND `beast-mode.flag` gone.
- **A5** Prompt exactly `===` after that `---` → `harness-disabled.flag` gone
  (harness on) AND `beast-mode.flag` STILL absent (not auto-resumed).
- **A6** Exact-match only: `beast-on ` with trailing text like `beast-on please`
  does NOT create the flag; padded `  beast-on  ` (whitespace only) DOES toggle.
- **A7** No prefix collision: `beast-off` never triggers the ON path.
- **A8** `bash -n` clean on every modified script; runs without error on MSYS
  (no `sed` backslash subs, `\r`-safe).

## B. Helpers — unit-level, real invocation
- **B1** `beast_is_on` / `beast_enable` / `beast_disable` exist in `lib-helpers.sh`
  and operate on the resolved project-root state dir (verified by calling them
  from a different cwd than the project root and asserting the flag lands in the
  project's `.claude/state/`, not cwd).
- **B2** Helpers tolerate a missing state dir (create as needed), and are atomic.

## C. Bulk pack — exercised against REAL mempalace
Tests run the initializer for real, then query the palace and assert content.
To avoid polluting live state, the test packs into a disposable wing
(`harness_infra_test`) and deletes it on teardown.

- **C1** After packing, the target wing exists and `mempalace_status` /
  `list_wings` reports **> 0 drawers** in it (was 0 before).
- **C2** A semantic search scoped to the wing for a known seeded concept (e.g.
  "kill-switch resolves by project root") returns a matching drawer with cosine
  distance below the agreed cutoff.
- **C3** **KG is populated** (the current gap): after packing, `kg_stats` shows
  **> 0 entities and > 0 facts**, and `kg_query` on a seeded entity (e.g.
  `harness_kill_switch`) returns at least one typed fact with a `valid_from`.
- **C4** **Exclusions hold**: no drawer in the wing originates from
  `.agent-memory/episodic/sessions/`, raw scripts, or hook source (asserted by
  scanning `source_file` of packed drawers).
- **C5** **Idempotent**: running the pack twice does NOT duplicate drawers/facts
  (second run is a near-no-op; drawer count stable, dedup honored).
- **C6** **No CMD window / no blocking subprocess**: the pack completes via the
  MCP/CLI path; the test asserts the process returns cleanly with no spawned
  interactive terminal (and the legacy auto-capture hook remains absent from
  settings).

## D. Non-regression
- **D1** With beast OFF and harness ON, existing harness behavior is unchanged:
  `tests/test-killswitch.sh` still passes, and a normal prompt produces the normal
  packet (no beast injection).
- **D2** With the harness DISABLED (`---`), all gates still bypass as before
  (beast adds no new always-on cost when off).
- **D3** `_install` copies are byte-equivalent to the live versions for every
  changed file (parity check, as prior sprints require).

## E. Process / evidence
- **E1** A real test script (e.g. `tests/test-beast-toggle.sh`,
  `tests/test-beast-pack.sh`) exists, is committed, and PASSES — written BEFORE
  the implementation and shown to FAIL first (TDD evidence captured).
- **E2** Independent verifier (separate sub-agent) re-runs both test scripts from
  scratch and returns PASS on all A–D criteria. Builder may not self-certify.

## Definition of done
All A–E criteria pass under the independent verifier. The toggle truth table is
demonstrably correct against the live hook, and mempalace wing `harness_infra`
can be populated (drawers + KG facts) deterministically, idempotently, with
exclusions enforced and no CMD-window regression.
