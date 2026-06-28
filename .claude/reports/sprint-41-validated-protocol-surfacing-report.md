# Sprint 41 Report — Validated-Protocol Surfacing + Enforced Adherence

**Date:** 2026-06-28
**Status:** BUILT, TDD-green (183/0), wired live + `_install`, and **proven end-to-end with the agent in
this project** (the loop caught a real deviation before any code was written).
**Spec:** `.claude/specs/beast-validated-protocol-surfacing-spec.md`

## 1. What we built
A new beast capability that surfaces the things **the human explicitly validated** (proven protocols),
keyed by **transferable concept**, and **forces the agent to verify it isn't going against them** —
via a mandatory, unbiased independent check.

- **`beast-wins-extract.sh`** — order-independent co-occurrence search over the project's transcripts:
  a USER validation/report marker near a concept term, in any order. Excludes compaction summaries,
  system messages, **negations**, **contract/plan approvals**, and verifier/instruction prompts. Output
  `.beast/validated-wins.jsonl`, keyed by the transferable **concept** (e.g. `microlabels`, `killswitch`)
  — so a protocol proven in one module reaches another. (12/12)
- **`beast-protocol-gate.sh`** (PreToolUse) — when the action's content touches a validated concept, it
  **BLOCKS** (exit 2) and surfaces the real validated moment + the agreed prompt, until an adherence
  artifact exists: `<state>/protocol-ack.<concept>.md`. Valid acks: a **dismissal** (`RELEVANT: NO` +
  reason — the relevance gate handling noise cheaply) OR an **`INDEPENDENT-CHECK: CONFIRMED`** verdict.
  A REJECTED check does NOT release the gate. Fail-safe, flag-gated, kill-switch superset, no deadlock
  (the ack file itself is never blocked). (14/14)

## 2. The agreed loop (now enforced)
surface the real hit (concept-keyed) → agent **relevance gate** → if relevant, agent does its **own**
mempalace search for *what worked + any reports* → writes an explanation → spawns an **unbiased
independent subagent** to check whether it's **going against** the protocol → proceeds **only on
CONFIRMED**. The independent check is mandatory — no CONFIRMED verdict on file ⇒ gate blocked.

## 3. End-to-end proof (with me as the agent, in harness infra)
Extracted real wins from this project's history, then drove the full loop:
1. I was about to edit a hook using `find_project_state_dir`. The gate **BLOCKED** me and surfaced the
   real validated moment.
2. Relevance: **yes**. I searched mempalace → found the `killswitch-cwd-independent` protocol.
3. Explanation-only ack **still blocked** (independent check mandatory).
4. I spawned an **unbiased** independent subagent — it **REJECTED** my plan: I'd used
   `find_project_state_dir` but **not `harness_disabled_resolved`**, and resolved only cwd — which would
   have **broken the kill-switch and reintroduced the nested-root lockout** the protocol exists to fix.
5. I **revised** to follow the protocol; re-verified → **CONFIRMED** (with 3 implementation caveats).
6. Only the CONFIRMED ack **released the gate** (exit 0).

**This is the whole value in one run:** the system stopped the agent from regressing on a solved problem,
caught by a neutral verifier, before a line of code was written.

## 4. Honest limits
- **Extraction precision:** deterministic keyword co-occurrence still surfaces some non-validations
  (questions, requests). The **relevance gate** is the backstop — the agent dismisses noise via a cheap
  `RELEVANT: NO` ack. An optional LLM classification pass would tighten extraction further.
- **Integrity:** a hook can't verify a subagent truly ran or that "CONFIRMED" is honest — it enforces the
  *artifact* + a passing verdict. The independent-agent requirement raises the bar but rests on honest
  recording (same limit as all reconcile gates).
- **Cost is bounded by the relevance gate** — the enforced independent check only fires once the agent
  itself admits relevance, and once per concept per session (the ack persists).

## 5. Files
- Live + `_install` (parity): `scripts/beast-wins-extract.sh`, `hooks/beast-protocol-gate.sh`,
  `settings.json` (PreToolUse protocol-gate; `.pre-protocolgate.bak`).
- `tests/test-beast-wins-extract.sh`, `tests/test-beast-protocol-gate.sh`;
  `.claude/specs/beast-validated-protocol-surfacing-spec.md`; `.beast/concepts.txt`,
  `.beast/validated-wins.jsonl` (this project's real wins). Full beast regression: **183/0** across 15 suites.

## 6. One line
Beast now surfaces what *you* confirmed worked, keyed by transferable concept, and **won't let the agent
proceed against a proven protocol** without an unbiased independent verdict — demonstrated live by it
catching me about to re-break the kill-switch.
