#!/usr/bin/env bash
# Per-session must-do summary files (default-on, per-model grounding, race-safe).
# Each distinct model/session validates against its OWN summary file
# (must-do-summary.<session_id>.md). A summary authored by a different session does NOT count
# — the gate blocks until THIS session has its own per-session file. post-write-check.sh
# (PostToolUse) snapshots the canonical must-do-summary.md into the per-session file, preferring
# the Write tool's own content so a parallel session can never clobber it.
#
# Drives the LIVE hooks through a HARNESS_STATE_DIR sandbox.
# Usage: bash tests/test-mustdo-session-owned.sh
set -u
HOOKS="$HOME/.claude/hooks"
PASS=0; FAIL=0
ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

SUMMARY_BODY="I read ref-one.md and understand the constraints in must-do.md fully. This summary is intentionally over two hundred characters long so it satisfies the minimum length requirement that the must-do summary gate enforces before it permits any source code writes to proceed."

mksandbox(){
  local d; d=$(mktemp -d)
  mkdir -p "$d/.claude/state" "$d/.claude/contracts" "$d/src" "$d/docs/must do"
  printf '{"phase":"BUILD","sprint":1,"iteration":0}' > "$d/.claude/state/current-phase.json"
  : > "$d/.claude/contracts/sprint-1-contract.md"
  printf 'docs/ref-one.md\n' > "$d/docs/must do/must-do.md"; : > "$d/docs/ref-one.md"
  echo "$d"
}
seed_shared(){ # $1=statedir  -> writes the canonical shared summary
  printf '%s\n' "$SUMMARY_BODY" > "$1/must-do-summary.md"
}
seed_session(){ # $1=statedir $2=session_id  -> writes a per-session summary
  printf '%s\n' "$SUMMARY_BODY" > "$1/must-do-summary.$2.md"
}
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

# T1: THIS session has its own per-session file -> ALLOWED
t1(){
  local SB S RC; SB=$(mksandbox); S="$SB/.claude/state"
  seed_session "$S" sessionA
  RC=$(run_write "$SB" "$S" "$(write_payload sessionA "$SB/src/foo.js")")
  if [ "$RC" -eq 0 ]; then ok "T1 own per-session file allowed (rc=$RC)"; else no "T1 own per-session file should pass (rc=$RC)"; fi
  rm -rf "$SB"
}

# T2: only a DIFFERENT session's file exists -> BLOCKED
t2(){
  local SB S RC; SB=$(mksandbox); S="$SB/.claude/state"
  seed_session "$S" sessionA
  RC=$(run_write "$SB" "$S" "$(write_payload sessionB "$SB/src/foo.js")")
  if [ "$RC" -eq 2 ]; then ok "T2 other session's file blocked (rc=$RC)"; else no "T2 other session's file should block (rc=$RC)"; fi
  rm -rf "$SB"
}

# T3: legacy shared summary only (no per-session file) + session present -> BLOCKED
t3(){
  local SB S RC; SB=$(mksandbox); S="$SB/.claude/state"
  seed_shared "$S"  # no per-session file for sessionB
  RC=$(run_write "$SB" "$S" "$(write_payload sessionB "$SB/src/foo.js")")
  if [ "$RC" -eq 2 ]; then ok "T3 legacy shared-only summary blocked for new session (rc=$RC)"; else no "T3 shared-only should block (rc=$RC)"; fi
  rm -rf "$SB"
}

# T4: shared summary, NO session_id in payload -> ALLOWED (back-compat / non-session callers)
t4(){
  local SB S RC P; SB=$(mksandbox); S="$SB/.claude/state"
  seed_shared "$S"
  P=$(jq -nc --arg f "$SB/src/foo.js" '{tool_name:"Write",tool_input:{file_path:$f}}')
  RC=$(run_write "$SB" "$S" "$P")
  if [ "$RC" -eq 0 ]; then ok "T4 no session_id -> shared fallback, allowed (rc=$RC)"; else no "T4 no session_id should pass (rc=$RC)"; fi
  rm -rf "$SB"
}

# T5: post-write-check snapshots must-do-summary.md into the per-session file (from tool content)
t5(){
  local SB S P; SB=$(mksandbox); S="$SB/.claude/state"
  P=$(jq -nc --arg s "sessionZ" --arg f "$S/must-do-summary.md" --arg c "$SUMMARY_BODY" \
        '{session_id:$s,tool_name:"Write",tool_input:{file_path:$f,content:$c}}')
  ( cd "$SB" && printf '%s' "$P" | HARNESS_STATE_DIR="$S" bash "$HOOKS/post-write-check.sh" >/dev/null 2>&1 )
  if [ -f "$S/must-do-summary.sessionZ.md" ] && grep -q 'ref-one.md' "$S/must-do-summary.sessionZ.md"; then
    ok "T5 post-write-check created per-session file from content"
  else no "T5 per-session file not created"; fi
  rm -rf "$SB"
}

