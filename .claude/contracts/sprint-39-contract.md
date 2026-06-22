# Sprint 39 — Contract: Wire mempalace semantic read into beast recall

**Status:** PROPOSED → building (per /goal "implement following the same process").
**Spec:** `.claude/specs/beast-mempalace-recall-spec.md`.

## Scope
Wire the mempalace **read** path into beast recall so the agent is surfaced relevant project
memory (e.g. "leave the temperature") by MEANING. Read-only; no capture; fail-safe; gated.

## Acceptance criteria (functional, reality-tested)

### beast-mp-recall.sh (the semantic backstop)
- **C1.** Given a fixture of mempalace CLI output (`BEAST_MP_FIXTURE`), it parses each result's
  `cosine=` score and text, and emits a packet line per hit naming a stable `[MP<hash>]` id + snippet.
- **C2.** **Threshold:** `cosine` is a SIMILARITY (higher = more relevant). Only results with
  `cosine >= BEAST_MP_CUTOFF` (default **0.40**) are surfaced; lower-similarity results are dropped.
  (Calibrated empirically: noise floor ~0.33, relevant project memory ~0.41–0.73.)
- **C3.** **Determinism:** identical fixture + query → byte-identical output; the `[MP<hash>]` id is
  stable for the same source/text.
- **C4.** **Fail-safe:** mempalace CLI absent, empty output, or timeout → **silence**, exit 0.
- **C5.** **No CMD window / read-only:** invokes only `mempalace … search …` (stderr suppressed);
  no mine/hook/capture; `timeout`-bounded.

### Fingerprint + hook integration
- **C6.** The recall hook (PreToolUse) builds a query from the action's folder + file + content
  and calls beast-mp-recall as a **gated secondary layer** (only when beast+harness on, consequential
  action); a mempalace hit is surfaced as additionalContext alongside any literal-lesson packet.
- **C7.** The watch hook (PostToolUse) likewise queries mempalace from the agent's reasoning + action.
- **C8.** **Dedup:** a given `[MP<hash>]` is surfaced at most once per session (reuses the
  `beast-surfaced.<sid>` mechanism).
- **C9.** **Reconcile-gate integration:** because `[MP<hash>]` matches the existing id regex, a
  HIGH-STAKES action carrying a mempalace memory is blocked-until-reconciled (no new gate code).
- **C10.** Wing scoping: query is scoped to the project's derived wing (override `BEAST_MP_WING`);
  wrong/empty wing → silence (safe).

### Live proof
- **C11.** A gated LIVE smoke check: a fingerprint query for editing the temperature code surfaces
  the real stored "leave the temperature" / temp-2.0 memory from the actual PCW wing.

### Regression / portability / process
- **C12.** All prior beast + killswitch suites stay green; the new hooks remain fail-safe (rc 0 on
  malformed input) and silent when mempalace is unavailable.
- **C13.** `bash -n` clean; live↔`_install` byte parity; Linux-safe (`command -v mempalace`,
  graceful absence, `pwd -W` guarded, no `<<<`); mirrored to `_install`.
- **C14.** TDD-first (suite shown failing before impl); **independent default-FAIL validator**
  reproduces C1–C5, C8, C11 functionally in its own sandbox; verdict in `.claude/evidence/`.

## Notes
- **N1 — read-only by design:** capture into mempalace (the disruptive part) is explicitly out;
  this is the safe half that delivers the value.
- **N2 — determinism caveat:** semantic recall is "deterministic given the index" (engine ranks),
  per D6 — not bit-pure across index changes, but no LLM judges relevance.
- **N3 — graceful degradation:** no mempalace CLI → beast still works on literal lessons.
