# Sprint 39 Report — Wiring mempalace SEMANTIC READ into beast recall (the missing intelligence)

**Date:** 2026-06-22
**Status:** BUILT, TDD-green, live-proven on the temperature case, independently validated **PASS (13/13)**.
**Evidence:** `.claude/evidence/sprint-39-functional-validation.md`
**Spec / contract:** `.claude/specs/beast-mempalace-recall-spec.md`, `.claude/contracts/sprint-39-contract.md`

## 1. Why this sprint existed
The user caught a real, twice-missed gap: **mempalace holds the project's actual conversation
history** — including their repeated instruction *"leave the temperature for now"* and the agent's
back-and-forth changing it 0.8↔2.0 — but **beast read none of it.** Beast matched git-fix-commit
keywords; the rich source sat unwired. This sprint wires the **read** path.

## 2. What was built
- **`beast-mp-recall.sh`** (new): the semantic backstop. Given a query + wing it runs the mempalace
  **CLI** (`mempalace … search`), parses results, keeps high-precision hits (**cosine SIMILARITY ≥
  cutoff**, default 0.40), and emits a packet with stable `[MP<hash>]` ids. **Read-only** (only
  `search` — no mine/hook/capture, the disruptive part the user disabled), `timeout`-bounded,
  fail-safe (no CLI / no hit → silence), deterministic given the index (engine ranks; no LLM).
- **Hook integration:** the recall hook (PreToolUse Write/Edit) and watch hook (PostToolUse) build a
  **folder/file/content fingerprint** query and call beast-mp-recall as a gated secondary layer. The
  `[MP<hash>]` ids merge into the existing **per-session dedup** and the **reconcile-gate** — so a
  high-stakes action carrying a mempalace memory is blocked-until-reconciled with no new gate code.
  The watch-hook call is **throttled** (default 15s/session) to bound cost.

## 3. The calibration finding (and a bug it caught)
Live calibration corrected a real error: `cosine` here is a **similarity** (higher = more relevant),
not a distance. Measured: irrelevant query ≈ 0.33; relevant project memory ≈ 0.41–0.73. My first
implementation kept *low* cosine — backwards. Fixed to keep `cosine >= 0.40`. This is exactly the
"tune the cutoff once packed" step D6 anticipated.

## 4. Proof
- TDD: `test-beast-mp-recall.sh` (13/13), `test-beast-mp-integration.sh` (6/6). Full beast +
  killswitch regression **142/0**. Both hooks fail-safe (rc 0 on malformed input).
- **Live, the user's case:** `beast-mp-recall "prompt-assembly.js temperature setting change"
  <PCW wing>` surfaces the real stored temperature history; an irrelevant query is silent.
- **Independent validator (default-FAIL): PASS 13/13**, live temperature case VERIFIED, similarity
  direction confirmed, read-only confirmed, nothing half-done.

## 5. Honest limits / what's still out
- **Latency:** the mempalace CLI now runs on each Write/Edit (recall) and throttled in-work (watch).
  It's `timeout`-bounded and gated, but it does add ~0.2–1s per consequential action. Acceptable for
  v1; async/caching is a later optimization.
- **Capture is still out (D3/D7).** This is the **read** path only — beast does not yet *write* new
  errors into mempalace at birth events. That's deferred precisely because the capture hook is the
  disruptive part the user disabled. (mempalace already has the history; recall is what was missing.)
- **Bash mempalace** not wired this sprint (Write/Edit + reasoning are; git-commit Bash uses literal
  lessons + reconcile-gate). Threshold needs per-project calibration; 0.40 is the default.

## 6. Files
- Live + `_install` (byte-parity): `scripts/beast-mp-recall.sh` (new), `hooks/beast-recall-hook.sh`
  (mempalace augment), `hooks/beast-watch-hook.sh` (throttled mempalace augment).
- `tests/test-beast-mp-recall.sh`, `tests/test-beast-mp-integration.sh` (new);
  `.claude/specs/beast-mempalace-recall-spec.md`, `.claude/contracts/sprint-39-contract.md`,
  `.claude/evidence/sprint-39-functional-validation.md`.

## 7. One line
Beast now reads the project's real memory by **meaning** — so "I'm changing the temperature" pulls up
"the user said leave the temperature, and you keep changing it" — the intelligence that was sitting in
mempalace, finally wired in (read-only, gated, validated).
