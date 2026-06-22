# Sprint 37 — Proposal: Session-Aware Must-Do File-Exists Branch

**Status:** PROPOSED (awaiting user go-ahead to BUILD).
**Spec:** `.claude/specs/mustdo-session-aware-spec.md` ·
**Criteria:** `.claude/specs/evaluation-criteria-sprint-37.md`
**Agreement of record:** `docs/applying fussion ideas/enhancing the must do system/discussion-agreement-session-aware-mustdo.md`

## What we will build
Make the must-do **file-exists branch** session-aware via a deterministic, hook-written session
stamp; route a foreign-stamped file to the create branch; archive (never delete) superseded files to
`docs/must do/history/`. Human-seeded (unstamped) and no-session cases unchanged.

## Files touched (exhaustive)
| File | Change |
|------|--------|
| `_install/scripts/build-mustdo-pack.sh` | New `--session S`; stamp first line; **archive-before-clobber** to `history/`. |
| `_install/hooks/on-prompt-submit.sh` | `+++pack` handler extracts `session_id` from payload → passes `--session`. |
| `_install/hooks/post-write-check.sh` | After an agent Write/Edit to a `docs/must do/*.md`, stamp it with that session (idempotent). |
| `_install/hooks/pre-write-gate.sh` | File-exists branch: read stamp, 3-arm routing (C5–C8); foreign-stamp exemptions; stamp-line skip in reader loops. |
| `_install/hooks/pre-bash-gate.sh` | Mirror the foreign-stamp routing for file-writing Bash. |
| `_install/scripts/generate-pre-flight-challenge.sh` | Skip the stamp line when generating per-file MCQs. |
| `tests/test-mustdo-session-aware.sh` | **New** functional suite (failing-first). |
| Live mirrors in `~/.claude/{hooks,scripts}` | Byte-identical to `_install`. |

## Stamp format
First line of an agent-authored must-do file:
`<!-- mustdo-session: <session_id> | built: pack|create -->`
Extraction: `grep -m1` for `mustdo-session:` then field-split. HTML-comment so it is inert markdown.

## Functional TDD plan (test in reality — failing first)
`tests/test-mustdo-session-aware.sh` mirrors `test-mustdo-session-owned.sh`: `mksandbox` builds a real
`mktemp` project (`.claude/state`, `.claude/contracts/sprint-1-contract.md`, `docs/must do/`, `src/`),
phase=BUILD; tests pipe real payloads into the **live** hooks under `HARNESS_STATE_DIR` and assert
`rc` + on-disk files. Planned cases:
- **Stamp:** run `build-mustdo-pack.sh --own … --session A` → assert first-line stamp (C1); drive
  `post-write-check.sh` with an agent Write to `docs/must do/must-do.md` → assert stamp added (C2/C3).
- **Routing (pre-write-gate):** unstamped+summary→rc0; unstamped no-summary→rc2 (C5); own-stamp+summary→rc0
  (C6); foreign-stamp+valid-summary→rc2 with ownership message (C7); foreign-stamp writing the must-do
  file itself→rc0 (C8); no-session→unchanged (C9); kill-switch→rc0 (C10).
- **Routing (pre-bash-gate):** foreign stamp + `echo x > src/foo.js`→rc2; own/none→rc0 (C11).
- **Archive:** seed foreign `must-do.md`, run pack as new session → old body under `history/`, new
  stamped file present, original NOT deleted (C12); same-session rerun → no dup history (C13);
  detection still resolves root file with populated `history/` (C14); unstamped human file archived
  on `+++pack` (C15).
- **Parser:** stamped `must-do.md` with one real path → exactly one MCQ file-question; summary
  mentions count keyed only on the real file (C16).
Each case is shown RED before implementation (captured in progress-notes), GREEN at EVALUATE.

## Build order (one feature at a time, tests between)
1. Stamp emit in `build-mustdo-pack.sh` (+ `--session` wiring in `+++pack`). 2. `post-write-check.sh`
stamping. 3. Archive-before-clobber. 4. `pre-write-gate.sh` 3-arm routing + exemptions. 5.
`pre-bash-gate.sh` mirror. 6. Stamp-line skip in readers + MCQ generator. 7. `_install`↔live parity.

## Risks / mitigations
- **Deadlock** (foreign-stamp block prevents writing the fix). → C8 exemptions (must-do file/`docs/`/`*.md`)
  mirror the existing create-branch exemptions; explicit test.
- **post-write-check is too late to archive on manual re-author** (PostToolUse fires after the Write
  clobbers content). → Resolved by the **"snapshot-then-write" by COPY** rule (O1): `pre-write-gate.sh`
  copies the on-disk foreign/unstamped owned file to `history/` *before allowing* the manual Write
  (old content still present), and `build-mustdo-pack.sh` copies inline before its rewrite. Copy (not
  move) means the owned file is never orphaned even if the subsequent write doesn't execute. C12/C15.
- **Stamp leaks into required-reading list** (false MCQ/mention). → C16 stamp-line skip across all readers.
- **`find -maxdepth 1` fallback grabbing a history file.** → `history/` is a subdirectory, excluded by
  `-maxdepth 1`; archived names never collide with root; C14 asserts.
- **Windows/MSYS footguns** (CRLF, `<<<`, trailing-newline read loops, `sed` backslash). → reuse the
  repo's known-safe idioms (`tr -d '\r'`, temp files, `|| [ -n "$var" ]`, `tr '\\' '/'`).

---

## Sceptical self-review (builder-as-evaluator)
- **Is the core fix actually at the right line?** Yes — evidence-cited: routing is the `if`/`else` at
  `pre-write-gate.sh:383`/`:525`. Adding the stamp check *inside* the file-exists branch (before the
  summary requirement) is the minimal correct intervention; the create branch is untouched. ✓
- **Does it regress human-seed projects?** Only stamped files trigger new behavior; unstamped → today's
  path verbatim (C5). The one new thing for humans is `+++pack` now archives their file instead of
  silently clobbering it — strictly safer. ✓
- **Can the agent cheat the stamp?** Stamp is written only by `build-mustdo-pack.sh`/`post-write-check.sh`
  using the harness-supplied `session_id`; the agent never writes it directly (C3). An agent *could*
  hand-write a fake `<!-- mustdo-session: … -->`, but it cannot know another live session's id, and
  faking its *own* id only reproduces the legitimate "it's mine" path. Acceptable. ✓
- **Weakest criterion (now resolved)?** The earlier risk was a gate `mv` mutating the folder. First
  principles replaced it with a **non-destructive copy** (O1): a PreToolUse allow doesn't guarantee
  the write runs, so a move could orphan the owned file — a copy cannot. Archive is now safe and
  idempotent on every path.
- **Scope creep?** None added; deletion and Stop-hook cleanup explicitly excluded.

## Decisions (resolved from first principles — defaults locked in the contract)
- **O1 → snapshot-then-write by COPY** (never a gate `mv`), enforced in both `build-mustdo-pack.sh`
  (inline) and `pre-write-gate.sh` (manual path). Copy ⇒ no orphan, idempotent, atomic-enough.
- **O2 → `history/<basename>.<cksum>.md`** (portable POSIX `cksum`): idempotent + collision-free;
  session provenance rides inside the archived file's stamp line, not the filename.
- **O3 → record `built: pack|create` for forensics only**; gate compares the session id, not origin.
