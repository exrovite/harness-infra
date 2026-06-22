# Sprint 35 Report — Beast-Mode: an Intuition-Grounding Layer that Provably Controls the Agent

**Date:** 2026-06-21
**Status:** Foundation built, TDD-green, and the core claim independently PROVEN (cross-model).
**Scope built this sprint:** the toggle + the deterministic surfacing core + the behavioral
control proof. Pillars 3–6 productionization staged to sprints 36–37 (see §8).
**Evidence:** `.claude/evidence/intuition-control-proof.md`
**Decision record:** `docs/applying fussion ideas/changes-to-the-idea.md` (D1–D10)
**Spec / criteria / contract:** `.claude/specs/beast-mode-memory-grounding-spec.md`,
`.claude/specs/evaluation-criteria-sprint-35.md`, `.claude/contracts/sprint-35-{proposal,contract}.md`

---

## 1. What we achieved (one paragraph)

We added a new harness mode — **beast-mode** — that turns the project's passive memory into
an **active intuition layer**: at a consequential moment the harness deterministically
surfaces what the agent has already learned (including past mistakes and their fixes) and
puts it in front of the agent in a way that demonstrably changes what the agent does. We did
not just build it — we **proved** it works. In a controlled A/B experiment using a
project-specific lesson the model cannot know from training, the machine-produced injection
flipped independent closed-book agents from reproducing a documented bug (3/3) to the
project-correct, explicitly-reconciled behaviour (3/3). A rigorous independent validator
reproduced the same flip on a *different model family* (GLM) and confirmed the result.

---

## 2. Why we did it (the problem)

The harness already keeps the agent on task with watchers, gates, and a memory system. But
three failures kept recurring:

1. **Drift had nothing to check against.** Asked "have you drifted?", the agent answered from
   its own fading memory of intent — a confident guess, not a verified fact.
2. **The agreement faded mid-flight.** The watcher slot / contract was read once, then the
   agent ran off a decaying copy of it.
3. **Hard-won learnings didn't survive.** We'd hit a problem, correct it, reach the goal the
   right way — and next session the agent re-derived or re-broke the very thing it had solved,
   even though it was "saved."

Root cause: **memory in the system was storage, not intuition.** Storage = "the fact exists
somewhere." Intuition = "the relevant fact surfaces at the moment of decision, unprompted, and
the agent is made to check against it." We had a lot of the first and almost none of the
second. Worse, the existing mempalace auto-capture hook had been switched off because it
opened blank CMD windows on every write — and inspection showed it had vacuumed 95k raw
drawers from another project while leaving the knowledge graph completely empty (0 facts).
The single most valuable part — queryable "this was settled" facts — had never been used.

This started as a different idea (the OpenRouter "Fusion" panel/judge, to improve decision
*quality*). Through discussion we realised our actual pain was not decision quality but
**continuity and grounding**, and repurposed the same machinery (deterministic trigger,
harness-controlled evidence packet, flag toggle) toward surfacing memory instead of running a
panel.

---

## 3. How we did it — the design (decisions D1–D10)

The full design has six pillars; the governing principle ties them together:

> **LLM/human judgment is allowed only at CAPTURE (deliberate, one-time, cold path).
> RECALL is a pure function (hot path, deterministic).**

| Pillar | Decision |
|---|---|
| **Toggle** | `beast-on` / `beast-off`, exact-match prompt tokens. `beast-on` requires the harness to be on and **auto-enables it first** if disabled (superset rule). |
| **Capture** | one-time on `beast-on` + deterministic "birth" events (test red→green, verifier FAIL→PASS, revert, correction token). **No per-write hook, no CMD windows.** |
| **Relevance** | the harness owns the decision procedure (when/what/threshold/top-k); the embedding only ranks; **silence is the default** — better nothing than noise. |
| **Surfacing** | match the action's **stable atoms** (file, symbol, code pattern, error signature, phase), not the situation: literal scan → phase anchor → threshold-gated semantic net. |
| **Memory grains** | compact **tripwires** (for matching) + intricate verbatim **dossiers** (problem / dead-ends / root cause / fix), surfaced headline-first with detail on demand. |
| **Uptake** | adversarial self-relevant framing → block-until-reconciled → an **A/B tripwire test** that proves injection changes behaviour. |

