#!/usr/bin/env bash
# Sprint 29 TDD - orphaned evidence-checkpoint auto-resolve
# Runs against the REAL hooks/helpers in a throwaway sandbox.
# Usage: bash tests/test-sprint29-checkpoint-autoresolve.sh
set -u
HOOKS="$HOME/.claude/hooks"
HELPERS="$HOME/.claude/scripts/lib-helpers.sh"
PASS=0; FAIL=0
ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

mksandbox(){
  local d; d=$(mktemp -d)
  mkdir -p "$d/.claude/state" "$d/.claude/evidence"
  echo "$d"
}
seed_checkpoint(){ printf '{"status":"pending","triggered_at":"%s","trigger_reason":"step_change"}' "$2" > "$1/evidence-checkpoint.json"; }
seed_phase(){ printf '{"phase":"%s","sprint":29,"iteration":0}' "$2" > "$1/current-phase.json"; }
seed_counter(){ printf '{"writes":7,"last_step":"x"}' > "$1/checkpoint-counter.json"; }
call_helper(){ # $1=statedir $2=phase
  ( HARNESS_STATE_DIR="$1" bash -c "source \"$HELPERS\"; clear_evidence_checkpoint_if_pass \"$1\" \"$2\"" )
}

t1(){
  local SB S OUT RC; SB=$(mksandbox); S="$SB/.claude/state"
  seed_phase "$S" BUILD; seed_counter "$S"
  seed_checkpoint "$S" "2026-06-02T10:00:00+01:00"
  printf '{"verdict":"PASS","sprint":29}' > "$S/evidence-verdict.json"
  printf '{}' > "$S/evidence-paths.json"
  : > "$S/evidence-remediation.md"
  sleep 1; touch "$S/evidence-verdict.json"
  OUT=$(call_helper "$S" BUILD 2>/dev/null); RC=$?
  if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q "cleared" \
     && [ ! -f "$S/evidence-checkpoint.json" ] && [ ! -f "$S/evidence-verdict.json" ] \
     && [ ! -f "$S/evidence-paths.json" ] && [ ! -f "$S/evidence-remediation.md" ] \
     && grep -q '"writes":0' "$S/checkpoint-counter.json" 2>/dev/null; then
    ok "T1 helper clears on fresh PASS + resets counter + prints 'cleared'"
  else
    no "T1 helper clears on fresh PASS (rc=$RC out='$OUT')"
  fi
  rm -rf "$SB"
}

t2(){
  local SB S OUT RC; SB=$(mksandbox); S="$SB/.claude/state"
  seed_phase "$S" BUILD; seed_counter "$S"
  seed_checkpoint "$S" "2026-06-02T10:00:00+01:00"
  printf '{"verdict":"PASS"}' > "$S/evidence-verdict.json"; sleep 1; touch "$S/evidence-verdict.json"
  call_helper "$S" BUILD >/dev/null 2>&1
  OUT=$(call_helper "$S" BUILD 2>&1); RC=$?
  if [ "$RC" -ne 0 ] && [ -z "$OUT" ]; then ok "T2 second call is silent no-op"; else no "T2 idempotent (rc=$RC out='$OUT')"; fi
  rm -rf "$SB"
}

t3(){
  local SB S RC; SB=$(mksandbox); S="$SB/.claude/state"
  seed_phase "$S" BUILD
  printf '{"verdict":"PASS"}' > "$S/evidence-verdict.json"
  sleep 1
  seed_checkpoint "$S" "2026-06-02T10:00:00+01:00"
  call_helper "$S" BUILD >/dev/null 2>&1; RC=$?
  if [ -f "$S/evidence-checkpoint.json" ] && [ -f "$S/evidence-verdict.json" ] && [ "$RC" -ne 0 ]; then
    ok "T3 stale verdict (older file) NOT cleared"
  else no "T3 stale verdict guard (rc=$RC)"; fi
  rm -rf "$SB"
}

