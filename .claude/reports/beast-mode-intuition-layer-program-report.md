# Beast-Mode: The Intuition Layer — Program Report

**Scope:** the whole arc, from the original idea through to a working, live, globally-installed
system — covering **what we achieved, why we decided to do it, and how we went about it**.
**Date:** 2026-06-22
**Spans:** Sprint 35 (mechanism + proof) and Sprint 36 (global wiring + per-project pack),
plus the live confirmation in a second real project (Private Content Wizard).
**Companion reports:** `sprint-35-beast-mode-intuition-report.md`,
`sprint-36-beast-mode-global-recall-report.md`.
**Decision record / agreement:** `docs/applying fussion ideas/changes-to-the-idea.md`,
`docs/applying fussion ideas/beast-mode-global-agreement-verbatim.md` (verbatim, independently verified).

---

## 1. Executive summary
We turned the harness's passive memory into an **active intuition layer**: at the moment the agent
is about to act, the harness now deterministically surfaces what *this project* has already learned —
including past mistakes and their fixes — and puts it in front of the agent. It is **installed once,
globally**, but **each project grows its own lessons**. We did not just build it; we **proved** it
controls agent behaviour (an independent agent reproduced the effect on a different model family),
shipped it into the install pack for Linux servers, and confirmed it firing live in a real, unrelated
project. What remains is honest and bounded: turning surfacing into a hard enforcement gate, automated
capture, and improving the *quality* of distilled lessons.

---

## 2. Why we decided to do it (the problem)
The harness already keeps the agent on task with watchers, gates, and a memory system. Yet three
failures kept recurring:

1. **Drift had nothing to check against.** Asked "have you drifted?", the agent answered from its own
   fading memory of intent — a confident guess, not a verified fact.
2. **The agreement faded mid-flight.** The contract / watcher slot was read once, then the agent ran
   off a decaying copy of it.
3. **Hard-won learnings didn't survive.** We'd hit a problem, fix it correctly, reach the goal — and
   next session the agent re-derived or re-broke the very thing it had solved, even though it was
   "saved" in memory.

**Root cause:** memory in the system was **storage, not intuition**. Storage = "the fact exists
somewhere." Intuition = "the relevant fact surfaces at the moment of decision, unprompted, and the
agent is made to check against it." We had lots of the first and almost none of the second. The one
memory system we had (mempalace) had even been switched off because its auto-capture hook opened blank
CMD windows on every write — and inspection showed it had vacuumed ~95k raw drawers from another
project while leaving the knowledge graph empty. The valuable part — surfacing "this was settled" at
the right moment — had never been used.

**The pivot.** This began as a different idea: the OpenRouter "Fusion" panel/judge, aimed at decision
*quality*. Through discussion we realised our real pain was not decision quality but **continuity and
grounding**, and repurposed the same machinery (deterministic trigger, harness-controlled evidence
packet, flag toggle) toward surfacing memory instead of running a panel.

---

## 3. What we decided (the design)
The governing principle that makes the whole thing safe and deterministic:

> **LLM/human judgment is allowed only at CAPTURE (deliberate, one-time, cold path).
> RECALL is a pure function (hot path, deterministic) — and silence is the default.**

Key agreed decisions:
- **Global system, per-project lessons.** Installed once (`~/.claude` + `_install`); every project
  runs the same machinery and surfaces its **own** `<project-root>/.beast/lessons.jsonl`. (This was
  explicitly corrected mid-discussion away from a single shared global store.)
- **A lesson is distilled, not a raw drawer.** Lessons are built *from* a project's own memory
  (mempalace facts + git fix-commits), structured into matchable units
  (`id/scope/trigger/lesson/fix/dossier`) — not copies of raw mempalace entries.
- **Deterministic surfacing by stable atoms.** We never match the *situation* (too dynamic); we match
  the stable atoms an action is built from — file scope (glob on basename) + a trigger regex over the
  action content. Same input → identical output, no LLM at recall time.
