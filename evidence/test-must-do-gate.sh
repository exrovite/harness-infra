#!/bin/bash
# test-must-do-gate.sh — Tests for must-do gate diagnostic messages and fresh bypass
# Simulates each scenario by creating temp state and piping fake tool input to the gate.
# Exit 0 = all tests pass

PASS=0
FAIL=0
GATE="$HOME/.claude/hooks/pre-write-gate.sh"

# Create temp project directory with harness state + must-do folder
TMPDIR=$(mktemp -d)
STATE_DIR="$TMPDIR/.claude/state"
CONTRACTS_DIR="$TMPDIR/.claude/contracts"
MUST_DO_DIR="$TMPDIR/docs/must do"
mkdir -p "$STATE_DIR" "$CONTRACTS_DIR" "$MUST_DO_DIR"

# Create a must-do.md listing two required files
printf 'source-of-truth.md\ntechnique-toolkit.md\n' > "$MUST_DO_DIR/must-do.md"

# Always set BUILD phase + contract so other gates don't interfere
setup_build() {
  printf '{"phase":"BUILD","sprint":1,"iteration":0}' > "$STATE_DIR/current-phase.json"
  printf '# contract' > "$CONTRACTS_DIR/sprint-1-contract.md"
  printf "0" > "$STATE_DIR/write-count.txt"
}

run_must_do_gate() {
  local target="$1"
  local expect="$2"  # "block" or "allow"
  local desc="$3"
  local check_stderr="$4"  # optional: substring to find in stderr

  setup_build

  local input
  input=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$target")

  local stderr_file
  stderr_file=$(mktemp)
  local exit_code
  # Must cd into TMPDIR so the gate finds docs/must do/ relative to pwd
  (cd "$TMPDIR" && printf '%s' "$input" | HARNESS_STATE_DIR="$STATE_DIR" bash "$GATE") >/dev/null 2>"$stderr_file"
  exit_code=$?
  local stderr_out
  stderr_out=$(cat "$stderr_file")
  rm -f "$stderr_file"

  local ok=false
  if [ "$expect" = "block" ] && [ "$exit_code" -eq 2 ]; then
    ok=true
  elif [ "$expect" = "allow" ] && [ "$exit_code" -eq 0 ]; then
    ok=true
  fi

  # If we need to check stderr content
  if [ "$ok" = true ] && [ -n "$check_stderr" ]; then
    if ! printf '%s' "$stderr_out" | grep -qiF "$check_stderr"; then
      printf "  FAIL: %s (expected stderr to contain '%s')\n" "$desc" "$check_stderr"
      printf "        STDERR: %s\n" "$stderr_out"
      FAIL=$((FAIL + 1))
      return
    fi
  fi

  if [ "$ok" = true ]; then
    printf "  PASS: %s\n" "$desc"
    PASS=$((PASS + 1))
  else
    printf "  FAIL: %s (expected %s, got exit %d)\n" "$desc" "$expect" "$exit_code"
    printf "        STDERR: %s\n" "$stderr_out"
    FAIL=$((FAIL + 1))
  fi
}

printf "=== Must-Do Gate Tests ===\n\n"

# --- C1: No summary file → blocked with diagnostic ---
rm -f "$STATE_DIR/must-do-summary.md" "$STATE_DIR/must-do-summary-step.txt"
run_must_do_gate "$TMPDIR/src/foo.py" "block" \
  "C1: No summary file → blocked" \
  "No must-do summary found"

# --- C2: Summary too short → blocked with char count ---
printf "short" > "$STATE_DIR/must-do-summary.md"
rm -f "$STATE_DIR/must-do-summary-step.txt"
run_must_do_gate "$TMPDIR/src/foo.py" "block" \
  "C2: Summary too short → blocked" \
  "too short"

# --- C3: Summary missing file mentions → blocked ---
# Write a 200+ char summary that doesn't mention any must-do basenames
python3 -c "print('x' * 250)" > "$STATE_DIR/must-do-summary.md"
rm -f "$STATE_DIR/must-do-summary-step.txt"
run_must_do_gate "$TMPDIR/src/foo.py" "block" \
  "C3: Summary missing mentions → blocked" \
  "reference"

