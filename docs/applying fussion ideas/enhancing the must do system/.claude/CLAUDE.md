# Enhanced Agent Harness — Autonomous Development Protocol

## BEFORE ANYTHING ELSE
1. Read `.claude/state/current-phase.json` to know where you are
2. Read `.claude/state/progress-notes.md` to know what's been done
3. If `.claude/state/injected-context.md` exists, read it — these are known fixes relevant to your work
4. You are resuming from the phase indicated. Do NOT restart from scratch.

## STATE MACHINE (follow in order, never skip)

Your current phase is in `.claude/state/current-phase.json`. Follow the phase you're in:

### PHASE: PLAN
- Read the user's request/brief
- Analyze the codebase structure
- Write a HIGH-LEVEL product spec to `.claude/specs/product-spec.md` (WHAT to build, not HOW)
- Write evaluation criteria to `.claude/specs/evaluation-criteria.md`
- Stay under ~100 lines — no implementation details (prevents cascading errors)
- When done: write `.claude/state/phase-complete-marker.md` explaining what you completed
- The harness validates your output. If validation fails, you'll see feedback in `.claude/state/phase-feedback.md`

### PHASE: NEGOTIATE
- Read the product spec from `.claude/specs/product-spec.md`
- Propose a sprint contract: what you will build and how success will be verified
- Write proposal to `.claude/contracts/sprint-N-proposal.md`
- Then INDEPENDENTLY review your own proposal as if you were a sceptical evaluator
- If the proposal is solid, write the contract to `.claude/contracts/sprint-N-contract.md`
- If not, revise. Max 3 attempts before escalating to user.

### PHASE: BUILD
- Read the sprint contract from `.claude/contracts/sprint-N-contract.md`
- Write tests FIRST (TDD Red phase) — tests MUST FAIL before implementation
- Implement ONE feature at a time to make tests pass (TDD Green phase)
- Run ALL tests after each feature (not just new ones)
- Update `.claude/state/progress-notes.md` as you work
- Update `features.json` and `tests.json` with status
- When sprint is complete: write `.claude/state/phase-complete-marker.md`
- If STUCK: see Escalation Protocol below

### PHASE: EVALUATE
- Spawn an independent sub-agent to verify your work (use the Agent tool)
- The verifier should NOT read your progress notes — it tests the live output
- The verifier checks every criterion in the sprint contract
- The verifier writes findings to `.claude/state/evaluation-results/sprint-N-evaluation.md`
- If ANY criterion fails: return to BUILD with specific feedback
- If ALL pass: advance to next sprint or COMPLETE
- Write `verification.result.json` with structured evidence

### PHASE: COMPLETE
- All sprints passed evaluation
- Write final handoff to `.claude/state/handoff-artifact.md`
- Commit with descriptive message
- Report completion to user

## ESCALATION PROTOCOL (when STUCK)

If you cannot make progress, DO NOT spin in circles. STOP and escalate.

**Triggers (any ONE is sufficient):**
- Same error 3 times in a row
- No progress for 5+ minutes
- Environment error you can't fix
- Don't know what to do next

**How to escalate:**
1. Write to `claude-progress.txt`:
   ```
   ## STATUS: STUCK
   Timestamp: [now]
   Last 3 actions: [what you tried]
   Raw errors: [exact error text, NO theories]
   ```
2. STOP working and tell the user you are stuck with the facts

## TDD PROTOCOL (mandatory for all development)
- Write tests FIRST — before any implementation
- Tests MUST FAIL before implementation begins
- ONE feature at a time
- Run ALL tests after completing each feature
- NEVER remove tests — only add
- Mark feature "passing" ONLY after ALL tests green

## BUILDER/VERIFIER SEPARATION
- You (the builder) can ONLY move to IMPLEMENTED
- You CANNOT declare your own work as VERIFIED or ACCEPTED
- When you reach EVALUATE, spawn an independent sub-agent verifier
- The verifier does NOT read your notes — it tests from scratch
- The verifier's default should be to FAIL if in doubt

## RULES (never violate)
- NEVER skip a phase
- NEVER proceed past validation without the harness confirming (write phase-complete-marker.md)
- ALWAYS update `.claude/state/progress-notes.md` as you work
- ALWAYS run tests after code changes
- If you lose track: read `.claude/state/current-phase.json`
- If context gets long: read `.claude/state/progress-notes.md` to remember
- If a known fix exists in `.claude/state/injected-context.md`: apply it EXACTLY, don't improvise
- NEVER self-certify your own work as complete — the evaluator decides
