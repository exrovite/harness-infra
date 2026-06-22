#!/usr/bin/env bash
# Sprint 37 — Session-aware must-do file-exists branch (functional, drives LIVE hooks).
#
# A must-do file left by a prior session must NOT satisfy the gate for a new session: a
# foreign-stamped file routes the new session to "author your own grounding" (block); the owned
# file is never deleted — superseded content is COPIED to docs/must do/history/ (snapshot-then-write,
# cksum-named, idempotent). Unstamped (human-seed) and no-session callers are unchanged.
#
# Drives the LIVE hooks/scripts via HARNESS_STATE_DIR sandboxes (style of test-mustdo-session-owned.sh).
# Usage: bash tests/test-mustdo-session-aware.sh
set -u
HOOKS="$HOME/.claude/hooks"
SCR="$HOME/.claude/scripts"
PASS=0; FAIL=0
ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

SRC="console.log('source');"
# >=200 chars and references ref-one.md so the summary gate is satisfied on its own merits.
SUMMARY_BODY="I read ref-one.md and understand the constraints in must-do.md fully. This summary is intentionally over two hundred characters long so it satisfies the minimum length requirement the must-do summary gate enforces before it permits source code writes to proceed."

mksandbox(){
  local d; d=$(mktemp -d)
  mkdir -p "$d/.claude/state" "$d/.claude/contracts" "$d/src" "$d/docs/must do"
  printf '{"phase":"BUILD","sprint":1,"iteration":0}' > "$d/.claude/state/current-phase.json"
  : > "$d/.claude/contracts/sprint-1-contract.md"
  : > "$d/docs/ref-one.md"
  echo "$d"
}
# put_mustdo SB STAMP_SESSION(empty=unstamped) [BODY_LINE]
put_mustdo(){
  local f="$1/docs/must do/must-do.md"; : > "$f"
  [ -n "$2" ] && printf '<!-- mustdo-session: %s | built: pack -->\n' "$2" >> "$f"
  printf '%s\n' "${3:-docs/ref-one.md}" >> "$f"
}
# put_mustdo_pack SB STAMP(empty=unstamped) -> AGENT-PACK-shaped file (build-mustdo-pack signature)
put_mustdo_pack(){
  local f="$1/docs/must do/must-do.md"; : > "$f"
  [ -n "$2" ] && printf '<!-- mustdo-session: %s | built: pack -->\n' "$2" >> "$f"
  { printf '# Must-Do — current task pack\n\n'
    printf '> Auto-built by build-mustdo-pack.sh. Links below ground the agent.\n\n'
    printf '## Grounding\n'; printf -- '- [Raw conversation (verbatim)](raw-conversation.jsonl)\n'
    printf 'docs/ref-one.md\n'; } >> "$f"
}
seed_session_summary(){ printf '%s' "$SUMMARY_BODY" > "$1/must-do-summary.$2.md"; }
seed_shared_summary(){  printf '%s' "$SUMMARY_BODY" > "$1/must-do-summary.md"; }

wp(){   jq -nc --arg s "$1" --arg f "$2" --arg c "$SRC" '{session_id:$s,tool_name:"Write",tool_input:{file_path:$f,content:$c}}'; }
wp_ns(){ jq -nc --arg f "$1" --arg c "$SRC" '{tool_name:"Write",tool_input:{file_path:$f,content:$c}}'; }
wp_md(){ jq -nc --arg s "$1" --arg f "$2" --arg c "new grounding" '{session_id:$s,tool_name:"Write",tool_input:{file_path:$f,content:$c}}'; }
bp(){   jq -nc --arg s "$1" --arg c "$2" '{session_id:$s,tool_name:"Bash",tool_input:{command:$c}}'; }

run_write(){ ( cd "$1" && printf '%s' "$3" | HARNESS_STATE_DIR="$2" bash "$HOOKS/pre-write-gate.sh" 2>"${4:-/dev/null}" >/dev/null ); echo $?; }
run_bash(){  ( cd "$1" && printf '%s' "$3" | HARNESS_STATE_DIR="$2" bash "$HOOKS/pre-bash-gate.sh"  2>"${4:-/dev/null}" >/dev/null ); echo $?; }
run_pwc(){   ( cd "$1" && printf '%s' "$3" | HARNESS_STATE_DIR="$2" bash "$HOOKS/post-write-check.sh" >/dev/null 2>&1 ); }

