#!/bin/bash
# test-watcher-reap.sh — intelligent stale-slot clearing (AC30): heartbeat (last_seen) + reap.
# A watcher whose heartbeat is stale (owning session gone) is freed; a fresh one is kept; a session
# NEVER reaps its own watcher; legacy watchers with no last_seen fall back to claimed_at.
set -u
HELP="$HOME/.claude/scripts/lib-helpers.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }
SBX=$(mktemp -d 2>/dev/null || echo "/tmp/wr-$$")
trap 'rm -rf "$SBX" 2>/dev/null' EXIT
HOMES="$SBX/home"; mkdir -p "$HOMES/.openclaw/watchers"
REG="$SBX/reg.json"
NOW=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
OLD="2020-01-01T00:00:00+00:00"

# registry: slot1 fresh (SA), slot2 stale heartbeat (SB), slot3 legacy no last_seen old claimed_at (SC),
# slot4 = MY own session (SME) but stale heartbeat -> must be PROTECTED (never reap own).
mkreg(){ cat > "$REG" <<JSON
{"version":"3.0.0","max_per_project":5,"watchers":[
 {"slot":1,"project":"p","session_id":"SA","status":"active","claimed_at":"$NOW","last_seen":"$NOW"},
 {"slot":2,"project":"p","session_id":"SB","status":"active","claimed_at":"$NOW","last_seen":"$OLD"},
 {"slot":3,"project":"p","session_id":"SC","status":"active","claimed_at":"$OLD"},
 {"slot":4,"project":"p","session_id":"SME","status":"active","claimed_at":"$NOW","last_seen":"$OLD"}
]}
JSON
}
present(){ jq -e --argjson s "$1" '[.watchers[]|select(.slot==$s)]|length>0' "$REG" >/dev/null 2>&1; }

# T1: watcher_touch_session refreshes THIS session's heartbeat
mkreg
( HOME="$HOMES" bash -c 'source "'"$HELP"'"; watcher_touch_session SB "'"$REG"'"' )
LS=$(jq -r '.watchers[]|select(.slot==2)|.last_seen' "$REG")
[ "$LS" != "$OLD" ] && ok "T1 watcher_touch_session refreshed SB's heartbeat ($LS)" || bad "T1 heartbeat not refreshed ($LS)"

# T1b: touch is a no-op for a session with no watcher (no crash, registry unchanged shape)
BEFORE=$(jq -S . "$REG"); ( HOME="$HOMES" bash -c 'source "'"$HELP"'"; watcher_touch_session NOBODY "'"$REG"'"' ); AFTER=$(jq -S . "$REG")
[ "$BEFORE" = "$AFTER" ] && ok "T1b touch no-op for a session with no watcher" || bad "T1b touch mutated registry for unknown session"

# T2: reap (as session SME) frees stale (slot2 heartbeat, slot3 legacy claimed_at), keeps fresh (slot1),
#     and NEVER reaps my own (slot4) even though its heartbeat is stale.
mkreg
REAPED=$( HOME="$HOMES" HARNESS_SESSION_ID=SME bash -c 'source "'"$HELP"'"; watcher_reap_stale 1200 "'"$REG"'"' )
present 1 && ok "T2a fresh watcher (slot1) kept" || bad "T2a fresh watcher wrongly reaped"
present 2 && bad "T2b stale-heartbeat watcher (slot2) NOT reaped" || ok "T2b stale-heartbeat watcher (slot2) reaped"
present 3 && bad "T2c legacy old-claimed_at watcher (slot3) NOT reaped" || ok "T2c legacy old watcher (slot3) reaped"
present 4 && ok "T2d my OWN watcher (slot4) protected even when stale" || bad "T2d reaped my own watcher!"
{ printf '%s' "$REAPED" | grep -q 2 && printf '%s' "$REAPED" | grep -q 3; } && ok "T2e reap echoed slots 2 and 3" || bad "T2e reaped='$REAPED'"
# freed slot file (sibling of the registry) reset to available
grep -qi 'available' "$SBX/slot-2.md" 2>/dev/null && ok "T2f freed slot-2.md reset to available" || bad "T2f slot-2.md not reset"

# T3: a FRESH-heartbeat non-owned watcher is NOT reaped
mkreg
( HOME="$HOMES" HARNESS_SESSION_ID=SME bash -c 'source "'"$HELP"'"; watcher_reap_stale 1200 "'"$REG"'"' ) >/dev/null
present 1 && ok "T3 fresh non-owned watcher survives reap" || bad "T3 fresh watcher reaped"

# T4: watcher_claim_pp stamps last_seen at claim (so a new watcher starts alive)
CREG="$SBX/creg.json"; printf '{"version":"3.0.0","max_per_project":5,"watchers":[]}\n' > "$CREG"
( HOME="$HOMES" bash -c 'source "'"$HELP"'"; watcher_claim_pp "NEWSESS" "someproj" "'"$CREG"'"' ) >/dev/null 2>&1
LS4=$(jq -r '.watchers[]|select(.session_id=="NEWSESS")|.last_seen // "MISSING"' "$CREG" 2>/dev/null)
[ "$LS4" != "MISSING" ] && [ -n "$LS4" ] && ok "T4 watcher_claim_pp stamps last_seen at claim" || bad "T4 no last_seen at claim ($LS4)"

bash -n "$HELP" 2>/dev/null && ok "bash -n lib-helpers" || bad "bash -n"
echo "----------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
