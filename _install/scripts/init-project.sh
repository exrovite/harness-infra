#!/bin/bash
# init-project.sh — One-command project setup
# Creates .claude/ structure with minimal CLAUDE.md, state dirs, known-fixes template,
# features.json, tests.json. Creates .gitattributes and .editorconfig for CRLF enforcement.
# For .agent-memory/ projects, COPIES (not symlinks) operating-procedure.md.
#
# Usage: bash init-project.sh [--with-memory /path/to/agent-memory]
# Exit: 0 = success

AGENT_MEMORY_SOURCE=""
if [ "$1" = "--with-memory" ] && [ -n "$2" ]; then
  AGENT_MEMORY_SOURCE="$2"
fi

# --- GUARD: never create a NESTED project root inside an existing project ---
# Walk up from the PARENT of cwd; if any ancestor already has .claude, this directory is inside an
# existing project — refuse, so the harness is not fragmented into nested roots (which split the
# kill-switch/state and were the cause of `.claude` dirs appearing all over a project). The global
# ~/.claude is the harness INSTALL, not a project root, so we stop the walk at $HOME.
_np_cwd="$(pwd -W 2>/dev/null || pwd)"
_np_home="$(cd "${HOME:-/nonexistent}" 2>/dev/null && pwd -W 2>/dev/null || printf '%s' "${HOME:-}")"
_np_p="$(dirname "$_np_cwd")"
while [ -n "$_np_p" ] && [ "$_np_p" != "/" ] && [ "$_np_p" != "." ]; do
  [ -n "$_np_home" ] && [ "$_np_p" = "$_np_home" ] && break
  if [ -d "$_np_p/.claude" ]; then
    printf 'init-project: refusing to create a nested .claude — existing project root at %s\n' "$_np_p" >&2
    exit 0
  fi
  case "$_np_p" in */*) _np_p="${_np_p%/*}" ;; *) break ;; esac
done

# Create directory structure
mkdir -p .claude/state/evaluation-results
mkdir -p .claude/specs
mkdir -p .claude/contracts
mkdir -p .claude/protocols
mkdir -p evidence

printf "init-project: Created directory structure.\n" >&2

# Create CLAUDE.md with full harness protocol if it doesn't exist
if [ ! -f ".claude/CLAUDE.md" ]; then
  cat > ".claude/CLAUDE.md" << 'CLAUDEMD'
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
CLAUDEMD
  printf "init-project: Created CLAUDE.md with full harness protocol\n" >&2
fi

# Create empty known-fixes registry
if [ ! -f ".claude/protocols/known-fixes.md" ]; then
  {
    printf "%s\n" "# Known Fixes Registry"
    printf "%s\n\n" "# Add fixes as they are discovered using the template format below."
    printf "%s\n" "# ## FIX-NNN: [Short description]"
    printf "%s\n" "# - **Symptom**: [Exact error text or pattern]"
    printf "%s\n" "# - **Root cause**: [Why this happens]"
    printf "%s\n" "# - **Fix**: [What to do]"
    printf "%s\n" "# - **File**: [Which file(s)]"
    printf "%s\n" "# - **Verified**: [Date]"
    printf "%s\n" "#"
    printf "%s\n" "# ## Verify"
    printf "%s\n" "# - type: file_exists"
    printf "%s\n" "#   file: [path]"
    printf "%s\n" "#"
    printf "%s\n" "# - type: file_contains"
    printf "%s\n" "#   file: [path]"
    printf "%s\n" "#   pattern: [regex]"
    printf "%s\n" "#   before_pattern: [optional ordering check]"
    printf "%s\n" "#"
    printf "%s\n" "# - type: test_passes"
    printf "%s\n" "#   command: [pytest|npm test|cargo test|python -m unittest]"
  } > ".claude/protocols/known-fixes.md"
  printf "init-project: Created known-fixes.md template\n" >&2
fi

# Create features.json
if [ ! -f "features.json" ]; then
  printf '{"project": "unnamed", "features": [], "total": 0, "passing": 0, "failing": 0, "in_progress": 0, "not_started": 0}\n' > "features.json"
  printf "init-project: Created features.json\n" >&2
fi

# Create tests.json
if [ ! -f "tests.json" ]; then
  printf '{"tests": [], "total": 0, "passing": 0, "failing": 0, "not_started": 0}\n' > "tests.json"
  printf "init-project: Created tests.json\n" >&2
fi

# Create claude-progress.txt
if [ ! -f "claude-progress.txt" ]; then
  printf "# Progress Log\n# Created: %s\n\n" "$(date -Iseconds)" > "claude-progress.txt"
  printf "init-project: Created claude-progress.txt\n" >&2
fi

# Initialize state
printf '{"phase": "PLAN", "sprint": 0, "iteration": 0}\n' > ".claude/state/current-phase.json"

# Create .gitattributes for CRLF enforcement
if [ ! -f ".gitattributes" ]; then
  printf "* text=auto eol=lf\n" > ".gitattributes"
  printf "init-project: Created .gitattributes (eol=lf)\n" >&2
fi

# Create .editorconfig for CRLF enforcement
if [ ! -f ".editorconfig" ]; then
  {
    printf "root = true\n\n"
    printf "[*]\n"
    printf "end_of_line = lf\n"
    printf "charset = utf-8\n"
    printf "insert_final_newline = true\n"
    printf "trim_trailing_whitespace = true\n"
  } > ".editorconfig"
  printf "init-project: Created .editorconfig (eol=lf)\n" >&2
fi

# Copy operating-procedure.md for .agent-memory projects
if [ -n "$AGENT_MEMORY_SOURCE" ] && [ -d "$AGENT_MEMORY_SOURCE" ]; then
  mkdir -p .agent-memory/core 2>/dev/null
  if [ -f "$AGENT_MEMORY_SOURCE/core/operating-procedure.md" ]; then
    cp "$AGENT_MEMORY_SOURCE/core/operating-procedure.md" ".agent-memory/core/operating-procedure.md"
    printf "init-project: Copied operating-procedure.md from %s\n" "$AGENT_MEMORY_SOURCE" >&2
  fi
fi

printf "init-project: Project initialized for harness. Run 'bash \$HOME/.claude/scripts/run-harness.sh' to start.\n" >&2
exit 0
