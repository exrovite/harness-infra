# Sprint 20 Contract: Turn Packet System

## Scope

Evolve `on-prompt-submit.sh` from a single-line status reporter into a structured turn packet assembler. Before the agent acts, it sees the ordered setup actions, read-first artifacts, hard blockers, exempt paths, current watcher step, and done criteria needed to operate inside the correct harness frame. Gates remain untouched as safety nets.

## Deliverables

### D1: on-prompt-submit.sh — Turn Packet Assembler

Replace the current flat `CONTEXT_MSG` with a structured packet built from local state files.

**Section 1: State summary** (always present)
- Phase, sprint, iteration, write count, watcher status.
- Format: `[HARNESS] Phase: X | Sprint: N | Iter: N | Writes: N | Watcher: status`.

**Section 2: Read first** (when relevant artifacts exist or required reading is incomplete)
- Existing sprint contract: `Read first: .claude/contracts/sprint-{N}-contract.md`.
- Must-do index/source docs when a must-do folder exists and summary is missing.
- This is first-class cockpit guidance, not merely a gate workaround.

**Section 3: Action queue** (only when soft setup conditions are unmet)
- Numbered list in dependency order, each item naming the tool and target path.
- Conditions checked in order:
  1. Watcher not claimed for project → `Claim watcher: Bash — jq-update ~/.openclaw/watchers/REGISTRY.json and write slot-N.md`.
  2. Cron not registered → `Start reminder: CronCreate — */3 * * * * read your watcher slot`.
  3. Sprint contract missing in NEGOTIATE or BUILD → `Write contract: Write — .claude/contracts/sprint-{N}-contract.md`.
  4. Must-do summary missing when must-do dir exists → `Write must-do summary: Write — .claude/state/must-do-summary.md after reading must-do docs`.
  5. Pre-flight MCQ approaching → `Note: MCQ gate fires on next gated write`.
- Only unmet conditions appear. When clear, this section is absent.
- Phase compliance is not a soft action; it appears as mode/block guidance.

**Section 4: Blocked-by** (only when hard blocks are active)
- Phase lock → `WRITES LOCKED: Phase is {PHASE} — write specs/contracts/state, not source code`.
- Phase-feedback FAIL → read `.claude/state/phase-feedback.md`, fix issues, write `.claude/state/phase-complete-marker.md`.
- Evidence checkpoint pending preserves all 3 existing sub-states:
  - No verdict yet → spawn verifier using `.claude/state/evidence-checkpoint.json`.
  - FAIL without remediation → write `.claude/state/evidence-remediation.md` (200+ chars).
  - FAIL with remediation → produce `.claude/evidence/`, delete verdict, spawn new verifier.
- Strategy loop tier 2 → write `.claude/state/strategy-ack.md` with `## New Approach`, 150+ chars, must-do reference.
- Strategy loop tier 1 is a warning/nudge, not `BLOCKED BY`.

**Section 5: Exempt paths** (only when tools are locked)
- `Always writable: .claude/state/, .claude/contracts/, .claude/specs/, .openclaw/watchers/, .agent-memory/, .claude/pre-flight/, .claude/evidence/, agentwiki/`.

**Section 6: Watcher cockpit** (whenever watcher active for this project)
- Current unchecked watcher step.
- SCOPE text, truncated.
- MISTAKES TO AVOID text, truncated.
- DONE WHEN / COMPLETION CRITERIA text, truncated.
- This resolves the earlier ambiguity: watcher context is shown even when there are no blocks, because the turn-kernel vision requires current step and what done looks like. Budget target for this steady-state cockpit is under 600 chars, not the old Section-1-only rule.

**Existing features preserved and integrated**
- Must-do summary injection remains appended as `[MUST-DO ACTIVE]` when summary exists.
- Evidence checkpoint injection is represented in Section 4 with the existing sub-state messages.
- Strategy loop nudge/block logic and existing state writes remain preserved.
- Must-do injection log remains preserved.

**Read-only constraint note:** New packet condition checks/assembly are read-only and exit 0. Existing strategy-loop state updates and must-do injection logging are preserved pre-existing writes, not new enforcement.

