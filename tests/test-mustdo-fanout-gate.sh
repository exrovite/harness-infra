#!/bin/bash
# test-mustdo-fanout-gate.sh — END-TO-END proof the multi-session must-do OWNERSHIP deadlock is broken.
# Drives the LIVE pre-write-gate / pre-bash-gate via HARNESS_STATE_DIR + HARNESS_REGISTRY sandboxes.
# Scenario: session A owns docs/must do/must-do.md. Session B does a source write.
#   CONTROL (B has NO watcher -> resolves to A's must-do.md): the old shared-file deadlock condition,
#           B is blocked with the "different session" ownership message.
#   FIX     (B HAS its own watcher slot2 -> resolves to its OWN must-do-2.md): B is NOT blocked by A's
#           file; the gate also NAMES B's own file so it knows what to author.
set -u
HOOKS="$HOME/.claude/hooks"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }
SBX=$(mktemp -d 2>/dev/null || echo "/tmp/mfg-$$")
trap 'rm -rf "$SBX" 2>/dev/null' EXIT
EF="$SBX/err.txt"; REG="$SBX/REGISTRY.json"
SA="aaaaaaaa-1111-1111-1111-111111111111"
SB="bbbbbbbb-2222-2222-2222-222222222222"

D="$SBX/proj"
mkdir -p "$D/.claude/state" "$D/.claude/contracts" "$D/src" "$D/docs/must do"
printf '{"phase":"BUILD","sprint":1,"iteration":0}' > "$D/.claude/state/current-phase.json"
: > "$D/.claude/contracts/sprint-1-contract.md"
ABS="$(cd "$D" && pwd -W 2>/dev/null || pwd)"
# A owns must-do.md (stamped)
printf '<!-- mustdo-session: %s | built: pack -->\n- src/ref.md\n' "$SA" > "$D/docs/must do/must-do.md"

regA(){ printf '{"version":"3.0.0","max_per_project":5,"watchers":[{"slot":1,"project":"%s","session_id":"%s","status":"active"}]}\n' "$ABS" "$SA" > "$REG"; }
regAB(){ printf '{"version":"3.0.0","max_per_project":5,"watchers":[{"slot":1,"project":"%s","session_id":"%s","status":"active"},{"slot":2,"project":"%s","session_id":"%s","status":"active"}]}\n' "$ABS" "$SA" "$ABS" "$SB" > "$REG"; }
wp(){ jq -nc --arg s "$1" --arg f "$2" '{session_id:$s,tool_name:"Write",tool_input:{file_path:$f,content:"print(1)"}}'; }
bp(){ jq -nc --arg s "$1" --arg c "$2" '{session_id:$s,tool_name:"Bash",tool_input:{command:$c}}'; }
runw(){ ( cd "$D" && printf '%s' "$2" | HARNESS_STATE_DIR="$D/.claude/state" HARNESS_REGISTRY="$REG" bash "$HOOKS/pre-write-gate.sh" 2>"$EF" >/dev/null ); }
runb(){ ( cd "$D" && printf '%s' "$2" | HARNESS_STATE_DIR="$D/.claude/state" HARNESS_REGISTRY="$REG" bash "$HOOKS/pre-bash-gate.sh" 2>"$EF" >/dev/null ); }

# CONTROL — B with no watcher resolves to A's must-do.md -> ownership block (the old deadlock condition)
regA
runw "x" "$(wp "$SB" "src/foo.py")"
if grep -qi 'different session' "$EF"; then ok "CONTROL B (no own file) blocked by A's must-do.md — reproduces the deadlock condition"; else bad "CONTROL expected ownership block [$(tr -d '\n' <"$EF"|head -c100)]"; fi

# FIX (Write) — B with its OWN watcher slot2 resolves to must-do-2.md -> NOT blocked by A's file
regAB
runw "x" "$(wp "$SB" "src/foo.py")"
if grep -qi 'different session' "$EF"; then bad "FIX(write) B still ownership-blocked by A's file [$(tr -d '\n' <"$EF"|head -c100)]"; else ok "FIX(write) B is NOT blocked by A's must-do.md (routed to its own file)"; fi

# FIX (Bash) — same via pre-bash-gate (the gate the user actually hit)
runb "x" "$(bp "$SB" "python -c 'open(\"src/foo.py\",\"w\").write(1)'")"
if grep -qi 'different session' "$EF"; then bad "FIX(bash) B still ownership-blocked [$(tr -d '\n' <"$EF"|head -c100)]"; else ok "FIX(bash) B is NOT ownership-blocked via pre-bash-gate"; fi

# The resolver names B's OWN file as must-do-2.md (so the system can tell B what to author)
OWN=$( cd "$D" && HARNESS_REGISTRY="$REG" HARNESS_SESSION_ID="$SB" bash -c 'source "$HOME/.claude/scripts/lib-helpers.sh" 2>/dev/null; mustdo_file_for_dir "docs/must do"' 2>/dev/null )
case "$OWN" in */must-do-2.md) ok "B's own file resolves to must-do-2.md (distinct from A's)";; *) bad "B own file = '$OWN'";; esac

echo "----------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
