# Sprint 5 Evaluation Criteria: Verification Enforcement (Revised)

## MCQ Q5 (Point 1 — Graduated)

1. **Q5 generated**: challenge.md contains a Q5 asking about unverified work with Yes/No options
2. **Q5 header updated**: challenge.md says "Answer all 5 questions" and format example includes Q5
3. **Q5 "No" increments counter**: answering Q5 with the "No" option increments `no_verify_count` in `verify-counter.json`
4. **Q5 "Yes" injects nudge**: answering Q5 with the "Yes" option outputs a nudge to stderr telling agent to spawn a verification subagent
5. **Counter persists across MCQ cycles**: `verify-counter.json` survives across multiple gate firings
6. **Hardening at 5**: when `no_verify_count` reaches 5, `hardened` flag is set to true in `verify-counter.json`
7. **Hardened gate blocks**: when `hardened: true` and no new verification ledger entry exists, pre-flight-gate.sh exits 2 with block message
8. **Hardened gate unblocks after verification**: after an Agent verification call writes a ledger entry and resets counter, gate allows again
9. **Q1-Q4 unchanged**: existing MCQ questions continue to work identically (same generation, same validation, same consumed-on-use)

## Step Completion Gate (Point 2 — Hard)

10. **Detects step check-off**: PreToolUse on Edit to watcher slot files detects when `- [ ]` changes to `- [x]`
11. **Blocks without ledger entry**: if no matching verification-ledger.jsonl entry exists for the step being checked off, exits 2 with block message
12. **Allows with ledger entry**: if a matching entry exists, allows the edit
13. **Trivial steps exempt**: steps containing "read", "search", "explore", "set up", "claim" in their text are allowed without ledger entries

## Phase Completion Gate (Point 3 — Hard)

14. **Blocks phase-complete without verification**: writing phase-complete-marker.md during BUILD or EVALUATE phase is blocked if verification-ledger.jsonl has no entries for the current phase+sprint
15. **Allows with ledger entry**: if at least one verification entry exists for the current phase+sprint, allows the write

## Agent Call Tracker (Shared Infrastructure)

16. **Verification Agent writes ledger**: Agent tool call with verification language in prompt appends entry to `verification-ledger.jsonl`
17. **Verification Agent resets counter**: same call resets `no_verify_count` to 0 and `hardened` to false in `verify-counter.json`
18. **Non-verification Agent ignored**: Agent call with "search", "explore", "find" but no verification language does NOT write ledger entry or reset counter
19. **Verification language detection**: `grep -iE 'verify|review|evaluate|check|validate|test|audit|assess'` on Agent prompt field

## Integration

20. **Existing hooks unbroken**: pre-write-gate.sh, post-write-check.sh continue to function unchanged
21. **Hook order preserved**: pre-write-gate → pre-flight-gate (with new checks) → write → post-write-check
22. **settings.json updated**: PostToolUse Agent hook added without removing existing entries
23. **All new/modified scripts pass bash -n**: syntax check passes on every .sh file touched
24. **verify-counter.json missing = allow**: if counter file doesn't exist, treat as count 0 (not hardened)
25. **verification-ledger.jsonl missing = no entries**: if ledger doesn't exist, step/phase gates block (no evidence of verification)
