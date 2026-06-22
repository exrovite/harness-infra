# Sprint 37 — Build Report: Session-Aware Must-Do File-Exists Branch

**Phase:** BUILD complete (pending independent EVALUATE). **Contract:** `.claude/contracts/sprint-37-contract.md`.

## What was built (TDD-first)
1. **Failing-first suite** `tests/test-mustdo-session-aware.sh` (19 cases) — shown RED (9/19, only pre-existing
   routing passing) before any implementation, then GREEN (19/19) after.
2. **`scripts/lib-helpers.sh`** — new helpers: `mustdo_stamp_of`, `mustdo_snapshot` (cksum-named, COPY,
   idempotent), `mustdo_ensure_stamp`, `mustdo_is_stampline`. Purely additive.
3. **`scripts/build-mustdo-pack.sh`** — `--session` arg; first-line stamp `<!-- mustdo-session: S | built: pack -->`;
   snapshot-then-write (COPY foreign/unstamped body to `docs/must do/history/<base>.<cksum>.md` before clobber).
4. **`hooks/on-prompt-submit.sh`** — `+++pack` handler threads `session_id` → `--session`.
5. **`hooks/post-write-check.sh`** — stamps an agent-authored `docs/must do/*.md` (idempotent; skips history/ & summary).
6. **`hooks/pre-write-gate.sh`** — 3-arm ownership routing in the file-exists branch: no-stamp/own/no-session →
   summary gate (unchanged); foreign + source write → BLOCK (author your own / +++pack); (re)authoring the owned
   file → COPY snapshot then allow. Robust owned-file match by basename + must-do dir (abs/rel safe). Stamp line
   skipped in both reader loops.
7. **`hooks/pre-bash-gate.sh`** — mirrors the foreign-stamp block for file-writing Bash.
8. **`scripts/generate-pre-flight-challenge.sh`** — MCQ loop skips the stamp/comment line.

## Verification
- **Sprint 37 suite: 19/19** against the LIVE hooks (real mktemp + HARNESS_STATE_DIR sandboxes, real rc/file asserts).
  Headline arms proven: C6 own-stamp allow, **C7 foreign-stamp BLOCK despite valid summary**, C8 re-author allowed,
  C11 bash mirror, C12/C12b/C15 history archive (pack + gate paths), C13 idempotent, C14 history invisible to
  resolution, C16 stamp-line skipped.
- **Regression green:** mustdo-session-owned 10/10, mustdo-default-on 11/11, mustdo-pack 25/25, killswitch 22/22,
  beast (pack/recall/roundtrip/surface/toggle) all green, lavish 19/19, perproject 7/7 + 6/6, glm 10/10 + 38/38,
  killswitch-resolve 7/7, intuition-control 8/8, evidence-checkpoint green.
- **`bash -n` clean** on all 7 changed files. **Live ↔ `_install` byte parity = 0** on all 7.

## Pre-existing failures (NOT caused by Sprint 37 — causality-checked)
- `test-preflight-session-keyed` 0/4 — reverting the generator to HEAD reproduces 0/4 (needs an unclaimed
  per-project watcher slot). Zero relation to the must-do file-exists branch.
- `test-headroom-last30days-integration` 48/1 — zero references to changed files; failure is an `install.sh`
  step-10 label.
- `test-ralph-loop` 34/2 — byte-identical result with HEAD gates; failures are ralph activation + steady-state
  packet size (my on-prompt-submit edit lives only in the `+++pack` branch, never hit by ralph).

## Migration: pre-existing files already in project folders (added per user)
Every must-do file on disk today is unstamped. `mustdo_is_agentpack` classifies an unstamped file by
content: a legacy **agent pack** (`current task pack` / `Auto-built by build-mustdo-pack` /
`raw-conversation`) is treated as **foreign** (forces the new session to author its own; archived to
`history/` on re-author); a plain **human list** stays a shared seed (unchanged). Proven by suite cases
C17 (legacy pack → block), C18 (human list → allowed), C19 (bash mirror), C20 (legacy → history). Suite
now 23/23. All must-do/killswitch regression still green after this addition.

## Design notes carried from NEGOTIATE (resolved decisions)
- **Snapshot by COPY, never move** (O1): a PreToolUse allow doesn't guarantee the write executes → a move could
  orphan the owned file; copy cannot. Enforced in both `build-mustdo-pack.sh` and `pre-write-gate.sh`.
- **`history/<base>.<cksum>.md`** (O2): idempotent + collision-free; provenance rides in the archived file's stamp.
- **Deadlock-free** (C8): foreign-stamp exemption set mirrors the create-branch list verbatim (incl. `docs/`, `*.md`).
