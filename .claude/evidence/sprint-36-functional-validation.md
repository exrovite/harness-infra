# Sprint 36 — Independent Functional Validation

**Verdict: PASS (re-validation 2026-06-22, pass 3 — standards now met FUNCTIONALLY)**

---

## RE-VALIDATION (pass 3) — item 7 RESOLVED, item 8-KG RESOLVED

The second fix is in place and **functionally verified in my own fresh sandboxes with NEW
unguessable symbols**. `emit()` now passes EVERY field through the environment and `$ENV`
(`BID/BSC/BTR/BLE/BFX/BDS jq -cn '{id:$ENV.BID,scope:$ENV.BSC,...}'`), never `jq --arg`, so native
`jq.exe`'s argv glob-expansion can no longer mangle a value (`*`, `?`, `[...]`, `$`, quotes, regex
metachars). Live `beast-pack.sh` == `_install` (md5 `aa3e8917...`), `bash -n` clean.

### Re-validation item results (pass 3)

| # | Item | Result | Exact command(s) + observed |
|---|------|--------|------------------------------|
| 1 | Wildcard-scope KG fact packs deterministically | **RESOLVED / PASS** | Own temp git repo + KG facts `VORPLEXNULL83`, `GHRONTIXSYM44` (no filename token). 20 runs alternating cwd `G:/harness infra` and `/tmp`: **VORPLEXNULL83 20/20, GHRONTIXSYM44 20/20**, scope of each is exactly `"*"`, **0 null rows** across all runs. Determinism: sorted md5 of all 20 outputs to **1 unique** (`068301a3...`). Idempotent: re-run 4 to 4 lines. All lines schema-valid. |
| 2 | Filename-token KG fact still packs | PASS | `JXBWQMARKER19` (subject `loader.py`): **20/20**, scope = `loader.py`. |
| 3 | git-sourced lesson still packs | PASS | `fix: KRYZZONAX31 deadlock in engine.rs` present, scope `engine.rs`, every run. |
| 4 | `_install` byte-identical + `bash -n` | PASS | md5 `aa3e8917...` (pack) and `e28666b6...` (recall-hook) match live; `diff` IDENTICAL; both `bash -n` clean. |
| 5 | Round-trip item 8 KG arm | **RESOLVED / PASS** | Packed a project with wildcard KG lesson `PLOONKWERTZ62` (trigger `ploonkwertz62|must_never|double_free`). Drove LIVE `beast-recall-hook.sh` (no `BEAST_LESSONS`; project-root resolved) on a real `Write` to an ARBITRARY file `whatever.md` with content containing `ploonkwertz62` to the `[Mk3807736255]` lesson surfaced through real on-disk files. Negative arm (content without trigger) to silence. |
| 6 | Regression suites | PASS | killswitch **22/0**, beast-toggle **21/0**, beast-surface **9/0**, intuition-control **8/0**, beast-recall-wiring **15/0**, beast-pack **19/0**, beast-roundtrip **7/0**. |

### Third root-cause hunt (no assumption that two was all)

Packed adversarial KG facts containing glob `?`, glob `[x]`, embedded double+single quotes,
`$HOME` + backticks, regex metachars `a.*(b|c)+`, and an empty predicate — all from the
`.agent-memory`-bearing `G:/harness infra` cwd:
- All 6 distinctive symbols present **1/1**, **0 null rows**, **empty stderr**, every line valid JSON.
- Recall fail-safety with a malformed/unbalanced-regex trigger (`badregex((unbalanced`): hook
  **exits 0**, never blocks (grep -E error to no match to silence). Safe degradation, not a defect.
- Glob `?` scope (`conf?.sh`) matching confirmed correct in `beast-surface.sh` directly.

**No third root cause found.** The env-`$ENV` emit is glob-immune across every special-char class
tested; recall remains pure and fail-safe.

### Re-validation verdict (pass 3)

**PASS.** Both previously-open items are now closed functionally: wildcard-scope KG lessons pack
deterministically (20/20, scope `*`, 0 nulls, single md5 across cwds), filename-token and git
lessons still pack, the 8-KG round-trip surfaces through real files, `_install` is byte-identical,
and all seven regression suites are green at the stated counts. **The standards are now met
FUNCTIONALLY.** No new defect.

