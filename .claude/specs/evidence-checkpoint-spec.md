# Product Spec: Evidence Checkpoint System

## Problem

Agents pass comprehension gates (must-do summary, pre-flight MCQ) then don't follow the process they acknowledged. The PCW agent wrote a perfect summary of the 7-phase experiment cycle, passed the gate, then did all 6 styles at once with no experimentation. Evaluators returned PASS because the builder controlled what the evaluators saw — they never received the templates or process docs.

**Root cause**: Enforcement exists at two points — entry (must-do gate) and exit (evaluation). The gap between them is unmonitored. No script checks whether the agent is following its declared process during execution.

**Why existing gates don't catch this**:
- Must-do summary gate: fires once at entry. Agent passes it and forgets.
- Pre-flight MCQ: tests task awareness, not process compliance.
- Strategy loop breaker: catches repeated failures, not silent shortcuts.
- Watcher cron: advisory. Agent acknowledges and moves on.
- Evaluator (sub-agent): only sees what the builder sends it.

## Solution: Evidence Checkpoints with Harness-Injected Verifier Context

### Core Idea

The agent's own must-do summary declares what process it will follow. Periodically during execution, the harness blocks the agent and forces it to spawn a verifier sub-agent. The verifier gets the must-do context injected by the harness (not by the builder), so the builder cannot filter what the verifier sees. The verifier checks whether evidence of the declared process exists and whether that evidence is substantive.

### Design Principles

1. **Generic** — works for any project. The harness doesn't parse phases or know what "DEFINE" means. The sub-agent (LLM) does all judgment.
2. **No CLAUDE.md changes** — all enforcement lives in hook scripts and state files.
3. **Dynamic** — reads the current must-do summary each time. If the process changes, the checkpoint adapts.
4. **Additive** — integrates with existing hooks. Does not replace or modify the must-do gate, pre-flight MCQ, or strategy loop breaker.
5. **Layer-correct** — Layer 2 (bash) handles triggers, blocks, and injection. Layer 3 (LLM sub-agent) handles judgment.

### What the Harness Does (Layer 2, Deterministic)

