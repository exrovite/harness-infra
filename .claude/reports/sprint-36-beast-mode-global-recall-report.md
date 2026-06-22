# Sprint 36 Report — Beast-Mode Goes Global: Recall Wiring + Per-Project Lesson Pack

**Date:** 2026-06-22
**Status:** BUILT, TDD-green, live-wired, and **independently validated FUNCTIONALLY** (PASS).
**Contract:** `.claude/contracts/sprint-36-contract.md` (C1–C20, C6b)
**Evidence:** `.claude/evidence/sprint-36-functional-validation.md`
**Agreement of record:** `docs/applying fussion ideas/beast-mode-global-agreement-verbatim.md`

---

## 1. What we achieved
Sprint 35 proved the intuition *mechanism* but only in harness infra, by a hand-made fixture.
Sprint 36 makes it **real in every project**: the harness now deterministically surfaces a
project's own learned lessons on the agent's consequential actions, in any project, with each
project growing its **own** lessons. The agreed shape — **global system, per-project lessons** —
is now live, not just designed.

## 2. What was built (to the agreed two-gap scope)
- **G1 — Global recall (`~/.claude/hooks/beast-recall-hook.sh`).** A fail-safe `PreToolUse`
  adapter wired for **Write/Edit and file-writing Bash**. It runs the pure `beast-surface.sh`,
  resolves lessons by **project root**, is gated by that project's `beast-mode.flag`, honours the
  **kill-switch superset** (harness off ⇒ silent), is **silent by default**, and injects matches
  as non-blocking `hookSpecificOutput.additionalContext`. It can **never block a tool call**
  (no `set -e`, every path `exit 0`; fuzzed with empty/malformed/missing/unrelated input → rc 0).
- **G2 — Per-project pack (`~/.claude/scripts/beast-pack.sh`).** **Deterministic, no LLM.** Builds
  `<project-root>/.beast/lessons.jsonl` from the project's **own** memory: git fix-commits + an
  env-pointed mempalace KG-facts seam (`BEAST_KG_FACTS_FILE`) — tests never touch the real ~95k
  palace. Idempotent, headless, per-project isolated. Invoked once via the existing `beast-on` seam.
- **Wiring + parity.** Two `PreToolUse` entries added to live `~/.claude/settings.json` (backed up),
  byte-mirrored to `_install` along with both scripts.

## 3. How it was proven (functional TDD, in reality)
TDD-first; each suite shown failing before its implementation. Tests drive the **real** hooks via
the real stdin contract in **fresh second-project sandboxes** (`mktemp`, never harness infra),
including the **end-to-end round-trip**: pack builds a project's lessons → a real Write **and** a
real file-writing Bash action → the live recall hook surfaces them; negatives for flag-off and
unrelated-atom; determinism.

| Suite | Result |
|---|---|
| `test-beast-recall-wiring.sh` | 15/15 |
| `test-beast-pack.sh` | 19/19 |
| `test-beast-roundtrip.sh` | 7/7 |
| Sprint 35 regression (killswitch 22, toggle 21, surface 9, intuition-control 8) | 60/60 |

Broad harness sweep: the standard suites are green; three legacy suites
(`preflight-session-keyed`, `ralph-loop`, `headroom-last30days`) show **pre-existing** failures in
components Sprint 36 never touched (none reference beast; the change is purely additive and the
direct `bash` test runs never load beast or `settings.json`).

## 4. Independent functional validation (the crux)
A strict adversarial validator (default-FAIL) verified by **reproducing in its own sandboxes**, not
reviewing code. It found and forced fixes for **two real, shippable bugs my tests missed by luck** —
both in the pack's JSON emit on native Windows `jq.exe`:
1. **`--arg do`** used a jq keyword → cwd-dependent mis-tokenisation, non-deterministic output.
2. **bare `*` scope** in argv was glob-expanded by jq.exe's CRT → wildcard-scope (conceptual) KG
   facts silently dropped (0/40).

**Fix:** `emit()` now passes **every** field via the environment (`$ENV`), which is glob-immune for
all special-char classes and also subsumes the keyword trap. The validator then hunted for a third
root cause (glob `?`/`[x]`, quotes, `$HOME`, regex metachars, empty predicate) and found **none**.
Final verdict: **PASS** — wildcard KG facts 20/20 across alternating cwds, single deterministic
hash, round-trip surfaces, `_install` byte-identical, all seven suites green.

## 5. Honest scope boundary (what this is, and isn't)
Recall this sprint is **inject-only (non-blocking)** per the agreed design (D5): it surfaces the
lesson with adversarial "you MUST follow it — state which apply" framing, but does **not** hard-block
the write. The **block-until-reconciled hard gate** and **automated lesson capture at birth events**
remain **Sprint 37**. So today the system *injects intuition and instructs*; turning that into a
hard *enforcement* gate is the next sprint. Also: recall trigger matching is case-sensitive (minor).

## 6. Files
- Live (`~/.claude`) + `_install` (byte-parity): `hooks/beast-recall-hook.sh` (new),
  `scripts/beast-pack.sh` (new), `settings.json` (2 PreToolUse entries; `.pre-beast36.bak`).
- Project: `tests/test-beast-recall-wiring.sh`, `tests/test-beast-pack.sh`,
  `tests/test-beast-roundtrip.sh` (new); `.claude/evidence/sprint-36-functional-validation.md`;
  spec/criteria/proposal/contract for Sprint 36.

## 7. One-line summary
Beast-mode now surfaces each project's own hard-won lessons on the agent's real actions in **any**
project — built TDD-first, fail-safe, and proven functionally by an independent agent that caught
two real bugs before sign-off.
