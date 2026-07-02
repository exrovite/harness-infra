# Product Spec — Sprint 51: Ship the improved harness (complete install pack, Linux-ready)

(Sprint-50 spec preserved in git history.)

## What
Everything built through Sprint 50 committed and pushed; `_install/` contains the WHOLE improved
harness (every hook, script, skill, doc the live machine runs) and installs/works on Linux.

## Why
The user distributes the harness via `_install/`. Sprint 50 changed 11 files; the pack was built on
Windows (Git Bash) — CRLF endings, `pwd -W`, or missing files would brick a Linux install.

## Outcome (WHAT, not HOW)
1. Git: no outstanding work; origin/master up to date.
2. Pack completeness: _install mirrors the live harness (justified exclusions only).
3. Linux portability: LF endings enforced, no Windows-only constructs on the default path,
   guarded optional tooling, executable bits handled by install.sh.
4. Proof: full regression green; independent verifier PASS.

## Evaluation Criteria
Binding: `.claude/specs/evaluation-criteria-sprint-51.md` (AC1-AC8).

## Constraints
- No secrets in the pack (GLM launcher stays templated).
- Live behavior unchanged except portability-neutral fixes, mirrored both ways.

## Stop condition
Verifier PASS on AC1-AC8; committed + pushed; COMPLETE.
