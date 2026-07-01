#!/bin/bash
# test-mustdo-ownership-churn.sh — the must-do file resolver must NOT churn a session's grounding when the
# claim/ground order differs from slot order. The OLD ordinal-by-slot assignment gave a lower-slot session
# the file a higher-slot session already OWNED (collision -> "no grounding" loop). The greedy resolver must
# assign each session a file NOT owned by a LIVE peer, keep a grounded file stable, and reclaim dead ones.
# Also: a busy agent's Bash/Write activity must refresh its heartbeat (so it is not reaped mid-work).
set -u
HELP="$HOME/.claude/scripts/lib-helpers.sh"; HOOKS="$HOME/.claude/hooks"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }
SBX=$(mktemp -d 2>/dev/null || echo "/tmp/moc-$$"); trap 'rm -rf "$SBX" 2>/dev/null' EXIT
PROJ="$SBX/proj"; MDIR="$PROJ/docs/must do"; mkdir -p "$MDIR"
PABS="$(cd "$PROJ" && pwd -W 2>/dev/null || pwd)"; REG="$SBX/reg.json"
NOW=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S'); OLD="2020-01-01T00:00:00+00:00"
# A holds slot 2 but grounded first; B holds slot 1 (claimed later) — the exact live PCW situation.
regAB(){ printf '{"version":"3.0.0","max_per_project":5,"watchers":[{"slot":1,"project":"%s","session_id":"SB","status":"active","last_seen":"%s"},{"slot":2,"project":"%s","session_id":"SA","status":"active","last_seen":"%s"}]}\n' "$PABS" "${1:-$NOW}" "$PABS" "${2:-$NOW}" > "$REG"; }
stamp(){ printf '<!-- mustdo-session: %s | built: pack -->\n- src/x\n' "$1" > "$2"; }
own(){ ( cd "$PROJ" && HARNESS_REGISTRY="$REG" HARNESS_SESSION_ID="$1" bash -c 'source "'"$HELP"'"; mustdo_file_for_dir "docs/must do"' 2>/dev/null ); }

# T1 (the reported bug): A (slot2) owns must-do.md and is LIVE; B (slot1, new) must NOT be assigned
# must-do.md — it must get must-do-2.md (the OLD ordinal resolver gave B must-do.md -> collision).
regAB; rm -f "$MDIR"/must-do*.md; stamp SA "$MDIR/must-do.md"
RB=$(own SB); case "$RB" in */must-do-2.md) ok "T1 lower-slot new session avoids a live peer's grounded must-do.md (-> must-do-2.md)";; *) bad "T1 B got '$RB' (collision)";; esac
# T2: A keeps its grounded file (stable)
RA=$(own SA); case "$RA" in */must-do.md) ok "T2 grounded session keeps must-do.md (stable)";; *) bad "T2 A got '$RA'";; esac

# T3: two NEW sessions (no stamps, no files) get DISTINCT files, deterministic by slot (no race)
regAB; rm -f "$MDIR"/must-do*.md
RB=$(own SB); RA=$(own SA)
{ case "$RB" in */must-do.md) true;; *) false;; esac; } && { case "$RA" in */must-do-2.md) true;; *) false;; esac; } \
  && ok "T3 two new sessions fan out distinctly: slot1->must-do.md slot2->must-do-2.md" || bad "T3 B='$RB' A='$RA'"

# T4: DEAD owner reclaim — A owns must-do.md but is DEAD; B (only live) reclaims must-do.md
regAB "$NOW" "$OLD"; rm -f "$MDIR"/must-do*.md; stamp SA "$MDIR/must-do.md"
RB=$(own SB); case "$RB" in */must-do.md) ok "T4 a DEAD owner's must-do.md is reclaimed by the live session";; *) bad "T4 B got '$RB' (should reclaim must-do.md)";; esac

# T5: heartbeat — a Bash command refreshes THIS session's last_seen (busy agent stays alive, not reaped)
mkdir -p "$PROJ/.claude/state"; printf '{"phase":"BUILD","sprint":1}' > "$PROJ/.claude/state/current-phase.json"
regAB "$OLD" "$NOW"   # SB's heartbeat is OLD
( cd "$PROJ" && printf '%s' '{"session_id":"SB","tool_name":"Bash","tool_input":{"command":"grep -r foo docs"}}' | HARNESS_STATE_DIR="$PROJ/.claude/state" HARNESS_REGISTRY="$REG" bash "$HOOKS/pre-bash-gate.sh" >/dev/null 2>&1 )
LS=$(jq -r '.watchers[]|select(.session_id=="SB")|.last_seen' "$REG" 2>/dev/null)
[ "$LS" != "$OLD" ] && ok "T5 pre-bash-gate refreshes a busy session's heartbeat ($LS)" || bad "T5 heartbeat not refreshed ($LS)"
# and it is now considered live
IS=$(bash -c 'source "'"$HELP"'"; session_is_live SB "'"$REG"'" && echo LIVE || echo DEAD')
[ "$IS" = LIVE ] && ok "T5b session is LIVE after a heartbeat" || bad "T5b still $IS"

bash -n "$HELP" 2>/dev/null && ok "bash -n lib-helpers" || bad "bash -n"
echo "----------------------------------------"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
