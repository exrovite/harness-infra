# Sprint 38 Spec — Beast-Mode: Forcing (D9) + In-Work Interjection

**Phase:** PLAN. Closes the two things the user flagged as agreed-but-undone, and audits the
**entire** agreed design (D1–D10) so nothing is silently dropped.
Decision record: `docs/applying fussion ideas/changes-to-the-idea.md`.

## 0. FULL AUDIT — agreed (D1–D10) vs built (so nothing is left half-done silently)

| # | Decision | Status before Sprint 38 | This sprint |
|---|---|---|---|
| D1 | Toggle `beast-on`/`beast-off` | **BUILT** (S35) | — |
| D2 | Superset rule (beast needs harness on) | **BUILT** (S35) | — |
| D3 | Capture once on activation, no CMD | **PARTIAL** — pack on `beast-on` built; birth-event capture not | tracked → backlog |
| D4 | Curated seed into mempalace wing | **PARTIAL** — pack builds `.beast/lessons.jsonl` from git + env KG seam; real mempalace wing seed not | tracked → backlog |
| D5 | Recall = silent text injection | **BUILT** (S36) | — |
| D6 | Relevance deterministic + threshold semantic net | **PARTIAL** — literal match built; semantic net not | tracked → backlog |
| D7 | Surface by stable atoms | **BUILT** (literal scan, S36) | — |
| D8 | Two grains: tripwires + dossiers | **PARTIAL** — tripwires built; verbatim dossiers + tiered recall not | tracked → backlog |
| **D9** | **Uptake: framing + block-until-reconciled + tiering** | **PARTIAL — framing built, FORCING NOT (deferred)** | **BUILT THIS SPRINT** |
| D10 | Tripwire behavioral test (A/B) | **BUILT** (S35 proof) | — |
| **NEW** | **In-work interjection (catch drift during work, not just at write)** | **not designed before** | **BUILT THIS SPRINT** |

**Honesty rule:** the PARTIAL items (D3 birth-event capture, D4 mempalace seed, D6 semantic net,
D8 dossiers) are **larger bodies of work**, each its own sprint. They are **explicitly tracked
here as backlog**, not silently dropped. This sprint completes the two the user is actively
blocked on: **D9 forcing** and **in-work interjection**.

## 1. Deliverable A — D9 reconcile-gate (forcing at the write)
When a lesson matches a **high-stakes** action, the write is **BLOCKED** until the agent writes a
reconciliation that **references each `[M#]`** (deterministic check, same machinery as the
pre-flight MCQ gate). Low-stakes matches stay **inject-only** (current behaviour).
- **High-stakes (v1):** `git commit` (Bash); `phase-complete-marker.md`; any pattern in an optional
  per-project `.beast/high-stakes` list.
- **Block mechanism:** `exit 2` + stderr packet (like every other gate), naming the exact
  reconciliation file path and the `[M#]` ids to address.
- **Reconciliation:** the agent writes `<state>/beast-reconcile.md` with, per id, applies/doesn't +
  a concrete reason. Gate re-checks: each currently-matched id present with substantive text → allow.
- **Fail-safe + no deadlock:** control paths (`.claude/`, `.beast/`, `.agent-memory/`, `.openclaw/`,
  `docs/`) are **never blocked** (so the reconciliation write itself is never gated). Any error →
  never block. Tiering ensures routine edits are untouched.

## 2. Deliverable B — In-work interjection (catch drift during work)
A new **PostToolUse** hook (`beast-watch-hook.sh`) fires after **every tool call** — the heartbeat
that runs *inside* a long working turn (Stop only fires at the end = too late; a timer only fires
between turns). It:
- reads the agent's **recent reasoning** from the transcript (`transcript_path`) + the action,
- feeds that prose to the **same** `beast-surface.sh` matcher (prose as `content`),
- surfaces matching lessons as `additionalContext` — **mid-work, between the agent's own steps**.
- **Noise control:** each lesson surfaced **at most once per session** (`beast-surfaced.<sid>`);
  silence by default; flag-gated + kill-switch superset; fail-safe (never breaks a tool call).
- **Honest limit (documented):** a long *pure-reasoning* stretch with no tool calls cannot be
  interrupted — no hook fires until output. Real work is punctuated by tool calls, so blind spots
  are short.

## 3. Constraints (inherited)
Judgment only at capture; recall pure; no CMD windows; kill-switch superset; MSYS-safe; mirror to
`_install`; functional TDD in real sandboxes; strict independent validator (default-FAIL),
reproducing functionally, confirming **both deliverables complete (not half)** and the audit honest.
