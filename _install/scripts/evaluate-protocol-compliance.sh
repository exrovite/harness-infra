#!/bin/bash
# evaluate-protocol-compliance.sh — Protocol compliance gate (Layer 2)
# Called by run-harness.sh at the START of the EVALUATE phase, BEFORE evaluator agent loads.
# Binary pass/fail. If fail: harness returns to BUILD (hard gate, evaluator never loads).
# Sprint cannot reach evaluator until all checks pass.
#
# Usage: bash evaluate-protocol-compliance.sh [sprint_number]
# Exit: 0 = all pass (proceed to evaluator), 1 = compliance failure

SPRINT="${1:-0}"
STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
PASS=true

printf "evaluate-protocol-compliance: Checking sprint %s...\n" "$SPRINT" >&2

# 1. Required state files exist
for REQUIRED_FILE in \
  "${STATE_DIR}/progress-notes.md" \
  "${STATE_DIR}/current-phase.json"; do
  if [ ! -f "$REQUIRED_FILE" ]; then
    printf "PROTOCOL FAIL: Required file missing: %s\n" "$REQUIRED_FILE" >&2
    PASS=false
  fi
done

# 2. Sprint contract exists and is locked
CONTRACT_FILE=".claude/contracts/sprint-${SPRINT}-contract.md"
if [ ! -f "$CONTRACT_FILE" ]; then
  # Try alternative locations
  CONTRACT_FILE=$(find .claude/contracts/ -name "sprint-*-contract.md" -type f 2>/dev/null | tail -1)
  if [ -z "$CONTRACT_FILE" ]; then
    printf "PROTOCOL FAIL: No sprint contract found for sprint %s\n" "$SPRINT" >&2
    PASS=false
  fi
fi

# 3. No negative loops
bash "$HOME/.claude/scripts/detect-loop.sh" 2>/dev/null
if [ $? -ne 0 ]; then
  printf "PROTOCOL FAIL: Negative loop detected\n" >&2
  PASS=false
fi

# 4. Tests pass (independent harness execution — Signal 5 nuclear backstop)
bash "$HOME/.claude/scripts/run-project-tests.sh" 2>/dev/null
if [ $? -ne 0 ]; then
  printf "PROTOCOL FAIL: Tests do not pass (harness independent run)\n" >&2
  PASS=false
fi

# 5. Known-fix application verified (if a fix was pending)
bash "$HOME/.claude/scripts/verify-fix-applied.sh" 2>/dev/null
if [ $? -ne 0 ]; then
  printf "PROTOCOL FAIL: Known fix was injected but not correctly applied\n" >&2
  PASS=false
fi

# 6. Phase-complete-marker exists (builder claims done)
if [ ! -f "${STATE_DIR}/phase-complete-marker.md" ]; then
  printf "PROTOCOL FAIL: Builder has not written phase-complete-marker.md\n" >&2
  PASS=false
fi

# 7. TDD evidence sufficient (Signal 4 — red→green temporal ordering)
bash "$HOME/.claude/scripts/validate-tdd.sh" 2>/dev/null
if [ $? -ne 0 ]; then
  printf "PROTOCOL FAIL: TDD evidence insufficient (validate-tdd gate)\n" >&2
  PASS=false
fi

if [ "$PASS" = false ]; then
  printf "evaluate-protocol-compliance: FAIL — Sprint %s cannot proceed to evaluator.\n" "$SPRINT" >&2
  exit 1
fi

printf "evaluate-protocol-compliance: PASS — Proceeding to evaluator agent for sprint %s.\n" "$SPRINT" >&2
exit 0