t4(){
  local SB S; SB=$(mksandbox); S="$SB/.claude/state"
  seed_phase "$S" BUILD; seed_counter "$S"
  seed_checkpoint "$S" "2026-06-02T10:00:00+01:00"
  printf '{"verdict":"PASS","sprint":48,"criteria":{}}' > "$S/evidence-verdict.json"
  sleep 1; touch "$S/evidence-verdict.json"
  call_helper "$S" BUILD >/dev/null 2>&1
  if [ ! -f "$S/evidence-checkpoint.json" ]; then ok "T4 timestamp-less but newer verdict clears (mtime path)"; else no "T4 mtime fallback"; fi
  rm -rf "$SB"
}

t5(){
  local SB S; SB=$(mksandbox); S="$SB/.claude/state"
  seed_phase "$S" BUILD
  seed_checkpoint "$S" "2026-06-02T10:00:00+01:00"
  printf '{"verdict":"FAIL"}' > "$S/evidence-verdict.json"; sleep 1; touch "$S/evidence-verdict.json"
  call_helper "$S" BUILD >/dev/null 2>&1
  if [ -f "$S/evidence-checkpoint.json" ] && [ -f "$S/evidence-verdict.json" ]; then ok "T5 FAIL verdict NOT cleared"; else no "T5 FAIL guard"; fi
  rm -rf "$SB"
}

t6(){
  local SB S; SB=$(mksandbox); S="$SB/.claude/state"
  seed_phase "$S" COMPLETE
  seed_checkpoint "$S" "2026-06-02T10:00:00+01:00"
  printf '{"verdict":"PASS"}' > "$S/evidence-verdict.json"; sleep 1; touch "$S/evidence-verdict.json"
  call_helper "$S" COMPLETE >/dev/null 2>&1
  if [ -f "$S/evidence-checkpoint.json" ]; then ok "T6 non-BUILD phase NOT cleared"; else no "T6 BUILD-only scoping"; fi
  rm -rf "$SB"
}

# Must-do is ON by default in BUILD; an evidence checkpoint only ever exists when must-do is
# active (it is built from the must-do sources), so seed real grounding for BUILD source writes.
seed_mustdo(){
  local SB="$1" S="$SB/.claude/state"
  mkdir -p "$SB/docs/must do"
  printf 'docs/ref-one.md\n' > "$SB/docs/must do/must-do.md"; : > "$SB/docs/ref-one.md"
  printf 'I read ref-one.md and understand the constraints in must-do.md fully. ' > "$S/must-do-summary.md"
  printf 'This summary is intentionally over two hundred characters long so it satisfies the minimum length requirement that the must-do summary gate enforces before it permits any source code writes to proceed.\n' >> "$S/must-do-summary.md"
}

t7(){
  local SB S IN; SB=$(mksandbox); S="$SB/.claude/state"
  seed_phase "$S" BUILD; seed_counter "$S"
  seed_checkpoint "$S" "2026-06-02T10:00:00+01:00"
  # BUILD writes require a contract — seed it so the gate reaches the evidence clear
  mkdir -p "$SB/.claude/contracts"; : > "$SB/.claude/contracts/sprint-29-contract.md"
  seed_mustdo "$SB"
  printf '{"verdict":"PASS"}' > "$S/evidence-verdict.json"; sleep 1; touch "$S/evidence-verdict.json"
  IN="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$SB/src/foo.js\"}}"
  ( cd "$SB" && printf '%s' "$IN" | HARNESS_STATE_DIR="$S" bash "$HOOKS/pre-write-gate.sh" >/dev/null 2>&1 )
  if [ ! -f "$S/evidence-checkpoint.json" ]; then ok "T7 pre-write-gate cleared checkpoint on fresh PASS"; else no "T7 pre-write-gate clear"; fi
  rm -rf "$SB"
}

