# Sprint 9 — Extend .md exemption to all phases

## Scope
Markdown files should be writable in ALL non-BUILD phases, not just PLAN/NEGOTIATE.

## Acceptance Criteria
1. PLAN + .md → allowed
2. NEGOTIATE + .md → allowed
3. EVALUATE + .md → allowed
4. COMPLETE + .md → allowed
5. All phases + .js/.py → still blocked
6. Bash gate has same exemption
7. Existing tests pass