---

## Pass-2 history (superseded by pass 3 above)

**Verdict: FAIL (re-validation 2026-06-22, pass 2)**
**Validator:** independent, adversarial, default-FAIL. Reproduced in own fresh `mktemp` sandboxes; did not reuse `tests/*.sh` fixtures or read builder progress notes.
**Date:** 2026-06-22

---

## RE-VALIDATION (pass 2) — item 7 STILL-OPEN

The builder fixed the **first** root cause (jq arg `do`→`dsr`) — that part is confirmed present
(live `beast-pack.sh:55` `--arg dsr "$6"`, byte-mirrored to `_install`, md5 `9a11d779...`, `bash -n`
clean). But item 7 is **STILL-OPEN**: KG-facts lessons still fail to materialise, due to a **second,
distinct root cause** the builder's regression does not exercise.

### Item 7 → STILL-OPEN. New root cause: bare `*` scope crashes native `jq.exe`

`mk_scope` returns `*` for any KG fact with no filename token in subject/object (the common case for
conceptual facts). `emit()` then calls `jq -cn --arg sc "$2" ...` with `$2="*"`. The system `jq` is
**native Windows** (`C:\Users\exrov\bin\jq.exe`, jq-1.7.1) whose MSVCRT startup **glob-expands the
bare `*` in argv** into cwd filenames before jq parses options — so jq receives a corrupted program
and aborts (`syntax error ... .78fcbfd9...node` in `/tmp`; `null` in a near-empty dir). The error is
swallowed by the emit's `2>/dev/null`, so the KG lesson is **silently dropped**.

**Discriminator proof (own fresh sandboxes, real `beast-pack.sh`, NEW unguessable symbols):**

```
# 40 runs, two cwds, KG fact WITHOUT a filename token (scope -> '*'):
for cwd in "G:/harness infra" /tmp: run beast-pack 20x each, grep ZBXKWELPMORN9
 -> KG symbol present 0/20 (harness infra cwd)   0/20 (/tmp cwd)   git lesson present 20/20

# Same harness, two KG facts side by side (15 runs from G:/harness infra cwd):
{"subject":"helper.sh", ... "object":"QQFILESYM55 wrapper"}     scope -> helper.sh
{"subject":"PLAINSYM88","predicate":"must_never","object":"leak_state"}  scope -> *
 -> WITH filename token (scope=helper.sh): present 15/15
 -> WITHOUT filename token (scope=*)      : present 0/15
```

```
# Minimal isolation (proves jq.exe, not the script, mangles bare *):
cd /tmp;  jq -cn --arg x '*' '{a:$x}'   -> jq: error: syntax error ... .78fcbfd9...node  (exit 3)
cd /tmp;  jq -cn --arg x 'literal' '{a:$x}' -> {"a":"literal"}                            (exit 0)
empty dir; jq -cn --arg x '*' '{a:$x}'  -> null  (the '*' expanded to nothing, arg dropped)
set -f / MSYS=noglob... do NOT help (native jq.exe globs in its own CRT, not the shell).
```

**Why the builder's `test-beast-pack.sh` (17/0) misses it:** its only seeded KG fact is
`{"subject":"pre-write-gate.sh", ...}` — subject IS a filename, so `mk_scope` returns
`pre-write-gate.sh`, never `*`. The new "no null rows" + "cwd-independence" assertions therefore
only ever exercise the filename-token path and never hit the broken `scope="*"` path. The suite is
green while the defect persists.

**Working fix (verified):** pass `*` to jq via the environment, not argv —
`STAR='*' jq -cn '{scope:$ENV.STAR, ...}'` yields `{"scope":"*"}` reliably (exit 0). Or coerce the
wildcard to a non-glob sentinel before the jq call. Any KG fact lacking a filename token must be
covered by the regression (add a `{"subject":"<UNGUESSABLE_SYMBOL>", ...}` fact with no `.ext`
token and assert the symbol appears, run from `/tmp`).

### Re-validation item results

