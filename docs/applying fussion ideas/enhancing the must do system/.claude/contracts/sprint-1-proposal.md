# Sprint 1 Proposal — Automated Must-Do Pack Builder

## What I will build (single sprint, Parts A+B)

### Part A — 5-file consistency fix
Add a resolver `mustdo_resolve_owned_file <state_dir> <session_id>` to `lib-helpers.sh` that returns
the caller's owned must-do file: if the session owns `slot-N`, return `must-do-N.md`; if solo /
unowned, return `must-do.md`; never `find … | head -1`. Rewire the hardcoded sites to use it:
- `pre-write-gate.sh` summary gate (`:268`, `:317`)
- `pre-write-gate.sh` evidence readers (`:533`, `:607`, `:665`)
- `on-prompt-submit.sh` injection (`:418`, `:583`)
Leave the pre-flight MCQ generator (already multi-file) unchanged.

### Part B — Ownership + auto-pack + validation
1. **Ownership layer** (`lib-helpers.sh`): `mustdo_claim` binds must-do file to the session's watcher
   slot (reuse `watcher_claim_pp` / `registry_lock` / stale-reap). `slot-N` ↔ `must-do-N.md`.
2. **Transcript-capture hook step**: copy the session `.jsonl` into the pack as
   `raw-conversation.jsonl` (true raw).
3. **Pack-builder script** `build-mustdo-pack.sh`: clears ONLY the caller's own file, writes
   `rough-plan.md` scaffold, relinks raw + agreement + grounding files.
4. **Trigger**: explicit signal (prompt token, kill-switch family) + PLAN-entry gate backstop that
   blocks first spec write until a claimed pack exists.
5. **Independent agreement validation** `validate-agreement.sh`: an independent check that every
   agreed point in the raw conversation appears in the agreement; FAIL blocks acceptance.

## How success is verified
Against `.claude/specs/evaluation-criteria.md` C1–C20, plus new bash test suite
`tests/test-mustdo-pack.sh`. Mirror all changes into `_install/` and live `~/.claude`.

## Out of scope
- Beast-mode / fusion (separate feature; this is a dependency of it).
- Changing the watcher registry schema (reuse v3.0.0 as-is).

## Self-review (sceptical evaluator)
- Risk: destructive clear under concurrency → mitigated by binding clear to owned file + atomic lock
  (C11, C20). 
- Risk: MSYS bash pitfalls → reuse catalogued safe idioms (sed→tr, trailing-newline loops, `\r`).
- Risk: breaking solo/no-folder cases → C5/C6 explicit back-compat tests.
- Risk: two harness instances drift → ship in `_install`, sync live, run full suite (C18/C19).
Verdict: scope bounded, verification concrete → proceed to contract.
