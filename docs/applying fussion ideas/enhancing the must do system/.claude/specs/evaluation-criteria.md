# Evaluation Criteria — Automated Must-Do Pack Builder

Independent verifier checklist. Default: FAIL if in doubt. Mirrors root
`must-do-pack-evaluation-criteria.md`.

## Part A — 5-file consistency fix
- C1. With 2+ must-do files, the summary gate enforces the caller's owned file (not `must-do.md`, not
  `find … | head -1`).
- C2. Evidence-checkpoint readers read the caller's owned file (all 3 hardcoded sites fixed).
- C3. Prompt injection (`on-prompt-submit.sh`) injects the caller's owned file.
- C4. Pre-flight MCQ still generates one question per file (no regression).
- C5. Single-`must-do.md` + one agent behaves exactly as before (back-compat).
- C6. No must-do folder → completely unaffected.

## Part B — Ownership + auto-pack
- C7. Session claims a must-do file bound to its watcher slot (`slot-N` ↔ `must-do-N.md`) using the
  existing watcher lock (no new registry).
- C8. Two concurrent sessions never own the same file; second claims the next.
- C9. Solo uses `must-do.md` (no numbering); numbering only under contention.
- C10. Pack-builder produces `raw-conversation.jsonl` (machine-copied transcript slice), the
  agreement / `rough-plan.md`, and a must-do file linking both + grounding files.
- C11. Pack build clears ONLY the caller's own file — sibling untouched (diff before/after).
- C12. Explicit signal triggers the build; PLAN-entry gate blocks first spec write until a claimed
  pack exists, unblocks once it does.
- C13. Stale claims reaped by existing watcher stale logic.

## Part B — Independent agreement validation
- C14. After the agent writes the agreement file, an independent agent validates it against the raw
  conversation for completeness — every agreed aspect present.
- C15. Validator is independent (does not read author notes; tests agreement vs raw conversation).
  Default FAIL if any agreed point missing/misstated.
- C16. On FAIL, agreement returned for revision; must-do file NOT accepted as grounding and PLAN does
  not proceed until it passes.
- C17. On PASS, the validated agreement is what the must-do file links to as grounding.

## Cross-cutting
- C18. Shipped in `_install`; live `~/.claude` synced; tests added and passing (0 failures).
- C19. No regression in existing suites (watcher, must-do, evidence, kill-switch).
- C20. All destructive ops concurrency-safe (atomic lock; no clobber under race).
