#!/bin/bash
# run-harness.sh — Outer loop driving the state machine
# Orchestrates: PLAN → NEGOTIATE → BUILD → EVALUATE → COMPLETE
# Manages iteration count, checks for blocked state, constructs prompts from files.
# Calls all Layer 1 scripts, Layer 2 guards, and invokes Claude sessions per phase.
#
# Usage: bash run-harness.sh
# Exit: 0 = complete, 1 = error or budget limit

set -euo pipefail

STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
SCRIPTS="$HOME/.claude/scripts"
HOOKS="$HOME/.claude/hooks"
AGENTS="$HOME/.claude/agents"
LOCKDIR="${STATE_DIR}/harness.lockdir"
MAX_ITERATIONS="${MAX_ITERATIONS:-30}"
ITERATION=0

# ─── STARTUP ───────────────────────────────────────────────
# 0. Explicit launch = explicit opt-in: bootstrap this folder as a project if it isn't one yet.
#    (startup-recovery.sh no longer auto-creates a .claude in a non-project folder, so the explicit
#    launcher must do it here. init-project.sh still refuses to nest inside an existing project root.)
[ -n "${HARNESS_STATE_DIR:-}" ] || [ -d ".claude" ] || bash "$SCRIPTS/init-project.sh" 2>/dev/null || true
# 1. Crash recovery (always first)
bash "$SCRIPTS/startup-recovery.sh" 2>/dev/null

# 2. Concurrency protection (mkdir atomic lock)
if mkdir "$LOCKDIR" 2>/dev/null; then
  printf "%s" "$$" > "$LOCKDIR/pid"
  trap 'rm -rf "$LOCKDIR" 2>/dev/null; kill "$POLL_PID" 2>/dev/null' EXIT
else
  EXISTING_PID=$(cat "$LOCKDIR/pid" 2>/dev/null)
  if [ -n "$EXISTING_PID" ] && kill -0 "$EXISTING_PID" 2>/dev/null; then
    printf "run-harness: Already running (PID %s).\n" "$EXISTING_PID" >&2
    exit 1
  else
    printf "run-harness: Stale lock. Cleaning and proceeding.\n" >&2
    rm -rf "$LOCKDIR" 2>/dev/null
    mkdir "$LOCKDIR" 2>/dev/null
    printf "%s" "$$" > "$LOCKDIR/pid"
    trap 'rm -rf "$LOCKDIR" 2>/dev/null; kill "$POLL_PID" 2>/dev/null' EXIT
  fi
fi

# 3. Start Telegram polling daemon (optional, background)
POLL_PID=""
bash "$SCRIPTS/telegram-poll.sh" &
POLL_PID=$!

# 4. Record session start time
printf "%s" "$(date +%s)" > "${STATE_DIR}/session-start-time.txt"

