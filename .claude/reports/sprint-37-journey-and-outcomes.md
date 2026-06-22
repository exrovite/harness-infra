# Sprint 37 — Journey & Outcomes Report
## Session-Aware Must-Do File-Exists Branch

**Date:** 2026-06-22 · **Commit:** `bd3a3f1` · **Branch:** master
**Status:** Built, independently validated (PASS), committed, in the install pack, Linux-verified.

This report is the *story* of the work: why we decided to do it, how we went about it, and what we
achieved. The companion technical report (`sprint-37-session-aware-mustdo-report.md`) holds the
criteria-by-criteria verification detail.

---

## 1. Why we decided to do it (the problem)

The must-do system exists to force an agent to **read the right files and build its own grounding
before it writes code**. The user noticed a hole in it:

> *"When an agent finishes, it leaves its must-do file in the folder. So when other agents come, they
> don't have to be forced to create one."*

In other words: the grounding ritual was **silently becoming a no-op for every agent after the first**.
The first agent in a project builds a must-do file; it stays on disk; the next agent arrives, the gate
sees "a must-do file already exists," and waves it through to merely *summarize* the previous agent's
list instead of doing its own grounding. The discipline the system was built to enforce quietly decayed
to nothing.

The user's first instinct was *"clean up the file when an agent finishes."* We treated that as the
starting hypothesis, not the conclusion — and the conversation that followed is what made the fix
correct rather than merely plausible.

---

## 2. How we went about it (the process)

The work deliberately followed the harness's own philosophy — **talk → ground in evidence → decide
from first principles → capture the agreement verbatim → verify independently → build TDD-first →
validate independently** — with the human in the loop at every decision point.

### 2.1 Talk it through before touching code
The user explicitly asked to discuss before building. We played the bug back to confirm understanding,
then resisted the urge to design from memory.

### 2.2 Ground every claim in the actual code
Rather than trust recollection of how the gates work, we read the real hooks and cited them by line:
- The routing pivot is a single test in `pre-write-gate.sh` — *"does a `.md` file exist in the
  folder?"* — branching to a **summary** path (file present) or a **create** path (file absent).
- A leftover file always takes the summary path, so a new session is never routed to build its own
  grounding. The per-session summary keying we already shipped sits *downstream* of that branch, so it
  couldn't help.
- We confirmed that **nothing** cleans the file (watcher auto-release was deliberately removed because
  sub-agents fire the Stop hook), and that an agent-built pack is distinguishable from a hand-written
  list by a content marker (`raw-conversation`).

This evidence reframed the problem: the file was being used as **both** the grounding *spec* (what to
read) and the proof *that this agent grounded itself* — two different things conflated into one file.

### 2.3 Choose the approach with the user, not for them
We surfaced the real fork: **(A)** delete/wipe the file on completion vs **(B)** make the file-exists
branch *session-aware* so a stale file simply stops counting for a new session. The user chose **B**,
explicitly because it *"helps us keep a history of what we have done in the must-do folder."* That one
sentence set a hard constraint — **never delete** — that shaped everything after.

### 2.4 Decide the hard sub-questions from first principles
Two design forks remained. Instead of asking the user to adjudicate plumbing, we reasoned them out:
- **Where does archiving happen?** A gate that *moves* a file on "allow" is unsafe — a PreToolUse allow
  doesn't guarantee the write executes (the user can decline, another hook can block, the tool can
  fail), so a move could leave the project with *no* must-do file. The principle "archive + write must
  be atomic, and a guard should not perform irreversible actions" led to **snapshot-then-write by COPY,
  never move** — non-destructive, idempotent, safe even if the write never runs.
- **How to name archives?** Only a **content hash** (`cksum`) is idempotent *and* collision-free by
  construction — identical content dedups to one file, distinct content never collides. Provenance
  isn't lost because the session stamp rides *inside* the archived file.

### 2.5 Capture the agreement verbatim — and prove the capture is faithful
At the user's request we saved the entire discussion **word-for-word** to
`docs/.../discussion-agreement-session-aware-mustdo.md`, then dispatched a **strict independent
subagent** to check it against the *actual session transcript* (not text we handed it — that would be
circular). The first pass **FAILED**: we'd dropped several short assistant lines and one whole turn. We
restored them verbatim from the transcript and re-ran; the second pass **PASSED**. The agreement became
the binding source of record.

### 2.6 Scope through the harness phases before building
We ran PLAN → NEGOTIATE as a **new sprint (37)** that overwrote nothing: a spec, 21 binary
reality-tested criteria, a proposal with a sceptical self-review, and a locked contract. A second
independent subagent validated the scoping *against the agreement and the real code* and returned PASS,
adding one drift-prevention nicety we folded in.

### 2.7 Build TDD-first, in reality
We wrote the test suite **before** the implementation and watched it go **RED (9/23)** — every failing
case was exactly a new behavior. The tests drive the **live hooks** through real `mktemp` +
`HARNESS_STATE_DIR` sandboxes with real JSON payloads and real exit-code/file assertions (the repo's
established pattern), not mocked internals. We implemented one piece at a time until **GREEN (19/23 →
fix a path bug → 19/19)**.

