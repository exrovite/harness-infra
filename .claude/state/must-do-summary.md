# Must-Do Summary — Default-On Must-Do System

Task: invert the must-do system from opt-in to default-on, switchable off only via the `---` kill-switch.

Files I have read and must respect:

1. **gentle-mapping-hejlsberg.md** (approved plan) — defines three changes: Change 1 pre-write-gate.sh no-folder else-branch (DONE, verified); Change 2 pre-bash-gate.sh mirror to close the bash bypass (NEXT); Change 3 on-prompt-submit.sh advisory action (~lines 454-488). Kill-switch always wins (checked at top of every gate). No-folder branch must exempt `docs/` and `*.md` to avoid deadlock. Out of scope: +++pack PLAN gate, MCQ generator, evidence-checkpoint.

2. **_install/hooks/pre-write-gate.sh** + live copy — Change 1 already applied as an `else` branch on `if [ -n "$MUST_DO_MD" ]`. Must stay byte-identical live↔_install after sync.

3. **_install/hooks/pre-bash-gate.sh** + live copy — must insert mirrored must-do enforcement after the phase gate (after the `fi` closing BUILD-only phase gate, before `# Ralph STUCK`). BUILD-scoped, exempt docs/ and .md, honor kill-switch.

4. **_install/hooks/on-prompt-submit.sh** + live copy — advisory packet action when no folder in BUILD.

5. **tests/test-mustdo-default-on.sh** — 11 checks via HARNESS_STATE_DIR sandbox driving live hooks. Pre-write tests 1-5 pass; pre-bash 6a/6b need Change 2.

Constraints carried forward: isolated venvs only; never break the Anthropic API connection; Anthropic models only. Mirror every hook edit to both live and _install; run full suite; spawn EVALUATE verifier before commit.
