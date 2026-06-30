#!/bin/bash
# test-mustdo-default-fanout.sh — per-session must-do FILE fan-out must be the DEFAULT (no multi-lane.json).
# Concurrent sessions in ONE project must each own a DISTINCT must-do file (must-do.md, must-do-2.md, …),
# keyed off the per-project watcher pool, so they never share a stamp and never deadlock on +++pack.
set -u
HELP="$HOME/.claude/scripts/lib-helpers.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }
SBX=$(mktemp -d 2>/dev/null || echo "/tmp/mdf-$$")
trap 'rm -rf "$SBX" 2>/dev/null' EXIT

PROJ="$SBX/proj"; MDIR="$PROJ/docs/must do"
mkdir -p "$MDIR"
PROJ_ABS="$(cd "$PROJ" && pwd -W 2>/dev/null || pwd)"
REG="$SBX/REGISTRY.json"
SA="aaaaaaaa-1111-1111-1111-111111111111"
SB="bbbbbbbb-2222-2222-2222-222222222222"
SGONE="cccccccc-3333-3333-3333-333333333333"

# registry with two ACTIVE sessions for this project: A=slot1, B=slot2
reg2(){ printf '{"version":"3.0.0","max_per_project":5,"watchers":[{"slot":1,"project":"%s","session_id":"%s","status":"active"},{"slot":2,"project":"%s","session_id":"%s","status":"active"}]}\n' "$PROJ_ABS" "$SA" "$PROJ_ABS" "$SB" > "$REG"; }
reg1(){ printf '{"version":"3.0.0","max_per_project":5,"watchers":[{"slot":1,"project":"%s","session_id":"%s","status":"active"}]}\n' "$PROJ_ABS" "$SA" > "$REG"; }

# resolve owned file for a session (real lib-helpers resolver, in the project cwd)
own(){ # $1=session  $2=registry
  ( cd "$PROJ" && HARNESS_REGISTRY="$2" HARNESS_SESSION_ID="$1" bash -c 'source "'"$HELP"'" 2>/dev/null; mustdo_file_for_dir "docs/must do"' 2>/dev/null )
}
stamp(){ printf '<!-- mustdo-session: %s | built: pack -->\n%s\n' "$1" "$2" > "$3"; }

# T1: SOLO session (only A active) -> must-do.md
reg1; rm -f "$MDIR"/must-do*.md
R=$(own "$SA" "$REG"); case "$R" in */must-do.md) ok "T1 solo session owns must-do.md";; *) bad "T1 got '$R'";; esac

# T2: TWO active sessions, neither grounded yet -> A=must-do.md, B=must-do-2.md (distinct, by slot order)
reg2; rm -f "$MDIR"/must-do*.md
RA=$(own "$SA" "$REG"); RB=$(own "$SB" "$REG")
{ case "$RA" in */must-do.md) true;; *) false;; esac; } && { case "$RB" in */must-do-2.md) true;; *) false;; esac; } \
  && ok "T2 two sessions fan out: A=must-do.md B=must-do-2.md" || bad "T2 A='$RA' B='$RB'"

# T3: B already grounded must-do-2.md (stamp B) -> B keeps must-do-2.md even if roster shifts (pass-1 stamp wins)
reg2; rm -f "$MDIR"/must-do*.md; stamp "$SA" "list" "$MDIR/must-do.md"; stamp "$SB" "list" "$MDIR/must-do-2.md"
RB=$(own "$SB" "$REG"); case "$RB" in */must-do-2.md) ok "T3 B keeps its stamped must-do-2.md";; *) bad "T3 got '$RB'";; esac
# and after A releases (only B active, now rank 1) B STILL keeps must-do-2.md (stability)
reg1b(){ printf '{"version":"3.0.0","max_per_project":5,"watchers":[{"slot":2,"project":"%s","session_id":"%s","status":"active"}]}\n' "$PROJ_ABS" "$SB" > "$REG"; }
reg1b
RB=$(own "$SB" "$REG"); case "$RB" in */must-do-2.md) ok "T3b B keeps must-do-2.md after roster shift";; *) bad "T3b got '$RB'";; esac

# T4: session A's view is unaffected by B — A always resolves must-do.md (its stamp)
reg2; rm -f "$MDIR"/must-do*.md; stamp "$SA" "list" "$MDIR/must-do.md"
RA=$(own "$SA" "$REG"); case "$RA" in */must-do.md) ok "T4 A unaffected by B (owns must-do.md)";; *) bad "T4 got '$RA'";; esac

# T5: LEFTOVER reclaim — must-do.md stamped by a GONE session, only C active -> C reclaims must-do.md
reg1c(){ printf '{"version":"3.0.0","max_per_project":5,"watchers":[{"slot":1,"project":"%s","session_id":"%s","status":"active"}]}\n' "$PROJ_ABS" "$SGONE" > "$REG"; }
# C is the only active session; must-do.md stamped by a different (gone) session
printf '{"version":"3.0.0","max_per_project":5,"watchers":[{"slot":1,"project":"%s","session_id":"%s","status":"active"}]}\n' "$PROJ_ABS" "aaaa-only-c" > "$REG"
rm -f "$MDIR"/must-do*.md; stamp "$SGONE" "leftover" "$MDIR/must-do.md"
R=$(own "aaaa-only-c" "$REG"); case "$R" in */must-do.md) ok "T5 lone session reclaims a gone session's must-do.md";; *) bad "T5 got '$R'";; esac

# T6: back-compat — no HARNESS_SESSION_ID -> must-do.md (tests / non-session callers)
R=$( cd "$PROJ" && HARNESS_REGISTRY="$REG" bash -c 'source "'"$HELP"'" 2>/dev/null; mustdo_file_for_dir "docs/must do"' 2>/dev/null )
case "$R" in */must-do.md) ok "T6 no session id -> must-do.md (back-compat)";; *) bad "T6 got '$R'";; esac

# T7: explicit multilane still honored (LANE=2 -> must-do-1.md when it exists)
: > "$MDIR/must-do-1.md"
R=$( cd "$PROJ" && LANE=2 HARNESS_REGISTRY="$REG" HARNESS_SESSION_ID="$SA" bash -c 'source "'"$HELP"'" 2>/dev/null; LANE=2 mustdo_file_for_dir "docs/must do"' 2>/dev/null )
case "$R" in */must-do-1.md) ok "T7 explicit multilane LANE=2 -> must-do-1.md";; *) bad "T7 got '$R'";; esac

bash -n "$HELP" 2>/dev/null && ok "bash -n lib-helpers" || bad "bash -n"
echo "----------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
