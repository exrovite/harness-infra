# Sprint 18 Contract — Verdict File Injection Fix

## Scope
Update prompt injection so verifier sub-agents know to write verdict to file.

## Acceptance Criteria
- C1: Injection includes verdict file path and JSON format
- C2: Sub-agent in same project sees the instruction via its own prompt-submit hook
