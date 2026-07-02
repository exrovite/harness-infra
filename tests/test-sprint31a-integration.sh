#!/usr/bin/env bash
# Sprint 31a integration TDD — drives the REAL hooks in a multi-lane sandbox; proves lane isolation
# and lane-1 transparency. Uses HARNESS_REGISTRY to point helpers at a sandbox registry.
set -u
PASS=0; FAIL=0
ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

mksb(){ # build a sandbox repo with lane-1 (flat) + lane-2 phases and a v2 registry; echo "SB|REG"
  local SB; SB=$(mktemp -d)
  mkdir -p "$SB/.claude/state" "$SB/.claude/state/lane-2"
  printf '{}' > "$SB/.claude/multi-lane.json"   # opt in to multilane (lanes only active with this flag)
  printf '{"phase":"PLAN","sprint":99,"iteration":0}' > "$SB/.claude/state/current-phase.json"
  printf '{"phase":"BUILD","sprint":7,"iteration":2}' > "$SB/.claude/state/lane-2/current-phase.json"
  local P; P=$( cd "$SB" && (pwd -W 2>/dev/null || pwd) )
  local REG="$SB/REG.json"
  printf '{"version":"2.0.0","max_lanes_per_project":5,"instances":[{"session_id":"L1","project":"%s","lane":1,"status":"active"},{"session_id":"L2","project":"%s","lane":2,"status":"active"}]}' "$P" "$P" > "$REG"
  echo "$SB|$REG"
}

t_lane2_isolated_turnpacket(){
  local R SB REG OUT; R=$(mksb); SB="${R%|*}"; REG="${R#*|}"
  OUT=$( cd "$SB" && printf '{"prompt":"hi","session_id":"L2"}' | HARNESS_REGISTRY="$REG" bash "$HOME/.claude/hooks/on-prompt-submit.sh" 2>/dev/null )
  if printf '%s' "$OUT" | grep -q 'Lane: 2 | Phase: BUILD | Sprint: 7' \
     && printf '%s' "$OUT" | grep -q '\[LANE 2\]' \
     && ! printf '%s' "$OUT" | grep -q 'Sprint: 99'; then
    ok "t_lane2_isolated_turnpacket lane-2 sees its OWN phase, [LANE 2] briefing, no lane-1 leak"
  else
    no "t_lane2_isolated_turnpacket"
  fi
  rm -rf "$SB"
}

t_lane1_transparent(){
  local R SB REG OUT; R=$(mksb); SB="${R%|*}"; REG="${R#*|}"
  OUT=$( cd "$SB" && printf '{"prompt":"hi","session_id":"L1"}' | HARNESS_REGISTRY="$REG" bash "$HOME/.claude/hooks/on-prompt-submit.sh" 2>/dev/null )
  if printf '%s' "$OUT" | grep -q 'Lane: 1 | Phase: PLAN | Sprint: 99' \
     && ! printf '%s' "$OUT" | grep -q '\[LANE '; then
    ok "t_lane1_transparent lane-1 = flat phase, no lane briefing (transparent)"
  else
    no "t_lane1_transparent"
  fi
  rm -rf "$SB"
}

t_lane2_state_write_isolated(){
  # post-write-check for a lane-2 session must write counters under lane-2/, not flat
  local R SB REG; R=$(mksb); SB="${R%|*}"; REG="${R#*|}"
  ( cd "$SB" && printf '{"tool_name":"Write","tool_input":{"file_path":"%s/src/x.js"},"session_id":"L2"}' "$SB" \
    | HARNESS_REGISTRY="$REG" bash "$HOME/.claude/hooks/post-write-check.sh" >/dev/null 2>&1 )
  # Sprint 50 (audit A5): counters are per-session — for session L2 the file is
  # lane-2/write-count.L2.txt. The isolation property is unchanged: the counter lands under
  # lane-2/, and nothing lands in the flat state dir.
  local L2C FLATC
  L2C=$(find "$SB/.claude/state/lane-2" -maxdepth 1 -name 'write-count*.txt' 2>/dev/null | head -1)
  FLATC=$(find "$SB/.claude/state" -maxdepth 1 -name 'write-count*.txt' 2>/dev/null | head -1)
  if [ -n "$L2C" ] && [ -z "$FLATC" ]; then
    ok "t_lane2_state_write_isolated lane-2 write-count under lane-2/, flat untouched"
  else
    no "t_lane2_state_write_isolated (lane2=$([ -n "$L2C" ] && echo y||echo n) flat=$([ -n "$FLATC" ] && echo y||echo n))"
  fi
  rm -rf "$SB"
}

echo "== Sprint 31a integration TDD =="
t_lane2_isolated_turnpacket; t_lane1_transparent; t_lane2_state_write_isolated
echo "-- RESULT: $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]