# ─── MAIN LOOP ─────────────────────────────────────────────
while [ "$ITERATION" -lt "$MAX_ITERATIONS" ]; do

  # Budget check
  bash "$SCRIPTS/check-budget.sh" || exit 0

  # Telegram daemon heartbeat check
  HEARTBEAT=$(cat "${STATE_DIR}/telegram-poll-heartbeat" 2>/dev/null || printf "0")
  NOW=$(date +%s)
  if [ -n "$POLL_PID" ] && [ "$HEARTBEAT" != "0" ] && [ $(( NOW - HEARTBEAT )) -gt 120 ]; then
    printf "run-harness: Telegram daemon appears dead. Restarting.\n" >&2
    kill "$POLL_PID" 2>/dev/null
    bash "$SCRIPTS/telegram-poll.sh" &
    POLL_PID=$!
  fi

  # Check for blocked state
  if [ -f "${STATE_DIR}/agent-blocked.md" ]; then
    printf "run-harness: Agent blocked. Waiting for human input.\n" >&2
    bash "$SCRIPTS/wait-for-human.sh" 30
    if [ $? -ne 0 ]; then
      exit 0  # Timed out, state saved
    fi
    # Human response becomes next instruction
    if [ -f "${STATE_DIR}/human-response.md" ]; then
      HUMAN_INPUT=$(cat "${STATE_DIR}/human-response.md")
      rm -f "${STATE_DIR}/human-response.md"
      rm -f "${STATE_DIR}/agent-blocked.md"
    fi
  fi

  # Read current state
  PHASE=$(jq -r '.phase // "PLAN"' "${STATE_DIR}/current-phase.json" 2>/dev/null)
  SPRINT=$(jq -r '.sprint // 0' "${STATE_DIR}/current-phase.json" 2>/dev/null)

  case "$PHASE" in

    # ─── PLAN ──────────────────────────────────────────────
    "PLAN")
      bash "$HOOKS/pre-phase-start.sh" 1 2>/dev/null
      HANDOFF=$(cat "${STATE_DIR}/handoff-artifact.md" 2>/dev/null || printf "")

      # Write prompt to file (avoid shell arg limits)
      {
        printf "You are the PLANNER agent. Read %s/planner.md for your role.\n" "$AGENTS"
        [ -n "$HANDOFF" ] && printf "\nPrevious context:\n%s\n" "$HANDOFF"
        printf "\nExpand the user brief into a product spec. Stay high-level.\n"
        printf "Write to .claude/specs/product-spec.md and .claude/specs/evaluation-criteria.md\n"
        printf "When done, write .claude/state/phase-complete-marker.md\n"
      } > "${STATE_DIR}/current-prompt.md"

      bash "$SCRIPTS/run-claude-safe.sh" "${STATE_DIR}/current-prompt.md" "plan"
      BUILD_EXIT=$?

      if [ $BUILD_EXIT -ne 0 ]; then
        continue
      fi

      # Check if phase completed
      if [ -f "${STATE_DIR}/phase-complete-marker.md" ]; then
        bash "$SCRIPTS/validate-phase.sh" 2 2>/dev/null
        if [ $? -eq 0 ]; then
          bash "$SCRIPTS/git-checkpoint.sh" "PLAN" "$SPRINT"
          printf '{"phase": "NEGOTIATE", "sprint": 1, "iteration": %s}\n' "$ITERATION" > "${STATE_DIR}/current-phase.json"
          rm -f "${STATE_DIR}/phase-complete-marker.md"
          bash "$SCRIPTS/notify.sh" "Plan complete. Moving to NEGOTIATE."
          # Log decision
          mkdir -p ".agent-memory/episodic/decisions" 2>/dev/null
          printf "# PLAN → NEGOTIATE\nTimestamp: %s\n" "$(date -Iseconds)" > ".agent-memory/episodic/decisions/PLAN-complete-$(date +%Y%m%d).md" 2>/dev/null
        fi
      fi
      ;;

    # ─── NEGOTIATE ─────────────────────────────────────────
    "NEGOTIATE")
      NEGOTIATE_ATTEMPTS=$(cat "${STATE_DIR}/negotiate-attempts.txt" 2>/dev/null || printf "0")

      if [ "$NEGOTIATE_ATTEMPTS" -ge 3 ]; then
        bash "$SCRIPTS/notify.sh" "Contract negotiation failed 3 times for sprint $SPRINT. Agent paused."
        bash "$SCRIPTS/wait-for-human.sh" 30
        if [ $? -ne 0 ]; then exit 0; fi

        HUMAN_REPLY=$(cat "${STATE_DIR}/human-response.md" 2>/dev/null)
        rm -f "${STATE_DIR}/human-response.md"

        if [ "$HUMAN_REPLY" = "skip" ]; then
          cp ".claude/contracts/sprint-${SPRINT}-proposal.md" ".claude/contracts/sprint-${SPRINT}-contract.md" 2>/dev/null
          printf '{"phase": "BUILD", "sprint": %s, "iteration": %s}\n' "$SPRINT" "$ITERATION" > "${STATE_DIR}/current-phase.json"
          printf "0" > "${STATE_DIR}/negotiate-attempts.txt"
        else
          printf "%s\n" "$HUMAN_REPLY" > "${STATE_DIR}/injected-context.md"
          printf "0" > "${STATE_DIR}/negotiate-attempts.txt"
        fi
        ITERATION=$(( ITERATION + 1 ))
        continue
      fi

      # Generator proposes contract
      {
        printf "You are the GENERATOR proposing sprint %s contract.\n" "$SPRINT"
        printf "Read %s/generator.md and .claude/specs/product-spec.md\n" "$AGENTS"
        printf "Propose what you will build and how success will be verified.\n"
        printf "Write proposal to .claude/contracts/sprint-%s-proposal.md\n" "$SPRINT"
      } > "${STATE_DIR}/current-prompt.md"

      bash "$SCRIPTS/run-claude-safe.sh" "${STATE_DIR}/current-prompt.md" "plan"

      # Evaluator reviews proposal (separate session)
      {
        printf "You are the EVALUATOR reviewing sprint %s proposal.\n" "$SPRINT"
        printf "Read %s/evaluator.md and .claude/specs/evaluation-criteria.md\n" "$AGENTS"
        printf "Read .claude/contracts/sprint-%s-proposal.md\n" "$SPRINT"
        printf "Either approve (write .claude/contracts/sprint-%s-contract.md)\n" "$SPRINT"
        printf "or reject with feedback (write .claude/contracts/sprint-%s-feedback.md)\n" "$SPRINT"
      } > "${STATE_DIR}/current-prompt.md"

      bash "$SCRIPTS/run-claude-safe.sh" "${STATE_DIR}/current-prompt.md" "plan"

      # Check result
      if [ -f ".claude/contracts/sprint-${SPRINT}-contract.md" ]; then
        printf '{"phase": "BUILD", "sprint": %s, "iteration": %s}\n' "$SPRINT" "$ITERATION" > "${STATE_DIR}/current-phase.json"
        printf "0" > "${STATE_DIR}/negotiate-attempts.txt"
        bash "$SCRIPTS/git-checkpoint.sh" "NEGOTIATE" "$SPRINT"
        bash "$SCRIPTS/notify.sh" "Sprint $SPRINT contract approved. Moving to BUILD."
      else
        printf "%s" "$(( NEGOTIATE_ATTEMPTS + 1 ))" > "${STATE_DIR}/negotiate-attempts.txt"
      fi
      ;;

    # ─── BUILD ─────────────────────────────────────────────
    "BUILD")
      bash "$HOOKS/pre-phase-start.sh" 3 2>/dev/null

      ACTIVE=$(cat "${STATE_DIR}/active-instructions.md" 2>/dev/null || printf "")
      INJECTED=$(cat "${STATE_DIR}/injected-context.md" 2>/dev/null || printf "")
      NEXT_FIX=$(cat "${STATE_DIR}/next-fix.md" 2>/dev/null || printf "")
      EVAL_FEEDBACK=""
      if [ -f ".claude/state/evaluation-results/sprint-${SPRINT}-FAIL.md" ]; then
        EVAL_FEEDBACK=$(cat ".claude/state/evaluation-results/sprint-${SPRINT}-FAIL.md" 2>/dev/null)
      fi

      {
        printf "You are the GENERATOR. Read %s/generator.md for your role.\n" "$AGENTS"
        printf "Sprint contract: .claude/contracts/sprint-%s-contract.md\n\n" "$SPRINT"
        [ -n "$ACTIVE" ] && printf "## Phase Instructions\n%s\n\n" "$ACTIVE"
        [ -n "$INJECTED" ] && printf "## Known Fixes To Be Aware Of\n%s\n\n" "$INJECTED"
        [ -n "$NEXT_FIX" ] && printf "## MANDATORY: Apply This Fix First\n%s\n\n" "$NEXT_FIX"
        [ -n "$EVAL_FEEDBACK" ] && printf "## Previous Evaluation Feedback — Address These Issues\n%s\n\n" "$EVAL_FEEDBACK"
        printf "Write progress to .claude/state/progress-notes.md as you work.\n"
        printf "When this sprint is complete, write .claude/state/phase-complete-marker.md\n"
      } > "${STATE_DIR}/current-prompt.md"

      bash "$SCRIPTS/run-claude-safe.sh" "${STATE_DIR}/current-prompt.md" "auto-accept"
      rm -f "${STATE_DIR}/next-fix.md" 2>/dev/null

      # Check if phase completed
      if [ -f "${STATE_DIR}/phase-complete-marker.md" ]; then
        bash "$SCRIPTS/validate-phase.sh" 3 2>/dev/null
        if [ $? -eq 0 ]; then
          bash "$SCRIPTS/git-checkpoint.sh" "BUILD" "$SPRINT"
          printf '{"phase": "EVALUATE", "sprint": %s, "iteration": %s}\n' "$SPRINT" "$ITERATION" > "${STATE_DIR}/current-phase.json"
          rm -f "${STATE_DIR}/phase-complete-marker.md"
        else
          rm -f "${STATE_DIR}/phase-complete-marker.md"
          # On test failure, try known-fix injection
          bash "$HOOKS/on-test-failure.sh" "${STATE_DIR}/test-output.txt" 2>/dev/null
        fi
      fi

      # Check for stuck condition
      bash "$HOOKS/on-stuck-detected.sh" 2>/dev/null
      ;;

    # ─── EVALUATE ──────────────────────────────────────────
    "EVALUATE")
      EVAL_ATTEMPTS=$(cat "${STATE_DIR}/eval-attempts-sprint-${SPRINT}.txt" 2>/dev/null || printf "0")

      if [ "$EVAL_ATTEMPTS" -ge 3 ]; then
        bash "$SCRIPTS/notify.sh" "Sprint $SPRINT failed evaluation 3 times. Agent paused."
        bash "$SCRIPTS/wait-for-human.sh" 30
        if [ $? -ne 0 ]; then exit 0; fi

        HUMAN_REPLY=$(cat "${STATE_DIR}/human-response.md" 2>/dev/null)
        rm -f "${STATE_DIR}/human-response.md"

        case "$HUMAN_REPLY" in
          "accept")
            # Ship current sprint as-is — move to COMPLETE if last sprint, else next sprint
            TOTAL_SPRINTS=$(cat "${STATE_DIR}/total-sprints.txt" 2>/dev/null || printf "5")
            if [ "$SPRINT" -ge "$TOTAL_SPRINTS" ]; then
              printf '{"phase": "COMPLETE", "sprint": %s, "iteration": %s}\n' "$SPRINT" "$ITERATION" > "${STATE_DIR}/current-phase.json"
            else
              NEXT_SPRINT=$(( SPRINT + 1 ))
              printf '{"phase": "NEGOTIATE", "sprint": %s, "iteration": %s}\n' "$NEXT_SPRINT" "$ITERATION" > "${STATE_DIR}/current-phase.json"
              printf "0" > "${STATE_DIR}/eval-attempts-sprint-${NEXT_SPRINT}.txt"
            fi
            ;;
          "skip")
            # Skip this sprint entirely — move to next sprint
            NEXT_SPRINT=$(( SPRINT + 1 ))
            printf '{"phase": "NEGOTIATE", "sprint": %s, "iteration": %s}\n' "$NEXT_SPRINT" "$ITERATION" > "${STATE_DIR}/current-phase.json"
            printf "0" > "${STATE_DIR}/eval-attempts-sprint-${NEXT_SPRINT}.txt"
            ;;
          *)
            printf "%s\n" "$HUMAN_REPLY" > "${STATE_DIR}/injected-context.md"
            printf "0" > "${STATE_DIR}/eval-attempts-sprint-${SPRINT}.txt"
            printf '{"phase": "BUILD", "sprint": %s, "iteration": %s}\n' "$SPRINT" "$ITERATION" > "${STATE_DIR}/current-phase.json"
            ;;
        esac
        ITERATION=$(( ITERATION + 1 ))
        continue
      fi

      # Step 1: Layer 2 protocol compliance (HARD GATE)
      bash "$SCRIPTS/evaluate-protocol-compliance.sh" "$SPRINT" 2>/dev/null
      if [ $? -ne 0 ]; then
        printf "run-harness: Protocol compliance failed. Returning to BUILD.\n" >&2
        printf '{"phase": "BUILD", "sprint": %s, "iteration": %s}\n' "$SPRINT" "$ITERATION" > "${STATE_DIR}/current-phase.json"
        ITERATION=$(( ITERATION + 1 ))
        continue
      fi

      # Step 2: Ensure dev server running (for web projects)
      bash "$SCRIPTS/ensure-dev-server.sh" 2>/dev/null
      if [ $? -ne 0 ]; then
        bash "$SCRIPTS/notify.sh" "Dev server failed to start. Cannot evaluate."
        printf "BLOCKED\nDev server won't start. Evaluator cannot proceed.\n" > "${STATE_DIR}/agent-blocked.md"
        bash "$SCRIPTS/wait-for-human.sh" 30
        [ $? -ne 0 ] && exit 0
        continue
      fi

      # Step 3: Calibration gate — plant deliberate failure before evaluator runs
      CALIBRATION_FILE=""
      CALIBRATION_BACKUP=""
      if [ -f ".claude/contracts/sprint-${SPRINT}-contract.md" ]; then
        # Temporarily rename the contract file (evaluator should notice it's missing)
        CALIBRATION_FILE=".claude/contracts/sprint-${SPRINT}-contract.md"
        CALIBRATION_BACKUP=".claude/contracts/sprint-${SPRINT}-contract.md.calibration-backup"
        cp "$CALIBRATION_FILE" "$CALIBRATION_BACKUP"
        mv "$CALIBRATION_FILE" "${CALIBRATION_FILE}.hidden-by-calibration"
      fi

      # Step 4: Evaluator agent (Layer 3, own clean session)
      {
        printf "You are the EVALUATOR. Read %s/evaluator.md for your role.\n" "$AGENTS"
        printf "Read .claude/specs/evaluation-criteria.md\n"
        printf "Read .claude/contracts/sprint-%s-contract.md\n\n" "$SPRINT"
        printf "Use Playwright MCP to interact with the running application (if web project).\n"
        printf "Test every criterion in the sprint contract.\n"
        printf "Grade: product depth, functionality, visual design, code quality, protocol compliance.\n\n"
        printf "Write detailed findings to .claude/state/evaluation-results/sprint-%s-evaluation.md\n\n" "$SPRINT"
        printf "Write evidence to evidence/ directory BEFORE issuing verdict.\n"
        printf "Write verification.result.json with structured results.\n\n"
        printf "If ANY criterion falls below threshold:\n"
        printf "  Write .claude/state/evaluation-results/sprint-%s-FAIL.md with specific feedback\n" "$SPRINT"
        printf "If ALL pass:\n"
        printf "  Write .claude/state/evaluation-results/sprint-%s-PASS.md\n" "$SPRINT"
      } > "${STATE_DIR}/current-prompt.md"

      bash "$SCRIPTS/run-claude-safe.sh" "${STATE_DIR}/current-prompt.md" "auto-accept"

      # Restore calibration file and check if evaluator caught the planted failure
      if [ -n "$CALIBRATION_BACKUP" ] && [ -f "$CALIBRATION_BACKUP" ]; then
        # Restore the hidden contract
        mv "${CALIBRATION_FILE}.hidden-by-calibration" "$CALIBRATION_FILE" 2>/dev/null
        rm -f "$CALIBRATION_BACKUP"

        # Check if evaluator caught the missing contract (should have reported FAIL)
        CALIBRATION_CAUGHT=$(jq -r '.calibration.caught // false' verification.result.json 2>/dev/null)
        if [ "$CALIBRATION_CAUGHT" != "true" ]; then
          # Check if evaluator reported any FAIL (which would indicate it noticed something wrong)
          FAIL_COUNT=$(jq -r '.fail_count // 0' verification.result.json 2>/dev/null)
          if [ "$FAIL_COUNT" -eq 0 ]; then
            printf "run-harness: CALIBRATION GATE FAILED — evaluator missed planted failure. Discarding results.\n" >&2
            bash "$SCRIPTS/notify.sh" "Calibration gate failed. Evaluator missed planted failure. Re-running." 2>/dev/null
            rm -f verification.result.json 2>/dev/null
            rm -f ".claude/state/evaluation-results/sprint-${SPRINT}-PASS.md" 2>/dev/null
            printf "%s" "$(( EVAL_ATTEMPTS + 1 ))" > "${STATE_DIR}/eval-attempts-sprint-${SPRINT}.txt"
            ITERATION=$(( ITERATION + 1 ))
            continue
          fi
        fi
      fi

      # Step 5: Cross-examiner (Layer 6, if evaluator passed)
      if [ -f ".claude/state/evaluation-results/sprint-${SPRINT}-PASS.md" ]; then
        {
          printf "You are the CROSS-EXAMINER. Read %s/cross-examiner.md for your role.\n" "$AGENTS"
          printf "Read evidence/ directory and verification.result.json.\n"
          printf "Assume the verifier MISSED something. What could still be wrong?\n"
          printf "Update verification.result.json cross_examination field.\n"
        } > "${STATE_DIR}/current-prompt.md"

        bash "$SCRIPTS/run-claude-safe.sh" "${STATE_DIR}/current-prompt.md" "plan"

        # Check if cross-examiner overrode
        OVERRIDE=$(jq -r '.cross_examination.override // false' verification.result.json 2>/dev/null)
        if [ "$OVERRIDE" = "true" ]; then
          printf "run-harness: Cross-examiner OVERRODE pass. Returning to BUILD.\n" >&2
          printf '{"phase": "BUILD", "sprint": %s, "iteration": %s}\n' "$SPRINT" "$ITERATION" > "${STATE_DIR}/current-phase.json"
          printf "%s" "$(( EVAL_ATTEMPTS + 1 ))" > "${STATE_DIR}/eval-attempts-sprint-${SPRINT}.txt"
          ITERATION=$(( ITERATION + 1 ))
          continue
        fi
      fi

      # Check evaluator result
      if [ -f ".claude/state/evaluation-results/sprint-${SPRINT}-PASS.md" ]; then
        NEXT_SPRINT=$(( SPRINT + 1 ))
        TOTAL_SPRINTS=$(cat "${STATE_DIR}/total-sprints.txt" 2>/dev/null || printf "5")

        if [ "$NEXT_SPRINT" -gt "$TOTAL_SPRINTS" ]; then
          printf '{"phase": "COMPLETE", "sprint": %s, "iteration": %s}\n' "$SPRINT" "$ITERATION" > "${STATE_DIR}/current-phase.json"
        else
          printf '{"phase": "NEGOTIATE", "sprint": %s, "iteration": %s}\n' "$NEXT_SPRINT" "$ITERATION" > "${STATE_DIR}/current-phase.json"
        fi

        bash "$SCRIPTS/write-handoff.sh" "SPRINT_${SPRINT}_COMPLETE"
        bash "$SCRIPTS/git-checkpoint.sh" "EVALUATE" "$SPRINT"
        bash "$SCRIPTS/notify.sh" "Sprint $SPRINT passed evaluation. Moving to sprint $NEXT_SPRINT."
        printf "0" > "${STATE_DIR}/eval-attempts-sprint-${NEXT_SPRINT}.txt" 2>/dev/null
      else
        # Evaluation failed
        printf "%s" "$(( EVAL_ATTEMPTS + 1 ))" > "${STATE_DIR}/eval-attempts-sprint-${SPRINT}.txt"
        printf '{"phase": "BUILD", "sprint": %s, "iteration": %s}\n' "$SPRINT" "$ITERATION" > "${STATE_DIR}/current-phase.json"
        bash "$SCRIPTS/notify.sh" "Sprint $SPRINT failed evaluation. Generator will iterate."
      fi
      ;;

    # ─── COMPLETE ──────────────────────────────────────────
    "COMPLETE")
      bash "$SCRIPTS/write-handoff.sh" "COMPLETE"
      bash "$SCRIPTS/git-checkpoint.sh" "COMPLETE" "$SPRINT"
      bash "$SCRIPTS/notify.sh" "All sprints complete. Final output ready for review."
      printf "run-harness: COMPLETE. All sprints passed.\n" >&2
      exit 0
      ;;

  esac

  ITERATION=$(( ITERATION + 1 ))
  # Update iteration count in state
  jq --argjson iter "$ITERATION" '.iteration = $iter' "${STATE_DIR}/current-phase.json" > "${STATE_DIR}/current-phase.json.tmp" && \
    mv "${STATE_DIR}/current-phase.json.tmp" "${STATE_DIR}/current-phase.json"
done

# Max iterations reached
bash "$SCRIPTS/write-handoff.sh" "MAX_ITERATIONS"
bash "$SCRIPTS/notify.sh" "Max iterations ($MAX_ITERATIONS) reached. Session saved."
printf "run-harness: Max iterations reached.\n" >&2
exit 0