# ---- C1: build-mustdo-pack stamps first line with --session ----
c1(){ local SB f; SB=$(mksandbox); f="$SB/docs/must do/must-do.md"
  bash "$SCR/build-mustdo-pack.sh" --own "$f" --session SESS_A --no-transcript >/dev/null 2>&1
  if head -1 "$f" 2>/dev/null | grep -q 'mustdo-session: SESS_A'; then ok "C1 pack writes first-line stamp"; else no "C1 pack stamp missing: $(head -1 "$f")"; fi
  rm -rf "$SB"; }

# ---- C2/C3: post-write-check stamps an agent-authored must-do file; plain file has no stamp ----
c2(){ local SB f; SB=$(mksandbox); f="$SB/docs/must do/must-do.md"
  put_mustdo "$SB" ""                 # unstamped (C3: plain file, no stamp)
  if grep -q 'mustdo-session:' "$f"; then no "C3 plain must-do.md unexpectedly stamped"; else ok "C3 plain must-do.md carries no stamp"; fi
  run_pwc "$SB" "$SB/.claude/state" "$(jq -nc --arg s SESS_A --arg f "$f" --arg c "docs/ref-one.md" '{session_id:$s,tool_name:"Write",tool_input:{file_path:$f,content:$c}}')"
  if grep -q 'mustdo-session: SESS_A' "$f"; then ok "C2 post-write-check stamped agent-authored file"; else no "C2 stamp not added: $(head -1 "$f")"; fi
  rm -rf "$SB"; }

# ---- C5: unstamped (human seed) behaves exactly as today ----
c5(){ local SB S RC; SB=$(mksandbox); S="$SB/.claude/state"
  put_mustdo "$SB" ""; seed_session_summary "$S" SESS_A
  RC=$(run_write "$SB" "$S" "$(wp SESS_A "$SB/src/foo.js")")
  [ "$RC" -eq 0 ] && ok "C5a unstamped + valid summary -> allowed" || no "C5a should allow (rc=$RC)"
  rm -rf "$SB"; SB=$(mksandbox); S="$SB/.claude/state"; put_mustdo "$SB" ""    # no summary
  RC=$(run_write "$SB" "$S" "$(wp SESS_A "$SB/src/foo.js")")
  [ "$RC" -eq 2 ] && ok "C5b unstamped + no summary -> blocked (summary gate)" || no "C5b should block (rc=$RC)"
  rm -rf "$SB"; }

# ---- C6: own stamp + valid summary -> allowed ----
c6(){ local SB S RC; SB=$(mksandbox); S="$SB/.claude/state"
  put_mustdo "$SB" SESS_A; seed_session_summary "$S" SESS_A
  RC=$(run_write "$SB" "$S" "$(wp SESS_A "$SB/src/foo.js")")
  [ "$RC" -eq 0 ] && ok "C6 own-stamp + summary -> allowed" || no "C6 should allow (rc=$RC)"
  rm -rf "$SB"; }

# ---- C7: foreign stamp blocks EVEN WITH a valid summary (headline) ----
c7(){ local SB S RC EF; SB=$(mksandbox); S="$SB/.claude/state"; EF="$SB/err.txt"
  put_mustdo "$SB" SESS_A; seed_session_summary "$S" SESS_B   # B has a valid summary
  RC=$(run_write "$SB" "$S" "$(wp SESS_B "$SB/src/foo.js")" "$EF")
  if [ "$RC" -eq 2 ] && grep -qi 'different session\|author your own' "$EF"; then ok "C7 foreign stamp blocks despite valid summary"; else no "C7 should block w/ownership msg (rc=$RC) [$(tr -d '\n' <"$EF" | head -c 120)]"; fi
  rm -rf "$SB"; }

# ---- C8: under foreign stamp, writing the must-do file itself is NOT ownership-blocked ----
c8(){ local SB S RC; SB=$(mksandbox); S="$SB/.claude/state"
  put_mustdo "$SB" SESS_A
  RC=$(run_write "$SB" "$S" "$(wp_md SESS_B "$SB/docs/must do/must-do.md")")
  [ "$RC" -eq 0 ] && ok "C8 re-author of must-do file allowed under foreign stamp" || no "C8 should allow re-author (rc=$RC)"
  rm -rf "$SB"; }

# ---- C9: no session_id -> ownership logic inert (back-compat) ----
c9(){ local SB S RC; SB=$(mksandbox); S="$SB/.claude/state"
  put_mustdo "$SB" SESS_A; seed_shared_summary "$S"
  RC=$(run_write "$SB" "$S" "$(wp_ns "$SB/src/foo.js")")
  [ "$RC" -eq 0 ] && ok "C9 no-session back-compat -> allowed via shared summary" || no "C9 should allow (rc=$RC)"
  rm -rf "$SB"; }

