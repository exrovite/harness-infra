# The Must-Do System — Agent Guide

**Read this when any project has a `docs/must do/` folder, or when a gate blocks you mentioning "must-do".**
This is the single source of truth for how the must-do system works and what you are expected to do.

---

## 1. What it is (one paragraph)

The must-do system forces an agent to **read the right files before writing code**. A project opts in by
creating a `docs/must do/` folder containing one or more must-do files that **link the files an agent MUST
read/respect** for the current task. The harness then refuses code writes until you have acknowledged those
files. On top of that, the **pack builder** automates the human's planning ritual: it captures the
originating conversation verbatim and links the grounding files into your must-do file before you plan.

If a project has **no** `docs/must do/` folder, none of this applies — there is zero overhead.

---

## 2. The convention

| Thing | Rule |
|-------|------|
| Trigger folder | `docs/must do/` (also accepts `docs/must-do/` and `.claude/must-do/`) |
| Must-do file | Markdown file listing **one file path per line** (the files you must read). `#` and `---` lines are ignored. |
| Solo file | If you are alone in the folder, your file is **`must-do.md`** — no numbering. |
| Under contention | Concurrent sessions fan out to **`must-do-2.md`, `must-do-3.md`, …**. Each session owns exactly one. |
| Ownership binding | Ownership rides on the per-project **watcher pool**: `slot-N` ↔ `must-do-N.md`, same owner / lock / lifecycle. There is **no separate registry** — do not build one. |
| Your owned file | Resolved by `mustdo_file_for_dir <dir>` in `lib-helpers.sh` using your lane. **Never hardcode `must-do.md`** in new hook code — always resolve. |

**Key rule for concurrency (D-Clear):** you only ever touch **your own** must-do file. Never read, clear,
or overwrite a sibling session's `must-do-N.md`.

---

## 3. What you must do — the workflow

### a) When a project has a must-do folder and you start coding
The gates will require you to **read every linked file** and write a summary to
`.claude/state/must-do-summary.md`. Do that first. The pre-flight MCQ may ask one question per linked file —
answer by reading the actual files, not from memory.

### b) When you are entering PLAN after a planning conversation (the pack)
Before you write the spec, **build your must-do pack** so your plan is grounded in what was actually agreed:

1. **Trigger the build** — send the signal **`+++pack`** as a prompt (exact, on its own line). This:
   - clears and repopulates **only your owned** must-do file,
   - copies the current conversation transcript verbatim to `docs/must do/raw-conversation.jsonl`,
   - writes a `## Grounding` section linking the raw conversation + any grounding files.
   You can also run it directly: `bash ~/.claude/scripts/build-mustdo-pack.sh --own "<your must-do file>" [--transcript <jsonl> | --no-transcript] [--agreement <file>] [--grounding "f1 f2"]`.
2. **Write the discussion-agreement** — write what was agreed (e.g. `docs/must do/rough-plan.md` or an
   agreement file) and add it to the grounding links.
3. **Validate the agreement independently (D-Validate)** — the agreement must contain *every* agreed point
   from the raw conversation **before** it is accepted as grounding. Run:
   `bash ~/.claude/scripts/validate-agreement.sh --raw docs/must\ do/raw-conversation.jsonl --agreement <agreement-file>`
   Exit 0 = PASS, exit 1 = FAIL (lists missing terms). On FAIL, revise the agreement and re-run. **Do not
   proceed to PLAN until it passes** — this mirrors the EVALUATE builder/verifier separation, applied to the
   plan itself.

### c) The PLAN-entry backstop (opt-in)
If a project sets `.claude/mustdo-pack.json` to `{"require_pack": true}`, the harness will **block your first
`product-spec.md` write in PLAN** until your owned must-do file carries a captured `raw-conversation` link.
This is the safety net behind the `+++pack` signal. Absent that json file, there is no block (default off,
zero regression).

---

## 4. The pieces (where the behavior lives)

| Piece | File | Role |
|-------|------|------|
| Lane-aware resolver | `lib-helpers.sh` → `mustdo_file_for_dir <dir>` | Returns the caller's owned must-do file for their lane. |
| Must-do summary gate | `pre-write-gate.sh` | Blocks code writes until linked files are acknowledged. |
| Per-file MCQ | `generate-pre-flight-challenge.sh` | One pre-flight question per linked file. |
| Summary injection | `on-prompt-submit.sh` | Re-injects the must-do file list each prompt. |
| Pack build trigger | `on-prompt-submit.sh` (`+++pack`) | Builds the pack from the live transcript. |
| Pack builder | `build-mustdo-pack.sh` | Scoped clear + raw capture + relink (own file only). |
| Agreement validator | `validate-agreement.sh` | Independent completeness check of the agreement vs raw conversation. |
| PLAN-entry backstop | `pre-write-gate.sh` (`mustdo-pack.json`) | Opt-in block on first spec write until a pack exists. |

---

## 5. Hard rules (do not violate)

- **Never hardcode `${dir}/must-do.md`** in hook code that reads a must-do file — resolve via
  `mustdo_file_for_dir` so lane-owned files are honored and siblings don't collide.
- **Never touch another session's must-do file.** You own exactly one.
- **Do not skip validation** of the discussion-agreement when building a pack — a plan grounded in an
  incomplete agreement is the failure this system exists to prevent.
- **No `docs/must do/` folder → do nothing.** The system is opt-in per project.
