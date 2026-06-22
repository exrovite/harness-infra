# Sprint 35 — Proposal: Beast-Mode Foundation (toggle + capture/init)

## What I propose to build this sprint
The FOUNDATION of beast-mode — pillars 1 (toggle) and 2 (capture/init) from the
spec. Concretely:

1. **Toggle** in `on-prompt-submit.sh` — exact-match `beast-on` / `beast-off`,
   implementing the full truth table (D1, D2):
   - `beast-on`: if harness disabled, enable it first (delete
     `harness-disabled.flag`), then write `beast-mode.flag`, then kick the
     one-time bulk pack; banner `[BEAST MODE ON — {project}]`.
   - `beast-off`: delete `beast-mode.flag` only; harness untouched.
   - `---`: harness OFF **and** beast OFF (clear `beast-mode.flag`).
   - `===`: harness ON only; beast stays off (explicit re-arm).
2. **Helpers** in `lib-helpers.sh` — `beast_is_on` / `beast_enable` /
   `beast_disable`, project-root-resolved (reuse `find_project_state_dir`).
3. **Curated bulk-pack initializer** — packs this project's distilled memory into
   mempalace wing `harness_infra` (drawers + KG facts), idempotent, exclusions
   enforced, no CMD window.
4. **Source manifest** — `docs/applying fussion ideas/seed-manifest.md` listing
   exactly what is seeded and what is excluded.
5. **`_install` mirror** of every changed hook/helper + the initializer.
6. **Tests** — `tests/test-beast-toggle.sh` (live hook, sandboxed state dir) and
   `tests/test-beast-pack.sh` (real mempalace, disposable test wing), written
   TDD-first.

## How success is verified
Per `evaluation-criteria-sprint-35.md`: functional tests that exercise the real
hook (A) and the real mempalace (C), helper resolution (B), non-regression (D),
and an independent verifier re-running everything (E). No self-certification.

## Staging recommendation (why only the foundation)
The full six-pillar design should be built across an ORDERED sequence, not one
mega-sprint, because each stage's tests depend on the previous stage's output:

- **Sprint 35 (this one)** — toggle + capture/init. *Testable in isolation.*
- **Sprint 36** — recall surfacing (pillars 3–5): deterministic literal-anchor
  scan + threshold-gated semantic net + tripwire/dossier grains. *Requires a
  packed palace (35) to test against.*
- **Sprint 37** — uptake (pillar 6): adversarial framing, block-until-reconciled
  gate, and the A/B tripwire behavioral test. *Requires surfacing (36) to gate on.*

Building 35 first de-risks the rest: if curated capture + KG population doesn't
work cleanly, recall is pointless, and we learn that for the lowest cost.

## Out of scope this sprint
Recall injection, the reconcile-gate, the adversarial framing, the A/B tripwire
test (all 36–37). No changes to any existing sprint/spec/contract.

---

## Self-review (skeptical evaluator)

**Q: Is "functional TDD against real mempalace" actually achievable, or will the
tests be flaky?**
Risk: real MCP calls in a test are slower and depend on the server being up.
Mitigation: scope pack tests to a disposable wing and assert via the same MCP
read tools; gate the pack-test behind a guard that SKIPS (loudly) if the MCP
server is unreachable, so CI degrades to toggle-only rather than failing
spuriously. The toggle tests (A, B) are pure-bash and fully deterministic —
those are the hard PASS bar; pack tests are the integration bar.

**Q: Can the bulk pack run "headless," or does it need the agent/MCP in-session?**
Open question flagged in the spec. Recommendation: make the initializer a thin
script that emits a deterministic pack PLAN (the curated file list + the KG facts
to add), and have the *actual* mempalace writes go through the MCP tools driven
once at `beast-on`. This keeps writes on the no-CMD path and makes the PLAN
independently testable (the script's output is checkable without the server).
NEGOTIATE must lock which half is "the deliverable" — proposed: the PLAN-emitter
+ the wiring are the deliverable; the MCP write is exercised in the integration
test.

**Q: Does adding the beast toggle risk breaking the kill-switch / harness-off
path?** This is the highest-blast-radius change (it edits `on-prompt-submit.sh`
and touches the disabled-flag). Mitigation: D1/D2 non-regression criteria run the
existing `test-killswitch.sh` unchanged; the beast logic must sit AFTER the
existing `---`/`===` handling and only act on its own exact tokens.

**Q: KG fact granularity is undecided — could we over- or under-seed?**
Yes. Resolution: seed conservatively — one fact per *settled feature* already
listed in MEMORY.md (≈10–15 facts), each linked to its dossier drawer. Finer
granularity is a 36+ concern once we see what recall actually needs.

**Q: Is the scope right-sized for one sprint?** Toggle + helpers + initializer +
manifest + tests + `_install` mirror is comparable to prior shipped sprints
(kill-switch was similar). Verdict: acceptable. If the initializer proves larger
than expected, split it to 35a (toggle) / 35b (init) — but do not expand 35 into
recall.

**Verdict: PROCEED to contract.** The foundation is coherent, independently
testable in reality, and de-risks the staged remainder. Lock the two NEGOTIATE
decisions (headless-vs-MCP pack boundary; KG granularity) in the contract.