| # | Item | Result | Evidence |
|---|------|--------|----------|
| fix | `do`→`dsr` applied, parity, `bash -n` | PASS | `beast-pack.sh:55` `--arg dsr`; live==`_install` md5 `9a11d779...`; `bash -n` clean. |
| 7 | Pack KG-facts deterministic (C8/C15/N2) | **STILL-OPEN** | KG fact with no filename token: symbol present **0/40** across two cwds; with filename token: 15/15. Native `jq.exe` globs bare `*` arg. |
| 8-KG | Round-trip KG arm | **STILL-OPEN** | Cannot round-trip a KG-derived lesson when scope=`*` — the lesson is never packed. (8-git already PASS in pass 1.) |
| 2 | git lesson path | PASS | `fix: WUNTRAXOID77 panic in router.go` → `trigger:"wuntraxoid77|panic|router"`, scope `router.go`, present in every run; idempotent. |
| 3 | `_install` byte-identical to live | PASS | md5 `9a11d779...` both (pack); recall-hook unchanged. |
| 4 | Regression suites | PASS | killswitch 22/0, beast-toggle 21/0, beast-surface 9/0, intuition-control 8/0, **beast-pack 17/0, beast-recall-wiring 15/0, beast-roundtrip 7/0** (builder suites green — but blind to the scope=`*` case, see above). `bash -n` clean. |

### Re-validation verdict

**FAIL.** The renamed-arg fix is genuine but only closed one of two causes of the same observable
failure. KG-derived lessons whose scope resolves to the wildcard `*` (the typical conceptual fact)
are still silently dropped — **0/40 in my sandboxes** — so C8 (KG atoms surface) and C15/N2
(deterministic pack) remain unmet functionally, and the 8-KG round-trip cannot complete. The
builder's new regressions pass only because they exclusively seed a filename-subject KG fact.
**To clear:** fix the bare-`*` jq-arg path (pass via `$ENV`) AND add a regression with a
filename-less, unguessable KG symbol packed from a neutral cwd.

---

## ORIGINAL PASS-1 REPORT (below) — the `do` defect it named is now partially fixed


## Headline defect (blocks PASS)

**The KG-facts seam of `beast-pack.sh` is broken and non-deterministic.** In a fresh git repo
with `BEAST_KG_FACTS_FILE` seeded with a distinctive symbol (`VYTHRENMARKER42`), the symbol was
emitted into `.beast/lessons.jsonl` in **0 of 8** runs. Earlier sandbox runs produced literal
`null` JSONL rows instead of lessons.

**Root cause (reproduced):** the `emit()` jq call uses `--arg do "$6"` and references `$do` in the
program (`{...dossier:$do}`). `do` collides with jq's grammar on this MSYS jq build; jq
intermittently mis-tokenizes the program and tries to load cwd filenames as the program text:
- cwd containing `kg.jsonl`      → `jq: error: kg/0 is not defined ... kg.jsonl`
- cwd containing `.agent-memory` → `jq: error: memory/0 is not defined ... .agent-memory`

Renaming the arg (`do`→`dz`/`dossier`) makes the identical command succeed every time. The git
fix-commit lessons happen to use the same `emit()` and thus carry the same latent flaw — they
passed in my runs only by luck of cwd contents.

