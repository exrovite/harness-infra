# Discussion Agreement — Session-Aware Must-Do File-Exists Branch

**Captured:** 2026-06-22
**Source-of-truth transcript:** `~/.claude/projects/G--harness-infra/414e75ab-dfaa-4a75-bd0b-7c47a8cf8174.jsonl`
**Status:** Agreement confirmed by user ("this is correct"). Verbatim capture of the planning conversation, to be independently verified against the transcript before PLAN.

> This file reproduces the conversation **word for word** (user typos preserved). Assistant tool calls
> are marked inline as `[TOOL CALLS: ...]`; only the prose text of each turn is reproduced verbatim.
> A distilled statement of the final agreement appears at the very end, clearly marked as a summary
> (NOT part of the verbatim record).

---

## VERBATIM TRANSCRIPT

### USER (turn 1)

We have a problem I would like to fix, but I would like us to talk through it first.

---

### ASSISTANT (turn 1)

I'm ready — what's the problem you're running into? Walk me through it: what's happening, what you expected instead, and where in the harness it's showing up if you know. I'll hold off on touching anything until we've talked it through.

---

### USER (turn 2)

We have a problem with our new must do system. Remember that the idea is that every agent must create its own However, at the moment, what's happening is when an agent finishes, it leaves its must do file in the folder. So when other agents come, they don't have to be forced to create one. We need a way to make sure that when agent finishes, the must do files must be cleaned as well before the agent is allowed to sign off as completed. Does this make sense?

---

### ASSISTANT (turn 2)

Yes, it makes sense — let me play it back to confirm I've got the actual mechanic right, then raise the one thing that worries me before we touch anything.

**What I understand the bug to be:**
- Design intent: every agent, every session, builds *its own* must-do file as part of grounding (the `+++pack` flow relinks grounding into the file it owns).
- The "force creation" gate is really a "does a must-do file exist?" check. It can't tell *whose* file it is or *when* it was made.
- So when Agent A finishes and leaves its file behind, Agent B walks in, the gate sees a file already present, and concludes "grounding already done" — B inherits A's stale grounding and never does its own. The grounding step silently becomes a no-op for everyone after the first agent.
- Fix direction: an agent must not be allowed to sign off as COMPLETE until its must-do file is cleaned up, so the folder is empty again for the next agent.

That all tracks. Before I propose anything, let me check one thing in the actual code rather than trusting my memory, because the right design hinges on it.

Let me look at how must-do files are currently detected, created, and tied to a session.

[TOOL CALLS: Grep for `must-do` across `**/*.sh`; Grep for `must-do-summary|must_do|MUST_DO|must-do-[0-9N]`]

---

### ASSISTANT (turn 2, continued — preamble)

Let me see how ownership and file naming actually work right now.

[TOOL CALLS: Grep ownership/lane patterns in `build-mustdo-pack.sh`; Read `_install/MUST-DO-SYSTEM.md` (+ `_install/CLAUDE.md` returned as context)]

---

### ASSISTANT (turn 2, continued — after first reads)

This is exactly the part I wanted to verify. Two facts now matter: ownership rides on the watcher lane (`slot-N` ↔ `must-do-N.md`), and the owned file is resolved by `mustdo_file_for_dir`. Let me read the resolver and the actual gate logic so I'm discussing the real behavior, not my memory of it.

[TOOL CALLS: Grep `mustdo_file_for_dir` in lib-helpers.sh]

---

### ASSISTANT (turn 2, continued — "Good — now I'm grounded")

Good — now I'm grounded in how it actually works, and I can see the real shape of the problem. Here's where it lands, and the one decision that determines the whole fix.

## What's actually going on

Two different things live in `docs/must do/` and the system half-conflates them:

1. **The grounding spec** — the list of files an agent must read (and, after `+++pack`, the links to the raw conversation + agreement). This is *content*.
2. **The proof-of-grounding** — the fact that *this* agent did the ritual. This is *per-session state*.

The owned file (`must-do.md` / `must-do-N.md`) is being used as **both**. So when Agent A leaves its file behind, Agent B's gate sees "a populated must-do file exists" and reads that as "grounding present" — even though B never did its own. The leftover *content* is masquerading as B's *proof*.

So your instinct is right, but I want to make sure we fix the right half, because "delete the file on completion" has a sharp edge.

## The decision that drives everything

**When the next agent starts with an empty folder, where does its list of files-to-read come from?**

