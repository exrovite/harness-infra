# Sprint 8 — Exempt .md files from phase gate in PLAN/NEGOTIATE

## Scope
Allow markdown (.md) files to be written in PLAN and NEGOTIATE phases. Markdown is documentation, not source code.

## Acceptance Criteria
1. PLAN phase + .md file → allowed
2. PLAN phase + .js/.py/.ts file → still blocked
3. NEGOTIATE phase + .md file → allowed
4. EVALUATE phase + .md file → still blocked (only PLAN/NEGOTIATE get the exemption)
5. BUILD phase unchanged
6. Bash gate has same exemption
7. Existing tests still pass
