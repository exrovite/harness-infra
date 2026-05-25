# Sprint 25 Contract: Fix Pre-Flight Gate Evidence Exemption

**Status**: LOCKED
**Locked at**: 2026-05-25

## Objective
Fix circular deadlock where phase-feedback FAIL blocks evidence file writes, preventing agents from clearing the evidence gate.

## Root Cause
`.claude/evidence/` is missing from the phase-feedback exemption list in `pre-flight-gate.sh` (line 54). Evidence files are harness infrastructure, not source code — they should always be writable.

## Deliverable
One-line fix: add `'.claude/evidence/'` to the `FB_PAT` exemption loop in `pre-flight-gate.sh`.

## Acceptance Criteria
- AC1: `pre-flight-gate.sh` exemption list includes `.claude/evidence/`
- AC2: `bash -n` passes on the modified file (no syntax errors)
- AC3: Fix synced to `_install/hooks/pre-flight-gate.sh`

## What Will NOT Change
- No gate logic changes
- No other exemption lists modified
- No other files touched
