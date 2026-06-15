#!/usr/bin/env bash
# Session-ownership of the must-do summary (default-on, per-model grounding).
# Each distinct model/session must author its OWN must-do summary before writing source
# code in BUILD. A summary authored by a different session does NOT count — the gate blocks
# until this session writes its own. Owner is stamped by post-write-check.sh (PostToolUse).
#
# Drives the LIVE hooks through a HARNESS_STATE_DIR sandbox.
# Usage: bash tests/test-mustdo-session-owned.sh
set -u
HOOKS="$HOME/.claude/hooks"
PASS=0; FAIL=0
ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

mksandbox(){
  local d; d=$(mktemp -d)
  mkdir -p "$d/.claude/state" "$d/.claude/contracts" "$d/src" "$d/docs/must do"
  printf '{"phase":"BUILD","sprint":1,"iteration":0}' > "$d/.claude/state/current-phase.json"
  : > "$d/.claude/contracts/sprint-1-contract.md"
  printf 'docs/ref-one.md\n' > "$d/docs/must do/must-do.md"; : > "$d/docs/ref-one.md"
  echo "$d"
}
seed_summary(){ # $1=statedir
  printf 'I read ref-one.md and understand the constraints in must-do.md fully. ' > "$1/must-do-summary.md"
  printf 'This summary is intentionally over two hundred characters long so it satisfies the minimum length requirement that the must-do summary gate enforces before it permits any source code writes to proceed.\n' >> "$1/must-do-summary.md"
}
# Build a Write hook payload with an explicit session_id.
write_payload(){ # $1=session_id $2=file_path
  jq -nc --arg s "$1" --arg f "$2" '{session_id:$s,tool_name:"Write",tool_input:{file_path:$f}}'
}
bash_payload(){ # $1=session_id $2=command
  jq -nc --arg s "$1" --arg c "$2" '{session_id:$s,tool_name:"Bash",tool_input:{command:$c}}'
}
run_write(){ # $1=sandbox $2=statedir $3=payload  -> echoes rc
  local rc
  ( cd "$1" && printf '%s' "$3" | HARNESS_STATE_DIR="$2" bash "$HOOKS/pre-write-gate.sh" >/dev/null 2>&1 ); rc=$?
  echo "$rc"
}
run_bash(){ # $1=sandbox $2=statedir $3=payload -> echoes rc
  local rc
  ( cd "$1" && printf '%s' "$3" | HARNESS_STATE_DIR="$2" bash "$HOOKS/pre-bash-gate.sh" >/dev/null 2>&1 ); rc=$?
  echo "$rc"
}

# T1: summary owned by THIS session -> ALLOWED
t1(){
  local SB S RC; SB=$(mksandbox); S="$SB/.claude/state"
  seed_summary "$S"; printf 'sessionA' > "$S/must-do-summary.owner"
  RC=$(run_write "$SB" "$S" "$(write_payload sessionA "$SB/src/foo.js")")
  if [ "$RC" -eq 0 ]; then ok "T1 owner==session allowed (rc=$RC)"; else no "T1 owner==session should pass (rc=$RC)"; fi
  rm -rf "$SB"
}

# T2: summary owned by a DIFFERENT session -> BLOCKED
t2(){
  local SB S RC; SB=$(mksandbox); S="$SB/.claude/state"
  seed_summary "$S"; printf 'sessionA' > "$S/must-do-summary.owner"
  RC=$(run_write "$SB" "$S" "$(write_payload sessionB "$SB/src/foo.js")")
  if [ "$RC" -eq 2 ]; then ok "T2 different owner blocked (rc=$RC)"; else no "T2 different owner should block (rc=$RC)"; fi
  rm -rf "$SB"
}

# T3: valid summary but NO owner stamp (legacy) + session present -> BLOCKED
t3(){
  local SB S RC; SB=$(mksandbox); S="$SB/.claude/state"
  seed_summary "$S"  # no owner file
  RC=$(run_write "$SB" "$S" "$(write_payload sessionB "$SB/src/foo.js")")
  if [ "$RC" -eq 2 ]; then ok "T3 legacy unowned summary blocked (rc=$RC)"; else no "T3 unowned summary should block (rc=$RC)"; fi
  rm -rf "$SB"
}

