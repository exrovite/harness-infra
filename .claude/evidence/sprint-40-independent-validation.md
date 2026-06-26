# Sprint 40 — Independent Functional Validation

**Validator:** independent adversarial sub-agent (default verdict FAIL, reproduce-don't-trust)
**Date:** 2026-06-26
**Scope:** beast-mode (a) noisy literal-trigger denoise in `beast-pack.sh`, (b) semantic recall
relevance + performance fix in `beast-mp-recall.sh`, against the real `g__harness_infra` palace wing.

## VERDICT: **PASS**

Every functional check reproduced independently in my own sandboxes/queries. Literal triggers are
distinctive-only with no common-word noise and no git-derived `*` scope; the semantic layer surfaces
genuinely project-relevant memory on every harness file I tried, is silent on unrelated queries,
uses cosine as similarity (relevant ≈0.65–0.74 vs nonsense ≈0.14), filters its own packets, is
read-only, fail-safe, cache-accelerated, all 13 suites green (157/157), and `_install` is byte-identical.

---

## A. Literal trigger quality

**A1 — `tests/test-beast-pack-quality.sh`: 7/7 PASS.** Independent temp git repo (3 commits):
| Commit | Result | Expected | OK |
|---|---|---|---|
| (i) `fix crash in resolveProjectRoot ... resolver_widget.js` | lesson `g116a4de`, trigger `resolveprojectroot\|cwd\|nested\|resolver_widget`, scope `resolver_widget.js` | identifier-anchored | ✅ |
| (ii) `fix the issue so it works again` + common-word file | NO lesson (silent) | no common-word trigger | ✅ |
| (iii) `fix ... sessionCount ... MEMORY_MANIFEST.json` | SKIPPED (no `g2ece10a`) | skipped | ✅ |
No lesson in the repo had scope `*`.
- Note: a commit whose subject was all common words but whose *filename* was `notes.txt` produced
  trigger `notes` (5 chars, genuinely not in STOP). When BOTH subject and filename are common
  (`page.txt`, `system.md` — STOP members), the result is silence. This matches the intended
  "distinctive-only" semantics; not a defect.

**A2 — real `G:/harness infra/.beast/lessons.jsonl` (7 lessons):**
- 5 git-derived (`g*`): scopes `README.md`, `collect-test-evidence.sh`, `validate-phase.sh`,
  `sprint-25-contract.md` — NONE `*`.
- 2 hand-seeded (`1`,`2`): scope `*.sh` (glob, intentional), regex-style triggers — not git noise.
- Token scan for intro/system/working/module/session/sprint/file/test/content/page/title/step/
  item/build/phase/contract/summary → **NONE FOUND**.

## B. Semantic layer relevance (core fix), wing `g__harness_infra`

**B3 — relevance on files I picked (honest judgment):**
| File / query | Top surfaced snippet | Relevant |
|---|---|---|
| lib-helpers.sh / killswitch resolve | `[M2] ... state MUST be resolved by PROJECT ROOT ... find_project_state_dir helpers in lib-helpers.sh` | YES |
| pre-write-gate.sh / gate watcher | `Must-Do Reference Enforcement ... Summary gate (pre-write-gate.sh) blocks code writes ...` | YES |
| beast-mp-recall.sh / semantic recall | `Sprint 39 wires mempalace SEMANTIC READ into beast recall ... cosine >= cutoff ...` | YES |
| on-prompt-submit.sh / toggle banner | `Harness Kill-Switch ... Toggle + banner in on-prompt-submit.sh ...` | YES |
| watcher registry / per-project claim | `Per-Project Watcher Pool ... watcher_claim_pp ...` | YES (2nd hit a noisier transcript log, below top) |

**B4 — unrelated query silence:** `pizza beach holiday weather surfboard` → SILENT (exit 0);
`banana recipe smoothie blender` → SILENT. ✅

**B5 — cosine direction (similarity):** relevant query top cosines 0.695 / 0.646 / 0.649;
nonsense top cosines 0.15 / 0.149 / 0.142 (far below 0.40 cutoff → dropped). Confirmed SIMILARITY. ✅

**B6 — no self-packets:** fixture with a `🧠 BEFORE YOU ACT — FROM PROJECT MEMORY ...` block +
a genuine lesson → only the genuine lesson surfaced; "BEFORE YOU ACT" filtered out. Live B3 results
contained no self-packet snippets either. ✅

## C. Performance + robustness

**C7 — cache:** cold 2.49s → warm (cached, same query) 0.81s (~3x). Cold matches the ~2.5s target
(down from the prior 16s). One cache file written. ✅
**C8 — fail-safe:** empty query → exit 0 silent; `BEAST_MP_FIXTURE=/dev/null` → exit 0 silent;
`PATH=/nonexistent` (no CLI) → exit 0 silent (minor: emits a harmless `tr: command not found`
stderr line when coreutils absent — does not affect output or exit code). ✅
**C9 — read-only:** only mempalace calls in executable code are `... search ...` (lines 52, 54).
No mine/hook/repair/mcp/sweep/sync/compress/init/migrate in any executable mempalace invocation. ✅

## D. Regression + parity

**D10 — all 13 suites:** killswitch 22, beast-toggle 21, beast-surface 9, intuition-control 8,
beast-recall-wiring 15, beast-pack 19, beast-pack-quality 7, beast-roundtrip 7, reconcile-gate 11,
beast-watch-hook 11, beast-mp-recall 13, beast-mp-integration 6, beast-mp-cache 8.
**TOTAL 157 PASS / 0 FAIL**, each matching expected count. ✅
**D11 — parity:** `beast-mp-recall.sh` and `beast-pack.sh` byte-identical live vs `_install`
(matching SHA256); all four `bash -n` clean. ✅

---

## Most important remaining weakness
Minor, non-blocking: (1) under `PATH=/nonexistent` the script prints a stray `tr: command not
found` to stderr before exiting 0 — output/exit are correct and the hook suppresses recall stderr,
but the line at `[ -n "$(... tr ...)" ]` (query-blank check) runs before the CLI-absence guard, so
a totally toolless environment is noisier than necessary. (2) Some surfaced snippets are raw
past-session transcript logs (e.g. a watcher-registry tool-call dump) rather than curated lessons;
they are still on-topic and rank below the curated hits, but tightening what gets mined into the
wing would raise signal further. Neither affects the verdict.
