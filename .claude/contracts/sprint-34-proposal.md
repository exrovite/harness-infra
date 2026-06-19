# Sprint 34 Proposal — Secret-Safe GLM Add-On

## Design decision: marker-gated dual supervisor (no secret in supervisor)
The 8791 proxy merely forwards to `https://api.z.ai/api/anthropic`; the z.ai **token is supplied by the
client (launcher)**, never by the proxy. So the supervisor carries NO secret. We make the supervisor
**dual-capable but gated** on a marker file `~/.headroom/glm.enabled`:
- marker ABSENT → supervisor keeps ONLY 8787 alive → behavior byte-identical to today (no-GLM case).
- marker PRESENT → supervisor ALSO keeps 8791 → z.ai alive.

This avoids task re-registration and gives a single, auditable code path. The secret lives only in the
generated launcher, which is gitignored.

## Deliverables
1. `_install/scripts/headroom-supervisor.ps1` + `.sh`: add marker-gated 8791 block (8787 untouched).
2. `_install/templates/claude-glm.cmd.template` + `_install/templates/claude-glm.template.sh`:
   launcher templates with `__ZAI_API_KEY__` placeholder, `CLAUDE_CONFIG_DIR` isolation, 8791 base URL,
   glm-5.1 pin, `ANTHROPIC_API_KEY` cleared.
3. `_install/scripts/glm-setup.sh`: given a z.ai key (env `ZAI_API_KEY` arg/prompt), (a) render the real
   launcher to a gitignored local path, (b) touch `~/.headroom/glm.enabled`, (c) create the isolated
   `~/.claude-glm-config` dir, (d) nudge the supervisor. `disable` removes marker + launcher.
4. `install.sh` step 11: opt-in. Runs `glm-setup.sh` only if a z.ai key is provided; else SKIP with a
   message, `set -e` safe, zero behavior change.
5. `.gitignore`: ignore the generated launcher(s).
6. Tests: keep `tests/test-glm-headroom.sh`; add `tests/test-glm-packaging.sh` asserting C1–C13.

## Success = all of evaluation-criteria.md (C1–C17), refined below to match design B.

## Self-review (sceptical)
- *"Does the supervisor change break the no-GLM case?"* No — 8791 block is inside `if marker exists`.
  Without the marker the loop does exactly what the single-proxy version did. Will verify byte-for-effect.
- *"Where does the secret end up?"* Only in the rendered launcher at a gitignored path. Template +
  all tracked files use the placeholder. Packaging test greps the whole tracked tree for the token regex.
- *"What if no uv/headroom?"* GLM step is independent of headroom venv presence for templating, but the
  proxy needs headroom; step 11 warns if headroom isn't installed and still writes the launcher (inert
  until proxy exists). `set -e` safe via `if` conditions.
- *"Cross-platform?"* `.cmd` for Windows, `.sh` for Unix; supervisor both `.ps1` and `.sh`.
- *"Live setup disturbed?"* No writes to `~/AppData/.../claude-glm.cmd`, live `~/.headroom` supervisor,
  or `~/.claude-glm-config` during BUILD/tests — tests use temp sandboxes.
