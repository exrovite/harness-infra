# Sprint 51 Contract — Commit everything; install pack complete + Linux-ready

User goal: "commit everything you have built and then make sure that the install pack has the whole
improved harness in it and is able to work properly for Linux machines."

Binding criteria: .claude/specs/evaluation-criteria-sprint-51.md (AC1-AC8).

## Scope
1. Commit + push all outstanding work (Sprint 50 aftermath: evidence, state churn, session files;
   gitignore transient per-session state rather than committing churn where appropriate).
2. Completeness audit live ~/.claude vs _install (hooks, scripts, skills, CLAUDE.md,
   MUST-DO-SYSTEM.md, settings.json wiring) — fill any gap; justify any exclusion.
3. Linux portability: CRLF scan + .gitattributes eol=lf; pwd -W fallbacks; Windows-ism scan;
   shebang/bash -n/exec bits; install.sh Linux path review with guarded optionals.
4. Fix everything found; mirror live<->_install; full regression; independent verifier PASS.

## Out of scope
Running on a real Linux host (static verification + syntax only); GLM/secret handling changes;
new features.

## Success = AC1-AC8 all PASS.