# T4: valid summary, no owner, NO session_id in payload -> ALLOWED (back-compat / non-session)
t4(){
  local SB S RC P; SB=$(mksandbox); S="$SB/.claude/state"
  seed_summary "$S"
  P=$(jq -nc --arg f "$SB/src/foo.js" '{tool_name:"Write",tool_input:{file_path:$f}}')
  RC=$(run_write "$SB" "$S" "$P")
  if [ "$RC" -eq 0 ]; then ok "T4 no session_id -> ownership skipped, allowed (rc=$RC)"; else no "T4 no session_id should pass (rc=$RC)"; fi
  rm -rf "$SB"
}

# T5: post-write-check stamps the owner when must-do-summary.md is written
t5(){
  local SB S P; SB=$(mksandbox); S="$SB/.claude/state"
  seed_summary "$S"
  P=$(jq -nc --arg s "sessionZ" --arg f "$S/must-do-summary.md" '{session_id:$s,tool_name:"Write",tool_input:{file_path:$f}}')
  ( cd "$SB" && printf '%s' "$P" | HARNESS_STATE_DIR="$S" bash "$HOOKS/post-write-check.sh" >/dev/null 2>&1 )
  if [ -f "$S/must-do-summary.owner" ] && grep -q 'sessionZ' "$S/must-do-summary.owner"; then
    ok "T5 post-write-check stamped owner=sessionZ"
  else no "T5 owner not stamped"; fi
  rm -rf "$SB"
}

# T5b: after stamping, the same session passes the gate end-to-end
t5b(){
  local SB S P RC; SB=$(mksandbox); S="$SB/.claude/state"
  seed_summary "$S"
  P=$(jq -nc --arg s "sessionZ" --arg f "$S/must-do-summary.md" '{session_id:$s,tool_name:"Write",tool_input:{file_path:$f}}')
  ( cd "$SB" && printf '%s' "$P" | HARNESS_STATE_DIR="$S" bash "$HOOKS/post-write-check.sh" >/dev/null 2>&1 )
  RC=$(run_write "$SB" "$S" "$(write_payload sessionZ "$SB/src/foo.js")")
  if [ "$RC" -eq 0 ]; then ok "T5b stamp->same session passes (rc=$RC)"; else no "T5b stamped session should pass (rc=$RC)"; fi
  rm -rf "$SB"
}

# T6: kill-switch wins regardless of ownership
t6(){
  local SB S RC; SB=$(mksandbox); S="$SB/.claude/state"
  seed_summary "$S"; printf 'sessionA' > "$S/must-do-summary.owner"
  : > "$S/harness-disabled.flag"
  RC=$(run_write "$SB" "$S" "$(write_payload sessionB "$SB/src/foo.js")")
  if [ "$RC" -eq 0 ]; then ok "T6 kill-switch overrides ownership block (rc=$RC)"; else no "T6 kill-switch should allow (rc=$RC)"; fi
  rm -rf "$SB"
}

# T7: pre-bash-gate — different owner blocked
t7(){
  local SB S RC; SB=$(mksandbox); S="$SB/.claude/state"
  seed_summary "$S"; printf 'sessionA' > "$S/must-do-summary.owner"
  RC=$(run_bash "$SB" "$S" "$(bash_payload sessionB 'echo hi > src/foo.js')")
  if [ "$RC" -eq 2 ]; then ok "T7 pre-bash different owner blocked (rc=$RC)"; else no "T7 pre-bash different owner should block (rc=$RC)"; fi
  rm -rf "$SB"
}

# T8: pre-bash-gate — same owner allowed
t8(){
  local SB S RC; SB=$(mksandbox); S="$SB/.claude/state"
  seed_summary "$S"; printf 'sessionA' > "$S/must-do-summary.owner"
  RC=$(run_bash "$SB" "$S" "$(bash_payload sessionA 'echo hi > src/foo.js')")
  if [ "$RC" -eq 0 ]; then ok "T8 pre-bash same owner allowed (rc=$RC)"; else no "T8 pre-bash same owner should pass (rc=$RC)"; fi
  rm -rf "$SB"
}

echo "== must-do session-ownership =="
t1; t2; t3; t4; t5; t5b; t6; t7; t8
echo "-- RESULT: $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]
