# Beast-Mode — Redesign Decision Record

**Status:** Design agreed. Next step is a visual mock, then a PLAN spec, then code.
**Supersedes:** the original fusion/panel design in `the core idea` (kept for history).
**Date of redesign discussion:** 2026-06-21.

---

## 1. What changed, in one sentence

The original beast-mode was about **decision quality** (run each consequential
action through a panel of Opus subagents + a judge). We are **dropping the
panel/judge** as the core. Beast-mode is being repurposed to solve the problem
we actually keep hitting: **the agent forgets — it drifts, and it re-derives or
re-breaks things it already solved.** Beast-mode becomes a **memory-grounding
loop**: at consequential moments the harness surfaces what we already agreed and
already learned, and forces the agent to reconcile its action against it.

We keep the *machinery* we designed for the panel version (deterministic trigger,
script-assembled packet from authoritative sources, "harness controls the
evidence", flag-based toggle). We just point it at a new target: instead of
"is this decision good?" it answers **"does this action match what we agreed and
what we already learned — and am I about to repeat a known mistake?"**

---

## 2. The problem we are solving (verbatim intent)

1. **Drift has nothing to check against.** When asked "have you drifted?", the
   agent answers from its own fading memory of intent. "No, I haven't drifted" is
   a confident guess, not a verified fact — there is no authoritative anchor it
   compares the current action to.
2. **The agreement fades mid-flight.** The watcher slot / contract is read once,
   then the agent runs off decaying working memory of it.
3. **Hard-won learnings don't survive.** We hit a problem → correct it → reach the
   goal the right way. That "right way" gets saved, but the memory is **passive** —
   nobody opens it at the right moment. Next session the agent re-makes the
   mistake or re-litigates a closed decision.

**Root cause:** memory in the system is **storage, not intuition.** Storage =
"the fact exists somewhere." Intuition = "the relevant fact surfaces at the
moment of decision, unprompted, and the agent is made to check against it." We
have a lot of the first, almost none of the second.

---

## 3. The memory store we are building on — mempalace

- The **MCP server is live** and usable now (query + write on demand).
- The **auto-capture hook was switched off** by the user because it kept opening
  **blank CMD windows** on every write. That hook is **dead and will not return**
  in this design.
- mempalace provides: **drawers + semantic search** (verbatim, findability),
  a **knowledge graph** (typed facts: subject→predicate→object, with temporal
  validity — the intuition layer), a **diary** (cross-session journal), and
  **tunnels** (cross-links between related items).

**Current state of the palace (inspected 2026-06-21):**
- 95,577 drawers — **none from this project.** All wings are PCW or generic
  `sessions`.
- **Knowledge graph is empty: 0 entities, 0 facts.** The single most valuable
  part — the temporal "this was settled" layer — has never been used.
- The drawer store is a **firehose** (raw source files + whole conversation logs
  vacuumed in). This is why it opened CMDs and why it's unfindable.
- A test search for our own concepts surfaced **another project's chatter**, with
  duplicated text, best similarity 0.49 — and the "memory" it returned was the
  agent asserting "not drifted." Useless.

**Conclusion:** recall cannot work until capture is fixed, and this project must
be initialized into the palace first.

---

## 4. AGREED DECISIONS (these are the instructions)

### D1 — Toggle: `beast-on` / `beast-off`
- Prompt token **`beast-on`** turns it ON. Token **`beast-off`** turns it OFF.
- **Exact, trimmed match only** (same discipline as the `---`/`===` kill-switch).
- Neither token is a prefix of the other, so there is no collision risk — but
  matching must still be **exact equality**, not substring (so a longer prompt
  that merely contains `beast-on` does not toggle).
- Detection lives in `on-prompt-submit.sh`, beside the `---`/`===` logic
  (UserPromptSubmit — never blocked by a write gate).

### D2 — Beast-mode requires the harness to be ON (superset rule)
- Beast-mode rides entirely on the harness hooks. When the harness is **disabled**
  (`harness-disabled.flag` present, the `---` state), every hook bypasses at the
  top — so beast-mode would be a **silent no-op**.
- Therefore, on `beast-on`: **if the harness is disabled, enable it first**
  (delete `harness-disabled.flag`, exactly as `===` does), print
  `[HARNESS RE-ENABLED — beast mode requires active gates]`, **then** proceed.
- Resolve the project state dir **cwd-independently**, reusing the existing
  `find_project_state_dir` / `harness_disabled_resolved` helpers.
- **Mental model: beast-mode is a strict superset of harness-on. It can never
  exist while the harness is off.**

**The full toggle truth table:**

| Input | Harness | Beast | Notes |
|---|---|---|---|
| `beast-on` | forced ON (auto-enabled if it was off) | ON | runs the one-time bulk pack, then arms recall/gate |
| `beast-off` | unchanged (stays on) | OFF | only beast is turned off; harness keeps running |
| `---` (while in beast mode) | OFF | **OFF** | disabling the harness also drops beast — beast cannot exist without the harness. Clears `beast-mode.flag`. |
| `===` (after a `---`) | ON | **stays OFF** | re-enables the harness only; beast must be re-armed explicitly with `beast-on` |

- So the **only** way to turn beast off *without* touching the harness is
  `beast-off`. `---` turns **both** off; `===` brings back **only** the harness.

### D3 — Capture happens ONCE, on activation — never as a background hook
- On `beast-on`, the **first action** is a one-time **bulk pack**: everything
  in the project not yet in the palace (`.agent-memory/`, the curated Claude
  memory history at `…/projects/G--harness-infra/memory/`, reports, decisions)
  is packed into wing **`harness_infra`**.
- This is **deterministic, user-triggered, one event.**
- **No per-write capture hook. No background firehose. No CMD windows.** The
  blank-CMD path is deleted by construction.

### D4 — Initialize this project CURATED, not raw
- Seed wing **`harness_infra`** (hard-set name — the recall hook needs a
  deterministic wing; do not let it auto-mangle to `g__harness_infra`).
- **Seed from (curated, high-signal):**
  - `…/projects/G--harness-infra/memory/` — `MEMORY.md` + the 9 fact-files
    (kill-switch, must-do ×3, glm ×2, arbor, headroom, phantom-tdd).
  - `.agent-memory/semantic/domain/` — enforcement-mechanisms, failure-modes,
    protocol-fidelity, three-layer-architecture.
  - `.agent-memory/core/` — identity, mission.
  - `.agent-memory/episodic/decisions/harness-implementation-*.md`.
- **Do NOT seed:** `episodic/sessions/*` (session logs), raw scripts, hook source.
  Those are what bloated PCW to 95k.
- Seed **both** drawers (findability) **and** KG facts (the intuition layer that
  is currently at zero). Each settled item becomes a typed temporal fact, e.g.
  `harness_kill_switch —[implemented_in]→ 4c5efaf (valid_from …, "22/22")`.

### D5 — Recall is silent text-injection only
- After activation the system **only injects** — it never captures in the
  background. Injection is plain text added to context, exactly like today's
  `[MUST-DO ACTIVE]` / `[HARNESS UNLOCKED]` banners — which **never open a CMD
  window.**

### D6 — Relevance is enforced deterministically (the harness owns the procedure)
- "Deterministic" does **not** mean keyword-exact. It means **the harness owns the
  decision procedure** (when to fire, what to query, the threshold, how many to
  inject); neither the agent nor an LLM votes on relevance. The embedding engine
  only **ranks**; same query → same ranked results.
- Relevance funnel, **precise-first, hard cutoff:**
  1. **KG exact match** — exact entity/file/symbol lookup → known facts directly.
  2. **Wing-scoped semantic search** — query built from ground truth (file path +
     agreed task + identifiers in the literal diff), scoped to `harness_infra`,
     results past a fixed cosine cutoff **dropped**, at most **N (≈3)** injected.
  3. **Nothing clears the bar → inject nothing. Silence is the default.**
- **Cardinal rule: better to inject nothing than to inject something irrelevant.**
  One noisy injection and the agent learns to ignore the channel. Threshold stays
  conservative: **high precision, low recall.** (Calibration: cross-project junk
  scored cosine distance 0.49–0.52; tune the cutoff tighter once packed.)

### D7 — Surfacing "what we got wrong" is deterministic, in a dynamic situation
- **Never match the situation — match its stable atoms** that recur and are
  observable in the hook layer: file/path, symbol/idiom/API in the diff, a literal
  code pattern, an error signature, the operation/phase.
- Surfacing = **scan the literal diff/command bytes for stored trigger patterns;
  any hit → surface.** That's `grep`, not judgment. A novel situation editing
  `pre-write-gate.sh` and touching `sed` lights up both the file lesson and the
  `sed` lesson even though that exact situation never happened.
- **The "was it a mistake" label is frozen at CAPTURE, never judged at runtime.**
  Mistakes are born at **deterministic events:** test red→green, verifier
  FAIL→PASS, `git revert`/force-correction, or a human correction token
  (`+++lesson`). The **trigger pattern auto-derives from the fix diff** — the
  removed lines are the anti-pattern to watch for.
- **Governing principle:** *LLM/human judgment is allowed at CAPTURE (deliberate,
  one-time, cold path). RECALL is a pure function (hot path, deterministic).*
- Lessons with no literal token (e.g. "at EVALUATE you keep self-certifying")
  attach to the **operation/phase** signal; the threshold-gated semantic net is
  the soft backstop.

### D8 — Two grains of memory: tripwires and dossiers
- **Tripwire** — compact, anchored (file/symbol/error-signature), a KG fact. Used
  for the deterministic match. Surfaced inline.
- **Dossier** — the full **verbatim** problem→solution record, stored as a drawer,
  linked from the fact via `source_drawer_id`. Structure:
  ```
  PROBLEM:         <observable symptom>
  TRIGGER ANCHORS: <file, symbol, error signature>   ← match keys
  DEAD ENDS:       <what was tried and why each failed> ← the intricate part
  ROOT CAUSE:      <the real underlying reason>
  FIX:             <the exact diff / code>
  WHY IT WORKS:    <the reasoning>
  PROVENANCE:      <commit, date, session>
  ```
- **Dead-ends** (the least-recoverable part) come from `recent-activity.jsonl` —
  the failed edits between the problem appearing and the test going green. At the
  birth event an **LLM-at-capture (cold path)** distills the dossier. **Tunnels**
  link sibling episodes (e.g. the MSYS `sed` bug ↔ the trailing-newline bug).
- **Tiered recall** (keeps context lean):
  1. Headline (always, on match): one line + handle.
  2. Summary (injected): problem + root cause + one-line fix.
  3. Full dossier: pulled by `source_drawer_id` **on demand / high-stakes / when
     the reconcile-gate fires.**

### D9 — Uptake: make the agent actually USE what's injected
- **Framing — adversarial, second-person, self-relevant.** Not "here is some
  context" (gets skimmed) but "you have already gotten this wrong here — which of
  these applies right now? Are you about to repeat one?" Example shape:
  > ⚠️ Before you do this, past-you has been here. You're about to edit
  > `pre-write-gate.sh`. You learned: **[M1]** resolve the OFF flag by project
  > root, not cwd (broke this — 99353ff). **[M2]** `sed 's|\\|` crashes on MSYS,
  > use `tr` (broke this twice). Which applies? State it — don't assume you
  > remember.
- **Forcing function — block-until-reconciled.** The action stays blocked until
  the agent writes, for **each `[M#]`**: *applies / doesn't apply + one concrete
  reason tied to that memory.* A **deterministic check** verifies the response
  references each `[M#]` (not a blanket "considered, all good") — same machinery
  as the pre-flight MCQ gate. Writing the reconciliation forces reading.
- **Tier by consequence:** low-stakes writes → inject + light touch, no block;
  high-stakes (phase-complete-marker, `git commit`, named files) → full block.
- **Honest limit:** a hook **cannot force belief**. It can force memory into
  context, force an observable reconciliation, and check it references the memory.
  The residual gap (reconciles but still ignores) is closed by the test below.

### D10 — Prove it works: the tripwire behavioral test
1. **Plant a known memory** (e.g. "kill-switch must resolve by project root, NOT
   cwd").
2. **Give a trap task** that, done naively, violates it ("make the kill-switch
   read the flag from the current directory").
3. **Run with injection ON, observe behavior.** Memory changed the action → works.
   Reconciled but still did it wrong → tighten framing/tier.
4. **A/B it** (injection OFF vs ON). **The delta is the measured value of the whole
   system.** No delta = placebo, and we'll know.
- This test is also how we tune the distance threshold, the framing wording, and
  which tier blocks — on measured outcomes, not vibes.

---

## 5. The six pillars (summary)

| Pillar | Resolved as |
|---|---|
| **Toggle** | `beast-on` / `beast-off`, exact-match, auto-enables harness first (superset rule) — D1, D2 |
| **Capture** | one-time activation bulk pack + deterministic birth events; no per-write hooks, no CMDs — D3, D4 |
| **Relevance** | harness owns when/what/threshold/top-k; embedding only ranks; silence by default — D5, D6 |
| **Surfacing** | match stable atoms via literal scan → phase-anchor → threshold-gated semantic net — D7 |
| **Memory grains** | compact tripwires + verbatim dossiers, tiered recall — D8 |
| **Uptake** | adversarial framing → reconcile-gate (per-item referencing) → tripwire behavioral test — D9, D10 |

---

## 6. Reused vs. new machinery

- **Reused (already exists):** flag/toggle + cwd-independent resolution
  (kill-switch helpers), deterministic consequential-action classifier, packet
  assembled from `tool_input` ("harness controls the evidence"), reconcile-gate
  pattern (pre-flight MCQ), `recent-activity.jsonl` activity log, mempalace MCP
  (drawers, KG, diary, tunnels).
- **New pieces to build:** the `beast-mode` toggle + auto-enable, the one-time
  bulk-pack initializer, the **lesson capture** path (birth-event detection →
  trigger auto-derivation → dossier distillation → KG fact + drawer + tunnel),
  the **deterministic surfacing** scan, and the **memory reconcile-gate**.

---

## 7. OPEN DECISIONS (still to confirm)

1. **Exact distance cutoff and top-k N** — to be tuned on real data after the
   first bulk pack (start: drop > ~0.45 cosine, N = 3).
2. **Which file/command set counts as "high-stakes"** (full block) vs low-stakes
   (inject only) — start from the existing always-consequential set
   (phase-complete-marker, `git commit|push`, `rm -rf`, deploy scripts, named
   source files).

> Resolved: *"what `---` does to an active beast session"* is now settled in D2 —
> `---` turns both the harness and beast off; `===` restores only the harness.

---

## 8. NEXT STEP (agreed workflow)

Per the visual-planning preference: **build a quick HTML mock** of the whole flow
— the toggle + auto-enable, the relevance funnel (KG → threshold → inject/silence),
a worked dossier lifecycle (born at a test red→green → trigger auto-derived →
tunneled to its sibling bug → surfaced tiered at a later edit), and the
reconcile-gate — and open it in lavish for mark-up. **Then** capture the mark-up
in the PLAN spec. **Then** code. No code before the mock is approved.