- **(A) It's regenerated fresh every task** — the human restates it, or `+++pack` rebuilds it from the new conversation. → Then wiping the owned file on completion is correct and safe. The folder *should* be empty between agents.
- **(B) `must-do.md` is a persistent, human-authored spec** that every agent is meant to read. → Then deleting it destroys the next agent's grounding, and the real fix is different: we keep the content but stop treating "file exists" as "I did the ritual" — i.e., make proof-of-grounding session-keyed (which `must-do-summary.<session_id>.md` already half-does) so a leftover file can't satisfy a fresh agent.

My read of `MUST-DO-SYSTEM.md` is that it's genuinely ambiguous — it calls the folder a place the project "opts in by creating must-do files that link the files an agent MUST read" (sounds like B), but `+++pack` "clears and repopulates your owned file" (sounds like A). Which did you intend?

## Two other things to settle before I'd write anything

- **Enforcement point.** Active (block the COMPLETE sign-off until the agent's own file is cleaned) vs passive (auto-clean deterministically in the Stop / watcher-release hook). Harness philosophy says hard/deterministic wins — *"a script checks whether the agent did… and blocks if not."* But the Stop hook has bitten us before (sub-agents trigger it and released the parent's watcher). My lean: do it in the **same place the watcher lane is released**, since ownership already rides that lane — when `must-do-N.md`'s lane is freed, its file goes with it. That keeps the two lifecycles in lockstep instead of inventing a third.
- **Concurrency + crashes.** Whatever we do must only ever delete the finishing session's *own* lane file (D-Clear: never touch a sibling's), and orphaned files from crashed sessions need reaping somewhere — `startup-recovery.sh` already reaps stale watchers, so the same place could reap their must-do files.

Before I propose a concrete design: **is it (A) or (B)?** That single answer tells me whether we're building "wipe-on-release" or "session-keyed proof," and I don't want to build the wrong one.

---

### USER (turn 3)

Can you please analyze what we currently have properly so that we are speaking from evidence?

---

### ASSISTANT (turn 3)

You're right — let me read the actual code paths, not my memory of them. I'll trace the full lifecycle: how the must-do file is detected at the gate, how the per-session summary works, how `+++pack` populates the file, and what happens at completion/release.

[TOOL CALLS: Grep must-do logic in pre-write-gate.sh and on-prompt-submit.sh]

Let me read the two decisive sections in full: the must-do summary gate + the "default-on / create grounding" block in `pre-write-gate.sh`, and what completion/release actually does.

[TOOL CALLS: Read pre-write-gate.sh lines 371-560; Grep release/clear logic in on-session-end.sh]

Now I have the decisive evidence. Let me confirm one more thing — what `+++pack` writes into the file (the marker that distinguishes a built pack from a bare list), since that's what the PLAN backstop keys on.

[TOOL CALLS: Grep build-mustdo-pack.sh write/clear logic; Read PLAN backstop lines 135-159]

I now have the full picture from the actual code. Here's what we have, cited.

## The must-do file lifecycle, as built

**Created in two places, cleaned in zero:**
- An agent is *forced to create* `docs/must do/must-do.md` only by the **default-on block** at `pre-write-gate.sh:526-559` — and that block is in the `else` arm at line 525, i.e. it runs **only when no must-do file exists** (`MUST_DO_MD` empty).
- `+++pack` (`on-prompt-submit.sh:112-132` → `build-mustdo-pack.sh`) **clears and rewrites** the owned file with a `## Grounding` section + a `raw-conversation` link (`build-mustdo-pack.sh:50-60`).
- **Nothing ever deletes it.** `on-session-end.sh:128-133` explicitly documents that watcher auto-release was *removed* (sub-agents trigger Stop and would release the parent). There is no must-do cleanup anywhere in the Stop hook, and no other hook removes the file.

## The bug, precisely

The two gate branches hinge on one test at `pre-write-gate.sh:383` — *does a `.md` file exist in the folder* (`MUST_DO_MD` non-empty, resolved at lines 374-381):

- **File exists → summary branch (383-524).** The agent must only write its *own* per-session summary `must-do-summary.<session_id>.md` (403) that references the basenames **listed in the existing file** (438-446). Per-session proof is correctly isolated — but the *content it grounds against is the leftover file*.
- **File absent → create branch (526-559).** Only here is the agent forced to *author its own grounding* / run `+++pack`.

