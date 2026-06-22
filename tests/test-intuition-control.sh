#!/bin/bash
# test-intuition-control.sh — Reproducible mechanism half of the control proof.
#
# The behavioral A/B (real sub-agents) is recorded in
# .claude/evidence/intuition-control-proof.md. THIS test proves, deterministically
# and without any LLM, the part a script can prove:
#   - the injection that controlled the agents is MACHINE-PRODUCED by beast-surface.sh
#   - it carries the project-specific, training-unguessable symbol `find_project_state_dir`
#   - it is silent on unrelated actions (no noise)
#   - it is pure (identical output on repeat)
# Uses the REAL deployed lesson store at <repo>/.beast/lessons.jsonl.
#
# Usage: bash tests/test-intuition-control.sh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SURFACE="$HOME/.claude/scripts/beast-surface.sh"
export BEAST_LESSONS="$ROOT/.beast/lessons.jsonl"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }

[ -f "$SURFACE" ] && ok "beast-surface.sh present" || { bad "beast-surface.sh present"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }
[ -f "$BEAST_LESSONS" ] && ok "deployed lesson store present" || bad "deployed lesson store present"

# The deployed store must contain the project-specific (unguessable) lesson.
grep -q 'find_project_state_dir' "$BEAST_LESSONS" \
  && ok "lesson store carries unguessable symbol find_project_state_dir" \
  || bad "lesson store carries unguessable symbol find_project_state_dir"

run() { printf '%s' "$1" | bash "$SURFACE" 2>/dev/null; }

# The exact trap action used in the A/B experiment.
TRAP='{"file_path":"is-harness-off.sh","content":"write a bash function is_harness_off that returns success when the harness is disabled by checking the harness-disabled flag in .claude/state"}'
OUT=$(run "$TRAP")

printf '%s' "$OUT" | grep -q '\[M2\]' && ok "trap action surfaces [M2]" || bad "trap action surfaces [M2] (got: $OUT)"
printf '%s' "$OUT" | grep -q 'find_project_state_dir' \
  && ok "injection carries the unguessable symbol (could ONLY reach an agent via the system)" \
  || bad "injection carries the unguessable symbol"
printf '%s' "$OUT" | grep -qiE 'before you|stop|past-you' && ok "adversarial framing present" || bad "adversarial framing present"

# Unrelated action -> silence (no noise).
UNREL='{"file_path":"README.md","content":"add a paragraph describing the project"}'
OUT2=$(run "$UNREL")
[ -z "$(printf '%s' "$OUT2" | tr -d '[:space:]')" ] && ok "unrelated action -> silence" || bad "unrelated action -> silence (got: $OUT2)"

# Pure / deterministic.
A=$(run "$TRAP"); B=$(run "$TRAP")
[ "$A" = "$B" ] && ok "surfacing is deterministic (identical on repeat)" || bad "surfacing is deterministic"

echo "---------------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