t8(){
  local SB S IN; SB=$(mksandbox); S="$SB/.claude/state"
  seed_phase "$S" BUILD; seed_counter "$S"
  seed_checkpoint "$S" "2026-06-02T10:00:00+01:00"
  printf '{"verdict":"PASS"}' > "$S/evidence-verdict.json"; sleep 1; touch "$S/evidence-verdict.json"
  IN="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$S/phase-complete-marker.md\"}}"
  ( cd "$SB" && printf '%s' "$IN" | HARNESS_STATE_DIR="$S" bash "$HOOKS/post-write-check.sh" >/dev/null 2>&1 )
  if [ ! -f "$S/evidence-checkpoint.json" ]; then ok "T8 post-write-check cleared checkpoint on exempt write"; else no "T8 post-write-check clear"; fi
  rm -rf "$SB"
}

t9(){
  local SB S IN OUT; SB=$(mksandbox); S="$SB/.claude/state"
  seed_phase "$S" BUILD; seed_counter "$S"
  seed_checkpoint "$S" "2026-06-02T10:00:00+01:00"
  printf '{"verdict":"PASS"}' > "$S/evidence-verdict.json"; sleep 1; touch "$S/evidence-verdict.json"
  IN="{\"prompt\":\"continue please\"}"
  OUT=$( cd "$SB" && printf '%s' "$IN" | HARNESS_STATE_DIR="$S" bash "$HOOKS/on-prompt-submit.sh" 2>/dev/null )
  if [ ! -f "$S/evidence-checkpoint.json" ] && printf '%s' "$OUT" | grep -q "CHECKPOINT RESOLVED"; then
    ok "T9 on-prompt-submit cleared + injected [CHECKPOINT RESOLVED]"
  else no "T9 on-prompt-submit clear+inject"; fi
  rm -rf "$SB"
}

# T10 (AC21): pre-bash-gate must NOT clear on a STALE pass, but MUST clear on a fresh one
t10(){
  local SB S IN; SB=$(mksandbox); S="$SB/.claude/state"
  seed_phase "$S" BUILD; seed_counter "$S"
  mkdir -p "$SB/.claude/contracts"; : > "$SB/.claude/contracts/sprint-29-contract.md"
  seed_mustdo "$SB"
  # STALE: verdict written FIRST (older), checkpoint NEWER
  printf '{"verdict":"PASS"}' > "$S/evidence-verdict.json"
  sleep 1
  seed_checkpoint "$S" "2026-06-02T10:00:00+01:00"
  mkdir -p "$SB/src"
  # project-relative redirect (cwd=$SB) so the gate detects a real source write
  IN='{"tool_name":"Bash","tool_input":{"command":"echo hi > src/foo.js"}}'
  ( cd "$SB" && printf '%s' "$IN" | HARNESS_STATE_DIR="$S" bash "$HOOKS/pre-bash-gate.sh" >/dev/null 2>&1 )
  if [ -f "$S/evidence-checkpoint.json" ]; then ok "T10a pre-bash-gate did NOT clear on STALE pass"; else no "T10a pre-bash-gate cleared a STALE pass (drift)"; fi
  # FRESH: verdict newer than checkpoint
  printf '{"verdict":"PASS"}' > "$S/evidence-verdict.json"; sleep 1; touch "$S/evidence-verdict.json"
  ( cd "$SB" && printf '%s' "$IN" | HARNESS_STATE_DIR="$S" bash "$HOOKS/pre-bash-gate.sh" >/dev/null 2>&1 )
  if [ ! -f "$S/evidence-checkpoint.json" ]; then ok "T10b pre-bash-gate cleared on FRESH pass"; else no "T10b pre-bash-gate did not clear fresh pass"; fi
  rm -rf "$SB"
}

echo "== Sprint 29 TDD =="
t1; t2; t3; t4; t5; t6; t7; t8; t9; t10
echo "-- RESULT: $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]
