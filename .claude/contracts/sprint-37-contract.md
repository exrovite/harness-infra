# Sprint 37 — Contract: Session-Aware Must-Do File-Exists Branch

**Status:** PROPOSED (awaiting user go-ahead to BUILD). New sprint — modifies no prior sprint.
**Spec:** `.claude/specs/mustdo-session-aware-spec.md` ·
**Criteria:** `.claude/specs/evaluation-criteria-sprint-37.md` ·
**Proposal:** `.claude/contracts/sprint-37-proposal.md`
**Agreement of record:** `docs/applying fussion ideas/enhancing the must do system/discussion-agreement-session-aware-mustdo.md`

## Scope (this sprint builds exactly this)
Make the must-do **file-exists branch** (`pre-write-gate.sh:383`, mirrored in `pre-bash-gate.sh`)
**session-aware** via a deterministic, hook-written **session stamp**, so a must-do file left behind by
a prior session no longer satisfies the gate for a new session — routing the new session to the
**create branch** to author its own grounding. Superseded files are **archived to
`docs/must do/history/`, never deleted**. Unstamped (human-seeded) and no-`session_id` cases are
byte-for-byte unchanged. No deletion anywhere; no Stop-hook/watcher-release cleanup.

## Acceptance criteria (binary, reality-tested)
Reality = drive the **live** hooks/scripts through `HARNESS_STATE_DIR` + `mktemp` sandboxes with real
JSON payloads and real exit-code/file assertions (style of `tests/test-mustdo-session-owned.sh`).

### Stamp emission (hook/script only)
- **C1.** `build-mustdo-pack.sh --own F --session S` writes `<!-- mustdo-session: S | built: pack -->`
  as the first line of `F`.
- **C2.** `post-write-check.sh` stamps an agent-authored `docs/must do/*.md` with the writing session
  (adds first-line stamp if absent; idempotent if already matching).
- **C3.** Stamp only via these scripts (no agent-direct emission); absent `session_id` ⇒ no stamp,
  file treated as unstamped (C4).

### Gate routing — `pre-write-gate.sh`
- **C5.** Unstamped owned file + session ⇒ today's behavior exactly: rc 2 only for missing/invalid
  summary, rc 0 once the per-session summary is valid. No ownership block.
- **C6.** Stamp == current session + valid summary ⇒ rc 0.
- **C7.** Stamp == different session ⇒ rc 2 with the "author your own grounding / +++pack" message,
  **even if a valid summary exists** (the headline fix).
- **C8.** Deadlock-free: under a foreign stamp, writes targeting the must-do file itself / `docs/` /
  any `*.md` / `.claude/state/` etc. are NOT ownership-blocked (rc 0) so the agent can re-author. The
  exemption set is **mirrored verbatim from the create-branch list** (`pre-write-gate.sh:540/:545`),
  not re-derived, to prevent drift between the two branches.
- **C9.** No `session_id` ⇒ ownership logic inert; rc identical to pre-sprint.
- **C10.** `harness-disabled.flag` present ⇒ no ownership block (superset).

### Gate routing — `pre-bash-gate.sh` twin
- **C11.** File-writing Bash under a foreign stamp ⇒ rc 2; own/absent stamp or no session ⇒ matches
  C6/C8/C9.

### Archive-on-supersede (history; never delete) — "snapshot-then-write" (O1/O2 resolved)
- **C12.** Before the owned must-do file is overwritten, its current non-empty content is **copied
  (never moved)** to `docs/must do/history/<basename>.<cksum>.md` (`<cksum>` = portable POSIX `cksum`
  token of the superseded content). Two enforcement points, one rule: (a) `build-mustdo-pack.sh`
  snapshots inline before its `> "$OWN"` rewrite on the `+++pack` path; (b) `pre-write-gate.sh`
  snapshots non-destructively when about to **allow** an agent Write to the owned must-do file whose
  on-disk body is **foreign-stamped or unstamped**. Nothing is ever deleted, and the owned file is
  never left missing (copy, not move ⇒ no orphan even if the subsequent write never executes).
