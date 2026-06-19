# Sprint 34 Contract — Secret-Safe GLM Add-On for the Install Pack

## Scope (what will be built)
Package the proven `claude-glm` fix into `_install`, secret-safe and opt-in. Design B: marker-gated
dual-capable supervisor (no secret in supervisor); secret only in a gitignored generated launcher.

## Files
1. **`_install/scripts/headroom-supervisor.ps1`** — add a marker-gated 8791 block. When
   `~/.headroom/glm.enabled` exists, also keep 8791 (`--anthropic-api-url https://api.z.ai/api/anthropic`,
   log `proxy-glm.jsonl`) alive in the watchdog loop. 8787 block unchanged. No token.
2. **`_install/scripts/headroom-supervisor.sh`** — same marker-gated 8791 block, Unix form.
3. **`_install/templates/claude-glm.cmd.template`** — Windows launcher: `CLAUDE_CONFIG_DIR` isolation,
   `set ANTHROPIC_API_KEY=`, `set ANTHROPIC_AUTH_TOKEN=__ZAI_API_KEY__`, `ANTHROPIC_BASE_URL=http://127.0.0.1:8791`,
   `API_TIMEOUT_MS`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`, all model slots = `glm-5.1`.
4. **`_install/templates/claude-glm.template.sh`** — Unix launcher equivalent (exports + `exec claude`).
5. **`_install/scripts/glm-setup.sh`** — `enable` (default) / `disable`.
   - enable: require a z.ai key from `$1`, `$ZAI_API_KEY`, or interactive prompt (tty only); render the
     matching template (token injected) to the gitignored launcher path; `mkdir -p` the isolated
     `~/.claude-glm-config`; `touch ~/.headroom/glm.enabled`; nudge supervisor (best-effort). `set -u`,
     guarded, never echoes the token.
   - disable: `rm` marker + generated launcher; leave 8787 untouched.
6. **`install.sh`** — new **Step 11 (GLM, opt-in)**: if `GLM_INSTALL!=1` -> skip; elif a z.ai key is
   present (env `ZAI_API_KEY`) -> run `glm-setup.sh enable`; else -> print how to enable later and SKIP.
   `set -e` safe (all fallible cmds are `if` conditions). Update the final summary block with a GLM line.
   Bump the `[N/10]` step counters to `/11`.
7. **`.gitignore`** — ignore the generated launcher (`*.generated*` under templates and the local
   launcher output path pattern).
8. **`tests/test-glm-packaging.sh`** — asserts C1-C13 mechanically (sandboxed; no live browser/proxy).

## Acceptance criteria (verifier checks ALL; default FAIL)
C1. No real z.ai token (`[0-9a-f]{32}\.[A-Za-z0-9_-]+`) in ANY git-tracked file (`git grep` empty).
C2. Launcher templates use the `__ZAI_API_KEY__` placeholder.
C3. Generated launcher path is gitignored and untracked.
C4. Both a `.cmd` and a `.sh` launcher template ship in `_install`.
C5. Both templates set a dedicated `CLAUDE_CONFIG_DIR`.
C6. Both clear `ANTHROPIC_API_KEY` and set `ANTHROPIC_AUTH_TOKEN` from the placeholder.
C7. Both set `ANTHROPIC_BASE_URL` to the 8791 proxy and pin all model slots to `glm-5.1`.
C8. Both supervisors reference 8787 AND (marker-gated) 8791; supervisor holds no token.
C9. 8787 behavior preserved (agent-90, RUST_DETECT=0, watchdog loop).
C10. Marker absent -> only 8787 runs (no second proxy, equivalent to prior behavior).
C11. `install.sh` GLM step runs only with a key; absent key -> SKIP, no error, `set -e` safe.
C12. No key -> install path identical to today (no GLM artifacts, single-8787 supervisor behavior).
C13. GLM step never writes the token to a tracked file; writes the real launcher to the gitignored path.
C14. `tests/test-glm-headroom.sh` present and `bash -n` clean.
C15. `tests/test-glm-packaging.sh` asserts C1-C13 and passes.
C16. `bash -n` clean on every modified/added `.sh`; no MSYS sed/read pitfalls.
C17. Normal `claude` path + 8787 untouched by the GLM step when disabled.

## TDD
Write `tests/test-glm-packaging.sh` FIRST; it must FAIL before the templates/scripts exist, PASS after.

## Out of scope
Live setup changes; model != glm-5.1; compression tuning; re-running live GLM verification.

## Revision: 1 (accepted after sceptical self-review in proposal).
