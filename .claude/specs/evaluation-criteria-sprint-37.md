# Evaluation Criteria — Sprint 37 (Session-Aware Must-Do File-Exists Branch)

Binary, reality-tested. "Reality" = drive the **live** hooks (`~/.claude/hooks/...`) and scripts via
`HARNESS_STATE_DIR` + `mktemp` sandboxes with real JSON payloads and real exit-code/file assertions,
in the style of `tests/test-mustdo-session-owned.sh`. No mocking of hook internals.

## Stamp emission (hook/script only, deterministic)
- **C1.** `build-mustdo-pack.sh --own F --session S` writes the stamp as the **first line** of `F`:
  `<!-- mustdo-session: S | built: pack -->`. Verified by running the script in a sandbox and reading `F`.
- **C2.** `post-write-check.sh`, on a PostToolUse Write/Edit by session `S` whose target is a must-do
  file under `docs/must do/`, ensures `F` carries `S`'s stamp (adds it as the first line if absent;
  leaves an existing matching stamp idempotently). Verified by driving the live hook with a payload.
- **C3.** No agent-forgeable path: a plain Write payload that does NOT go through these scripts leaves
  no stamp; only the two scripts emit one. (Asserted by test.)
- **C4.** Stamp uses the caller-passed `session_id`; absent a session id, no stamp is written and the
  file is treated as unstamped (back-compat).

## Gate routing — `pre-write-gate.sh` file-exists branch (core fix)
- **C5.** Unstamped owned file + session present: behaves exactly as today — source write blocked
  ONLY for a missing/invalid summary (rc 2, summary message), allowed (rc 0) once the per-session
  summary is valid. NO ownership block fires.
- **C6.** Owned file stamped == current session + valid summary → source write **allowed (rc 0)**.
- **C7.** Owned file stamped == **different** session → source write **BLOCKED (rc 2)** with the
  "author your own grounding / send +++pack" message — *even if a valid summary exists*. (The bug dies here.)
- **C8.** Deadlock-free: under a foreign stamp, writes whose target is exempt (the must-do file
  itself, anything under `docs/`, any `*.md`, `.claude/state/`, etc.) are **not** ownership-blocked,
  so the agent can re-author. Verified by a foreign-stamp sandbox writing `docs/must do/must-do.md` → rc 0.
- **C9.** No `session_id` in payload (tests / non-session callers) → ownership logic does NOT fire;
  rc identical to pre-sprint behavior.
- **C10.** Kill-switch superset: `harness-disabled.flag` present → no ownership block (rc 0).

## Gate routing — `pre-bash-gate.sh` twin
- **C11.** A file-writing Bash command (redirect/tee/sed -i/heredoc/cp/mv/python-write) under a
  foreign stamp is **blocked (rc 2)**; under own/absent stamp or no session it matches C6/C8/C9.
  Verified by driving the live `pre-bash-gate.sh`.

## Archive-on-supersede (history; never delete)
- **C12.** `build-mustdo-pack.sh`, before clobbering an existing owned file that is non-empty AND
  (unstamped OR stamped by a different session than `--session`), moves the existing file to
  `docs/must do/history/<basename>.<prev-session-or-ts>.md`, THEN writes the new stamped pack.
  Verified: seed a foreign `must-do.md` → run pack with a new session → old content present under
  `history/`, new stamped file in place, **nothing deleted**.
- **C13.** Same-session re-author does not spam history (an existing file already stamped with
  `--session` is overwritten in place; at most one archived copy per genuine supersede).
- **C14.** History is invisible to resolution: after archiving, the gate's owned-file detection and
  `find -maxdepth 1` fallback resolve the **root** file, never a `history/` entry. Verified by
  detection returning the root path with a populated `history/`.
- **C15.** Human-seed preserved: running `+++pack` over an **unstamped** human file archives that
  human file to `history/` before writing the new pack (human work is never lost).

## Parser robustness
- **C16.** The stamp line is ignored by every must-do reader: the summary-gate basename counter, the
  printed "files listed" block (`pre-write-gate.sh`), `generate-pre-flight-challenge.sh` MCQ
  generation, and `on-prompt-submit.sh` injection. Verified: a stamped `must-do.md` listing exactly
  one real file path yields exactly **one** MCQ file-question and a summary "mentions" count keyed
  only on the real file — the stamp never appears as a "file to read".

## Regression, safety, process
- **C17.** Existing suites green, unchanged: `test-mustdo-session-owned.sh` (10/10),
  `test-mustdo-default-on.sh`, `test-mustdo-pack.sh`, `test-killswitch.sh` (22/22).
- **C18.** Projects with no `docs/must do/`: zero behavioral change on Write/Edit/Bash (the new logic
  lives only inside the file-exists branch).
- **C19.** `bash -n` clean on every changed script; **live ↔ `_install` byte parity** verified for
  each changed hook/script.
- **C20.** TDD-first: a new `tests/test-mustdo-session-aware.sh` (covering C5–C16) is demonstrated
  **FAILING before implementation** and **all green at EVALUATE**, driving the live hooks in real
  sandboxes.
- **C21.** Independent verifier reproduces the headline arms (C6/C7/C8 routing + C12 archive) in its
  **own** fresh `mktemp` sandbox, does **not** read progress notes, default-FAIL; verdict written to
  `.claude/evidence/`.

## Definition of done
All C1–C21 pass; `phase-complete-marker.md` written; live + `_install` in parity; report appended to
`.claude/reports/`.
