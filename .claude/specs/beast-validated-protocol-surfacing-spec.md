# Beast — Validated-Protocol Surfacing + Enforced Adherence (agreed design)

**Status:** AGREED (this conversation, 2026-06-28). To be built functionally and proven with the
agent in this project. Extends the beast intuition layer (Sprints 35–40).

## 1. The problem this solves
Beast surfaces generic semantic matches → noisy, often dismissed. What we actually want is to
surface the things **the human explicitly blessed** — proven, validated protocols — and **force the
agent not to regress on them**. The user's approval is a far higher-precision signal than cosine
similarity.

## 2. What counts (and what must NOT be mixed in)
We capture **validation of DONE WORK** only:
- ✅ **A — Validated work**: the user praised an outcome that already happened — "it works well now",
  "that fixed it", "this has now worked / given very good results", "the How-to is working better
  now", "fully verified and working" — and/or asked for a report on achieved work ("write up what we
  achieved / how / why / how it worked").
- ❌ **B — Contract / plan approval** (EXCLUDE): procedural sign-off — "this is correct, save the
  agreement", "yes proceed", "approved, build it". Approving a *future* action, not validating a result.
- ❌ **C — Instructions with positive words** (EXCLUDE): "write a perfect prompt", "reply exactly PONG".

The tell for A vs B/C: **A praises an outcome that already happened** (works/worked/fixed/solved/now).

## 3. Extraction — the "validated wins" search (proven)
Order-independent **co-occurrence** over the project's transcripts: a **concept/topic term** AND a
**validation OR report-request marker** appearing within a small window, in any order.
- **Exclusions (mandatory):** compaction summaries ("This session is being continued", "Primary
  Request and Intent", "Summary:"), system msgs ("Stop hook feedback", "WATCHER REMINDER",
  "system-reminder", "Caveat:", "local-command", "PONG"), **negations** ("still wrong", "not work",
  "isn't/doesn't work", "broke/broken", "not correct"), and **contract/plan approvals** (B above).
- **Key by the transferable CONCEPT** (e.g. `microlabels`), NOT the module/file it happened in — so a
  protocol proven in *bullets* can reach the *headline* module.
- Output: `.beast/validated-wins.jsonl` — `{concept, quote (the user's real words), context, source}`.

## 4. Surfacing — rides the existing file/content fingerprint
Beast-recall already fingerprints **file + folder + content** (the original grounding; the harness
packet separately injects the must-do summary every prompt; function-level was never built).
- The transferable **concept is detected from that same content** the agent is editing.
- When a concept with a validated win is present → surface the **real hit** (the user's actual words),
  framed as an **authoritative established protocol** — NEVER "you (the model) confirmed it" (the model
  didn't; the human did, in past sessions).

## 5. The enforced adherence loop (the teeth)
1. **Surface** (beast): presents the real hit, concept-keyed.
2. **Relevance gate** (agent): "Am I working with <concept> here?"
   - Not relevant → state why, proceed.
   - **Relevant → the next consequential action is BLOCKED** until the steps below are done.
3. **Deep search** (agent, its OWN): `mempalace_search "<concept> protocol what worked"`, read the
   docs, look at **what made it work** and **whether any reports were created** — get the established approach.
4. **Adherence — ENFORCED on BOTH branches** (gate stays blocked until satisfied):
   - **Following:** write a **short explanation** (what's relevant, why, what you intend to do) +
     spawn an **independent subagent to cross-check the plan is correct**.
   - **Deviating:** state a **genuinely good cause** + spawn an **independent subagent to check whether
     you're wrong**.
   - The independent check is **mandatory** — **no independent verdict ⇒ gate blocked**.
   - **Do NOT bias the subagent** — present the question neutrally; never lead it toward your answer.
5. **Proceed** only after the independent verdict returns.

## 6. The surfaced prompt template (agreed wording)
```
⚠️ IMPORTANT PROTOCOL — <concept>. Project memory surfaced this from a search of your past work:
   <the surfaced hit — the user's real validation + context>

❓ Are you working with <concept> here? If YES, before you proceed:
 1. Do your own quick search — mempalace_search "<concept> protocol what worked" — read the docs,
    and look at WHAT made the process work and WHETHER any reports were created — to get the exact
    approach we established.
 2. Follow it. This prevents wasting time and tokens going down a path we already know is wrong.
 3. ENFORCED: write a short explanation (what is relevant, why, what you intend to do) AND spawn an
    independent subagent to cross-check it is correct. If you choose NOT to follow, you must have a
    genuinely good cause AND have the independent subagent check whether you are wrong.
    DO NOT bias that subagent — give it the question neutrally.
   (You cannot proceed until the independent check is on file — the gate blocks otherwise.)
```

## 7. Build split
- **Deterministic / harness:** the validated-wins extractor (§3), concept-detection + surfacing (§4),
  and the **enforced gate** (§5 step 4 — block the consequential action until an adherence artifact
  exists: explanation + independent-check evidence for that concept).
- **Agent-runtime (prompted + gated):** relevance judgment, the deep search, the explanation, spawning
  the unbiased independent subagent. The harness surfaces and enforces; the agent reasons and verifies.

## 8. Constraints (inherited)
Read-only recall; no CMD windows; kill-switch superset (harness off ⇒ beast off); MSYS-safe; mirror to
`_install`; functional TDD; prove the full loop end-to-end with the agent in THIS project.
