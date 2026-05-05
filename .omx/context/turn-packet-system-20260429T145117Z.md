# Context Snapshot: Sprint 20 Turn Packet System

Timestamp UTC: 20260429T145117Z

## Task statement
Continue the interrupted Sprint 20 harness work under Ralph: validate the sprint-20 contract against ig -harness-fix.md, transition from NEGOTIATE to BUILD only with evidence, implement the Turn Packet System, verify it, and obtain independent/architect sign-off.

## Desired outcome
on-prompt-submit.sh should assemble a concise structured turn packet before each agent turn so agents know required setup/actions/blocks/exempt paths/current step before attempting writes. Existing gates remain safety nets and are not modified.

## Known facts / evidence
- Vision source: ig -harness-fix.md says the harness should stop being a courtroom of after-the-fact gates and become a turn kernel that prepares full context before action.
- Existing sprint artifacts: .claude/contracts/sprint-20-proposal.md, .claude/contracts/sprint-20-contract.md, .claude/state/progress-notes.md.
- Current phase file still says NEGOTIATE sprint 20.
- Watcher slot 4 is active for G:/harness infra and still marks Step 2 NEGOTIATE unchecked.
- Implementation touchpoints are global harness files under C:\Users\exrov\.claude\hooks and C:\Users\exrov\.claude\scripts.

## Constraints
- Do not modify gate scripts: pre-write-gate.sh, pre-bash-gate.sh, pre-flight-gate.sh.
- Preserve existing on-prompt-submit features: must-do injection/log, evidence checkpoint guidance, strategy loop nudge/block behavior and existing state writes.
- New packet assembly logic should read state only; existing preserved features may continue writing.
- Output budgets: unblocked packet <200 chars; fully blocked packet <1500 chars.
- Windows/MSYS constraints from contract: prefer 	r '\\' '/' over problematic sed replacement, strip CR from jq, avoid grep \d, avoid here-strings in hook subprocesses.

## Unknowns / open questions
- No persisted independent validation artifact from the interrupted prior agent was found; validation must be recreated and saved.
- Need discover exact existing hook behavior before patching.
- Need identify a robust test harness for shell hook on Windows/Git Bash.

## Likely codebase touchpoints
- C:\Users\exrov\.claude\hooks\on-prompt-submit.sh
- C:\Users\exrov\.claude\scripts\lib-helpers.sh
- .claude/state/current-phase.json, .claude/state/progress-notes.md, watcher slot 4 metadata
- .omx/plans/prd-turn-packet-system.md, .omx/plans/test-spec-turn-packet-system.md for Ralph planning gate

## Vision excerpt summary
The packet should tell the agent what to do before code writes, what paths are exempt, what files to read first, current step/done criteria, and what is blocked versus available. Gates stay as guardrails but should rarely fire.
