# Evaluation Criteria — lavish-axi Harness Integration (Sprint 32)

An independent verifier (does NOT read progress notes) must confirm ALL of the following against the
live output. Default verdict FAIL.

## Install
- [ ] `_install/install.sh` has a step that installs `lavish-axi@0.1.20` globally via npm.
- [ ] If node/npm is missing, the installer WARNS and CONTINUES (harness install still succeeds).
- [ ] Re-running the installer is idempotent (no duplicate hooks, no error).

## Always-on SessionStart hook
- [ ] `_install/settings.json` contains a `hooks.SessionStart` entry that runs lavish's ambient-context command.
- [ ] The SessionStart entry coexists with existing `PreToolUse`, `PostToolUse`, `Stop`, `UserPromptSubmit` (none removed/altered).
- [ ] The live `~/.claude/settings.json` carries the same SessionStart entry and remains valid JSON.

## Gate exemptions for .lavish-axi/
- [ ] Writing under `.lavish-axi/` is exempt in `pre-write-gate.sh` (all exemption lists).
- [ ] `.lavish-axi/`-writing Bash commands are exempt in `pre-bash-gate.sh`.
- [ ] `pre-flight-gate.sh` does not gate `.lavish-axi/` writes.

## Skill
- [ ] A skill exists (e.g. `~/.claude/skills/lavish-review/`) that ensures a lavish session for an HTML file and polls for feedback.
- [ ] The skill pauses the watcher cron around the (blocking) poll and resumes after.
- [ ] Sandbox/dry run of the skill's wrapper logic behaves correctly (no live browser needed for the test).

## License
- [ ] `_install/LICENSES/` (or equivalent) contains lavish-axi's and axi-sdk-js's MIT notices.

## Regression (no harness ability broken)
- [ ] `bash -n` clean on every modified hook/script.
- [ ] All existing test suites pass (watcher pool, sprint31a, sprint29, evidence, preflight-session-keyed).
- [ ] New lavish tests pass.

## Verdict
PASS only if every box is checked with observed evidence. Any unchecked → FAIL with the specific gap.
