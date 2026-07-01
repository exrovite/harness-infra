#!/bin/bash
# test-session-scoping.sh — every per-session artifact must resolve to THIS session's OWN watcher,
# never the project's first/stale watcher. Covers the reported bug: a GLM session was answering a stale
# Image Studio watcher's pre-flight questions instead of its own task.
set -u
HELP="$HOME/.claude/scripts/lib-helpers.sh"
GEN="$HOME/.claude/scripts/generate-pre-flight-challenge.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }
SBX=$(mktemp -d 2>/dev/null || echo "/tmp/ss-$$")
trap 'rm -rf "$SBX" 2>/dev/null' EXIT

PROJ="p"; REG="$SBX/reg.json"
# Registry: session SA owns slot 1, session SB owns slot 2 (both active, same project)
printf '{"version":"3.0.0","max_per_project":5,"watchers":[{"slot":1,"project":"%s","session_id":"SA","status":"active","cron_job_id":"c1","cron_interval":"*/3 * * * *"},{"slot":2,"project":"%s","session_id":"SB","status":"active","cron_job_id":"c2","cron_interval":"*/3 * * * *"}]}\n' "$PROJ" "$PROJ" > "$REG"
# Registry with ONLY SA active (SB has NOT claimed a watcher yet)
REG_A="$SBX/reg_a.json"
printf '{"version":"3.0.0","max_per_project":5,"watchers":[{"slot":1,"project":"%s","session_id":"SA","status":"active","cron_job_id":"c1","cron_interval":"*/3 * * * *"}]}\n' "$PROJ" > "$REG_A"

# T1: watcher_slot_for_session resolves each session's OWN slot
R=$(bash -c 'source "'"$HELP"'"; printf "%s|%s|%s|%s" "$(watcher_slot_for_session SA "'"$REG"'")" "$(watcher_slot_for_session SB "'"$REG"'")" "$(watcher_slot_for_session SZ "'"$REG"'")" "$(watcher_slot_for_session "" "'"$REG"'")"')
[ "$R" = "1|2||" ] && ok "T1 watcher_slot_for_session: SA->1 SB->2 unknown->empty no-id->empty" || bad "T1 got '$R'"

# T2: check_watcher_for_project prefers THIS session's slot (HARNESS_SESSION_ID), else project-first
R2A=$(bash -c 'source "'"$HELP"'"; HARNESS_SESSION_ID=SB check_watcher_for_project "'"$PROJ"'" "'"$REG"'"')
R2B=$(bash -c 'source "'"$HELP"'"; check_watcher_for_project "'"$PROJ"'" "'"$REG"'"')   # no session -> project-first (slot 1)
{ [ "$R2A" = "2" ] && [ "$R2B" = "1" ]; } && ok "T2 check_watcher_for_project: session SB->2, session-less->1 (back-compat)" || bad "T2 SB='$R2A' none='$R2B'"

# T3: compute_pending_gates claim gate is PER-SESSION — SB (no own watcher, but project HAS SA's) is
#     STILL told to claim; SA (has its own) is NOT; session-less falls back to project-count (no claim).
gates(){ bash -c 'source "'"$HELP"'"; WATCHER_REGISTRY="'"$2"'"; HARNESS_STATE_DIR="'"$SBX"'/st"; '"$1"' compute_pending_gates BUILD 0 "'"$PROJ"'" 2>/dev/null'; }
G_SB=$(gates 'HARNESS_SESSION_ID=SB' "$REG_A")   # SB not in reg_a -> must claim
G_SA=$(gates 'HARNESS_SESSION_ID=SA' "$REG_A")   # SA is in reg_a -> no claim
G_NONE=$(gates '' "$REG_A")                       # no session -> project has SA -> no claim
printf '%s' "$G_SB"   | grep -q 'watcher claim' && ok "T3a SB (no own watcher) is told to claim its own" || bad "T3a SB not prompted [$G_SB]"
printf '%s' "$G_SA"   | grep -qv 'watcher claim' >/dev/null; printf '%s' "$G_SA" | grep -q 'watcher claim' && bad "T3b SA wrongly prompted" || ok "T3b SA (has own watcher) not prompted"
printf '%s' "$G_NONE" | grep -q 'watcher claim' && bad "T3c session-less regressed (should be project-count)" || ok "T3c session-less falls back to project-count (no claim)"

# T4: THE REPORTED BUG — session SB's pre-flight challenge is derived from SB's OWN slot (slot 2 =
#     prompt-assembly), NOT the project's first/stale watcher (slot 1 = Image Studio).
HOMES="$SBX/home"; mkdir -p "$HOMES/.openclaw/watchers" "$HOMES/.openclaw/distractor-pool" "$SBX/proj/.claude"
cp "$HOME/.openclaw/distractor-pool/"*.txt "$HOMES/.openclaw/distractor-pool/" 2>/dev/null
PROJ_ABS="$(cd "$SBX/proj" && pwd -W 2>/dev/null || pwd)"
printf '{"version":"3.0.0","max_per_project":5,"watchers":[{"slot":1,"project":"%s","session_id":"SA","status":"active"},{"slot":2,"project":"%s","session_id":"SB","status":"active"}]}\n' "$PROJ_ABS" "$PROJ_ABS" > "$HOMES/.openclaw/watchers/REGISTRY.json"
printf '# Watcher Slot 1\n**Status**: active\n**Task**: IMAGESTUDIO build the image studio gallery panel\n## TO-DO\n- [ ] Step 1: wire IMAGESTUDIO gallery grid\n## OUT OF SCOPE\n- do not touch prompt code\n' > "$HOMES/.openclaw/watchers/slot-1.md"
printf '# Watcher Slot 2\n**Status**: active\n**Task**: PROMPTASSEMBLY refactor the prompt assembly module\n## TO-DO\n- [ ] Step 1: fix PROMPTASSEMBLY token order\n## OUT OF SCOPE\n- do not touch image code\n' > "$HOMES/.openclaw/watchers/slot-2.md"
if [ -f "$GEN" ]; then
  ( cd "$SBX/proj" && HOME="$HOMES" bash "$GEN" "prompt-assembly.js" "SB" >/dev/null 2>&1 )
  CH="$SBX/proj/.claude/pre-flight/SB/challenge.md"
  if [ -f "$CH" ]; then
    if grep -qi 'PROMPTASSEMBLY' "$CH" && ! grep -qi 'IMAGESTUDIO' "$CH"; then
      ok "T4 session SB's challenge is from SB's slot (prompt-assembly), NOT slot-1 (Image Studio)"
    else
      bad "T4 challenge content wrong: PROMPTASSEMBLY=$(grep -ci PROMPTASSEMBLY "$CH") IMAGESTUDIO=$(grep -ci IMAGESTUDIO "$CH")"
    fi
  else
    bad "T4 no challenge generated at $CH"
  fi
fi

bash -n "$HELP" 2>/dev/null && ok "bash -n lib-helpers" || bad "bash -n"
echo "----------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
