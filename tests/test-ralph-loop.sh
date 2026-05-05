#!/bin/bash
# Sprint 22 Ralph loop regression tests.
set -u

PASS=0
FAIL=0
HOOKS_DIR="$HOME/.claude/hooks"
BASH_HOOK="$HOOKS_DIR/pre-bash-gate.sh"
WRITE_HOOK="$HOOKS_DIR/pre-write-gate.sh"
PROMPT_HOOK="$HOOKS_DIR/on-prompt-submit.sh"

pass(){ PASS=$((PASS+1)); printf '  PASS: %s\n' "$1"; }
fail(){ FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1"; }
assert(){ if eval "$1"; then pass "$2"; else fail "$2"; fi; }

ORIG=$(pwd)
TMPROOT=$(mktemp -d)
cleanup(){ cd "$ORIG" >/dev/null 2>&1 || true; rm -rf "$TMPROOT"; }
trap cleanup EXIT

new_case(){
  CASEDIR="$TMPROOT/$1"
  rm -rf "$CASEDIR"
  mkdir -p "$CASEDIR/.claude/state" "$CASEDIR/.claude/contracts" "$CASEDIR/src"
  export HARNESS_STATE_DIR="$CASEDIR/.claude/state"
  printf '{"phase":"BUILD","sprint":22,"iteration":0}' > "$HARNESS_STATE_DIR/current-phase.json"
  printf '# Sprint 22 Contract\n' > "$CASEDIR/.claude/contracts/sprint-22-contract.md"
  printf '0' > "$HARNESS_STATE_DIR/write-count.txt"
  cd "$CASEDIR" || exit 1
}

run_prompt(){ printf '%s' "$1" | bash "$PROMPT_HOOK" 2>/dev/null; }
run_write_gate(){ printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "${2:-Write}" "$1" | bash "$WRITE_HOOK" >/dev/null 2>"$CASEDIR/err.txt"; return $?; }
run_bash_gate(){ printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" | bash "$BASH_HOOK" >/dev/null 2>"$CASEDIR/err.txt"; return $?; }

# Keyword Detection
new_case activation
OUT=$(run_prompt '{"prompt":"please $ralph implement"}')
assert '[ -f "$HARNESS_STATE_DIR/ralph-mode.json" ] && jq -e ".active == true and .iteration == 1 and .max_iterations == 5 and .sprint == 22" "$HARNESS_STATE_DIR/ralph-mode.json" >/dev/null' '1: $ralph during BUILD activates state'
assert 'printf "%s" "$OUT" | grep -q "RALPH LOOP: Iteration 1/5"' '9: first iteration packet instructs verifier'
assert '[ ! -f "$HARNESS_STATE_DIR/evidence-checkpoint.json" ]' '6: activation only creates ralph state'

new_case max_override
run_prompt '{"prompt":"go $ralph:3"}' >/dev/null
assert 'jq -e ".max_iterations == 3" "$HARNESS_STATE_DIR/ralph-mode.json" >/dev/null' '2: $ralph:N overrides max_iterations'

new_case uppercase
run_prompt '{"prompt":"go $RALPH"}' >/dev/null
assert 'jq -e ".active == true" "$HARNESS_STATE_DIR/ralph-mode.json" >/dev/null' '3: uppercase $RALPH activates'

new_case no_keyword
run_prompt '{"prompt":"ordinary prompt"}' >/dev/null
assert '[ ! -f "$HARNESS_STATE_DIR/ralph-mode.json" ]' '4: no keyword does not activate'

new_case preserve_active
cat > "$HARNESS_STATE_DIR/ralph-mode.json" <<JSON
{"active":true,"activated_by":"user_prompt","activated_at":"2026-05-04T10:00:00+00:00","iteration":4,"max_iterations":9,"last_verdict":null,"last_verdict_at":null,"failed_criteria":[],"sprint":22}
JSON
run_prompt '{"prompt":"again $ralph"}' >/dev/null
assert 'jq -e ".iteration == 4 and .max_iterations == 9" "$HARNESS_STATE_DIR/ralph-mode.json" >/dev/null' '5: active ralph prompt does not reset iteration'

new_case wrong_phase
printf '{"phase":"PLAN","sprint":22,"iteration":0}' > "$HARNESS_STATE_DIR/current-phase.json"
OUT=$(run_prompt '{"prompt":"$ralph"}')
assert '[ ! -f "$HARNESS_STATE_DIR/ralph-mode.json" ] && printf "%s" "$OUT" | grep -q "RALPH IGNORED"' '7: non-BUILD warns without activation'

new_case malformed
run_prompt 'not json' >/dev/null
assert '[ ! -f "$HARNESS_STATE_DIR/ralph-mode.json" ]' '8: malformed stdin is safe no-op'

# Turn packet states
new_case packet_fail
cat > "$HARNESS_STATE_DIR/ralph-mode.json" <<JSON
{"active":true,"activated_by":"user_prompt","activated_at":"2026-05-04T10:00:00+00:00","iteration":2,"max_iterations":5,"last_verdict":"FAIL","last_verdict_at":"2026-05-04T10:01:00+00:00","failed_criteria":["A"],"sprint":22}
JSON
OUT=$(run_prompt '{"prompt":"continue"}')
assert 'printf "%s" "$OUT" | grep -q "Iteration 2/5 | FAIL"' '10: FAIL packet shows fix instruction'

new_case packet_pass
cat > "$HARNESS_STATE_DIR/ralph-mode.json" <<JSON
{"active":true,"activated_by":"user_prompt","activated_at":"2026-05-04T10:00:00+00:00","iteration":2,"max_iterations":5,"last_verdict":"PASS","last_verdict_at":"2026-05-04T10:02:00+00:00","failed_criteria":[],"sprint":22}
JSON
OUT=$(run_prompt '{"prompt":"continue"}')
assert 'printf "%s" "$OUT" | grep -q "RALPH LOOP: PASSED at iteration 2"' '11: PASS packet shows phase-complete instruction'

new_case packet_stuck
cat > "$HARNESS_STATE_DIR/ralph-mode.json" <<JSON
{"active":true,"activated_by":"user_prompt","activated_at":"2026-05-04T10:00:00+00:00","iteration":6,"max_iterations":5,"last_verdict":"FAIL","last_verdict_at":"2026-05-04T10:02:00+00:00","failed_criteria":[],"sprint":22}
JSON
OUT=$(run_prompt '{"prompt":"continue"}')
assert 'printf "%s" "$OUT" | grep -q "RALPH LOOP: STUCK"' '12: exhausted packet shows STUCK'

new_case packet_inactive
OUT=$(run_prompt '{"prompt":"continue"}')
assert '! printf "%s" "$OUT" | grep -q "RALPH LOOP"' '13: inactive ralph injects no loop section'

# Completion gate
new_case complete_no_verdict
cat > "$HARNESS_STATE_DIR/ralph-mode.json" <<JSON
{"active":true,"activated_by":"user_prompt","activated_at":"2026-05-04T10:00:00+00:00","iteration":1,"max_iterations":5,"last_verdict":null,"last_verdict_at":null,"failed_criteria":[],"sprint":22}
JSON
run_write_gate '.claude/state/phase-complete-marker.md'; RC=$?
assert '[ "$RC" -eq 2 ] && grep -q "verifier must return PASS" "$CASEDIR/err.txt"' '14/18: completion blocked without verdict and gives resolution path'
run_bash_gate 'echo done > .claude/state/phase-complete-marker.md'; RC=$?
assert '[ "$RC" -eq 2 ] && grep -q "verifier must return PASS" "$CASEDIR/err.txt"' '14b: Bash completion marker bypass blocked without PASS'

new_case complete_fail
cat > "$HARNESS_STATE_DIR/ralph-mode.json" <<JSON
{"active":true,"activated_by":"user_prompt","activated_at":"2026-05-04T10:00:00+00:00","iteration":1,"max_iterations":5,"last_verdict":null,"last_verdict_at":"2026-05-04T10:00:00+00:00","failed_criteria":[],"sprint":22}
JSON
printf '{"verdict":"FAIL","timestamp":"2026-05-04T10:01:00+00:00"}' > "$HARNESS_STATE_DIR/evidence-verdict.json"
run_write_gate '.claude/state/phase-complete-marker.md'; RC=$?
assert '[ "$RC" -eq 2 ]' '15: completion blocked on FAIL verdict'

new_case complete_pass
cat > "$HARNESS_STATE_DIR/ralph-mode.json" <<JSON
{"active":true,"activated_by":"user_prompt","activated_at":"2026-05-04T10:00:00+00:00","iteration":1,"max_iterations":5,"last_verdict":"FAIL","last_verdict_at":"2026-05-04T10:00:00+00:00","failed_criteria":[],"sprint":22}
JSON
printf '{"verdict":"PASS","timestamp":"2026-05-04T10:01:00+00:00"}' > "$HARNESS_STATE_DIR/evidence-verdict.json"
run_write_gate '.claude/state/phase-complete-marker.md'; RC=$?
assert '[ "$RC" -eq 0 ]' '16: completion allowed on fresh PASS verdict'
printf '{"verdict":"PASS","timestamp":"2026-05-04T10:00:00+00:00"}' > "$HARNESS_STATE_DIR/evidence-verdict.json"
run_write_gate '.claude/state/phase-complete-marker.md'; RC=$?
assert '[ "$RC" -eq 2 ]' '25: stale verdict does not satisfy completion'

new_case complete_inactive
run_write_gate '.claude/state/phase-complete-marker.md'; RC=$?
assert '[ "$RC" -eq 0 ]' '17: inactive ralph leaves completion unaffected'

# State protection
new_case protect_write
run_write_gate '.claude/state/ralph-mode.json'; RC=$?
assert '[ "$RC" -eq 2 ] && grep -q "user-controlled" "$CASEDIR/err.txt"' '19/20/22: Write/Edit to ralph-mode blocked with message'
run_bash_gate 'echo x > .claude/state/ralph-mode.json'; RC=$?
assert '[ "$RC" -eq 2 ] && grep -q "user-controlled" "$CASEDIR/err.txt"' '21/22: Bash write to ralph-mode blocked with message'

# Iteration accounting
new_case fail_accounting
cat > "$HARNESS_STATE_DIR/ralph-mode.json" <<JSON
{"active":true,"activated_by":"user_prompt","activated_at":"2026-05-04T10:00:00+00:00","iteration":1,"max_iterations":5,"last_verdict":null,"last_verdict_at":null,"failed_criteria":[],"sprint":22}
JSON
printf '{"verdict":"FAIL","timestamp":"2026-05-04T10:01:00+00:00","failed_criteria":["C1"]}' > "$HARNESS_STATE_DIR/evidence-verdict.json"
run_prompt '{"prompt":"next"}' >/dev/null
assert 'jq -e ".iteration == 2 and .last_verdict == \"FAIL\" and .failed_criteria[0] == \"C1\"" "$HARNESS_STATE_DIR/ralph-mode.json" >/dev/null && [ ! -f "$HARNESS_STATE_DIR/evidence-verdict.json" ]' '23/29: fresh FAIL increments and deletes verdict'
printf '{"verdict":"FAIL","timestamp":"2026-05-04T10:01:00+00:00"}' > "$HARNESS_STATE_DIR/evidence-verdict.json"
run_prompt '{"prompt":"stale"}' >/dev/null
assert 'jq -e ".iteration == 2" "$HARNESS_STATE_DIR/ralph-mode.json" >/dev/null' '25: stale FAIL does not increment'

new_case pass_accounting
cat > "$HARNESS_STATE_DIR/ralph-mode.json" <<JSON
{"active":true,"activated_by":"user_prompt","activated_at":"2026-05-04T10:00:00+00:00","iteration":2,"max_iterations":5,"last_verdict":"FAIL","last_verdict_at":"2026-05-04T10:01:00+00:00","failed_criteria":["C1"],"sprint":22}
JSON
printf '{"verdict":"PASS","timestamp":"2026-05-04T10:02:00+00:00"}' > "$HARNESS_STATE_DIR/evidence-verdict.json"
OUT=$(run_prompt '{"prompt":"next"}')
assert 'jq -e ".active == false and .last_verdict == \"PASS\"" "$HARNESS_STATE_DIR/ralph-mode.json" >/dev/null && printf "%s" "$OUT" | grep -q "PASSED at iteration 2"' '24: fresh PASS auto-deactivates and reports pass'
OUT=$(run_prompt '{"prompt":"after"}')
assert '! printf "%s" "$OUT" | grep -q "RALPH LOOP"' '30: subsequent turn after PASS injects no section'

new_case sprint_mismatch
cat > "$HARNESS_STATE_DIR/ralph-mode.json" <<JSON
{"active":true,"activated_by":"user_prompt","activated_at":"2026-05-04T10:00:00+00:00","iteration":1,"max_iterations":5,"last_verdict":null,"last_verdict_at":null,"failed_criteria":[],"sprint":21}
JSON
run_prompt '{"prompt":"next"}' >/dev/null
assert 'jq -e ".active == false" "$HARNESS_STATE_DIR/ralph-mode.json" >/dev/null' '28: sprint mismatch auto-deactivates'

new_case stuck_gate
cat > "$HARNESS_STATE_DIR/ralph-mode.json" <<JSON
{"active":true,"activated_by":"user_prompt","activated_at":"2026-05-04T10:00:00+00:00","iteration":6,"max_iterations":5,"last_verdict":"FAIL","last_verdict_at":"2026-05-04T10:02:00+00:00","failed_criteria":[],"sprint":22}
JSON
run_write_gate 'src/app.js'; RC=$?
assert '[ "$RC" -eq 2 ] && grep -q "STUCK" "$CASEDIR/err.txt"' '26/27: max exceeded blocks source writes'

# Evidence bridge
new_case evidence_bridge
cat > "$HARNESS_STATE_DIR/ralph-mode.json" <<JSON
{"active":true,"activated_by":"user_prompt","activated_at":"2026-05-04T10:00:00+00:00","iteration":3,"max_iterations":5,"last_verdict":"FAIL","last_verdict_at":"2026-05-04T10:01:00+00:00","failed_criteria":[],"sprint":22}
JSON
printf '{"ts":"2026-05-04T10:02:00+00:00","file":"src/app.js"}\n' > "$HARNESS_STATE_DIR/unverified-writes.jsonl"
run_prompt '{"prompt":"next"}' >/dev/null
assert 'jq -e ".status == \"pending\" and .ralph.iteration == 3 and .ralph.sprint_contract == \".claude/contracts/sprint-22-contract.md\"" "$HARNESS_STATE_DIR/evidence-checkpoint.json" >/dev/null' '32/33: ralph writes create evidence checkpoint with contract and iteration'

new_case evidence_bridge_existing
cat > "$HARNESS_STATE_DIR/ralph-mode.json" <<JSON
{"active":true,"activated_by":"user_prompt","activated_at":"2026-05-04T10:00:00+00:00","iteration":4,"max_iterations":5,"last_verdict":"FAIL","last_verdict_at":"2026-05-04T10:01:00+00:00","failed_criteria":[],"sprint":22}
JSON
printf '{"status":"pending","triggered_at":"2026-05-04T10:01:30+00:00"}' > "$HARNESS_STATE_DIR/evidence-checkpoint.json"
printf '{"ts":"2026-05-04T10:02:00+00:00","file":"src/app.js"}
' > "$HARNESS_STATE_DIR/unverified-writes.jsonl"
run_prompt '{"prompt":"next"}' >/dev/null
assert 'jq -e ".status == \"pending\" and .ralph.iteration == 4 and .ralph.sprint_contract == \".claude/contracts/sprint-22-contract.md\"" "$HARNESS_STATE_DIR/evidence-checkpoint.json" >/dev/null' '32/33b: ralph writes enrich existing evidence checkpoint'

new_case evidence_inactive
printf '{"ts":"2026-05-04T10:02:00+00:00","file":"src/app.js"}\n' > "$HARNESS_STATE_DIR/unverified-writes.jsonl"
run_prompt '{"prompt":"next"}' >/dev/null
assert '[ ! -f "$HARNESS_STATE_DIR/evidence-checkpoint.json" ]' '34: inactive ralph does not change checkpoint behavior'

# Quality / syntax / packet position and size
for f in "$PROMPT_HOOK" "$WRITE_HOOK" "$BASH_HOOK"; do
  if bash -n "$f"; then pass "42: bash -n $(basename "$f")"; else fail "42: bash -n $(basename "$f")"; fi
done

new_case packet_size
cat > "$HARNESS_STATE_DIR/ralph-mode.json" <<JSON
{"active":true,"activated_by":"user_prompt","activated_at":"2026-05-04T10:00:00+00:00","iteration":1,"max_iterations":5,"last_verdict":null,"last_verdict_at":null,"failed_criteria":[],"sprint":22}
JSON
OUT=$(run_prompt '{"prompt":"next"}')
LEN=${#OUT}
assert '[ "$LEN" -lt 800 ]' '41: steady-state ralph packet under 800 chars'
assert 'printf "%s" "$OUT" | awk "BEGIN{r=9999; f=9999} /RALPH LOOP/{r=NR} /READ FIRST/{f=NR} END{exit !(r<f)}"' '39: RALPH LOOP is before READ FIRST'
mkdir -p 'docs/must-do'
printf 'docs/must-do/process.md\n' > 'docs/must-do/must-do.md'
printf 'process docs\n' > 'docs/must-do/process.md'
printf '%3000s' 'x' > "$HARNESS_STATE_DIR/must-do-summary.md"
OUT=$(run_prompt '{"prompt":"next"}')
assert 'printf "%s" "$OUT" | grep -q "RALPH LOOP"' '40: RALPH LOOP survives 2000-char truncation'

printf '\nPassed: %s\nFailed: %s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]