- **No CMD windows.** Capture happens once on activation (and, later, at deterministic "birth"
  events) — never as a per-write background hook. Recall is silent text injection.
- **Toggle:** `beast-on` / `beast-off`. `beast-on` auto-enables the harness first if disabled (the
  superset rule: beast cannot exist while the harness is off); `---` (harness off) also drops beast.

---

## 4. How we went about it — Sprint 35 (mechanism + proof)
We built the smallest end-to-end slice and **proved it controls the agent**:
- the toggle + helpers; `beast-surface.sh` (the pure recall function); a hand-seeded lesson store.
- **The proof:** an A/B experiment with a **project-specific, unguessable** lesson (an internal helper
  name absent from any training corpus). Closed-book agents flipped from reproducing a documented bug
  (3/3 without injection) to the project-correct, explicitly-reconciled behaviour (3/3 with injection).
  A negative control (a lesson the model already knows) showed no delta — proving the method measures
  *system-supplied* knowledge, not task difficulty.
- **Independent validation:** a separate adversarial agent reproduced the flip on a **different model
  family** (GLM) — strengthening the unguessability argument. Verdict: PASS.

What Sprint 35 deliberately left open: it proved the mechanism but only in harness infra, via a
hand-made fixture. It did not fire in any real project, and nothing built a project's lessons.

---

## 5. How we went about it — Sprint 36 (global wiring + per-project pack)
We closed exactly the two gaps that made it global-in-machinery but inert-in-practice:
- **G1 — Global recall (`beast-recall-hook.sh`).** A **fail-safe** `PreToolUse` adapter wired for
  **Write/Edit and file-writing Bash**, in every project. Resolves lessons by project root, gated by
  that project's `beast-mode.flag`, honours the kill-switch (harness off ⇒ silent), silent by default,
  injects matches as non-blocking `additionalContext`. It can **never block a tool call** (no `set -e`;
  every path exits 0; fuzzed with empty/malformed/missing/unrelated input → rc 0).
- **G2 — Per-project pack (`beast-pack.sh`).** **Deterministic, no LLM.** Builds a project's own
  `.beast/lessons.jsonl` from its git fix-commits + an env-pointed mempalace KG seam (tests never
  touch the real ~95k palace). Idempotent, headless. Invoked once via the existing `beast-on` seam.

---

## 6. How we worked (the method that caught real bugs)
- **Functional TDD, in reality.** Tests drive the *real* hooks via the real stdin contract in **fresh
  second-project sandboxes** (`mktemp`, never harness infra), including the **end-to-end round-trip**:
  pack builds a project's lessons → a real Write *and* a real file-writing Bash action → the live hook
  surfaces them. Suites: recall 15/15, pack 19/19, round-trip 7/7; Sprint 35 regression 60/60.
- **Builder/verifier separation, taken seriously.** A strict, default-FAIL independent validator
  verified by **reproducing in its own sandboxes**, not reviewing code. Across three rounds it found
  and forced fixes for **two real bugs my own green tests had missed by luck** — both in the pack's
  JSON emit on native Windows `jq.exe`:
  1. a `jq --arg do` keyword collision → cwd-dependent, non-deterministic output;
  2. a bare `*` scope glob-expanded by `jq.exe` in argv → conceptual (wildcard-scope) lessons silently
     dropped (0/40).
  **Fix:** emit every field via the environment (`$ENV`), glob-immune for all special-char classes.
  It then hunted for a third root cause (globs, quotes, `$HOME`, regex metachars) and found none. PASS.
- **Honesty about scope.** We repeatedly separated "proven" from "live", and "Sprint 36" from
  "Sprint 37", so the reports never overclaim.

---

## 7. What we achieved — proof it works
- **Behavioural control proven** (Sprint 35 A/B, cross-model independent reproduction).
- **Global recall proven functionally** in fresh second projects (Sprint 36 round-trip).
- **Install-pack proven** by simulating a fresh install into a clean `$HOME` and running the
  pack-deployed copies end-to-end (pack → recall → surface, plus flag-off silence).