# ---- C10: kill-switch superset ----
c10(){ local SB S RC; SB=$(mksandbox); S="$SB/.claude/state"
  put_mustdo "$SB" SESS_A; : > "$S/harness-disabled.flag"
  RC=$(run_write "$SB" "$S" "$(wp SESS_B "$SB/src/foo.js")")
  [ "$RC" -eq 0 ] && ok "C10 kill-switch overrides ownership block" || no "C10 should allow (rc=$RC)"
  rm -rf "$SB"; }

# ---- C11: pre-bash-gate mirror ----
c11(){ local SB S RC; SB=$(mksandbox); S="$SB/.claude/state"
  put_mustdo "$SB" SESS_A; seed_session_summary "$S" SESS_A; seed_session_summary "$S" SESS_B
  RC=$(run_bash "$SB" "$S" "$(bp SESS_B 'echo x > src/foo.js')")   # B has a valid summary -> only ownership can block
  [ "$RC" -eq 2 ] && ok "C11a bash foreign stamp -> blocked (despite valid summary)" || no "C11a should block (rc=$RC)"
  RC=$(run_bash "$SB" "$S" "$(bp SESS_A 'echo x > src/foo.js')")
  [ "$RC" -eq 0 ] && ok "C11b bash own stamp + summary -> allowed" || no "C11b should allow (rc=$RC)"
  rm -rf "$SB"; }

# ---- C12: build-mustdo-pack archives foreign file to history/ before clobber (never deletes) ----
c12(){ local SB f hist; SB=$(mksandbox); f="$SB/docs/must do/must-do.md"; hist="$SB/docs/must do/history"
  { printf '<!-- mustdo-session: SESS_A | built: pack -->\n'; printf 'OLD-CONTENT-MARKER\n'; } > "$f"
  bash "$SCR/build-mustdo-pack.sh" --own "$f" --session SESS_B --no-transcript >/dev/null 2>&1
  if [ -d "$hist" ] && grep -rq 'OLD-CONTENT-MARKER' "$hist" 2>/dev/null; then ok "C12 old foreign content archived to history/"; else no "C12 history snapshot missing"; fi
  if head -1 "$f" | grep -q 'mustdo-session: SESS_B'; then ok "C12 new pack stamped with new session"; else no "C12 new stamp wrong: $(head -1 "$f")"; fi
  rm -rf "$SB"; }

# ---- C12b: gate snapshots foreign owned file before allowing a manual re-author write ----
c12b(){ local SB S hist RC; SB=$(mksandbox); S="$SB/.claude/state"; hist="$SB/docs/must do/history"
  { printf '<!-- mustdo-session: SESS_A | built: pack -->\n'; printf 'GATE-OLD-MARKER\n'; } > "$SB/docs/must do/must-do.md"
  RC=$(run_write "$SB" "$S" "$(wp_md SESS_B "$SB/docs/must do/must-do.md")")
  if [ "$RC" -eq 0 ] && [ -d "$hist" ] && grep -rq 'GATE-OLD-MARKER' "$hist" 2>/dev/null; then ok "C12b gate copied foreign file to history before re-author"; else no "C12b gate snapshot missing (rc=$RC)"; fi
  rm -rf "$SB"; }

