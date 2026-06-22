# Beast-Mode — Global System / Per-Project Lessons — VERBATIM AGREEMENT

> This file is a **word-for-word** capture of the conversation in which the beast-mode
> global design was agreed. Turns are reproduced exactly as they occurred (source:
> session transcript `eeea7b75-234f-4c91-b7cd-7e7624b156fa.jsonl`, turns 109–123).
> Nothing below the divider is paraphrased. Header text above the divider is the only
> non-transcript content.

---

## USER

I am currently working with the Private Content Wizard agent. Can you see if... can you help me analyze what it's doing and see if the beast mode is actually working as it's meant to in that particular conversation?

---

## ASSISTANT (Claude)

I'll investigate the actual state rather than guess. Let me check three things: whether beast-mode is even active in that project, whether the recall path is wired to fire, and whether that project has any lessons to surface.

---

## ASSISTANT (Claude)

Confirmed the key facts. Let me check what the toggle actually *did* (the background pack) and whether the hook injects anything per-prompt when beast is on.

---

## ASSISTANT (Claude)

I analyzed it against the actual files, not the report's claims. Here's the straight verdict.

## In the Private Content Wizard conversation, beast mode is *not* functioning as an intuition layer — it's only a flag.

What the toggle did do (this part is live and works):
- `beast-on` was typed in PCW today at **08:43:37**, and the hook correctly wrote `…/Private Content Wizard Web/.claude/state/beast-mode.flag`. The toggle half of the system is genuinely wired.

But nothing is actually surfacing or steering that agent, for **three independent reasons**, each confirmed by file inspection:

| # | What's missing in PCW | Evidence |
|---|---|---|
| 1 | **The recall path isn't wired to fire.** `beast-surface.sh` is not referenced in `settings.json` for *any* hook (PreToolUse or otherwise). So it never runs on the agent's writes. | `grep beast-surface settings.json` → nothing |
| 2 | **PCW has zero lessons to surface.** The lesson store `.beast/lessons.jsonl` exists **only in `G:/harness infra`**. The PCW project has no `.beast/` folder at all. | `ls .beast/` → "No such file or directory" |
| 3 | **`beast-on` does no per-prompt injection, and its one background action is a no-op.** The hook only writes the flag and *tries* to run `beast-pack.sh` once — but `beast-pack.sh` doesn't exist yet, so the `[ -x ]` guard skips it silently. There is no `[BEAST MODE ACTIVE]`-style injection block (unlike `[MUST-DO ACTIVE]`). | `ls beast-pack.sh` → missing; no injection grep hits |

## Why this is exactly what we should expect

This matches **§8 of the Sprint 35 report** precisely. What we built and *proved* last sprint was the **vertical slice in a controlled sandbox** — `beast-surface.sh` produces a deterministic injection, and that injection demonstrably steers a closed-book agent. That proof was real and independently reproduced.

But the three things that would make it *live in an arbitrary project like PCW* are all **Sprint 36 work that hasn't been done**:
1. Wire `beast-surface.sh` into the real `PreToolUse` path in `settings.json`.
2. Build `beast-pack.sh` + the one-time curated capture so a project actually *has* lessons.
3. Add the per-prompt / per-write injection so surfaced lessons reach the agent.

So: in that PCW conversation, "beast mode on" currently means **a flag is set and nothing else happens.** The agent there is not being grounded by any intuition. It's not broken — it's unbuilt. The toggle is honest; the engine behind it isn't connected yet.

If you want, the next step would be to scope **Sprint 36** (wire recall into PreToolUse + build the pack so a live project like PCW actually surfaces lessons). I won't start that without your go-ahead, since it's a new build — but that's the gap between "the flag flips" and "the agent in PCW is actually steered."

---

## USER

But you were meant to create this as a global system, not just for a system that can surface in here, in this project alone.

---

## ASSISTANT (Claude)

You're right, and I want to be precise about where I fell short versus what's actually in place. Let me check the lesson-source resolution before I answer, because that's the crux of "global vs. this-project-only."

---

## ASSISTANT (Claude)

