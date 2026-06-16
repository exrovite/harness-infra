# Must-Do Summary — Per-Session Summary Files (race fix)

Task: parallel sessions in one project were clobbering the shared `.claude/state/must-do-summary.md`,
so the session-ownership check thrashed. Fix: each model validates against its OWN per-session file
`must-do-summary.<session_id>.md`, written by post-write-check.sh from the model's canonical
must-do-summary.md write. The per-session file is the ownership proof (replaces the owner file).

Files I have read and must respect:
1. **gentle-mapping-hejlsberg.md** — approved plan for default-on must-do; kill-switch always wins;
   exempt docs/ and *.md to avoid deadlock.
2. **_install/hooks/pre-write-gate.sh** + live — per-session SUMMARY_FILE/STEP_FILE resolution; remove
   old owner block; keep length/mentions/staleness checks against the per-session file.
3. **_install/hooks/pre-bash-gate.sh** + live — mirror per-session check (replace owner check).
4. **_install/hooks/on-prompt-submit.sh** + live — advisory uses per-session file existence.
5. **tests/test-mustdo-default-on.sh** + test-mustdo-session-owned.sh — rewrite to per-session model;
   add a race test (session B's writes never break session A's grounding).

Constraints: isolated venvs only; never break the Anthropic API; Anthropic models only. Mirror every
hook edit live<->_install; run full suite; spawn EVALUATE verifier before commit.
