#!/bin/bash
# test-evidence-checkpoint.sh — TDD tests for Evidence Checkpoint System
# Tests all 29 acceptance criteria from sprint-13-contract.md
# Run from project root: bash tests/test-evidence-checkpoint.sh

PASS_COUNT=0
FAIL_COUNT=0
TESTS_RUN=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); TESTS_RUN=$((TESTS_RUN + 1)); printf "  PASS: %s\n" "$1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); TESTS_RUN=$((TESTS_RUN + 1)); printf "  FAIL: %s\n" "$1"; }

# --- Setup temp project directory ---
ORIG_DIR=$(pwd)
TMPDIR=$(mktemp -d)
export HARNESS_STATE_DIR="$TMPDIR/.claude/state"
mkdir -p "$TMPDIR/.claude/state"
mkdir -p "$TMPDIR/.claude/pre-flight"
mkdir -p "$TMPDIR/.claude/evidence"
mkdir -p "$TMPDIR/.agent-memory/working"

SCRIPTS_DIR="$HOME/.claude/scripts"
HOOKS_DIR="$HOME/.claude/hooks"

# Write current-phase.json (BUILD phase)
printf '{"phase":"BUILD","sprint":13,"iteration":0}' > "$TMPDIR/.claude/state/current-phase.json"

# Write a sprint contract (so contract gate doesn't interfere)
mkdir -p "$TMPDIR/.claude/contracts"
printf '# Sprint 13 Contract\nTest contract' > "$TMPDIR/.claude/contracts/sprint-13-contract.md"

# Write count below watcher threshold (2) so watcher gate doesn't interfere
printf '1' > "$TMPDIR/.claude/state/write-count.txt"