So when Agent A leaves `must-do.md` behind, Agent B hits the **file-exists** branch. B is never routed through the create branch — it just summarizes A's stale list. Your description was exact: the leftover file silently downgrades every subsequent agent from "build your own grounding" to "summarize someone else's." The per-session summary keying (which we built) doesn't save us, because it sits *downstream* of the branch that already picked the wrong path.

## Two more facts that constrain the fix

1. **There's already a marker that distinguishes "an agent built this" from a bare list:** a packed file contains a `raw-conversation` link. The PLAN backstop at `pre-write-gate.sh:149` keys on exactly that (`grep -qiF "raw-conversation"`). So we *can* tell an agent-built pack from a stale/human-seeded list on disk — we don't have to guess by timestamps.

2. **Completion is not the Stop hook.** Auto-release was deliberately pulled from `on-session-end.sh` because sub-agents fire Stop. The real completion chokepoints are (a) the **watcher release at COMPLETE** (manual, harness blocks release unless phase is COMPLETE), and (b) **`startup-recovery.sh`** stale reaping (4h project-scoped / 72h orphan). Any cleanup we add must hang off one of those — **not** the Stop hook, or we'll wipe live files every time an agent spawns a sub-agent.

## What this means for the decision

The "source of truth" question I raised is now answerable from the code: in the **default-on** model the must-do file is *agent-generated grounding* (the create block literally tells the agent to author it, line 553), and `+++pack` treats it as disposable (clears+rewrites). A human *can* still hand-seed `must-do.md`, and on disk it's indistinguishable from an agent pack **except** for the `raw-conversation` marker.

That gives us a cleaner fix than blunt "delete on completion," and it splits into the same A/B you'd expect — but now evidence-backed:

- **The leftover problem is real and the file-exists branch is the cause.** Whatever we do, the fix has to make a stale file *stop satisfying* the file-exists branch for a new session.
- **We already have a per-session identity** (`session_id`) and **a pack marker** (`raw-conversation`) to decide "did *this* session build *this* file."

So before I design: do you want cleanup to mean **(A) wipe the owned file when its lane is released at COMPLETE** (folder empties between agents; human-seeded lists are sacrificed unless we protect unmarked files), or **(B) make the file-exists branch session-aware** — a file not built/claimed by the current session is treated as absent, routing the new agent through the create branch regardless of leftovers (no deletion needed; stale files become inert)?

They're not mutually exclusive — B fixes the *symptom* without deletion, A gives you the *clean folder* you described. My instinct is B is the more robust core (it can't be defeated by a crash that skips cleanup), with A layered on as housekeeping at release. But that's the call I want from you.

---

### USER (turn 4)

make the file-exists branch session-aware This feels better as it also helps us to keep a history of what we have have done in the must do folder.

---

### ASSISTANT (turn 4)

Locked: **session-aware file-exists branch, no deletion.** Let me make sure the mechanism actually delivers the "history in the folder" benefit you want, because that constrains *how* we make it session-aware. Here's the design I'd build, then the one judgment call I need from you.

## The mechanism: a deterministic session stamp

The branch at `pre-write-gate.sh:383` currently asks *"does a must-do file exist?"* We change it to *"does a must-do file that **this session authored** exist?"* — and we decide authorship by a **session stamp** written into the file.

