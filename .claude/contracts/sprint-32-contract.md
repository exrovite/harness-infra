# Sprint 32 Contract — lavish-axi Harness Integration

## Scope (what I will build)
Integrate lavish-axi into the Enhanced Agent Harness, harness-native, shipped in `_install`.

### Deliverables
1. **Installer step** (`_install/install.sh`): new step `[8]` installs `lavish-axi@0.1.20` globally
   (`npm i -g lavish-axi@0.1.20`). Guarded: if `command -v npm` fails → print WARN, `continue`, exit 0
   path unaffected (`set -e` must not abort the harness install). Idempotent (re-run safe).
2. **Always-on SessionStart hook**: bake lavish's SessionStart entry into `_install/settings.json`
   under `.hooks.SessionStart`, captured verbatim from a SANDBOX `lavish-axi setup hooks` run so the
   command string is exactly what upstream uses. Apply the same entry to live `~/.claude/settings.json`
   via a marker-aware merge (never overwrite existing hooks). Both files remain valid JSON.
3. **Gate exemptions** for `.lavish-axi/`: add to every exemption list in `pre-write-gate.sh`,
   `pre-bash-gate.sh`, `pre-flight-gate.sh` (mirror the `agentwiki/` / `.claude/state/` pattern).
4. **Skill** `~/.claude/skills/lavish-review/SKILL.md` (+ copy in `_install/`): documents the wrapper
   flow — ensure session (`lavish-axi <file> --no-open`), `cron_pause` for poll duration, `lavish-axi
   poll <file>`, return feedback, `cron_resume`. Plus a helper `lavish-review.sh` encapsulating the
   pause/poll/resume so an agent runs one command.
5. **License**: `_install/LICENSES/lavish-axi-LICENSE` + `axi-sdk-js-LICENSE` (MIT text + copyright),
   and a NOTICE line in `_install/README.md` crediting both.
6. **Tests** (`tests/test-lavish-integration.sh`, TDD): assert installer has the guarded npm step;
   settings.json has SessionStart coexisting with the 4 existing hook types; `.lavish-axi/` is exempt
   in all 3 gates (drive the real gate logic / grep the exemption lists); skill + helper exist and the
   helper's pause/poll/resume sequence is correct (dry-run with a stub `lavish-axi`).

## Verification (how success is judged) — maps to evaluation-criteria.md
- C1 installer npm step present + node-absent-safe + idempotent.
- C2 SessionStart baked in `_install/settings.json` AND live settings, valid JSON, 4 prior hooks intact.
- C3 `.lavish-axi/` exempt in pre-write, pre-bash, pre-flight (proven by gate behavior or exemption-list grep).
- C4 skill + helper exist; helper pauses cron, polls, resumes (dry-run with stub binary).
- C5 MIT notices for lavish-axi + axi-sdk-js present in `_install/`.
- C6 `bash -n` clean; ALL existing suites green; new lavish suite green.
- C7 independent validator (default-FAIL) confirms every criterion against live output → PASS, zero bugs.

## Out of scope
- Editing lavish-axi/axi-sdk-js source. Cloud features. Replacing wait-for-human.
- Fixing the pre-existing ralph-loop test 7/41 failures (separate subsystem) — but they must not
  newly break (already red; not counted against this sprint).

## Constraints / risks
- Do NOT run `setup hooks` against live `~/.claude/settings.json` until verified in a sandbox HOME.
- `install.sh` uses `set -e`; the npm step must be wrapped so a failure cannot abort the install.
- Retain MIT notices (legal). Windows/MSYS gotchas (jq `\r`, no `setup hooks` clobber).
- Self-lock: keep my own watcher (slot 1) valid; bash -n + suites after every edit.

## Definition of done
All C1–C7 met; `_install` synced; committed; memory updated. Independent validator: PASS, no bugs.
