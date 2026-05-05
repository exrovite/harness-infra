#!/bin/bash
# test-phase-gate.sh — Tests for phase-appropriate write restrictions
# Simulates each scenario by creating temp state and piping fake tool input to gate scripts.
# Exit 0 = all tests pass

PASS=0
FAIL=0
GATE="$HOME/.claude/hooks/pre-write-gate.sh"
BASH_GATE="$HOME/.claude/hooks/pre-bash-gate.sh"

# Create temp project directory with harness state
TMPDIR=$(mktemp -d)
STATE_DIR="$TMPDIR/.claude/state"
CONTRACTS_DIR="$TMPDIR/.claude/contracts"
mkdir -p "$STATE_DIR" "$CONTRACTS_DIR"

run_write_gate() {
  local phase="$1"
  local target="$2"
  local expect="$3"  # "block" or "allow"
  local desc="$4"

  printf '{"phase":"%s","sprint":2,"iteration":0}' "$phase" > "$STATE_DIR/current-phase.json"
  # Ensure write count is 0 so watcher gate doesn't interfere
  printf "0" > "$STATE_DIR/write-count.txt"
  # For BUILD phase, create a contract so contract gate doesn't interfere
  if [ "$phase" = "BUILD" ]; then
    printf "# contract" > "$CONTRACTS_DIR/sprint-2-contract.md"
  else
    rm -f "$CONTRACTS_DIR/sprint-2-contract.md"
  fi

  local input
  input=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$target")

  local exit_code
  printf '%s' "$input" | HARNESS_STATE_DIR="$STATE_DIR" bash "$GATE" >/dev/null 2>/dev/null
  exit_code=$?

  if [ "$expect" = "block" ] && [ "$exit_code" -eq 2 ]; then
    printf "  PASS: %s (blocked as expected)\n" "$desc"
    PASS=$((PASS + 1))
  elif [ "$expect" = "allow" ] && [ "$exit_code" -eq 0 ]; then
    printf "  PASS: %s (allowed as expected)\n" "$desc"
    PASS=$((PASS + 1))
  else
    printf "  FAIL: %s (expected %s, got exit %d)\n" "$desc" "$expect" "$exit_code"
    FAIL=$((FAIL + 1))
  fi
}

run_bash_gate() {
  local phase="$1"
  local command="$2"
  local expect="$3"
  local desc="$4"

  printf '{"phase":"%s","sprint":2,"iteration":0}' "$phase" > "$STATE_DIR/current-phase.json"
  printf "0" > "$STATE_DIR/write-count.txt"

  local input
  input=$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$command")

  local exit_code
  printf '%s' "$input" | HARNESS_STATE_DIR="$STATE_DIR" bash "$BASH_GATE" >/dev/null 2>/dev/null
  exit_code=$?

  if [ "$expect" = "block" ] && [ "$exit_code" -eq 2 ]; then
    printf "  PASS: %s (blocked as expected)\n" "$desc"
    PASS=$((PASS + 1))
  elif [ "$expect" = "allow" ] && [ "$exit_code" -eq 0 ]; then
    printf "  PASS: %s (allowed as expected)\n" "$desc"
    PASS=$((PASS + 1))
  else
    printf "  FAIL: %s (expected %s, got exit %d)\n" "$desc" "$expect" "$exit_code"
    FAIL=$((FAIL + 1))
  fi
}

printf "=== Phase Gate Tests ===\n\n"

# --- Criterion 1: PLAN + source code = BLOCKED ---
run_write_gate "PLAN" "$TMPDIR/src/foo.py" "block" \
  "C1: PLAN phase + source code file → blocked"

# --- Criterion 2: PLAN + spec file = ALLOWED ---
run_write_gate "PLAN" "$TMPDIR/.claude/specs/my-spec.md" "allow" \
  "C2: PLAN phase + spec file → allowed"

# --- Criterion 3: NEGOTIATE + source code = BLOCKED ---
run_write_gate "NEGOTIATE" "$TMPDIR/src/foo.py" "block" \
  "C3: NEGOTIATE phase + source code → blocked"

