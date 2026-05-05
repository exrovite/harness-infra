# Sprint 10 Contract — Fix COMPLETE→Sprint Transition Deadlock

## Problem
When an agent transitions from COMPLETE to a new sprint, three gates form a circular dependency:
1. `pre-flight-gate.sh` phase-feedback FAIL block doesn't exempt `.claude/contracts/` — blocks contract writing
2. `pre-write-gate.sh` contract gate blocks Agent tool — prevents spawning verifiers
3. `pre-bash-gate.sh` phase-feedback FAIL block doesn't exempt contract paths — blocks Bash workaround

## Deliverables
1. **pre-flight-gate.sh**: Expand phase-feedback FAIL exemptions to include `.claude/contracts/`, `.claude/specs/`, `.agent-memory/`, `agentwiki/`, `.claude/pre-flight/`
2. **pre-write-gate.sh**: Exempt Agent tool from contract gate (spawned agents get their own Write/Edit gating)
3. **pre-bash-gate.sh**: Add `.claude/contracts/` to bootstrap path exemptions

## Verification Criteria
- [ ] Agent can write sprint contracts when stale phase-feedback.md exists
- [ ] Agent can spawn sub-agents without a contract (for verification)
- [ ] No circular dependency on COMPLETE→BUILD transition
- [ ] Existing enforcement still blocks actual source code writes in non-BUILD phases
- [ ] Existing enforcement still blocks source code writes when phase-feedback FAIL is active

## Scope
- 3 files modified: pre-flight-gate.sh, pre-write-gate.sh, pre-bash-gate.sh
- No new files
- No behavioral change for source code gating — only infrastructure paths unblocked
