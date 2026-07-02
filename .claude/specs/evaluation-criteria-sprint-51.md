# Evaluation Criteria — Sprint 51 (commit everything; install pack complete + Linux-ready)

Binary criteria; independent verifier defaults to FAIL, cites evidence per criterion.

- **AC1 (committed)**: `git status --porcelain` shows no uncommitted tracked changes and no untracked
  project files (transient per-session state may be gitignored instead); branch pushed — `git log
  origin/master..master` empty at sprint end.
- **AC2 (completeness)**: every hook command referenced in `_install/settings.json` exists in
  `_install/hooks/`; every live `~/.claude/hooks/*.sh` and `~/.claude/scripts/*.sh` that belongs to
  the harness exists in `_install/` and is byte-identical (exclusions allowed ONLY for
  machine-specific/secret files — each exclusion named and justified in the sprint report);
  skills/, CLAUDE.md, MUST-DO-SYSTEM.md, README/LICENSES ship in _install.
- **AC3 (line endings)**: zero CRLF bytes in any shipped `_install/**/*.sh`, `settings.json`,
  `CLAUDE.md` (verified by scan, e.g. `grep -rlU $'\r'`), and `.gitattributes` (or equivalent)
  pins `*.sh text eol=lf` so Windows checkouts cannot reintroduce CRLF.
- **AC4 (no Windows-isms)**: in shipped .sh — every `pwd -W` has the `2>/dev/null || pwd` fallback;
  no cmd.exe/powershell/cscript invocations outside explicitly Windows-only guarded branches or
  Windows launcher templates; no hardcoded drive-letter paths (C:/, G:/) outside comments; no
  `%VAR%` expansion; no `.exe` suffix dependence.
- **AC5 (syntax/shebang/exec)**: every shipped .sh has a `#!` shebang line 1 and passes `bash -n`;
  install.sh sets executable bits (chmod) on installed hooks/scripts.
- **AC6 (install.sh Linux flow)**: install.sh runs on Linux bash: no Windows-only commands on the
  default path; all optional tooling (npm/uv/git/jq) is guarded with clear skip messages; jq is
  checked/required with an actionable message; settings merge does not clobber user settings.
- **AC7 (regression)**: full tests/ sweep still zero failures after any portability edits;
  live↔_install parity for every changed file.
- **AC8 (verifier)**: independent verifier PASS on AC1-AC7.