Confirmed by inspection. You're right, and here's the precise anatomy of the gap.

## What I actually built is global *plumbing* with a single hand-placed lesson file here — which makes it behave as project-only.

**What genuinely is global (installed in `~/.claude`, fires everywhere):**
- The toggle `beast-on`/`beast-off` — it fired in PCW today, proving it's global.
- The `beast_*` helpers in `lib-helpers.sh`.
- `beast-surface.sh` itself — global, and mirrored to `_install` so fresh installs get it.

**What makes it collapse to "this project only" — three structural gaps:**

| Gap | Evidence | Consequence |
|---|---|---|
| **No global lesson source.** `beast-surface.sh` resolves `$BEAST_LESSONS` → else walks up for `<project-root>/.beast/lessons.jsonl`. There is **no** `~/.claude/.beast/` fallback and no mempalace link. | script line 29–35 | Even though the script is global, it has data to read **only where a `.beast/` file physically exists** |
| **The only lessons file anywhere is the one I hand-made here.** | `harness infra/.beast/lessons.jsonl` exists; PCW, claude-mesh, Onebright all **missing** | Surfacing is *possible* only in harness infra — by accident of where I seeded the proof fixture |
| **No populating mechanism + not wired to fire.** `beast-pack.sh` doesn't exist; no `PreToolUse` entry. | earlier greps | No project ever *gets* a store, and even here it never fires in production |

## So your criticism is correct on substance.

The decision record (D3/D4) and the original intent were explicitly **global** — a one-time bulk pack drawing on **mempalace** (which is global, 95k drawers) plus Claude history, surfacing wherever you're working. What I delivered and proved was the *mechanism*, seeded with **one project-local fixture** used as a controlled proof. That fixture is narrower than the brief, and I presented the proof without flagging clearly enough that the lesson source was local-by-accident, not global-by-design.

## The corrected global design

To match what you actually asked for, three changes — none of which I've built:

1. **Global-first lesson source.** Change `beast-surface.sh`'s resolution to a chain: **global store** (`~/.claude/.beast/lessons.jsonl`, or mempalace-backed) **+ optional per-project overlay**. Then surfacing works in *any* project, with project-specific lessons layered on top.
2. **The pack that fills the global store once** (`beast-pack.sh` — the "one-time bulk pack" from mempalace + history that D3 specified). This is what's currently a dangling no-op.
3. **Global `PreToolUse` wiring** so recall fires on the agent's writes in every project, gated by the (already-global) `beast-mode.flag`.

That's the difference between "the flag flips everywhere" (true today) and "the agent is grounded everywhere" (the actual goal).

Let me record this correction so it drives the next sprint correctly, then I'll await your call on scoping it.

---

## USER

[Request interrupted by user]

---

## USER

What I'm saying is that every project should have the system working in it, so which means that the system is globally created, but each project gets its own lessons

---

## ASSISTANT (Claude)

Got it — and that's a cleaner design than what I just proposed. Let me restate it precisely so we're locked:

## The system is global; the lessons are per-project.

- **Installed once, globally** (`~/.claude` + `_install`): the toggle, the helpers, `beast-surface.sh`, and the `PreToolUse` wiring. Same code runs in every project.
- **Each project owns its own lessons**: `<project-root>/.beast/lessons.jsonl`. When you're in PCW, beast surfaces *PCW's* lessons; in claude-mesh, *claude-mesh's*. Mistakes and their fixes are project-specific, so the store is too.

That means my actual per-project resolution in `beast-surface.sh` (`<project-root>/.beast/lessons.jsonl`) was **the right shape all along** — I was wrong a moment ago to propose folding it into one shared global store. Scrap that.

So the real gaps to make it work *in every project* are just two:

1. **Global `PreToolUse` wiring** — so `beast-surface.sh` actually fires on the agent's writes in whatever project you're in, gated by that project's `beast-mode.flag`. (Currently wired nowhere → fires nowhere.)
2. **A per-project populating mechanism** (`beast-pack.sh`) — when you `beast-on` in a project, it builds *that project's* `.beast/lessons.jsonl` once, sourced from mempalace filtered to that project + that project's Claude history + its git history. Plus ongoing capture at birth events. (Currently a dangling no-op → only harness infra has lessons because I hand-made them.)