Critically, the stamp must be written **by a hook/script, never by the agent** (the agent doesn't reliably know its own `session_id`, and a self-reported stamp is forgeable). Two deterministic write points already exist:

- **`+++pack` path** → `build-mustdo-pack.sh` already runs as a script with `session_id` in the payload. It writes the stamp when it builds the pack.
- **Default-on create path** → the agent writes `docs/must do/must-do.md` via the Write tool; `post-write-check.sh` (PostToolUse, already receives `session_id` + `file_path` via stdin) stamps it right after.

This gives us a clean, free signal: **agent-authored files get stamped; human-authored files never do** (a human editing the file outside Claude triggers no hook). That distinction turns out to be the answer to the human-seed problem below.

## How the branches resolve after the change

```
docs/must do/  resolves owned file ──► is it stamped?
        │
        ├─ no stamp (human-seeded spec)  ──► SUMMARY branch  (read it, summarize — unchanged, zero regression)
        │
        ├─ stamped == THIS session       ──► SUMMARY branch  (it's mine, proceed)
        │
        └─ stamped == ANOTHER session    ──► CREATE branch  (author your OWN grounding / +++pack)
                                                   │
                                                   └─ on rebuild, the prior session's file is
                                                      moved to docs/must do/history/ ◄── your history
```

So the leftover-file bug dies at the third arm: Agent B finds Agent A's stamp, gets routed to *build its own*, and A's file is archived into `history/` rather than deleted. The `history/` subfolder is automatically ignored by the resolver because every lookup uses `find -maxdepth 1` (`pre-write-gate.sh:378`), so old packs never pollute spec resolution — they're pure record.

## Blast radius (honest)

Small and contained, because lane filenames and every caller of `mustdo_file_for_dir` stay exactly as they are:
- `pre-write-gate.sh` — add the stamp check at the file-exists branch (+ mirror in the `pre-bash-gate.sh` twin).
- `build-mustdo-pack.sh` — emit the stamp; archive-on-supersede.
- `post-write-check.sh` — stamp agent-authored must-do files; archive-on-supersede.
- Tests for each.

No change to the MCQ generator, summary injection, PLAN backstop, or the lane resolver — they keep reading the same filenames.

## The one call I need from you

The human-seed case is the only real fork. Original use of this system: a human hand-writes `docs/must do/must-do.md` listing required reading. Under my design, an **unstamped** file is treated as a shared human spec and behaves exactly as today (summarize-and-proceed, no per-session forcing). That's a deliberate choice: it means **the session-aware forcing applies only to agent-generated grounding**, not to a human's required-reading list.

Is that what you want — *human-seeded lists stay shared/persistent, and only agent-built packs get the per-session "build your own" treatment*? Or do you want **every** session forced to build its own pack even when a human seeded the list (in which case the human file becomes required-reading the new pack must link, not a standalone summary)?

Once you confirm that, I'll write it up as a spec and we go through the phases.

---

### USER (turn 5)

this is correct please can you save the whole agreement in our conversation word for worfd and get a strict indipendent subagent to check that   what you saved matches our discussion verbatim

---

### ASSISTANT (turn 5)

Good — agreement confirmed. I'll do this in the harness's own style: capture the conversation verbatim to a file, then have an independent subagent verify it against the **actual session transcript** (the ground truth), not against text I hand it — otherwise the check is circular.

First, let me locate the real transcript JSONL for this session so the verifier has an independent source of truth.

[TOOL CALLS: locate transcript JSONL under `~/.claude/projects/G--harness-infra/`; confirm this session by the distinctive phrase "file-exists branch session-aware" (→ `414e75ab-…jsonl`, 3 hits); Write this agreement file; dispatch a strict independent verifier subagent]

*(Every assistant turn after this point in the session is the save / verify / correction loop itself — confirming the transcript, writing this file, dispatching the strict verifier, and applying its fixes — not new substance of the agreement.)*

---

## DISTILLED FINAL AGREEMENT (summary — NOT part of the verbatim record)

**Problem:** A must-do file left behind by a finished agent satisfies the gate's file-exists check (`pre-write-gate.sh:383`), so the next agent is routed to the SUMMARY branch and only summarizes the stale list instead of being forced through the CREATE branch to build its own grounding. The grounding ritual silently becomes a no-op for every agent after the first.

**Chosen fix (option B):** Make the file-exists branch **session-aware** — no deletion (files persist as history).

**Mechanism:**
1. A **deterministic session stamp** is written into an agent-authored must-do file, **by hook/script only, never by the agent** (forgeable / agent doesn't know its own session_id). Write points: `build-mustdo-pack.sh` (the `+++pack` path) and `post-write-check.sh` (the default-on agent-create path).
2. Gate decision at the file-exists branch:
   - **No stamp** (human-seeded spec) → SUMMARY branch (unchanged, zero regression).
   - **Stamp == this session** → SUMMARY branch (it's mine, proceed).
   - **Stamp == another session** → CREATE branch (author your own grounding / `+++pack`).
3. **History:** on rebuild, the prior session's file is moved to `docs/must do/history/` (not deleted). The `history/` subfolder is ignored by resolution because lookups use `find -maxdepth 1`.

**Human-seed semantics (confirmed by user "this is correct"):** Human-seeded (unstamped) lists stay shared/persistent and behave exactly as today; the per-session "build your own" forcing applies **only** to agent-generated packs.

**Blast radius:** `pre-write-gate.sh` (+ `pre-bash-gate.sh` twin), `build-mustdo-pack.sh`, `post-write-check.sh`, plus tests. No change to the MCQ generator, summary injection, PLAN backstop, or the lane resolver.

**Next step:** write this up as a spec and proceed through the harness phases.
