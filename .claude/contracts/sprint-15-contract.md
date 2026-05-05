# Sprint 15 Contract — MSYS sed Bug Fix

## Scope
Fix MSYS sed escaping bug in `create-evidence-checkpoint.sh` that prevents evidence checkpoints from firing on Windows/Git Bash.

## Deliverables
1. Remove redundant sed JSON escaping from source file loop (jq --arg handles it)
2. Remove redundant sed JSON escaping from summary/instruction build (jq --arg handles it)

## Acceptance Criteria
- C1: create-evidence-checkpoint.sh runs successfully from PCW project directory (exit 0)
- C2: Generated checkpoint JSON contains real file content (not empty strings)
- C3: Generated checkpoint JSON contains real file paths (not empty strings)
- C4: No sed errors on MSYS/Git Bash