### D2: lib-helpers.sh — Shared Condition Functions

New functions only; no existing functions modified or removed:
- `find_must_do_dir()` — returns first must-do directory or empty string.
- `check_watcher_for_project()` — returns active watcher slot for a project path or empty string.
- `read_watcher_step_scope()` — extracts current step, SCOPE, MISTAKES TO AVOID, and COMPLETION CRITERIA/DONE WHEN as delimited stdout.

## NOT In Scope

- Changing gate scripts (`pre-write-gate.sh`, `pre-bash-gate.sh`, `pre-flight-gate.sh`).
- Refactoring gates to call shared functions.
- Adding or removing gates.
- Changing any gate exit code or blocking behavior.
- Multi-model deployment.

## Acceptance Criteria (25 items)

### Packet Structure (10)
1. State summary is always present.
2. Read-first artifacts appear when a sprint contract exists and/or must-do reading is required.
3. Action queue appears only when soft setup conditions are unmet.
4. Action queue items are numbered in dependency order: watcher > cron > contract > must-do > MCQ.
5. Each action queue item names the tool and target path.
6. Hard blocks appear as `BLOCKED BY:` with specific resolution path.
7. Exempt paths are listed when tools are locked.
8. Watcher cockpit appears whenever watcher is active for this project.
9. Watcher cockpit includes current step and done/completion criteria when present.
10. Full packet stays under 1500 chars with all sections active.

### Gate Coverage (9)
11. Watcher-not-claimed condition detected and queued.
12. Cron-not-registered condition detected and queued.
13. Phase compliance: non-BUILD phases show writes-locked/mode guidance, not a soft action.
14. Sprint contract absence detected in NEGOTIATE and BUILD, and queued.
15. Phase-feedback FAIL detected as hard block.
16. Must-do summary absence detected only when must-do dir exists.
17. Evidence checkpoint pending detected with all 3 sub-states preserved.
18. Strategy loop tier 1 appears as warning; tier 2 appears as `BLOCKED BY`.
19. MCQ-due detection reads `.claude/pre-flight/gate-counter.json` without writing.

### Safety (4)
20. New packet assembly logic is read-only; only preserved existing features write state.
21. Existing on-prompt-submit features preserved: must-do injection/log, evidence checkpoint guidance, strategy loop nudge/block with state updates.
22. Gate scripts have zero diff: `pre-write-gate.sh`, `pre-bash-gate.sh`, `pre-flight-gate.sh` untouched.
23. `lib-helpers.sh` only adds new helper functions; existing functions unchanged.

### Quality (2)
24. Steady-state watcher cockpit stays under 600 chars when no hard blocks/actions are active.
25. Packet assembler adds no meaningful prompt latency: no network calls, no repo-wide expensive loops.

## Verification

Independent verifier must:
1. Validate this contract against `big -harness-fix.md`, including read-first and done-criteria requirements.
2. Syntax-check changed shell files with `bash -n`.
3. Simulate unblocked, fresh/locked, NEGOTIATE missing-contract, BUILD missing-contract, must-do missing-summary, phase feedback FAIL, evidence sub-states, strategy nudge/block, and MCQ-due scenarios.
4. Measure steady-state watcher packet under 600 chars and worst-case packet under 1500 chars.
5. Verify action queue ordering.
6. Diff gate scripts against pre-sprint backups; must be zero diff.
7. Verify `lib-helpers.sh` existing functions unchanged and helper additions only.

## Implementation Constraints

- `sed 's|\\|/|g'` can crash on MSYS — prefer `tr '\\' '/'` for path normalization.
- Strip Windows jq CR with `tr -d '\r'`.
- `while IFS= read -r` loops need `|| [ -n "$var" ]`.
- `grep -E` does not support `\d`; use `[0-9]`.
- Avoid here-strings in hook subprocesses; use pipes/temp files.
- Hook runs on every prompt; keep operations local and bounded.
- Watcher project matching uses `pwd -W` fallback to `pwd`, lowercase, forward slashes.
- Use POSIX classes like `[^[:space:]]`, not `[^\s]`.