The global plumbing stays global; each project just grows its own lesson file. Let me fix the memory note I just wrote, since it captured the wrong "global store" idea.

---

## ASSISTANT (Claude)

Memory corrected. Now the pointer in the index:

---

## ASSISTANT (Claude)

Locked in. To summarize where we landed:

**The design (now unambiguous):** beast-mode is a **global system, per-project lessons**. Install once; every project runs the same machinery but surfaces *its own* `.beast/lessons.jsonl`. The per-project resolution already in `beast-surface.sh` is correct — no shared global store.

**Current reality:** the toggle is genuinely global (it fired in PCW). But the grounding fires in no project, because (1) `beast-surface.sh` isn't wired into `PreToolUse` anywhere, and (2) nothing populates a project's lesson file — so only harness infra has lessons, hand-made as a proof fixture.

**To make it live everywhere = Sprint 36, two pieces:**
1. Global `PreToolUse` wiring, gated by each project's `beast-mode.flag`.
2. `beast-pack.sh` — on `beast-on` in a project, build *that project's* lessons from mempalace-filtered-to-this-project + its Claude/git history, plus ongoing capture at birth events.

I haven't built any of that — it's a new build, and your pattern is scope → validate → build. Say the word and I'll scope Sprint 36 properly (proposal + contract + functional TDD that proves surfacing fires in a *second* project, not just here) before writing any code.

---

## USER

But I'm a bit confused. is the bestt lesson what we get from mempalace

---

## ASSISTANT (Claude)

Good question — this is exactly the part worth nailing down, because "lesson" and "mempalace drawer" are **not the same thing**, and right now they're not even connected.

## Two honest answers: what's true now vs. what's intended

**Right now:** No. The two lessons in `G:/harness infra/.beast/lessons.jsonl` are **hand-written by me** for the proof. They did *not* come from mempalace. mempalace is sitting there untouched by beast.

**Intended (the unbuilt `beast-pack.sh`):** Yes — mempalace is meant to be the **main source** the pack distills lessons *from*. But a beast lesson is not a copy of a mempalace drawer. It's a **distilled, structured unit** built from raw memory.

## The distinction that resolves the confusion

| | **mempalace** | **a beast lesson** |
|---|---|---|
| What it is | raw memory — verbatim drawers + KG facts | a distilled, *matchable* unit |
| Shape | freeform text, 95k of them | structured: `scope` (which files) + `trigger` (what content lights it up) + `fix` + dossier |
| Purpose | **storage** — "the fact exists somewhere" | **intuition** — "the right fact fires at the moment of action" |
| Surfacing | you have to go *search* for it | it comes to *you*, deterministically, on a matching write |

So the relationship is: **mempalace = the quarry; a beast lesson = the cut stone.** The pack's whole job is the cutting — read this project's relevant mempalace drawers/KG, plus the project's git history and Claude session history, and **transform** them into a handful of tight, matchable lessons.

## And mempalace isn't the *only* source

A lesson can be distilled from any of:
- **mempalace** (the richest — your accumulated memory of the project)
- **git history** (the actual commits where a bug was fixed — e.g. commit `99353ff`)
- **Claude session history** (where the dead-ends and the eventual fix played out)
- **live capture** at birth events (a test going red→green, a verifier FAIL→PASS) — caught as they happen, going forward

mempalace is the big back-catalogue you already have; the others keep the lesson file growing. The pack reads all of them and writes *one project's* `.beast/lessons.jsonl`.

So: a beast lesson is **derived from** mempalace (among other sources), not **equal to** a mempalace entry. Does that clear it up, or do you want me to sketch what one distilled lesson looks like next to the raw mempalace material it'd come from?

---

## USER

 this is correct please can you save the whole agreement in our conversation word for worfd and get a strict indipendent subagent to check that   what you saved matches our discussion verbatim

---

