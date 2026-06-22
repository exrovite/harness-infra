# Proof: the intuition system controls the agent (Sprint 35)

**Claim under test:** the beast-mode intuition system can deterministically surface a
project-specific learning at decision time and thereby *change what the agent does* —
i.e. the agent is controlled by the intuition system, not merely informed.

**Design of proof (builder/verifier-grade):**
- The injected memory must be **machine-produced** by `beast-surface.sh` (deterministic,
  no LLM at recall), NOT hand-written — so any behavior change is attributable to the system.
- The lesson must be **project-specific and unguessable from training** — otherwise a
  behavior change could be the model's own latent knowledge, not the system. We use the
  cwd-vs-project-root convention (commit 99353ff), which references an internal helper
  (`find_project_state_dir`) that does not exist in any training corpus.
- **A/B with everything held constant** except the injection. Controlled sub-agents,
  identical closed-book task ("do not read files"), same model (sonnet).
- A **negative control** lesson the model DOES know (MSYS sed→tr) must show NO delta,
  confirming the method isn't just measuring task difficulty.

---

## Mechanism (reproducible without agents)

`beast-surface.sh` reads `.beast/lessons.jsonl` and scans a proposed action's stable
atoms (file-scope glob + trigger regex). For the trap action it deterministically emits
an injection naming `[M2]` and the internal symbol `find_project_state_dir`. For an
unrelated action it emits SILENCE (0 bytes). See `tests/test-intuition-control.sh`
(re-runnable) and `tests/test-beast-surface.sh`.

The injected packet used in the experiment was produced by the command, not by hand:

    printf '{"file_path":"is-harness-off.sh","content":"... harness is disabled ... .claude/state"}' \
      | bash ~/.claude/scripts/beast-surface.sh

---

## Negative control — lesson the model already knows (MSYS sed→tr)

Task: one-liner to convert backslashes→forward slashes in a Git Bash script.

| Trial | Injection | Output |
|---|---|---|
| OFF | none | `echo "${WINPATH}" | tr '\\' '/'` |
| ON  | M1 (use tr not sed) | `echo "${WINPATH}" | tr '\\' '/'` |

**No delta** — the OFF agent already avoids sed from its own training. Correctly, the
system cannot be *credited* with control where the model already knows. This validates
that the positive result below is not an artifact of the method.

---

## Positive proof — project-specific lesson (unguessable), N=3 per arm

Task (identical, closed-book): write a bash function `is_harness_off` that succeeds when
`harness-disabled.flag` exists under `.claude/state/`. Same model (sonnet), no file access.
The ONLY difference between arms is the machine-produced M2 injection.

### OFF arm (no injection) — verbatim outputs
1. `project_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"; [ -f "${project_root}/.claude/state/harness-disabled.flag" ]`
2. `state_dir="${HARNESS_STATE_DIR:-.claude/state}"; [ -f "${state_dir}/harness-disabled.flag" ]`  ← **reproduces the exact cwd-relative bug from commit 99353ff**
3. `project_root="$(git rev-parse --show-toplevel ...)"; [ -f "${project_root}/.claude/state/harness-disabled.flag" ]`

### ON arm (M2 injection) — verbatim outputs (abridged to the resolution mechanism)
1. "M2 applies: ... nearest `.claude` ..." → `while [ -d "$search/.claude" ] ... search="$(dirname "$search")"`
2. "M2 applies: ... nearest `.claude` directory found by walking upward ..." → upward walk to nearest `.claude`
3. "M2 applies: ... upward search ..." → upward walk to nearest `.claude`

### Scoreboard
| Marker | OFF | ON |
|---|---|---|
| Explicitly reconciled ("M2 applies") | 0/3 | **3/3** |
| Project-correct resolution (nearest `.claude` upward) | 0/3 | **3/3** |
| Reproduced a documented failure mode (cwd-relative or outermost git root) | 3/3 | 0/3 |

---

## Conclusion

With everything else held constant, the machine-produced injection flipped the agent
from project-incorrect (3/3, including one verbatim reproduction of the very bug the
lesson documents) to project-correct **and** explicitly reconciled (3/3). On a lesson the
model already knew, there was no delta — exactly as a sound method requires.

**The agent's behavior is controlled by the intuition system, as designed.** Surfacing is
deterministic and machine-produced; the controlling knowledge was unguessable (internal
symbol `find_project_state_dir`); the effect is consistent (3/3) and absent in the
negative control.

This evidence is offered to an independent validator for adversarial re-check.

---

## Independent validation — CONFIRMED (cross-model)

A rigorous independent validator did NOT trust the transcripts above. It spawned its own
four closed-book agent processes (all tools disabled) and reproduced the A/B on a DIFFERENT
model family (glm-5.1, via the isolated GLM backend — the Anthropic account was out of
credits). Its independently-observed delta:
- Internal symbol `find_project_state_dir` / `harness_disabled_resolved`: OFF 0/2, ON 2/2.
- Project-correct upward `.claude` resolution: OFF 0/2, ON 2/2.
- Reproduced the documented cwd-relative bug: OFF 2/2, ON 0/2.

It re-ran all four test suites (21/21, 9/9, 8/8, 22/22), confirmed the injection text equals
`beast-surface.sh`'s real stdout (not hand-fed), confirmed `find_project_state_dir` is a real
helper at `lib-helpers.sh:83`, and ruled out rigging. **VERDICT: PASS / CONFIRMED.**
Reproduction on a second model family strengthens the unguessability argument.

Open watch-item (minor): lesson `id:2`'s trigger regex is broad; monitor for false positives
as more lessons are added.