### 2.8 Catch what the upgrade itself would miss (the migration question)
Mid-build the user raised a sharp point: *"make sure this addresses must-do files that may already be
in the folders."* Every file on disk today predates stamping, so it's unstamped — and many are agent
leftovers, not human seeds. Treating "unstamped = human seed" would re-open the very bug for the
existing corpus. We resolved it without breaking the agreed human-seed rule by **classifying unstamped
files by content signature**: a file bearing the `build-mustdo-pack.sh` markers is a legacy *agent
pack* (treated as foreign → forces rebuild); a plain list is a *human seed* (stays shared). Suite grew
to **23/23**.

### 2.9 Prove nothing else broke — by causality, not assertion
Running the full test directory surfaced three nonzero suites. Rather than wave them off, we proved
each was **pre-existing and unrelated** by reverting our files to their `HEAD` versions and reproducing
the *identical* failures (preflight-session-keyed needs an unclaimed watcher slot; headroom is an
`install.sh` label; ralph is a steady-state packet-size assertion in code our changes never touch).

### 2.10 Validate independently, then ship
A third **strict independent subagent** rebuilt its own sandboxes from scratch (default-FAIL, did not
read our notes) and reproduced all 13 headline behaviors — including the two FAIL-gating ones
(foreign-stamp block and migration legacy-pack block) — verdict **PASS**. Only then did we commit,
confirm the install pack, and verify Linux readiness.

---

## 3. What we achieved (outcomes)

### The fix
The must-do **file-exists branch is now session-aware**. A first-line stamp
`<!-- mustdo-session: <id> | built: pack|create -->`, written **only by hooks/scripts (never the
agent, so it can't be forged)**, drives three-arm routing:

| What the gate finds | What happens |
|---|---|
| No stamp + plain list (human seed) | Summary branch — **unchanged**, zero regression |
| Stamp == this session | Summary branch — it's mine, proceed |
| Stamp == another session | **BLOCK** — author your own grounding (`+++pack`) |
| Unstamped but agent-pack-shaped (legacy leftover) | **BLOCK** — treated as foreign (migration) |

Superseded content is **copied — never moved or deleted** — to
`docs/must do/history/<base>.<cksum>.md`, preserving the project's history exactly as the user wanted.
The bash gate mirrors the rule; the pre-flight MCQ and summary readers ignore the stamp line.

### Coverage
- **8 files changed:** `lib-helpers.sh` (5 new helpers, all additive), `build-mustdo-pack.sh`
  (`--session` + stamp + snapshot-before-clobber), `on-prompt-submit.sh` (`+++pack` threads the
  session id), `post-write-check.sh` (stamps agent-authored files), `pre-write-gate.sh` (routing +
  reader skips), `pre-bash-gate.sh` (mirror), `generate-pre-flight-challenge.sh` (reader skip), and a
  new functional test suite.

### Verification
- New suite **23/23** against live hooks; regression green (session-owned 10/10, default-on 11/11,
  pack 25/25, killswitch 22/22; full dir otherwise green).
- `bash -n` clean; live ↔ `_install` byte parity.
- **Three independent strict subagent verdicts: PASS** — verbatim-agreement fidelity, scoping vs
  agreement+code, and live-behavior validation.

### Shipped & portable
- Committed as `bd3a3f1` (focused, feature-only).
- **In the install pack:** all 7 code files live in `_install/`; `install.sh` copies `hooks/*` +
  `scripts/*` and `chmod +x`, so a fresh install gets the whole feature.
- **Linux-ready:** `.gitattributes` (`eol=lf`) means committed blobs are pure LF (0 CR bytes) — no
  `\r` to break bash; the new code is POSIX/GNU-clean (`cksum`, `grep -m1/-E`, `sed` BRE, `mktemp`,
  `find -maxdepth`, parameter expansion). Proven by installing the committed LF versions and re-running
  the full suite (**23/23**) plus regression on LF hooks.

---

## 4. What made this work (the method, distilled)

- **We treated the user's first idea as a hypothesis, then improved it with evidence.** "Delete on
  completion" became "session-aware, copy-not-delete" — safer and history-preserving — because we read
  the code and reasoned about failure modes instead of implementing the first plan.
- **We kept the human in the loop on decisions that were theirs** (delete vs session-aware; human-seed
  semantics; the migration requirement) and **decided the engineering plumbing from first principles**
  (copy-not-move; content-hash naming) rather than offloading it.
- **We never let ourselves be the judge of our own work.** Every claim that mattered — the verbatim
  capture, the scoping, the final behavior, and "nothing else broke" — was checked by an *independent*
  agent or by a *causality experiment*, defaulting to FAIL/skeptical.
- **We built the enforcement, not just the intention.** True to the harness creed —
  *"every 'the agent must…' becomes 'a script checks whether the agent did… and blocks if not'"* —
  the fix is deterministic hook logic, proven by tests that drive the real hooks in reality.
