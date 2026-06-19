# Evaluation Criteria — Secret-Safe GLM Add-On (Sprint 34)

An independent verifier (sub-agent, does NOT read progress notes) must confirm ALL of the following
against the live `_install` tree and tests. Default verdict FAIL.

## Secret hygiene
- C1. No real z.ai token (`8b3cb44...`, or any `[0-9a-f]{32}\.[A-Za-z0-9_-]+`) appears in ANY git-tracked
  file. `git grep`/scan for the pattern returns nothing.
- C2. The launcher template uses an obvious placeholder (e.g. `__ZAI_API_KEY__` / `${ZAI_API_KEY}`).
- C3. The generated real launcher path is in `.gitignore` and is NOT tracked by git.

## Launcher template (cross-platform)
- C4. `_install` ships a Windows `.cmd` template and a Linux/mac shell template.
- C5. Both set a dedicated `CLAUDE_CONFIG_DIR` (isolation — the OAuth-hijack fix).
- C6. Both clear `ANTHROPIC_API_KEY` and set `ANTHROPIC_AUTH_TOKEN` from the placeholder.
- C7. Both point `ANTHROPIC_BASE_URL` at the 8791 proxy and pin all model slots to `glm-5.1`.

## Dual-capable, marker-gated supervisor (no secret in supervisor)
- C8. Both `headroom-supervisor.ps1` and `.sh` reference 8787 (-> anthropic) AND, gated behind a
  `~/.headroom/glm.enabled` marker, 8791 (-> z.ai api). The supervisor contains NO z.ai token.
- C9. The 8787/anthropic behavior is preserved (same profile agent-90, RUST_DETECT=0, watchdog loop).
- C10. With the marker ABSENT, the supervisor keeps ONLY 8787 alive — behavior is equivalent to the
  prior single-proxy supervisor (no GLM artifacts, no second proxy). The 8791 block runs only when the
  marker is present.

## Guarded install
- C11. `install.sh` GLM step runs ONLY when a z.ai key is provided (env or prompt); absent key -> skip
  with warning, no error, `set -e` safe.
- C12. With no key, the install path is identical to today (single-8787 supervisor; no GLM artifacts).
- C13. The GLM step never writes the token into a tracked file; it writes the real launcher to the
  gitignored local path.

## Tests & no-regression
- C14. `tests/test-glm-headroom.sh` is present and `bash -n` clean.
- C15. New packaging tests assert C1–C13 mechanically and pass.
- C16. `bash -n` clean on every modified/added `.sh`; no MSYS sed/read pitfalls introduced.
- C17. Normal `claude` path and 8787 proxy provably untouched by the install step when GLM disabled.

## Verdict
PASS only if every criterion holds with observed evidence. Any failure -> FAIL with the specific gap.