This violates **C8** (lessons must reference seeded KG atoms), **C15 / N2** (deterministic,
reproducible pack — "same sources → same lessons"), and mandate item 7 ("a lesson references the
seeded KG symbol"). The git half of the pack works; the KG half does not.

**Fix:** rename the jq arg `do` to a non-keyword (e.g. `dz`) in the `emit()` function of
`beast-pack.sh` (live + `_install`), and add a regression asserting a seeded KG symbol surfaces.

## Per-item results

| # | Item | Result | Command(s) / observed |
|---|------|--------|------------------------|
| 1 | Recall fires in a SECOND project (Write + Edit) | PASS | `printf '{"tool_name":"Write",...content:"echo ZXQWPLUMBUS"...}' \| HARNESS_STATE_DIR=$SB/.claude/state bash ~/.claude/hooks/beast-recall-hook.sh` → valid JSON with `.hookSpecificOutput.additionalContext` carrying the lesson; Edit via `new_string` also surfaced. Wrong scope (`.py` vs `*.sh`) → empty. |
| 2 | Flag gating (C3) | PASS | Removed `beast-mode.flag` → same Write yields empty (exit 0); restoring flag surfaces again. |
| 3 | Kill-switch superset (C4) | PASS | Added `harness-disabled.flag` → empty (exit 0). |
| 4 | Silent by default (C5) | PASS | Flag on + no lessons file → empty; non-matching content → empty. |
| 5 | Bash recall + C6b | PASS | `sed -i s/x/ZXQWPLUMBUS/ $SB/foo.sh` → lesson surfaced. `ls -la` and `git status` → empty. |
| 6 | Fail-safety (never blocks) | PASS | empty stdin / malformed JSON / missing tool_input / `Read` tool → all exit 0, no output. |
| 7 | Pack builds per-project lessons deterministically (B1,B2,B4 / C8) | **FAIL** | Own temp git repo (fix-commit touching `widget_handler.rb`, keyword `QFLORBNAX`) + own `BEAST_KG_FACTS_FILE` (`VYTHRENMARKER42`). `BEAST_PACK_ROOT=.. BEAST_LESSONS=.. BEAST_KG_FACTS_FILE=.. bash ~/.claude/scripts/beast-pack.sh`. Git lesson: schema-valid, references file+keyword, idempotent (1→1 on re-run), real palace untouched. **KG lesson: NEVER emitted (0/8 runs); jq `emit()` compile error from `--arg do`.** |
| 8 | End-to-end round-trip (git atom) | PASS (git only) | Packed temp project → drove LIVE recall hook with **no** `BEAST_LESSONS` (project-root resolution) on a Write touching `parser.sh` with packed trigger `glerpnax42` → packed lesson `[Mgf080491]` surfaced through the real on-disk file. KG round-trip unverifiable (pack broken). Note: trigger match is case-sensitive (uppercase content vs lowercase trigger missed). |
| 9 | Regression suites + bash -n | PASS | `test-killswitch.sh` 22/0, `test-beast-toggle.sh` 21/0, `test-beast-surface.sh` 9/0, `test-intuition-control.sh` 8/0. `bash -n` clean on both new scripts. |
| 10 | Live wiring + mirror parity | PASS | `settings.json` PreToolUse has both `Write|Edit` and `Bash` beast-recall entries; mirrored in `_install/settings.json`. md5 identical: recall-hook `e28666b6...`, pack `0e65335b...` (live == `_install`). |
| 11 | Scope honesty (non-blocking, no Sprint 37) | PASS | recall-hook: every exit path is `exit 0`; no `decision`/`deny`/`block`/`exit 2`. No `reconcil`/`birth-event`/`auto-capture`/`uptake` markers in either script. |

## Anti-rigging

- additionalContext observed is the **genuine** stdout of `beast-surface.sh`: it carried the
  distinctive, validator-seeded tokens (`ZXQWPLUMBUS`, `GLERPNAX42`) inside the real
  "⚠️ BEFORE YOU ACT" framing — not hand-fabricated.
- The KG symbol `VYTHRENMARKER42` is unguessable; its absence proves the KG seam failed (it was
  not silently substituted with generic text).

## Defects

| Severity | Defect |
|----------|--------|
| **HIGH** | `beast-pack.sh` `emit()` `--arg do "$6"` — jq keyword collision makes KG-facts lessons fail (0/8) and the pack non-deterministic (cwd-dependent compile errors). Violates C8, C15, N2. Same latent flaw threatens git lessons. Fix: rename jq arg `do`→non-keyword; add KG-symbol regression. |
| LOW | Recall trigger matching is case-sensitive (`grep -E`), so uppercase content vs lowercase-distilled trigger misses. Usability nit; not a contract criterion, but reduces real-world recall. |

## Conclusion

Recall (G1) is functionally solid: fires in a second project, project-root resolved, flag-gated,
kill-switch-honoring, silent by default, Bash-aware with correct C6b discrimination, fail-safe,
non-blocking, correctly wired and mirrored. **But the pack (G2) does not meet the deterministic
per-project-lessons standard:** its KG-facts seam is broken and non-deterministic, so a core
contract criterion (C8) and the determinism requirement (C15/N2) FAIL functionally. Per default-FAIL
and the rule that any functional failure fails the sprint, the verdict is **FAIL**. Fixing the jq
`do` keyword arg (one-line rename in both live and `_install`) plus a KG regression should clear it.