# T5b: after snapshot, the same session passes the gate end-to-end
t5b(){
  local SB S P RC; SB=$(mksandbox); S="$SB/.claude/state"
  seed_shared "$S"
  P=$(jq -nc --arg s "sessionZ" --arg f "$S/must-do-summary.md" --arg c "$SUMMARY_BODY" \
        '{session_id:$s,tool_name:"Write",tool_input:{file_path:$f,content:$c}}')
  ( cd "$SB" && printf '%s' "$P" | HARNESS_STATE_DIR="$S" bash "$HOOKS/post-write-check.sh" >/dev/null 2>&1 )
  RC=$(run_write "$SB" "$S" "$(write_payload sessionZ "$SB/src/foo.js")")
  if [ "$RC" -eq 0 ]; then ok "T5b snapshot->same session passes (rc=$RC)"; else no "T5b snapshotted session should pass (rc=$RC)"; fi
  rm -rf "$SB"
}

# T6: kill-switch wins regardless of per-session grounding
t6(){
  local SB S RC; SB=$(mksandbox); S="$SB/.claude/state"
  seed_session "$S" sessionA
  : > "$S/harness-disabled.flag"
  RC=$(run_write "$SB" "$S" "$(write_payload sessionB "$SB/src/foo.js")")
  if [ "$RC" -eq 0 ]; then ok "T6 kill-switch overrides grounding block (rc=$RC)"; else no "T6 kill-switch should allow (rc=$RC)"; fi
  rm -rf "$SB"
}

# T7: pre-bash-gate — other session's file only -> BLOCKED
t7(){
  local SB S RC; SB=$(mksandbox); S="$SB/.claude/state"
  seed_session "$S" sessionA
  RC=$(run_bash "$SB" "$S" "$(bash_payload sessionB 'echo hi > src/foo.js')")
  if [ "$RC" -eq 2 ]; then ok "T7 pre-bash other session blocked (rc=$RC)"; else no "T7 pre-bash other session should block (rc=$RC)"; fi
  rm -rf "$SB"
}

# T8: pre-bash-gate — own per-session file -> ALLOWED
t8(){
  local SB S RC; SB=$(mksandbox); S="$SB/.claude/state"
  seed_session "$S" sessionA
  RC=$(run_bash "$SB" "$S" "$(bash_payload sessionA 'echo hi > src/foo.js')")
  if [ "$RC" -eq 0 ]; then ok "T8 pre-bash own file allowed (rc=$RC)"; else no "T8 pre-bash own file should pass (rc=$RC)"; fi
  rm -rf "$SB"
}

# T9: THE RACE — session B writing/overwriting the shared summary must NOT break session A's grounding.
# A is grounded (own per-session file). B then performs a must-do-summary.md write (snapshots to B's
# own file, optionally clobbering the shared file). A must STILL pass — its per-session file is intact.
t9(){
  local SB S RC P; SB=$(mksandbox); S="$SB/.claude/state"
  seed_session "$S" sessionA              # A is grounded
  # B writes its summary: post-write-check snapshots into B's file, and B's content lands in shared.
  P=$(jq -nc --arg s "sessionB" --arg f "$S/must-do-summary.md" --arg c "B-OVERWRITE $SUMMARY_BODY" \
        '{session_id:$s,tool_name:"Write",tool_input:{file_path:$f,content:$c}}')
  ( cd "$SB" && printf '%s' "$P" | HARNESS_STATE_DIR="$S" bash "$HOOKS/post-write-check.sh" >/dev/null 2>&1 )
  # A's file untouched?
  if grep -q 'B-OVERWRITE' "$S/must-do-summary.sessionA.md" 2>/dev/null; then
    no "T9 session B clobbered session A's per-session file"
  else
    RC=$(run_write "$SB" "$S" "$(write_payload sessionA "$SB/src/foo.js")")
    if [ "$RC" -eq 0 ]; then ok "T9 race: B's write did not break A's grounding (rc=$RC)"; else no "T9 A should still pass after B's write (rc=$RC)"; fi
  fi
  rm -rf "$SB"
}

echo "== must-do per-session summary files =="
t1; t2; t3; t4; t5; t5b; t6; t7; t8; t9
echo "-- RESULT: $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]
