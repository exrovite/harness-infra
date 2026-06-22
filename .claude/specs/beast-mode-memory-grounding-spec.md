# Beast-Mode (Memory-Grounding) — Product Spec (Sprint 35+)

> Full agreed detail and rationale: `docs/applying fussion ideas/changes-to-the-idea.md`
> (decisions D1–D10). This spec is the high-level WHAT. Sprint 35 builds the
> FOUNDATION slice; surfacing/recall/uptake are staged into sprints 36+.

## Problem
The agent forgets. It drifts with nothing concrete to check against ("have you
drifted?" → confident guess, not a verified fact). Hard-won learnings — a problem
hit, corrected, solved the right way — are saved but never surface at the moment
they matter, so the agent re-derives or re-breaks what it already solved. Memory
in the system is **storage, not intuition**.

## Solution (whole design, at altitude)
A harness mode, **beast-mode**, that turns passive memory into an active grounding
layer. At consequential moments the harness deterministically surfaces what was
already agreed and already learned (including past mistakes and their detailed
fixes), and forces the agent to reconcile its action against it before proceeding.
Built on mempalace (drawers + knowledge graph + tunnels) and the existing harness
hooks. Ships OFF by default; never fires unless turned on.

## The six pillars (WHAT each must achieve)
1. **Toggle** — `beast-on` turns it on, `beast-off` turns it off (exact-match
   prompt tokens). `beast-on` requires the harness to be on and **auto-enables it
   first** if disabled. Beast-mode is a strict superset of harness-on.
2. **Capture** — happens ONCE on `beast-on` (a one-time bulk pack) and at
   deterministic "birth" events (test red→green, verifier FAIL→PASS, revert,
   correction token). **No per-write background hook. No CMD windows.**
3. **Relevance** — the harness owns the decision procedure (when to fire, what to
   query, threshold, top-k); the embedding engine only ranks. Silence is the
   default; better to inject nothing than noise.
4. **Surfacing** — match the action's **stable atoms** (file, symbol, code
   pattern, error signature, phase), not the situation; literal scan → phase
   anchor → threshold-gated semantic net.
5. **Memory grains** — compact **tripwires** (KG facts, for matching) plus
   intricate verbatim **dossiers** (drawers: problem / dead-ends / root cause /
   fix / why), surfaced headline-first with full detail on demand.
6. **Uptake** — adversarial, self-relevant framing → **block-until-reconciled**
   (agent must address each surfaced item by reference) → a **tripwire behavioral
   test** that proves injection changes behavior (A/B, injection ON vs OFF).

## Governing principle
LLM/human judgment is allowed only at CAPTURE (deliberate, one-time, cold path).
RECALL is a pure function (hot path, deterministic). This is what keeps "surface
what we got wrong" deterministic in a dynamic situation.

## Sprint 35 scope (the FOUNDATION — what this sprint delivers)
Pillars 1 and 2 only, because recall (3–6) cannot be functionally tested until
capture exists and the project is packed:
- `beast-on` / `beast-off` toggle in `on-prompt-submit.sh` (exact-match), with the
  full truth table: `beast-on` auto-enables harness (printing the exact notice
  `[HARNESS RE-ENABLED — beast mode requires active gates]` when it was disabled);
  `beast-off` leaves harness on; `---` drops BOTH harness and beast; `===` restores
  ONLY the harness.
- `beast-mode.flag` state + `beast_*` helpers in `lib-helpers.sh`, resolved by
  project root (cwd-independent), mirroring the kill-switch helpers.
- One-time **curated bulk-pack initializer** that packs this project's distilled
  memory into mempalace wing `harness_infra` — drawers + KG facts — idempotent,
  no CMD windows.
- A **curated source manifest** (what is seeded; what is excluded — sessions logs,
  raw scripts, hook source).
- Mirrored into `_install`.

## Constraints
- Detection in `on-prompt-submit.sh` via stdin prompt JSON; exact trimmed match;
  the toggle messages themselves must never be blocked by a gate.
- Reuse existing kill-switch resolution (`find_project_state_dir`,
  `harness_disabled_resolved`); never re-mangle the wing name (hard-set
  `harness_infra`).
- Bulk pack is curated, NOT a firehose (the PCW failure: 95k raw drawers, empty
  KG). Seed only the distilled sources; seed BOTH drawers and KG facts.
- Windows/MSYS-safe (`tr -d '\r'`, `tr` not `sed` for backslashes, temp files not
  here-strings, `read` loops tolerate missing trailing newline).
- mempalace writes go through the MCP server / its CLI — never a hook that spawns
  a visible terminal.

## Open questions for NEGOTIATE
- Bulk pack: drive it through the MCP tools (agent-mediated, one-time) or a
  standalone script callable headless? (affects how it is functionally tested)
- KG fact granularity: how many facts to seed from MEMORY.md (one per settled
  feature vs. finer)?
- Functional test isolation: pack into a disposable test wing (`harness_infra_test`)
  and clean up, so live-palace state is not polluted by CI runs.