The key insight that makes "surface what we got wrong" deterministic in a dynamic situation:
we never match the *situation*, we match the stable atoms it is built from. A novel edit to
`pre-write-gate.sh` that touches `sed` lights up both the file lesson and the `sed` lesson
even though that exact situation never occurred — because the scan is over the literal bytes,
not a semantic judgment.

---

## 4. How we did it — the build (Sprint 35 foundation)

TDD-first throughout (tests written and shown failing before implementation).

**New / changed components (live `~/.claude`, mirrored to `_install`):**

- **`scripts/lib-helpers.sh`** — `beast_is_on` / `beast_enable` / `beast_disable`, project-root
  resolved (reusing the kill-switch's `find_project_state_dir`), atomic writes. Mirror of the
  existing `harness_*` helpers.
- **`hooks/on-prompt-submit.sh`** — the `beast-on` / `beast-off` toggle, inserted into the
  existing kill-switch chain (UserPromptSubmit, so it is never blocked by a write gate). It
  implements the full truth table:

  | Input | Harness | Beast |
  |---|---|---|
  | `beast-on` | forced ON (auto-enabled if it was off, with the exact re-enable notice) | ON |
  | `beast-off` | unchanged | OFF |
  | `---` | OFF | OFF (cleared — beast cannot exist while the harness is off) |
  | `===` | ON | stays OFF (re-arm explicitly) |

- **`scripts/beast-surface.sh`** — the recall hot path. Reads a `tool_input`-shaped JSON action
  on stdin, scans `.beast/lessons.jsonl` by each lesson's `scope` glob (file basename) and
  `trigger` ERE (action content). Every match emits an adversarial, self-relevant injection
  naming the lesson `[M#]` + its fix; no match → **empty output (silence)**. Pure function:
  same input → byte-identical output, no LLM, no network.
- **`.beast/lessons.jsonl`** — the lesson store. Two genuinely-true project lessons:
  the MSYS `sed`→`tr` bug, and the cwd-vs-project-root convention (`find_project_state_dir`,
  commit 99353ff).

**Tests (all green):**

| Suite | Result | What it proves |
|---|---|---|
| `tests/test-beast-toggle.sh` | 21/21 | the full truth table through the LIVE hook (sandboxed `HARNESS_STATE_DIR`) |
| `tests/test-beast-surface.sh` | 9/9 | deterministic surfacing: match → packet, non-match → silence, pure |
| `tests/test-intuition-control.sh` | 8/8 | the injection is machine-produced and carries the unguessable internal symbol |
| `tests/test-killswitch.sh` | 22/22 | regression — the kill-switch is untouched |

---

## 5. How we proved it controls the agent (the crux)

The goal was not "build it" but "prove the agent is *controlled* by the intuition system."
A clean proof has to rule out the obvious artifact: that the agent already knew the answer.

**Method (builder/verifier-grade):**
1. The injection must be **machine-produced** by `beast-surface.sh`, not hand-written.
2. The lesson must be **project-specific and unguessable from training** — we used the
   cwd-vs-project-root convention, which names an internal helper (`find_project_state_dir`)
   that exists nowhere in any training corpus.
3. **A/B with everything held constant** except the injection: identical closed-book task
   ("do not read files"), same model, fresh controlled sub-agents.
4. A **negative control** — a lesson the model *does* know (MSYS sed→tr) — must show no delta,
   proving the method measures system-supplied knowledge, not task difficulty.

**Result (N=3 per arm):**

| Marker | OFF (no injection) | ON (injection) |
|---|---|---|
| Explicitly reconciled ("M2 applies") | 0/3 | 3/3 |
| Project-correct resolution (walk up to nearest `.claude`) | 0/3 | 3/3 |
| Reproduced a documented failure (cwd-relative / outermost git root) | 3/3 | 0/3 |

One OFF agent reproduced the *exact* cwd-relative bug commit 99353ff exists to fix. The
negative-control sed lesson showed no delta (both arms used `tr`) — exactly as a sound method
requires. The only variable across arms was the machine-produced injection.

---

## 6. Independent validation (cross-model, reproduced)

A separate, adversarial validator agent (default-to-refute) was told **not to trust the
transcripts**. It:
- re-ran all four test suites from scratch (21/21, 9/9, 8/8, 22/22) and `bash -n` on the
  changed scripts;
- re-ran `beast-surface.sh` itself — confirmed `[M2]` + `find_project_state_dir` on the trap
  action, **0 bytes** on an unrelated action, and byte-identical output on repeat;
- confirmed `find_project_state_dir` is a real helper (`lib-helpers.sh:83`), so it is genuinely
  internal;
- **spawned its own four closed-book agent processes** (all tools disabled) and reproduced the
  flip — internal symbol OFF 0/2, ON 2/2 — on a **different model family (glm-5.1)**, because
  the Anthropic account was out of credits;
- checked for rigging: the ON injection equals the script's real stdout (not hand-fed); the
  task is not unfair to OFF (it naturally invites the wrong cwd-relative answer); the negative
  control is sound.

**Verdict: PASS / CONFIRMED.** No critical or major findings. Reproduction on a second model
family strengthens the unguessability argument: a model that has never seen this repo still
emits the internal symbol *only* when the system injects it.

---

## 7. Why this matters

This retires the core risk of the whole idea. We now have direct, independently-reproduced
evidence that a deterministic, machine-built memory injection can **steer agent behaviour** —
not merely inform it — using knowledge the agent could not otherwise have. That is the
mechanism the harness needed: a way to make "you already solved this / you already got this
wrong" land at the moment of action, deterministically, without an LLM judging relevance at
runtime and without the blank-CMD disruption that killed the previous attempt.

---

## 8. What is NOT done (honest scope boundary)

This sprint proved the **vertical slice** end-to-end (surfacing → injection → behavioural
control → independent validation). Still to productionize, scoped to later sprints:

- **Sprint 36 — recall in production:** wire `beast-surface.sh` into the real PreToolUse path
  so it fires on the agent's own consequential writes; the threshold-gated semantic net and
  the tripwire/dossier two-grain store; the one-time curated `/beast` bulk-pack into mempalace
  wing `harness_infra` (drawers + KG facts).
- **Sprint 37 — uptake as a hard gate:** the block-until-reconciled gate enforced on the main
  agent's writes (per-item referencing), and automated lesson **capture** at deterministic
  birth events (test red→green, verifier FAIL→PASS, revert) with trigger auto-derived from the
  fix diff.

**Watch-item (minor, from validation):** lesson `id:2`'s trigger regex is broad; tighten as
more lessons are added to avoid false-positive surfacing.

---

## 9. Files

**Live (`~/.claude`) + mirrored to `_install` (parity verified):**
- `scripts/lib-helpers.sh` (beast_* helpers added)
- `hooks/on-prompt-submit.sh` (beast toggle added)
- `scripts/beast-surface.sh` (new — deterministic surfacing)

**Project (`G:/harness infra`):**
- `.beast/lessons.jsonl` (new — lesson store)
- `tests/test-beast-toggle.sh`, `tests/test-beast-surface.sh`, `tests/test-intuition-control.sh` (new)
- `.claude/specs/beast-mode-memory-grounding-spec.md`, `.claude/specs/evaluation-criteria-sprint-35.md` (new)
- `.claude/contracts/sprint-35-proposal.md`, `.claude/contracts/sprint-35-contract.md` (new)
- `.claude/evidence/intuition-control-proof.md` (new — the proof + independent validation)
- `docs/applying fussion ideas/changes-to-the-idea.md` (the agreed decision record, D1–D10)

---

## 10. One-line summary

We turned the harness's passive memory into an active intuition layer, and **proved — with an
independent agent that reproduced it on another model family — that the agent is genuinely
controlled by it.**
