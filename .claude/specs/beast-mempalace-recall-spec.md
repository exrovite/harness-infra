# Sprint 39 Spec — Wire mempalace SEMANTIC READ into beast recall (D6)

**Phase:** PLAN. Closes the gap the user flagged: mempalace holds the project's real
conversation history (incl. "leave the temperature for now" + the repeated changes), but beast
reads none of it. This wires the **read** path so beast surfaces it by MEANING.

## 1. Problem
Beast recall is literal grep over `.beast/lessons.jsonl` (git-fix-commit derived). The rich source
— **mempalace** (drawers + semantic index) — is unwired. Proven live: `mempalace search` finds
"leave the temperature" / the temp-2.0 flaky-generation FAIL; beast never sees it.

## 2. What this sprint builds (read-only; capture/write stays out — that's what was disruptive)
- **`beast-mp-recall.sh`** (new): given a query + project wing, calls the mempalace CLI
  (`mempalace [--palace P] search "<q>" --wing <wing> --results N`), parses results, keeps only
  those within a **cosine cutoff** (high precision), and emits an injection packet naming each hit
  with a **stable synthetic id `[MP<hash>]`**. Fail-safe: mempalace missing / timeout / no hit →
  **silence**. Deterministic given the index (engine ranks; no LLM) — honours D6.
- **Fingerprint query** in the recall + watch hooks: build the query from the action's
  **folder + file + salient content tokens** (the "where it's working" fingerprint) and call
  `beast-mp-recall` as a **gated secondary layer** after the literal lessons.
- **Free integration:** `[MP<hash>]` ids match the existing `matched_ids` regex, so mempalace hits
  flow through the **per-session dedup** AND the **reconcile-gate** automatically — i.e. a
  high-stakes action carrying a mempalace memory is **blocked-until-reconciled** like any lesson.

## 3. Success (must demonstrate on the real case)
Editing the temperature code (`prompt-assembly.js`, content mentions `temperature`) → beast's
fingerprint query hits mempalace → the agent is shown *"the user has said leave the temperature…"*
(the actual stored memory), where today it sees nothing. Unrelated action → silence.

## 4. Constraints / safety (why this is the READ path only)
- **No capture, no CMD windows.** mempalace auto-capture is exactly what the user disabled; this
  sprint only **reads** (CLI search, stderr suppressed). No background mining, no windows.
- **Bounded + gated:** only on consequential actions; `timeout`-wrapped; threshold-gated
  (silence beats noise — D6 cardinal rule); per-session dedup; runs only when beast+harness on.
- **Graceful degradation:** if the `mempalace` CLI is absent (e.g. a server without it), beast
  falls back to literal lessons — no error. Linux-safe (`command -v mempalace`, `pwd -W` guarded).
- **Test isolation:** a `BEAST_MP_FIXTURE` seam (canned CLI output) for deterministic unit tests +
  a `--palace`/`BEAST_MP_PALACE` seam; the real ~95k palace is never required by tests. Plus a
  gated LIVE smoke test on the temperature query.
- **Mirror to `_install`; functional TDD; independent default-FAIL validator.**

## 5. Tuning knobs (env, with sane defaults)
`BEAST_MP_CUTOFF` (cosine SIMILARITY, keep `>=`, default 0.40), `BEAST_MP_RESULTS` (default 3), `BEAST_MP_WING`
(override derivation), `BEAST_MP_FIXTURE` / `BEAST_MP_PALACE` (test seams).

## 6. Out of scope (named, not dropped)
Automated **capture** into mempalace at birth events (D3/D7) — deferred precisely because the
capture hook is the disruptive part. Tighter function-level fingerprint parsing — incremental.