- **C13.** Idempotent: the content-`cksum` filename means re-snapshotting identical content adds no
  duplicate; repeated blocked/allowed attempts yield exactly one `history/` entry per distinct prior
  content. Same-session own-stamp ⇒ **no** snapshot (it's mine).
- **C14.** `history/` invisible to resolution: owned-file detection + `find -maxdepth 1` fallback
  resolve the **root** file even with a populated `history/`.
- **C15.** Human-seed preserved: the same snapshot rule copies an unstamped human file to `history/`
  before it is overwritten (via `+++pack` or a manual Write), so human work is never lost.

### Pre-existing files already in project folders (migration — added per user)
Every must-do file on disk today predates stamping, so it is UNSTAMPED. Such a file may be a genuine
human seed OR a leftover agent pack from a prior session. They are distinguished by content signature
(`mustdo_is_agentpack`: a pack carries `current task pack` / `Auto-built by build-mustdo-pack` /
`raw-conversation`; a human list does not).
- **C22.** An UNSTAMPED file bearing the agent-pack signature is treated as **foreign** (a leftover):
  a source write by a session is BLOCKED (rc 2, ownership message); writing the must-do file itself is
  exempt; the file is snapshotted to `history/` on re-author. Mirrored in `pre-bash-gate.sh`.
- **C23.** An UNSTAMPED **plain human list** (no pack signature) stays a **shared seed** — the summary
  branch, unchanged (honors the agreed human-seed semantics). No ownership forcing.
- **C24.** No-session callers: the legacy-pack foreign rule is inert without a `session_id` (back-compat).

### Parser robustness
- **C16.** The stamp line is ignored by every reader (summary basename counter, printed "files
  listed" block, `generate-pre-flight-challenge.sh` MCQ, `on-prompt-submit.sh` injection): a stamped
  `must-do.md` with one real path ⇒ exactly one MCQ file-question and a mention count keyed only on
  the real file; the stamp is never shown as a "file to read".

### Regression, safety, process
- **C17.** Green & unchanged: `test-mustdo-session-owned.sh` 10/10, `test-mustdo-default-on.sh`,
  `test-mustdo-pack.sh`, `test-killswitch.sh` 22/22.
- **C18.** Projects with no `docs/must do/`: zero behavioral change (new logic lives only in the
  file-exists branch).
- **C19.** `bash -n` clean on every changed script; **live ↔ `_install` byte parity** for each.
- **C20.** TDD-first: new `tests/test-mustdo-session-aware.sh` (C5–C16) shown **FAILING before
  implementation**, **all green at EVALUATE**, driving live hooks in real sandboxes.
- **C21.** Independent verifier reproduces C6/C7/C8 routing + C12 archive in its **own** fresh
  `mktemp` sandbox, does not read progress notes, default-FAIL; verdict to `.claude/evidence/`.

## Resolved decisions (decided from first principles — see report rationale)
- **O1 → RESOLVED.** Uniform **"snapshot-then-write" via non-destructive COPY**, never a gate `mv`.
  Rationale: a PreToolUse *allow* does not guarantee the Write executes (user-decline / other hook /
  tool failure), so a gate `mv` could orphan the owned file; archive+write must be atomic, which only
  the writer can guarantee; restructuring files is a Layer-1 action, not a Layer-2 guard decision. A
  **copy** has none of these hazards (non-destructive, idempotent, safe on non-execution), so both
  `build-mustdo-pack.sh` (inline) and `pre-write-gate.sh` (manual path) snapshot by copy. This keeps
  history on every overwrite path without the move-orphan risk.
- **O2 → RESOLVED.** Archive filename `<basename>.<cksum>.md` using portable POSIX `cksum` of the
  superseded content. Chosen for **idempotency + collision-freedom by construction** (identical
  content dedups to one file; distinct content never collides). No `sha1sum` availability assumption.
  Session provenance is **not** in the filename — it rides inside the archived file's own stamp line.
- **O3 → kept.** `built: pack|create` recorded for forensics only; the gate compares the session id,
  not the origin.

## Boundaries (must NOT do)
- **N1.** No deletion of any must-do file — archive-only, and the gate archives by **copy, never
  move** (the owned file must never be momentarily missing).
- **N2.** No Stop-hook / watcher-release cleanup (sub-agents fire Stop).
- **N3.** No change to `mustdo_file_for_dir`, MCQ count semantics, PLAN-entry backstop, or summary
  injection beyond stamp-line skipping.
- **N4.** Every changed hook/script byte-mirrored live ↔ `_install`.

## Definition of done
All C1–C21 pass; O1–O3 resolved (defaults unless overridden); `phase-complete-marker.md` written;
live + `_install` in parity; report appended to `.claude/reports/`.
