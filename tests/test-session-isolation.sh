#!/bin/bash
# test-session-isolation.sh — a session physically CANNOT write into another, still-LIVE session's must-do
# property (summary lane or owned must-do file). A DEAD/reaped owner's property is reclaimable (NOT blocked)
# so no one is ever locked out; your own is always writable; fail-open when there is no session id.
# Also: stale summary lanes (dead sessions) are actively reaped.
set -u
HELP="$HOME/.claude/scripts/lib-helpers.sh"; HOOKS="$HOME/.claude/hooks"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }
SBX=$(mktemp -d 2>/dev/null || echo "/tmp/si-$$"); trap 'rm -rf "$SBX" 2>/dev/null' EXIT
D="$SBX/proj"; ST="$D/.claude/state"; MD="$D/docs/must do"; EF="$SBX/ef"; REG="$SBX/reg.json"
mkdir -p "$ST" "$MD" "$D/src"
printf '{"phase":"BUILD","sprint":1}' > "$ST/current-phase.json"
NOW=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S'); OLD="2020-01-01T00:00:00+00:00"
SA="aaaa-1111"; SB="bbbb-2222"
reg(){ printf '{"version":"3.0.0","max_per_project":5,"watchers":[{"slot":1,"project":"p","session_id":"SA","status":"active","last_seen":"%s"}]}\n' "$1" > "$REG"; }
stamp(){ printf '<!-- mustdo-session: %s | built: pack -->\n- src/ref.md\n' "$1" > "$2"; }
wp(){ jq -nc --arg s "$1" --arg f "$2" '{session_id:$s,tool_name:"Write",tool_input:{file_path:$f,content:"x"}}'; }
bp(){ jq -nc --arg s "$1" --arg c "$2" '{session_id:$s,tool_name:"Bash",tool_input:{command:$c}}'; }
runw(){ ( cd "$D" && printf '%s' "$1" | HARNESS_STATE_DIR="$ST" HARNESS_REGISTRY="$REG" bash "$HOOKS/pre-write-gate.sh" 2>"$EF" >/dev/null ); }
runb(){ ( cd "$D" && printf '%s' "$1" | HARNESS_STATE_DIR="$ST" HARNESS_REGISTRY="$REG" bash "$HOOKS/pre-bash-gate.sh" 2>"$EF" >/dev/null ); }
blocked(){ grep -qi 'SESSION ISOLATION' "$EF"; }

# --- A is LIVE (fresh heartbeat) ---
reg "$NOW"; stamp SA "$MD/must-do.md"
# T1: B -> A's SUMMARY lane -> BLOCKED
runw "$(wp SB "$ST/must-do-summary.SA.md")"; blocked && ok "T1 write to a LIVE peer's summary lane is BLOCKED" || bad "T1 not blocked"
# T2: B -> A's MUST-DO FILE (stamped SA) -> BLOCKED
runw "$(wp SB "docs/must do/must-do.md")"; blocked && ok "T2 write to a LIVE peer's must-do file is BLOCKED" || bad "T2 not blocked"
# T3: B -> its OWN summary lane -> ALLOWED
runw "$(wp SB "$ST/must-do-summary.SB.md")"; blocked && bad "T3 own summary wrongly blocked" || ok "T3 own summary lane allowed"
# T4: shared must-do-summary.md (no sid) -> ALLOWED
runw "$(wp SB "$ST/must-do-summary.md")"; blocked && bad "T4 shared summary wrongly blocked" || ok "T4 shared must-do-summary.md allowed"
# T5: no session id in payload -> fail-open ALLOWED
runw '{"tool_name":"Write","tool_input":{"file_path":".claude/state/must-do-summary.SA.md","content":"x"}}'; blocked && bad "T5 fail-open regressed" || ok "T5 no-session-id fail-open (allowed)"
# T6: Bash bypass echo > A's summary -> BLOCKED
runb "$(bp SB "echo hi > $ST/must-do-summary.SA.md")"; blocked && ok "T6 Bash write to a LIVE peer's summary is BLOCKED" || bad "T6 bash not blocked"

# --- A is DEAD (stale heartbeat) -> its property is RECLAIMABLE, must NOT be blocked ---
reg "$OLD"
runw "$(wp SB "$ST/must-do-summary.SA.md")"; blocked && bad "T7 dead peer's summary wrongly LOCKED (lockout!)" || ok "T7 a DEAD peer's summary is reclaimable (not blocked)"
runw "$(wp SB "docs/must do/must-do.md")"; blocked && bad "T7b dead peer's must-do file LOCKED" || ok "T7b a DEAD peer's must-do file is reclaimable"
runb "$(bp SB "echo hi > $ST/must-do-summary.SA.md")"; blocked && bad "T7c dead peer's summary LOCKED via bash" || ok "T7c DEAD peer's summary reclaimable via bash"

# T8: session_is_live unit
reg "$NOW"; L=$(bash -c 'source "'"$HELP"'"; session_is_live SA "'"$REG"'" && echo LIVE || echo DEAD')
reg "$OLD"; Dd=$(bash -c 'source "'"$HELP"'"; session_is_live SA "'"$REG"'" && echo LIVE || echo DEAD')
Uk=$(bash -c 'source "'"$HELP"'"; session_is_live NOBODY "'"$REG"'" && echo LIVE || echo DEAD')
{ [ "$L" = LIVE ] && [ "$Dd" = DEAD ] && [ "$Uk" = DEAD ]; } && ok "T8 session_is_live: fresh=LIVE stale=DEAD unknown=DEAD" || bad "T8 live='$L' stale='$Dd' unk='$Uk'"

# T9: stale-summary reap — dead owner removed, live owner kept, own kept, too-fresh kept, shared kept
reg "$NOW"   # SA live
: > "$ST/must-do-summary.SA.md"        # live owner
: > "$ST/must-do-summary.DEADSESS.md"  # dead owner, old
: > "$ST/must-do-summary.SME.md"       # my own
: > "$ST/must-do-summary.FRESHDEAD.md" # dead owner but fresh mtime
: > "$ST/must-do-summary.md"           # shared (no sid)
touch -d '2 hours ago' "$ST/must-do-summary.DEADSESS.md" 2>/dev/null || touch -t 202001010000 "$ST/must-do-summary.DEADSESS.md"
( HARNESS_SESSION_ID=SME bash -c 'source "'"$HELP"'"; mustdo_reap_stale_summaries "'"$ST"'" "'"$REG"'"' ) >/dev/null 2>&1
{ [ ! -f "$ST/must-do-summary.DEADSESS.md" ] && [ -f "$ST/must-do-summary.SA.md" ] && [ -f "$ST/must-do-summary.SME.md" ] \
  && [ -f "$ST/must-do-summary.FRESHDEAD.md" ] && [ -f "$ST/must-do-summary.md" ]; } \
  && ok "T9 reap: dead removed; live+own+too-fresh+shared kept" \
  || bad "T9 reap wrong: DEAD=$([ -f "$ST/must-do-summary.DEADSESS.md" ]&&echo present||echo gone) SA=$([ -f "$ST/must-do-summary.SA.md" ]&&echo kept||echo GONE) SME=$([ -f "$ST/must-do-summary.SME.md" ]&&echo kept||echo GONE) FRESH=$([ -f "$ST/must-do-summary.FRESHDEAD.md" ]&&echo kept||echo GONE)"

bash -n "$HELP" 2>/dev/null && ok "bash -n lib-helpers" || bad "bash -n"
echo "----------------------------------------"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