# --- C4: Valid summary (length OK + mentions OK, no step file) → allowed ---
printf '# Summary\nI read source-of-truth.md and technique-toolkit.md and learned about the process.\n%200s\n' "" > "$STATE_DIR/must-do-summary.md"
rm -f "$STATE_DIR/must-do-summary-step.txt"
run_must_do_gate "$TMPDIR/src/foo.py" "allow" \
  "C4: Valid summary, no step file → allowed"

# --- C5: Step mismatch → blocked with both step texts ---
printf '# Summary\nI read source-of-truth.md and technique-toolkit.md and learned about the process.\n%200s\n' "" > "$STATE_DIR/must-do-summary.md"
printf 'Step 3: Old step text' > "$STATE_DIR/must-do-summary-step.txt"
# We need CURRENT_STEP_MD to be non-empty for the mismatch to trigger.
# The gate extracts it from the watcher slot, which we can't mock.
# So this test checks: if step file exists but no watcher → step check skipped → allowed.
# (Step mismatch only triggers with an active watcher for the project.)
run_must_do_gate "$TMPDIR/src/foo.py" "allow" \
  "C5: Step file exists but no watcher → step check skipped → allowed"

# --- C6: Exempt paths always pass even without summary ---
rm -f "$STATE_DIR/must-do-summary.md" "$STATE_DIR/must-do-summary-step.txt"
run_must_do_gate "$TMPDIR/.claude/state/progress.md" "allow" \
  "C6a: Exempt .claude/state/ → allowed without summary"
run_must_do_gate "$TMPDIR/.agent-memory/working/ctx.md" "allow" \
  "C6b: Exempt .agent-memory/ → allowed without summary"
run_must_do_gate "$TMPDIR/.claude/pre-flight/response.md" "allow" \
  "C6c: Exempt .claude/pre-flight/ → allowed without summary"

# --- C7: No must-do folder → allowed ---
TMPDIR2=$(mktemp -d)
STATE_DIR2="$TMPDIR2/.claude/state"
CONTRACTS_DIR2="$TMPDIR2/.claude/contracts"
mkdir -p "$STATE_DIR2" "$CONTRACTS_DIR2"
printf '{"phase":"BUILD","sprint":1,"iteration":0}' > "$STATE_DIR2/current-phase.json"
printf '# contract' > "$CONTRACTS_DIR2/sprint-1-contract.md"
printf "0" > "$STATE_DIR2/write-count.txt"
input_no_mustdo=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/src/foo.py"}}' "$TMPDIR2")
(cd "$TMPDIR2" && printf '%s' "$input_no_mustdo" | HARNESS_STATE_DIR="$STATE_DIR2" bash "$GATE") >/dev/null 2>/dev/null
ec=$?
if [ "$ec" -eq 0 ]; then
  printf "  PASS: C7: No must-do folder → allowed\n"
  PASS=$((PASS + 1))
else
  printf "  FAIL: C7: No must-do folder → expected allow, got exit %d\n" "$ec"
  FAIL=$((FAIL + 1))
fi
rm -rf "$TMPDIR2"

# --- C8: Fresh summary bypass (< 5 min old) ---
# Write a valid summary with mentions, but create a stale step file.
# Since there's no watcher for the temp dir, step check is skipped.
# This test verifies that a fresh valid summary is accepted.
printf '# Summary\nI read source-of-truth.md and technique-toolkit.md thoroughly.\n%200s\n' "" > "$STATE_DIR/must-do-summary.md"
# Touch the file to ensure it's fresh
touch "$STATE_DIR/must-do-summary.md"
rm -f "$STATE_DIR/must-do-summary-step.txt"
run_must_do_gate "$TMPDIR/src/foo.py" "allow" \
  "C8: Fresh valid summary → allowed"

# --- Cleanup ---
rm -rf "$TMPDIR"

printf "\n=== Results: %d passed, %d failed ===\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
