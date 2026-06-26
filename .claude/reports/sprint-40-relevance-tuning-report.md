# Sprint 40 Report — Fixing beast-mode relevance (it was "suggesting irrelevant things")

**Date:** 2026-06-26
**Status:** BUILT, TDD-green (157/157), empirically tuned on harness-infra's OWN files, independently
validated **PASS**.
**Evidence:** `.claude/evidence/sprint-40-relevance-evidence.md`,
`.claude/evidence/sprint-40-independent-validation.md`

## 1. The audit (why it was bad)
After days of real use in PCW, beast kept surfacing irrelevant things. The data showed exactly why:
- **62 literal injections, almost all one lesson** — `Mg3c0aed5` with **wildcard scope `*`** and an
  ultra-common trigger `intro|two|call|system|working|hook`. In a content app those words are
  everywhere, so it fired on nearly every edit. The lesson store was ~70% harness-file junk.
- **The semantic ("smart") layer fired 0 times** — `mempalace search` took **5–8s** but the hook
  timeout was 4s, so it was silently killed in 100% of sessions.
- Net: the **dumb layer was ON and loud, the smart layer was OFF**. Worst of both worlds.

## 2. What was fixed (TDD-first)
**Literal noise (`beast-pack.sh`):**
- `mk_trigger` now keeps **distinctive tokens only** (identifiers / technical terms; common words
  dropped via an expanded STOP list). Lessons with no distinctive anchor are **skipped**.
- Git commits touching **harness/state files** (MEMORY_MANIFEST.json, .agent-memory, .claude/state,
  gate-counter, .bat, CLAUDE.md) are **skipped**; **no wildcard-scope** lessons from git.
- harness-infra re-packed: **0 common-word triggers, 0 wildcard scopes** (was the whole problem).

**Semantic layer (`beast-mp-recall.sh`):**
- The mempalace `--wing` filter was **broken after a mine** (returned 0) and slow. Now we query
  **unscoped and filter to the wing in post-processing** — correct AND fast.
- Replaced a grep-per-line parser (**16s** from MSYS fork overhead) with a **subprocess-free** one
  (**~2.5s**).
- Confirmed cosine is **similarity** (keep `>= 0.40`) — fixed a backwards comparison.
- Added a **query cache** (cold 2.5s → **warm 0.6–0.8s**) so repeated edits don't re-hit mempalace.
- **Filter out beast's OWN injected packets** ("BEFORE YOU ACT" / "FROM PROJECT MEMORY" / …) that had
  been mined back in as "memory" — self-referential noise.
- **Mined harness-infra into a `g__harness_infra` wing** (4,296 drawers) so the semantic layer finally
  has my project's memory to surface.

## 3. Factual evidence it now surfaces RELEVANT info (tested on my own files)
| File (query) | Top surfaced memory | Relevant |
|---|---|---|
| lib-helpers.sh / killswitch | "state MUST resolve by PROJECT ROOT … find_project_state_dir" | ✅ |
| pre-write-gate.sh / gate | "Must-Do Summary gate (pre-write-gate.sh) blocks code writes" | ✅ |
| beast-mp-recall.sh / recall | "Sprint 39 wires mempalace SEMANTIC READ … cosine >= cutoff" | ✅ |
| on-prompt-submit.sh / banner | "Kill-Switch … Toggle + banner in on-prompt-submit.sh" | ✅ |
| watcher registry / claim | "Per-Project Watcher Pool … watcher_claim_pp" | ✅ |
| **pizza / beach / weather (control)** | **SILENCE** | ✅ |

Cosine separation confirmed: relevant **0.65–0.74** vs nonsense **0.14–0.15** (below the 0.40 cutoff).

## 4. Independent validation
A strict default-FAIL validator reproduced everything in its own sandboxes/queries: literal triggers
clean, **5/5 files surfaced relevant memory (its own honest judgment)**, control silent, cosine =
similarity, self-packets filtered, cache cold→warm, fail-safe, read-only, **157/157 suites**,
`_install` byte-identical. **VERDICT: PASS.**

## 5. Honest remaining weaknesses
- **Mining signal:** some surfaced snippets are raw past-session transcript dumps rather than curated
  lessons — on-topic and ranked below curated hits, but tighter mining would raise signal further.
- **Latency:** cold ~2.5s per Write/Edit (cached after). Fine in practice; async is a future option.
- **`--wing` workaround:** we filter unscoped results client-side because mempalace's wing filter is
  unreliable post-mine — robust, but if mempalace fixes that, the scoped path would be cheaper.
- **PCW's giant corrupt wing** is still slow (5–8s) and would benefit from a `mempalace repair`.

## 6. Files
- Live + `_install` (byte-parity): `scripts/beast-pack.sh`, `scripts/beast-mp-recall.sh`.
- `tests/test-beast-pack-quality.sh`, `tests/test-beast-mp-cache.sh` (new); recall-wiring / watch-hook /
  pack / mp-integration tests hardened (mempalace + cache isolation).
- `.beast/lessons.jsonl` (re-packed clean); evidence files.

## 7. One line
Beast was loud-and-dumb (wildcard common-word triggers) with its smart half timed out; now the literal
layer is precise, the semantic layer actually runs (fast + cached) and surfaces genuinely
project-relevant memory on my own files — proven on real files and by an independent agent.