# ---- C13: snapshot is idempotent (same content -> one history entry) ----
c13(){ local SB S n; SB=$(mksandbox); S="$SB/.claude/state"
  { printf '<!-- mustdo-session: SESS_A | built: pack -->\n'; printf 'IDEM-MARKER\n'; } > "$SB/docs/must do/must-do.md"
  run_write "$SB" "$S" "$(wp_md SESS_B "$SB/docs/must do/must-do.md")" >/dev/null
  run_write "$SB" "$S" "$(wp_md SESS_B "$SB/docs/must do/must-do.md")" >/dev/null
  n=$(find "$SB/docs/must do/history" -maxdepth 1 -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" = "1" ] && ok "C13 idempotent history (1 entry for identical content)" || no "C13 expected 1 history entry, got $n"
  rm -rf "$SB"; }

# ---- C14: history/ invisible to resolution (subdir excluded by -maxdepth 1) ----
c14(){ local SB S RC; SB=$(mksandbox); S="$SB/.claude/state"
  put_mustdo "$SB" SESS_B; seed_session_summary "$S" SESS_B
  mkdir -p "$SB/docs/must do/history"; printf 'docs/ref-one.md\n' > "$SB/docs/must do/history/must-do.999.md"
  RC=$(run_write "$SB" "$S" "$(wp SESS_B "$SB/src/foo.js")")
  [ "$RC" -eq 0 ] && ok "C14 populated history/ does not break resolution" || no "C14 history interfered (rc=$RC)"
  rm -rf "$SB"; }

# ---- C15: human-seed preserved on +++pack supersede ----
c15(){ local SB f hist; SB=$(mksandbox); f="$SB/docs/must do/must-do.md"; hist="$SB/docs/must do/history"
  printf 'HUMAN-SEED-MARKER\ndocs/ref-one.md\n' > "$f"          # unstamped human file
  bash "$SCR/build-mustdo-pack.sh" --own "$f" --session SESS_A --no-transcript >/dev/null 2>&1
  if [ -d "$hist" ] && grep -rq 'HUMAN-SEED-MARKER' "$hist" 2>/dev/null; then ok "C15 unstamped human file archived before pack"; else no "C15 human file not preserved"; fi
  rm -rf "$SB"; }

# ---- C16: stamp line is ignored by the must-do reader (not listed as a required file) ----
c16(){ local SB S EF; SB=$(mksandbox); S="$SB/.claude/state"; EF="$SB/err.txt"
  put_mustdo "$SB" SESS_A      # stamped + one real file (docs/ref-one.md); no summary -> triggers files-listed
  run_write "$SB" "$S" "$(wp SESS_A "$SB/src/foo.js")" "$EF" >/dev/null
  if grep -q 'ref-one.md' "$EF" && ! grep -q 'mustdo-session' "$EF"; then ok "C16 stamp line skipped by reader (real file listed, stamp not)"; else no "C16 reader mishandled stamp [$(tr -d '\n' <"$EF" | head -c 160)]"; fi
  rm -rf "$SB"; }

# ---- C17-C20: PRE-EXISTING files already in project folders (migration) ----
# C17: an unstamped AGENT pack left by a prior session is treated as foreign -> source write blocked
c17(){ local SB S RC EF; SB=$(mksandbox); S="$SB/.claude/state"; EF="$SB/err.txt"
  put_mustdo_pack "$SB" ""; seed_session_summary "$S" SESS_B
  RC=$(run_write "$SB" "$S" "$(wp SESS_B "$SB/src/foo.js")" "$EF")
  if [ "$RC" -eq 2 ] && grep -qi 'different session\|author your own' "$EF"; then ok "C17 legacy unstamped agent pack -> foreign block (migration)"; else no "C17 should block legacy pack (rc=$RC)"; fi
  rm -rf "$SB"; }
# C18: a PLAIN unstamped human list is NOT a pack -> stays a shared seed (allowed with summary)
c18(){ local SB S RC; SB=$(mksandbox); S="$SB/.claude/state"
  put_mustdo "$SB" ""; seed_session_summary "$S" SESS_B
  RC=$(run_write "$SB" "$S" "$(wp SESS_B "$SB/src/foo.js")")
  [ "$RC" -eq 0 ] && ok "C18 plain human list stays shared seed (not foreign)" || no "C18 plain list must not be foreign (rc=$RC)"
  rm -rf "$SB"; }
# C19: bash mirror for the legacy unstamped agent pack
c19(){ local SB S RC; SB=$(mksandbox); S="$SB/.claude/state"
  put_mustdo_pack "$SB" ""; seed_session_summary "$S" SESS_B
  RC=$(run_bash "$SB" "$S" "$(bp SESS_B 'echo x > src/foo.js')")
  [ "$RC" -eq 2 ] && ok "C19 bash legacy pack -> blocked" || no "C19 bash should block legacy pack (rc=$RC)"
  rm -rf "$SB"; }
# C20: re-authoring a legacy unstamped pack snapshots it to history first (never deletes)
c20(){ local SB S hist RC; SB=$(mksandbox); S="$SB/.claude/state"; hist="$SB/docs/must do/history"
  put_mustdo_pack "$SB" ""; printf 'LEGACY-MARKER\n' >> "$SB/docs/must do/must-do.md"
  RC=$(run_write "$SB" "$S" "$(wp_md SESS_B "$SB/docs/must do/must-do.md")")
  if [ "$RC" -eq 0 ] && [ -d "$hist" ] && grep -rq 'LEGACY-MARKER' "$hist" 2>/dev/null; then ok "C20 legacy pack snapshotted before re-author"; else no "C20 legacy snapshot missing (rc=$RC)"; fi
  rm -rf "$SB"; }

echo "== Sprint 37: session-aware must-do file-exists branch =="
c1; c2; c5; c6; c7; c8; c9; c10; c11; c12; c12b; c13; c14; c15; c16; c17; c18; c19; c20
echo "-- RESULT: $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]