- **Live in a real, unrelated project.** In Private Content Wizard, `beast-on` triggered the pack,
  which built **19 lessons from PCW's own git history**; the live recall hook then surfaced the
  matching lesson on a real action (the full "BEFORE YOU ACT — past-you has been here…" packet) and
  stayed silent on non-matching ones. The loop works in the wild.

---

## 8. Install pack & Linux servers
Everything is in `_install` and deployed by `install.sh` (which copies `hooks/*`, `scripts/*`, and
`settings.json`, with `chmod +x`): `beast-surface.sh`, `beast-recall-hook.sh`, `beast-pack.sh`, the
`beast-on→pack` seam in `on-prompt-submit.sh`, the beast helpers in `lib-helpers.sh`, and the recall
wiring in `settings.json`. **Linux-safe** by construction — `bash` + coreutils + `git` + `jq` only;
`pwd -W` guarded (`|| pwd`); no here-strings; JSON via `$ENV` not the glob-prone `--arg`. Verified
both statically and by the fresh-`$HOME` install simulation.

**Commits:** `8bf2d22` (Sprint 36) and `55bc603` (the previously-uncommitted Sprint 35 foundation,
including the critical `_install/scripts/beast-surface.sh` the install pack was missing). Committed
surgically so a parallel session's unrelated work was left untouched.

---

## 9. Honest status — what's solid, what's rough, what's next
**Solid (live & proven):** global wiring; per-project pack; deterministic, fail-safe, silent-by-default
recall; kill-switch superset; install-pack + Linux readiness.

**Rough (quality, not mechanism):** the lessons PCW auto-built are real but **noisy** — because PCW is
itself harness-managed, its git fix-commits are full of `.claude/`/contract/state churn, so some lesson
scopes/triggers point at harness bookkeeping rather than PCW's product code; triggers are broad keyword
bags (occasional over-matching); and git-log em-dashes show as mojibake. These are **distillation**
refinements.

**Deferred by design (Sprint 37 territory):**
- **Enforcement as a hard gate.** Today recall is **inject-only** (it surfaces and instructs but does
  not block). Turning it into a block-until-reconciled gate is the next step.
- **Automated capture at birth events** (test red→green, verifier FAIL→PASS, revert).
- **Pack quality:** filter `.claude/`/`.agent-memory/` churn from the git source, tighter trigger
  derivation, UTF-8 fix.

---

## 10. Artifacts
- **Scripts (live + `_install`):** `hooks/beast-recall-hook.sh`, `scripts/beast-pack.sh`,
  `scripts/beast-surface.sh`; seam in `hooks/on-prompt-submit.sh`; helpers in `scripts/lib-helpers.sh`;
  wiring in `settings.json`.
- **Tests:** `tests/test-beast-{toggle,surface,recall-wiring,pack,roundtrip}.sh`,
  `tests/test-intuition-control.sh`.
- **Specs/contracts/criteria:** `beast-mode-memory-grounding-spec.md`,
  `beast-mode-global-recall-spec.md`, `evaluation-criteria-sprint-{35,36}.md`,
  `sprint-3{5,6}-{proposal,contract}.md`.
- **Evidence:** `.claude/evidence/intuition-control-proof.md`,
  `.claude/evidence/sprint-36-functional-validation.md`.
- **Decision record / agreement:** `docs/applying fussion ideas/changes-to-the-idea.md`,
  `docs/applying fussion ideas/beast-mode-global-agreement-verbatim.md`.
- **Reports:** this file + `sprint-35-…` + `sprint-36-…`.

---

## 11. One line
We turned passive memory into an active, deterministic intuition layer — installed globally,
lessons per-project — proved it changes agent behaviour, shipped it for Linux, and watched it fire on
a real project's own history; what's left is making it *enforce* and making the lessons *sharper*.
