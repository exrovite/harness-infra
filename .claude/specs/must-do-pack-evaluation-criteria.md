# Evaluation Criteria — Automated Must-Do Pack Builder

How an independent verifier will judge success. Default: FAIL if in doubt.

## Sprint 1 — 5-file consistency fix
- C1. With 2+ must-do files in the folder, the **summary gate** enforces the caller's owned file,
  not `must-do.md` and not `find … | head -1`.
- C2. The **evidence-checkpoint readers** read the caller's owned file (all 3 hardcoded sites fixed).
- C3. The **prompt injection** (`on-prompt-submit.sh`) injects the caller's owned file.
- C4. The **pre-flight MCQ** still generates one question per file (no regression).
- C5. A project with a single `must-do.md` and one agent behaves exactly as before (back-compat).
- C6. A project with NO must-do folder is completely unaffected.

## Sprint 2 — Ownership + auto-pack
- C7. A session claims a must-do file bound to its watcher slot (`slot-N` ↔ `must-do-N.md`); the
  claim uses the existing watcher lock (no new registry).
- C8. Two concurrent sessions in one folder never own the same file; the second claims the next one.
- C9. Solo session uses `must-do.md` with no numbering; numbering appears only under contention.
- C10. The pre-PLAN pack-builder, when triggered, produces: `raw-conversation.jsonl` (machine-copied
  from the session transcript, byte-faithful slice), the discussion-agreement / `rough-plan.md`
  (agent-written), and a must-do file whose links point at both plus grounding files.
- C11. The pack build clears ONLY the caller's own file — a sibling agent's must-do file is untouched
  (verified by diffing the sibling before/after).
- C12. Explicit signal triggers the pack build; independently, the PLAN-entry gate blocks the first
  spec write when no claimed pack exists, and unblocks once it does.
- C13. Stale claims are reaped by the existing watcher stale logic (no orphaned must-do ownership).

## Sprint 2 — Independent agreement validation (user correction 2026-06-15)
- C14. After the agent writes the discussion-agreement file, an **independent agent** validates it
  **against the raw conversation transcript** for completeness — every agreed aspect is present in
  the agreement (and therefore in the must-do content that links to it).
- C15. The validator is independent: it does not read the author's notes; it tests the agreement vs
  the raw conversation only. Default verdict FAIL if any agreed point is missing or misstated.
- C16. On FAIL, the agreement is returned for revision; the must-do file is NOT accepted as grounding
  and PLAN does NOT proceed until validation passes.
- C17. On PASS, the validated agreement is what the must-do file links to as the grounding record.

## Cross-cutting
- C18. Shipped in `_install`; live `~/.claude` synced; tests added and passing (0 failures).
- C19. No regression in existing harness test suites (watcher, must-do, evidence, kill-switch).
- C20. All destructive operations are concurrency-safe (atomic lock; no clobber under race).