1. **Triggers checkpoints** — based on write count since last checkpoint.
2. **Blocks writes** — when a checkpoint is active, source code writes are blocked until a verdict file exists.
3. **Writes the checkpoint brief** — reads the must-do summary AND the must-do source files (the actual docs, not just the agent's summary of them), reads modified files since last checkpoint, writes all of this to a state file.
4. **Injects the brief into every prompt** — `on-prompt-submit.sh` detects the checkpoint file and injects its content. Both main agent and sub-agents in the same project see this injection.
5. **Reads the verdict** — checks `.claude/state/evidence-verdict.json` for PASS/FAIL. On PASS: clears checkpoint, resumes writes. On FAIL: stays blocked, injects failure reasons.

### What the Sub-Agent Does (Layer 3, LLM Judgment)

The sub-agent receives the checkpoint brief (injected by harness via on-prompt-submit, not by builder) and:

1. Reads the must-do summary to understand what process was declared
2. Reads the must-do source files to understand the full requirements (not just the agent's summary)
3. Checks: for the current work item, does evidence exist for each declared phase/step?
4. If evidence is missing: reports which phases have no evidence
5. If evidence exists: reads it and judges whether it's substantive (not filler written to pass a gate)
6. Writes a verdict to `.claude/state/evidence-verdict.json`

### Checkpoint Trigger

**When**: Every N writes after the must-do summary exists (configurable, default: 15 writes).

**Why write-count, not time**: Hooks are event-driven. They fire on tool use, not on wall clock. Write count directly measures "how much unsupervised work has happened."

**Reset**: The counter resets after each successful checkpoint. Failed checkpoints do not reset — the agent must fix the issue and re-verify.

**Step change**: When the watcher step changes (agent moves to next to-do item), the counter resets to 0 and a checkpoint fires immediately. This catches the "jump to next item without finishing current item" pattern.

### State Files

| File | Written By | Purpose |
|------|-----------|---------|
| `.claude/state/evidence-checkpoint.json` | Harness (bash) | Checkpoint is active. Contains: must-do summary text, must-do source file contents, modified files list, trigger reason |
| `.claude/state/evidence-verdict.json` | Sub-agent | Verdict: PASS/FAIL, per-phase findings, missing evidence list |
| `.claude/state/checkpoint-counter.json` | Harness (bash) | Writes since last checkpoint, last step seen |

### Checkpoint Brief Format

Written by the harness to `evidence-checkpoint.json`:

```json
{
  "status": "pending",
  "triggered_at": "ISO timestamp",
  "trigger_reason": "write_count | step_change",
  "writes_since_last": 15,
  "must_do_summary": "(full text of .claude/state/must-do-summary.md)",
  "must_do_source_files": [
    {
      "path": "docs/must do/experimentation-process.md",
      "content": "(full text, truncated to 3000 chars per file)"
    }
  ],
  "modified_files_since_last": ["src/foo.js", "src/bar.js"],
  "evidence_dir": ".claude/evidence/",
  "instruction": "You are an evidence checkpoint verifier. The must-do source files above define the process this agent declared it would follow. Check whether the agent's work so far has evidence for each phase/step of the declared process. Write your verdict to .claude/state/evidence-verdict.json"
}
```

### Verdict Format

Written by the sub-agent to `evidence-verdict.json`:

```json
{
  "verdict": "PASS | FAIL",
  "checked_at": "ISO timestamp",
  "phases_found": ["DEFINE", "SURVEY"],
  "phases_missing": ["BUILD", "RUN", "EVALUATE"],
  "findings": [
    {
      "phase": "DEFINE",
      "evidence_file": ".claude/evidence/style-1/define.md",
      "quality": "substantive"
    },
    {
      "phase": "BUILD",
      "evidence_file": null,
      "note": "No evidence found. Looked in .claude/evidence/, checked modified files list. If this work exists elsewhere, provide the file path in your next verification attempt."
    }
  ],
  "summary": "2 of 7 declared phases have evidence. 5 are missing.",
  "agent_provided_paths": []
}
```

### Iterative Verification Loop

The verdict is not a dead end — it's a conversation between the block/unblock cycle.

**First verification**: Verifier checks obvious locations (`.claude/evidence/`, modified files). If evidence is missing, the FAIL verdict names each missing phase and says: "If this evidence exists elsewhere, include the file paths when you spawn the next verifier."

**Agent response to FAIL**: Two options:
1. **Evidence doesn't exist** → agent must do the actual work, produce the evidence, then re-verify
2. **Evidence exists but verifier missed it** → agent spawns a new verifier with specific file paths: "Check `src/experiments/hypothesis-v2.md` for the HYPOTHESIZE phase"

**Next verification**: Verifier receives `agent_provided_paths` in the checkpoint brief (harness reads them from the agent's verifier prompt or from a paths file). Verifier reads those specific files and judges whether they constitute real evidence for the declared phase. If they're garbage or filler, FAIL again with specifics.

**Key property**: The agent can't fake evidence. It can point to a file, but the verifier will READ it against the must-do source requirements. And it can't skip phases — each missing phase is named in the FAIL verdict and must be addressed individually.

The verifier gets smarter each cycle because it accumulates knowledge of where the agent's work actually lives. The harness doesn't need to know the project's file structure — the iterative loop surfaces it naturally.

### Integration Points (Minimal, Additive)

#### on-prompt-submit.sh — add injection block

- **When**: `evidence-checkpoint.json` exists with `"status": "pending"`
- **What**: Inject a message into the prompt context:
  - "EVIDENCE CHECKPOINT ACTIVE — writes blocked. Spawn a verifier sub-agent. The harness has injected the checkpoint brief at `.claude/state/evidence-checkpoint.json`. Do NOT tell the verifier what to check — the brief is already in its environment."
- **Size**: Keep injection short (~200 chars). The full brief is in the file. Sub-agent reads the file; injection just alerts.
- **Position**: After must-do injection, before strategy loop breaker.

#### pre-write-gate.sh — add checkpoint block

- **When**: `evidence-checkpoint.json` exists with `"status": "pending"` AND no valid verdict exists
- **Exempt**: `.claude/state/` (verdict must be writable), `.claude/evidence/` (evidence must be writable), plus all existing exemptions
- **Block message**: "EVIDENCE CHECKPOINT — writes blocked. Spawn a verifier sub-agent to check your work against the must-do process."
- **Clear condition**: `evidence-verdict.json` exists with `"verdict": "PASS"` — delete checkpoint file, reset counter.
- **On FAIL verdict**: Keep checkpoint active. Inject failure summary. Agent must address issues, delete the verdict file, then re-verify.
- **Position**: After must-do summary gate, before watcher/cron gate.

#### pre-bash-gate.sh — mirror checkpoint block

- Same evidence checkpoint block logic as pre-write-gate.sh for file-writing Bash commands.

#### post-write-check.sh — checkpoint counter

- After each write, increment counter in `checkpoint-counter.json`.
- If counter >= threshold AND must-do summary exists AND no active checkpoint: trigger checkpoint (write `evidence-checkpoint.json`).
- On watcher step change: reset counter and trigger immediately.

### Gate Order (complete picture)

```
Agent tries Write/Edit
  |
  v
pre-write-gate.sh
  |- Phase gate (BUILD only)
  |- Contract gate (sprint contract exists)
  |- Strategy loop block
  |- Must-do summary gate
  |- Evidence checkpoint block    <-- NEW
  |- Watcher/cron gate
  |
  v
pre-flight-gate.sh
  |- Phase feedback block
  |- Step completion verification
  |- MCQ challenge
```

Projects without a must-do folder are completely unaffected — the checkpoint only activates when a must-do summary exists.

### What This Catches (mapped to PCW failure)

| PCW Failure | How This Catches It |
|-------------|-------------------|
| Did all 6 styles at once | Step-change checkpoint fires when moving to style 2. Verifier checks: did style 1 complete all 7 phases? |
| Skipped experimentation phases | Periodic checkpoint (every 15 writes) asks verifier to check phase evidence |
| Evaluator didn't have templates | Verifier gets must-do SOURCE FILES (not just summary) injected by harness |
| Agent controlled verifier's context | Harness injects the brief via on-prompt-submit. Agent doesn't construct the verifier's context. |

### What This Does NOT Do

- Parse phase names from the must-do summary (that's LLM judgment)
- Require a specific evidence file format (agent decides how to organize)
- Replace the must-do gate (still required at entry)
- Replace the pre-flight MCQ (still fires on writes)
- Replace the EVALUATE phase (still required at sprint end)
- Modify CLAUDE.md in any project
- Affect projects without a must-do folder

### Known Limitations

1. **Agent can write fake verdict**: The verdict file is in `.claude/state/` which must be writable. The agent could write `{"verdict":"PASS"}` itself. Mitigation: the injection tells the agent NOT to write it — this is soft enforcement, but faking a JSON verdict is a deliberate act of sabotage, not a lazy shortcut. The friction is high enough to prevent the failure mode we're solving (optimization for throughput).

2. **Agent can tell verifier to ignore the brief**: The harness injection appears in the verifier's context via on-prompt-submit regardless. The verifier would have to actively ignore what appears to be system-level context. Unlikely for the same reason — this is deliberate sabotage, not laziness.

3. **Must-do source files may be large**: Truncate each to 3000 chars in the checkpoint brief. The sub-agent can Read the full files if needed.

### Configurability

- **Checkpoint interval**: Default 15 writes. Per-project override via `.claude/state/checkpoint-config.json`: `{"interval": 15}`
- **Disable**: Set interval to 0.
- **Force checkpoint**: Write `evidence-checkpoint.json` manually.