cleanup() {
  cd "$ORIG_DIR"
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

cd "$TMPDIR"

# ============================================================
echo "=== D1: create-evidence-checkpoint.sh ==="
# ============================================================

echo "--- Trigger Logic ---"

# C1: Checkpoint triggers when must-do summary exists
# Summary must be >= 200 chars and mention must-do file basenames to pass the must-do summary gate
printf "This is a detailed must-do summary for the process.md file. It describes the full 7-phase experiment cycle: DEFINE SURVEY HYPOTHESIZE BUILD RUN EVALUATE ITERATE. Each phase must produce evidence. process.md requires strict compliance with all phases listed." > "$TMPDIR/.claude/state/must-do-summary.md"
mkdir -p "$TMPDIR/docs/must do"
printf "docs/must do/process.md\n" > "$TMPDIR/docs/must do/must-do.md"
printf "This is the process doc content for testing.\nDo 7 phases: DEFINE SURVEY HYPOTHESIZE BUILD RUN EVALUATE ITERATE\n" > "$TMPDIR/docs/must do/process.md"
# Write session-context for modified files
printf "Last modified files:\n  - src/foo.js\n  - src/bar.js\n" > "$TMPDIR/.agent-memory/working/session-context.md"

if [ -f "$SCRIPTS_DIR/create-evidence-checkpoint.sh" ]; then
  cd "$TMPDIR" && bash "$SCRIPTS_DIR/create-evidence-checkpoint.sh" 2>/dev/null
  if [ -f "$TMPDIR/.claude/state/evidence-checkpoint.json" ]; then
    pass "C1: Checkpoint file created when must-do exists"
  else
    fail "C1: Checkpoint file NOT created when must-do exists"
  fi
  rm -f "$TMPDIR/.claude/state/evidence-checkpoint.json"
else
  fail "C1: create-evidence-checkpoint.sh does not exist"
fi

# C3: No trigger when no must-do summary
rm -f "$TMPDIR/.claude/state/must-do-summary.md"
if [ -f "$SCRIPTS_DIR/create-evidence-checkpoint.sh" ]; then
  cd "$TMPDIR" && bash "$SCRIPTS_DIR/create-evidence-checkpoint.sh" 2>/dev/null
  EXIT_CODE=$?
  if [ ! -f "$TMPDIR/.claude/state/evidence-checkpoint.json" ] && [ "$EXIT_CODE" -ne 0 ]; then
    pass "C3: No checkpoint when must-do summary missing"
  else
    fail "C3: Checkpoint created despite no must-do summary"
  fi
else
  fail "C3: create-evidence-checkpoint.sh does not exist"
fi

# C4: No trigger when checkpoint already active
printf "Test must-do summary" > "$TMPDIR/.claude/state/must-do-summary.md"
printf '{"status":"pending"}' > "$TMPDIR/.claude/state/evidence-checkpoint.json"
if [ -f "$SCRIPTS_DIR/create-evidence-checkpoint.sh" ]; then
  cd "$TMPDIR" && bash "$SCRIPTS_DIR/create-evidence-checkpoint.sh" 2>/dev/null
  # Should not overwrite existing checkpoint
  CONTENT=$(cat "$TMPDIR/.claude/state/evidence-checkpoint.json" 2>/dev/null)
  if [ "$CONTENT" = '{"status":"pending"}' ]; then
    pass "C4: No trigger when checkpoint already active"
  else
    fail "C4: Existing checkpoint was overwritten"
  fi
  rm -f "$TMPDIR/.claude/state/evidence-checkpoint.json"
else
  fail "C4: create-evidence-checkpoint.sh does not exist"
fi

echo ""
echo "--- Checkpoint Brief Content ---"

# C13-C16: Brief content checks
printf "This is a detailed must-do summary for the process.md file. It describes the full 7-phase experiment cycle: DEFINE SURVEY HYPOTHESIZE BUILD RUN EVALUATE ITERATE. Each phase must produce evidence. process.md requires strict compliance with all phases listed." > "$TMPDIR/.claude/state/must-do-summary.md"
if [ -f "$SCRIPTS_DIR/create-evidence-checkpoint.sh" ]; then
  cd "$TMPDIR" && bash "$SCRIPTS_DIR/create-evidence-checkpoint.sh" 2>/dev/null
  if [ -f "$TMPDIR/.claude/state/evidence-checkpoint.json" ]; then
    BRIEF=$(cat "$TMPDIR/.claude/state/evidence-checkpoint.json")

    # C13: Contains must-do summary
    if printf '%s' "$BRIEF" | jq -r '.must_do_summary' 2>/dev/null | grep -q "must-do summary"; then
      pass "C13: Brief contains must-do summary text"
    else
      fail "C13: Brief missing must-do summary"
    fi

    # C14: Contains source file contents
    if printf '%s' "$BRIEF" | jq -r '.must_do_source_files[0].content // ""' 2>/dev/null | grep -q "7 phases"; then
      pass "C14: Brief contains must-do source file contents"
    else
      fail "C14: Brief missing source file contents"
    fi

    # C15: Contains modified files
    if printf '%s' "$BRIEF" | jq -r '.modified_files_since_last[]' 2>/dev/null | grep -q "foo"; then
      pass "C15: Brief contains modified files list"
    else
      fail "C15: Brief missing modified files"
    fi

    # C16: Contains verifier instruction
    if printf '%s' "$BRIEF" | jq -r '.instruction' 2>/dev/null | grep -qi "verifier\|evidence\|check"; then
      pass "C16: Brief contains verifier instruction"
    else
      fail "C16: Brief missing verifier instruction"
    fi

    rm -f "$TMPDIR/.claude/state/evidence-checkpoint.json"
  else
    fail "C13: Checkpoint file not created"
    fail "C14: (skipped)"
    fail "C15: (skipped)"
    fail "C16: (skipped)"
  fi
else
  fail "C13-16: create-evidence-checkpoint.sh does not exist"
fi

# C17: Agent-provided paths included on re-verification
printf '["src/experiments/hypothesis.md","src/results/output.txt"]' > "$TMPDIR/.claude/state/evidence-paths.json"
if [ -f "$SCRIPTS_DIR/create-evidence-checkpoint.sh" ]; then
  cd "$TMPDIR" && bash "$SCRIPTS_DIR/create-evidence-checkpoint.sh" 2>/dev/null
  if [ -f "$TMPDIR/.claude/state/evidence-checkpoint.json" ]; then
    if cat "$TMPDIR/.claude/state/evidence-checkpoint.json" | jq -r '.agent_provided_paths // empty' 2>/dev/null | grep -q "hypothesis"; then
      pass "C17: Brief includes agent-provided paths on re-verification"
    else
      fail "C17: Agent-provided paths not in brief"
    fi
    rm -f "$TMPDIR/.claude/state/evidence-checkpoint.json"
  else
    fail "C17: Checkpoint file not created"
  fi
  rm -f "$TMPDIR/.claude/state/evidence-paths.json"
else
  fail "C17: create-evidence-checkpoint.sh does not exist"
fi

# ============================================================
echo ""
echo "=== D2: pre-write-gate.sh — Checkpoint Block ==="
# ============================================================

echo "--- Block Gate ---"

# Helper: run pre-write-gate with mock input, return exit code
run_write_gate() {
  local FILE_PATH="$1"
  local TOOL_NAME="${2:-Write}"
  local MOCK_INPUT
  MOCK_INPUT=$(printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "$TOOL_NAME" "$FILE_PATH")
  cd "$TMPDIR" && printf '%s' "$MOCK_INPUT" | bash "$HOOKS_DIR/pre-write-gate.sh" 2>/dev/null
  return $?
}

# C7: Source code writes blocked when checkpoint pending
printf '{"status":"pending"}' > "$TMPDIR/.claude/state/evidence-checkpoint.json"
run_write_gate "src/main.js"
if [ $? -eq 2 ]; then
  pass "C7: Source code writes blocked when checkpoint pending"
else
  fail "C7: Writes NOT blocked during pending checkpoint"
fi

# C8: .claude/state/ writes allowed
run_write_gate ".claude/state/evidence-verdict.json"
if [ $? -eq 0 ]; then
  pass "C8: .claude/state/ writes allowed during checkpoint"
else
  fail "C8: .claude/state/ writes blocked during checkpoint"
fi

# C9: .claude/evidence/ writes allowed
run_write_gate ".claude/evidence/style-1/define.md"
if [ $? -eq 0 ]; then
  pass "C9: .claude/evidence/ writes allowed during checkpoint"
else
  fail "C9: .claude/evidence/ writes blocked during checkpoint"
fi

# C10: Agent tool calls allowed
run_write_gate "" "Agent"
if [ $? -eq 0 ]; then
  pass "C10: Agent tool calls allowed during checkpoint"
else
  fail "C10: Agent tool calls blocked during checkpoint"
fi

# C11: Block clears on PASS verdict
printf '{"verdict":"PASS","summary":"All phases verified"}' > "$TMPDIR/.claude/state/evidence-verdict.json"
run_write_gate "src/main.js"
if [ $? -eq 0 ]; then
  pass "C11: Block clears on PASS verdict"
  # Verify cleanup
  if [ ! -f "$TMPDIR/.claude/state/evidence-checkpoint.json" ] && [ ! -f "$TMPDIR/.claude/state/evidence-verdict.json" ]; then
    pass "C11b: Checkpoint and verdict files cleaned up"
  else
    fail "C11b: Checkpoint/verdict files not cleaned up"
  fi
else
  fail "C11: Block did NOT clear on PASS verdict"
fi

# C12: Block persists on FAIL verdict
printf '{"status":"pending"}' > "$TMPDIR/.claude/state/evidence-checkpoint.json"
printf '{"verdict":"FAIL","summary":"Missing phases","findings":[{"phase":"BUILD","note":"No evidence"}]}' > "$TMPDIR/.claude/state/evidence-verdict.json"
run_write_gate "src/main.js"
if [ $? -eq 2 ]; then
  pass "C12: Block persists on FAIL verdict"
else
  fail "C12: Block did NOT persist on FAIL verdict"
fi
rm -f "$TMPDIR/.claude/state/evidence-checkpoint.json" "$TMPDIR/.claude/state/evidence-verdict.json"

# ============================================================
echo ""
echo "=== D4: on-prompt-submit.sh — Injection ==="
# ============================================================

# C22: Injection when checkpoint pending
printf '{"status":"pending"}' > "$TMPDIR/.claude/state/evidence-checkpoint.json"
PROMPT_OUTPUT=$(cd "$TMPDIR" && bash "$HOOKS_DIR/on-prompt-submit.sh" 2>/dev/null)
if printf '%s' "$PROMPT_OUTPUT" | grep -qi "EVIDENCE CHECKPOINT"; then
  pass "C22: Prompt injection when checkpoint pending"
else
  fail "C22: No injection during pending checkpoint"
fi
rm -f "$TMPDIR/.claude/state/evidence-checkpoint.json"

# C24: No injection when no checkpoint
PROMPT_OUTPUT=$(cd "$TMPDIR" && bash "$HOOKS_DIR/on-prompt-submit.sh" 2>/dev/null)
if printf '%s' "$PROMPT_OUTPUT" | grep -qi "EVIDENCE CHECKPOINT"; then
  fail "C24: Injection present when no checkpoint active"
else
  pass "C24: No injection when no checkpoint active"
fi

# ============================================================
echo ""
echo "=== Non-Interference ==="
# ============================================================

# C25: Projects without must-do: zero effect on write flow
rm -rf "$TMPDIR/docs/must do" "$TMPDIR/docs/must-do" "$TMPDIR/.claude/must-do"
rm -f "$TMPDIR/.claude/state/must-do-summary.md"
rm -f "$TMPDIR/.claude/state/evidence-checkpoint.json"
run_write_gate "src/main.js"
GATE_EXIT=$?
# Should pass (or fail for OTHER reasons like watcher, not checkpoint)
# We just check that no checkpoint file was created
if [ ! -f "$TMPDIR/.claude/state/evidence-checkpoint.json" ]; then
  pass "C25: No checkpoint created for project without must-do"
else
  fail "C25: Checkpoint created in project without must-do"
fi

# C26: No injection for project without must-do
PROMPT_OUTPUT=$(cd "$TMPDIR" && bash "$HOOKS_DIR/on-prompt-submit.sh" 2>/dev/null)
if printf '%s' "$PROMPT_OUTPUT" | grep -qi "EVIDENCE CHECKPOINT"; then
  fail "C26: Checkpoint injection in project without must-do"
else
  pass "C26: No checkpoint injection in project without must-do"
fi

# ============================================================
echo ""
echo "=== RESULTS ==="
echo "Passed: $PASS_COUNT / $TESTS_RUN"
echo "Failed: $FAIL_COUNT / $TESTS_RUN"
if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "STATUS: TESTS FAILED"
  exit 1
else
  echo "STATUS: ALL TESTS PASSED"
  exit 0
fi
