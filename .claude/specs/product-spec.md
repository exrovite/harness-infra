# Product Spec — Secret-Safe GLM Add-On for the Install Pack (Sprint 34)

## Problem
`claude-glm` (GLM via z.ai, routed through the headroom 8791 compression proxy) was fixed on this
machine, but the fix lives entirely OUTSIDE the repo:
- the launcher (`~/AppData/Roaming/npm/claude-glm.cmd`) contains the z.ai token in cleartext
- the 8791 GLM proxy is only in the hand-edited live supervisor (`~/.headroom`)
- the `CLAUDE_CONFIG_DIR` isolation (the actual OAuth-hijack fix) has no template

So shipping the harness ships headroom but NOT GLM. We want GLM to be a first-class, installable,
secret-safe part of `_install`.

## What to build (WHAT, not HOW)
1. **Launcher templates**, cross-platform, with the z.ai token as a placeholder (never a real secret):
   - Windows `.cmd` and Linux/mac shell wrapper
   - Each sets a dedicated `CLAUDE_CONFIG_DIR` (no OAuth login -> clean z.ai auth), clears
     `ANTHROPIC_API_KEY`, sets `ANTHROPIC_AUTH_TOKEN`, points `ANTHROPIC_BASE_URL` at the 8791 proxy,
     pins model **glm-5.1**.
2. **Dual-proxy supervisor variant** (`.ps1` + `.sh`): keeps 8787 -> Anthropic (untouched) AND
   8791 -> z.ai alive. Used only when GLM is enabled; otherwise the existing single-8787 supervisor ships.
3. **Guarded install step** in `install.sh`:
   - GLM is **opt-in**. Enabled only when a z.ai key is supplied (env `ZAI_API_KEY` or interactive prompt).
   - No key -> installs the normal single-8787 supervisor, **zero behavior change**. `set -e` safe; skips
     cleanly with a warning, like the existing node/uv-optional steps.
   - On enable: writes the real launcher (token injected) to a **gitignored** local path, installs the
     dual supervisor, creates the isolated GLM config dir.
4. **Secret hygiene**: `.gitignore` the generated real launcher; only the placeholder template is tracked.
5. **Tests (TDD)**: keep `tests/test-glm-headroom.sh` (live-setup tests); add packaging tests that prove
   the template has no real secret, the install step is guarded, and the dual supervisor carries both ports.

## Constraints
- **Do NOT touch the live working setup** (`claude-glm.cmd`, `~/.headroom` dual supervisor,
  `~/.claude-glm-config`). The packaging must reproduce it, not disturb it.
- **Do NOT touch the normal `claude` path** (settings.json -> 8787 -> api.anthropic.com).
- **Never commit the real z.ai token.**
- MSYS-safe bash throughout (no `sed 's|\\|/|'`; trailing-newline-safe read loops).

## Out of scope
- Changing model from glm-5.1.
- Compression-effectiveness tuning (routing is proven; savings show on real long sessions).
- Re-running/altering the live GLM verification.