# --- Criterion 4: NEGOTIATE + contract file = ALLOWED ---
run_write_gate "NEGOTIATE" "$TMPDIR/.claude/contracts/sprint-2-proposal.md" "allow" \
  "C4: NEGOTIATE phase + contract file → allowed"

# --- Criterion 5: BUILD + source code = ALLOWED ---
run_write_gate "BUILD" "$TMPDIR/src/foo.py" "allow" \
  "C5: BUILD phase + source code → allowed"

# --- Criterion 6: EVALUATE + source code = BLOCKED ---
run_write_gate "EVALUATE" "$TMPDIR/src/foo.py" "block" \
  "C6: EVALUATE phase + source code → blocked"

# --- Criterion 7: PLAN + bash file write = BLOCKED ---
run_bash_gate "PLAN" "echo hello > src/foo.py" "block" \
  "C7: PLAN phase + bash file write → blocked"

# --- Criterion 8: Exempt paths in PLAN = ALLOWED ---
run_write_gate "PLAN" "$TMPDIR/.claude/state/progress.md" "allow" \
  "C8a: PLAN phase + .claude/state/ → allowed"
run_write_gate "PLAN" "$TMPDIR/.agent-memory/working/ctx.md" "allow" \
  "C8b: PLAN phase + .agent-memory/ → allowed"
run_write_gate "EVALUATE" "$TMPDIR/.claude/state/eval-result.md" "allow" \
  "C8c: EVALUATE phase + .claude/state/ → allowed"

# --- Criterion 9: No phase file = ALLOWED ---
rm -f "$STATE_DIR/current-phase.json"
input_no_phase=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/src/foo.py"}}' "$TMPDIR")
printf '%s' "$input_no_phase" | HARNESS_STATE_DIR="$STATE_DIR" bash "$GATE" >/dev/null 2>/dev/null
ec=$?
if [ "$ec" -eq 0 ]; then
  printf "  PASS: C9: No current-phase.json → allowed (exit 0)\n"
  PASS=$((PASS + 1))
else
  printf "  FAIL: C9: No current-phase.json → expected allow, got exit %d\n" "$ec"
  FAIL=$((FAIL + 1))
fi

# --- Criterion 10: PLAN + .md file = ALLOWED ---
run_write_gate "PLAN" "$TMPDIR/docs/plan.md" "allow" \
  "C10: PLAN phase + .md file → allowed"

# --- Criterion 11: NEGOTIATE + .md file = ALLOWED ---
run_write_gate "NEGOTIATE" "$TMPDIR/docs/proposal.md" "allow" \
  "C11: NEGOTIATE phase + .md file → allowed"

# --- Criterion 12: EVALUATE + .md file = ALLOWED (md exempt in all phases) ---
run_write_gate "EVALUATE" "$TMPDIR/docs/report.md" "allow" \
  "C12: EVALUATE phase + .md file → allowed"

# --- Criterion 16: COMPLETE + .md file = ALLOWED ---
run_write_gate "COMPLETE" "$TMPDIR/docs/handoff.md" "allow" \
  "C16: COMPLETE phase + .md file → allowed"

# --- Criterion 13: PLAN + .js file = still BLOCKED ---
run_write_gate "PLAN" "$TMPDIR/src/app.js" "block" \
  "C13: PLAN phase + .js file → still blocked"

# --- Criterion 14: PLAN + bash .md write = ALLOWED ---
run_bash_gate "PLAN" "echo hello > docs/plan.md" "allow" \
  "C14: PLAN phase + bash .md write → allowed"

# --- Criterion 15: PLAN + bash .js write = BLOCKED ---
run_bash_gate "PLAN" "echo hello > src/app.js" "block" \
  "C15: PLAN phase + bash .js write → blocked"

# --- Cleanup ---
rm -rf "$TMPDIR"

printf "\n=== Results: %d passed, %d failed ===\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
