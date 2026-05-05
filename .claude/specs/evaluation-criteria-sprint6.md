# Sprint 6 Evaluation Criteria: Verification Type Enforcement

## File Write Tracker (4 criteria)
1. post-write-check.sh appends TOOL_INPUT_FILE_PATH to unverified-writes.jsonl on every Write/Edit
2. Each entry contains ts and file fields
3. unverified-writes.jsonl is cleared when agent-call-tracker logs a verification call
4. Exempt paths (.claude/state/, .claude/pre-flight/, .openclaw/watchers/) are not logged

## Classifier (6 criteria)
5. classify-verification-need.sh reads unverified-writes.jsonl and outputs JSON
6. .html/.css/.jsx/.tsx/.vue/.svelte files produce required type "vision"
7. .sh/.py/.js/.ts (non-UI) files produce required type "functional"
8. .md/.txt only files produce required type "review"
9. Test files produce required type "functional"
10. Mixed file types produce multiple required types

## Prescriptive Block Messages (3 criteria)
11. Step gate block message lists each modified file with its required verification type
12. Hardened gate block message includes the same file-specific prescription
13. Phase gate block message includes the same file-specific prescription

## Verification Type Matching (5 criteria)
14. agent-call-tracker classifies verification prompt and adds verification_type to ledger entry
15. "screenshot"/"vision"/"visual" in prompt -> type "vision"
16. "run"/"execute"/"test"/"curl"/"functional" in prompt -> type "functional"
17. "review"/"read"/"code"/"analyze" in prompt -> type "review"
18. Step gate rejects ledger entry with type "review" when classifier requires "vision" or "functional"

## Strength Hierarchy (3 criteria)
19. "vision" verification satisfies "functional" requirement
20. "functional" verification satisfies "review" requirement
21. "review" verification does NOT satisfy "vision" or "functional" requirement

## Integration (3 criteria)
22. Sprint 5 Q5 counter/hardening still works
23. Sprint 5 step completion gate still works (with added type checking)
24. All modified scripts pass bash -n syntax check
