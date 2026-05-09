#!/bin/bash
# validate-phase.sh — Phase validation (Layer 2)
# Runs deterministic checks per phase. Binary pass/fail.
# Phase 1 (Research): output file exists, contains required sections.
# Phase 2 (Plan): plan file exists, has acceptance criteria, line count check (~100 line cap).
# Phase 3 (Execute): all tests pass, no loops detected.
#
# Usage: bash validate-phase.sh <phase_number>
# Exit: 0 = pass, 1 = fail (with specific failure message)

PHASE="$1"
STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"

if [ -z "$PHASE" ]; then
  printf "validate-phase: ERROR — phase number required\n" >&2
  exit 1
fi

case "$PHASE" in
  1|"PLAN"|"RESEARCH")
    # Research phase: output file exists, contains required sections
    RESEARCH_FILE="${STATE_DIR}/step-1-analysis.md"
    if [ ! -f "$RESEARCH_FILE" ]; then
      printf "FAIL: Research output file does not exist: %s\n" "$RESEARCH_FILE" >&2
      exit 1
    fi
    for SECTION in "## Codebase Structure" "## Identified Issues" "## Applicable Patterns"; do
      if ! grep -q "$SECTION" "$RESEARCH_FILE" 2>/dev/null; then
        printf "FAIL: Research output missing required section: %s\n" "$SECTION" >&2
        exit 1
      fi
    done
    printf "PASS: Phase 1 (Research) validation complete.\n" >&2
    exit 0
    ;;

  2|"NEGOTIATE")
    # Plan phase: plan file exists, has acceptance criteria, not over-specified
    PLAN_FILE=".claude/specs/product-spec.md"
    if [ ! -f "$PLAN_FILE" ]; then
      printf "FAIL: Plan file does not exist: %s\n" "$PLAN_FILE" >&2
      exit 1
    fi
    if ! grep -q "## Acceptance Criteria\|## Evaluation Criteria\|## Success Criteria" "$PLAN_FILE" 2>/dev/null; then
      printf "FAIL: Plan missing acceptance/evaluation criteria.\n" >&2
      exit 1
    fi
    # Line count check for over-specification (Failure Mode #10)
    LINE_COUNT=$(wc -l < "$PLAN_FILE")
    if [ "$LINE_COUNT" -gt 100 ]; then
      printf "WARNING: Plan is %s lines. Likely over-specified. Review for cascading implementation detail.\n" "$LINE_COUNT" >&2
      bash "$HOME/.claude/scripts/notify.sh" "Plan may be over-specified ($LINE_COUNT lines). Review .claude/specs/product-spec.md" 2>/dev/null
      # Warning, not blocking — let human decide
    fi
    printf "PASS: Phase 2 (Plan) validation complete.\n" >&2
    exit 0
    ;;

  3|"BUILD"|"EXECUTE")
    # Verification ledger check: at least one independent verification during BUILD
    LEDGER="${STATE_DIR}/verification-ledger.jsonl"
    CURRENT_SPRINT=$(jq -r '.sprint // 0' "${STATE_DIR}/current-phase.json" 2>/dev/null)
    SPRINT_ENTRIES=0
    if [ -f "$LEDGER" ]; then
      SPRINT_ENTRIES=$(grep '"phase":"BUILD"' "$LEDGER" | grep -c "\"sprint\":${CURRENT_SPRINT}" 2>/dev/null) || SPRINT_ENTRIES=0
    fi
    if [ "$SPRINT_ENTRIES" -eq 0 ]; then
      printf "FAIL: Phase completion requires at least one independent verification during BUILD (sprint %s).\n" "$CURRENT_SPRINT" >&2
      if [ -f "${STATE_DIR}/unverified-writes.jsonl" ]; then
        BUILD_RX_TMP=$(mktemp)
        bash "$HOME/.claude/scripts/classify-verification-need.sh" > "$BUILD_RX_TMP" 2>/dev/null
        if [ -s "$BUILD_RX_TMP" ]; then
          printf "Files modified since last verification:\n" >&2
          jq -r '.files[] | "  - " + .file + "  -> requires " + (.type | ascii_upcase) + " validation"' "$BUILD_RX_TMP" >&2
          printf "\n" >&2
          jq -r '"Required: " + .prescription' "$BUILD_RX_TMP" >&2
          printf "\n" >&2
        fi
        rm -f "$BUILD_RX_TMP"
      fi
      printf "Spawn a subagent to verify your work, then retry phase completion.\n" >&2
      exit 1
    fi
    # Verification type check: strongest type must satisfy classifier requirements
    if [ -f "${STATE_DIR}/unverified-writes.jsonl" ]; then
      BEST_VTYPE="review"
      for VT in $(grep '"phase":"BUILD"' "$LEDGER" | grep "\"sprint\":${CURRENT_SPRINT}" | jq -r '.verification_type // "review"' 2>/dev/null); do
        case "$VT" in
          browser)    BEST_VTYPE="browser" ;;
          vision)     [ "$BEST_VTYPE" != "browser" ] && BEST_VTYPE="vision" ;;
          functional) case "$BEST_VTYPE" in browser|vision) ;; *) BEST_VTYPE="functional" ;; esac ;;
        esac
      done
      rank_vtype() { case "$1" in browser) echo 4;; vision) echo 3;; functional) echo 2;; *) echo 1;; esac; }
      BEST_RANK=$(rank_vtype "$BEST_VTYPE")
      BUILD_CLS_TMP=$(mktemp)
      bash "$HOME/.claude/scripts/classify-verification-need.sh" > "$BUILD_CLS_TMP" 2>/dev/null
      PHASE_SATISFIED="true"
      if [ -s "$BUILD_CLS_TMP" ]; then
        for PREQ in $(jq -r '.required[]' "$BUILD_CLS_TMP" | tr -d '\r'); do
          REQ_RANK=$(rank_vtype "$PREQ")
          [ "$BEST_RANK" -lt "$REQ_RANK" ] && PHASE_SATISFIED="false"
        done
      fi
      if [ "$PHASE_SATISFIED" = "false" ]; then
        printf "FAIL: Verification type mismatch. Your verification was '%s' but modified files require stronger verification.\n" "$BEST_VTYPE" >&2
        jq -r '.files[] | "  - " + .file + "  -> requires " + (.type | ascii_upcase) + " validation"' "$BUILD_CLS_TMP" >&2
        printf "\nSpawn a subagent with the appropriate verification type.\n" >&2
        rm -f "$BUILD_CLS_TMP"
        exit 1
      fi
      rm -f "$BUILD_CLS_TMP"
    fi
    # Execute phase: all tests pass, no loops detected
    # Run test suite if it exists
    TEST_EXIT=0
    if [ -f "package.json" ] && grep -q '"test"' "package.json" 2>/dev/null; then
      npm test > "${STATE_DIR}/test-output.txt" 2>&1
      TEST_EXIT=$?
    elif [ -f "pytest.ini" ] || [ -f "setup.py" ] || [ -f "pyproject.toml" ]; then
      python -m pytest > "${STATE_DIR}/test-output.txt" 2>&1
      TEST_EXIT=$?
    fi
    if [ "$TEST_EXIT" -ge 128 ]; then
      # Exit >= 128 means process killed by signal (segfault=139, killed=137, etc.)
      # This is an environment crash, not a test failure — warn but don't block.
      printf "WARNING: Test runner crashed with signal %s (exit %s). This is an environment issue, not a test failure.\n" "$((TEST_EXIT - 128))" "$TEST_EXIT" >&2
      printf "WARNING: Check test-output.txt. Common cause: bare pytest segfault on Windows/venv.\n" >&2
    elif [ "$TEST_EXIT" -ne 0 ]; then
      # Structured feedback: include exact test output so the agent can fix specific errors
      printf "FAIL: Tests did not pass (exit code %s).\n\n" "$TEST_EXIT" >&2
      if [ -f "${STATE_DIR}/test-output.txt" ]; then
        printf "## Specific Failures\n" >&2
        # Extract error/failure lines from test output
        grep -n -i "error\|fail\|assert\|TypeError\|NameError\|ImportError\|SyntaxError\|FAILED" "${STATE_DIR}/test-output.txt" 2>/dev/null | head -20 | while IFS= read -r ERR_LINE || [ -n "$ERR_LINE" ]; do
          printf "- %s\n" "$ERR_LINE" >&2
        done
        printf "\n## Test Output (last 40 lines)\n" >&2
        tail -40 "${STATE_DIR}/test-output.txt" >&2
        printf "\n" >&2
      fi
      printf "## Expected\nAll tests pass with exit code 0.\n\n" >&2
      printf "## Found\nTest runner exited with code %s.\n" "$TEST_EXIT" >&2
      exit 1
    fi
    # Check for negative loops
    bash "$HOME/.claude/scripts/detect-loop.sh"
    if [ $? -ne 0 ]; then
      printf "FAIL: Negative loop detected.\n" >&2
      exit 1
    fi
    printf "PASS: Phase 3 (Execute) validation complete.\n" >&2
    exit 0
    ;;

  4|"EVALUATE")
    # Verification ledger check: at least one independent verification during EVALUATE
    LEDGER="${STATE_DIR}/verification-ledger.jsonl"
    CURRENT_SPRINT=$(jq -r '.sprint // 0' "${STATE_DIR}/current-phase.json" 2>/dev/null)
    SPRINT_ENTRIES=0
    if [ -f "$LEDGER" ]; then
      SPRINT_ENTRIES=$(grep '"phase":"EVALUATE"' "$LEDGER" | grep -c "\"sprint\":${CURRENT_SPRINT}" 2>/dev/null) || SPRINT_ENTRIES=0
    fi
    if [ "$SPRINT_ENTRIES" -eq 0 ]; then
      printf "FAIL: Phase completion requires at least one independent verification during EVALUATE (sprint %s).\n" "$CURRENT_SPRINT" >&2
      if [ -f "${STATE_DIR}/unverified-writes.jsonl" ]; then
        EVAL_RX_TMP=$(mktemp)
        bash "$HOME/.claude/scripts/classify-verification-need.sh" > "$EVAL_RX_TMP" 2>/dev/null
        if [ -s "$EVAL_RX_TMP" ]; then
          printf "Files modified since last verification:\n" >&2
          jq -r '.files[] | "  - " + .file + "  -> requires " + (.type | ascii_upcase) + " validation"' "$EVAL_RX_TMP" >&2
          printf "\n" >&2
          jq -r '"Required: " + .prescription' "$EVAL_RX_TMP" >&2
          printf "\n" >&2
        fi
        rm -f "$EVAL_RX_TMP"
      fi
      printf "Spawn a subagent to verify your work, then retry phase completion.\n" >&2
      exit 1
    fi
    # Evaluate phase: protocol compliance checked separately by evaluate-protocol-compliance.sh
    # This validation just checks evaluator output exists
    EVAL_DIR="${STATE_DIR}/evaluation-results"
    SPRINT=$(jq -r '.sprint // 0' "${STATE_DIR}/current-phase.json" 2>/dev/null || printf "0")
    if [ ! -f "${EVAL_DIR}/sprint-${SPRINT}-evaluation.md" ]; then
      printf "FAIL: Evaluation results not found for sprint %s\n" "$SPRINT" >&2
      exit 1
    fi
    printf "PASS: Phase 4 (Evaluate) validation complete.\n" >&2
    exit 0
    ;;

  *)
    printf "FAIL: Unknown phase: %s\n" "$PHASE" >&2
    exit 1
    ;;
esac
