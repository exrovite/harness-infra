#!/usr/bin/env bash
# Sprint 31a foundation TDD — resolve_instance + registry v2 + lane namespacing.
# Drives the REAL lib-helpers functions in a sandbox registry. MUST fail before implementation.
set -u
HELPERS="$HOME/.claude/scripts/lib-helpers.sh"
PASS=0; FAIL=0
ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

newreg(){ # create an empty v2 registry, echo its path
  local d; d=$(mktemp -d); local r="$d/REGISTRY.json"
  printf '{"version":"2.0.0","max_lanes_per_project":5,"instances":[]}' > "$r"
  echo "$r"
}
src(){ source "$HELPERS"; }
# Opt-in: lanes only activate when .claude/multi-lane.json exists in cwd. cd into a flagged temp dir so
# resolve_instance enables lanes (registry paths are absolute, so cwd is otherwise irrelevant to tests).
_flagcd(){ local m; m=$(mktemp -d); mkdir -p "$m/.claude"; : > "$m/.claude/multi-lane.json"; cd "$m" 2>/dev/null; }

# ---- claim + numbering (AC5/AC6) ----
t_claim(){
  local R; R=$(newreg)
  ( src; _flagcd
    a=$(instance_claim_lane "sessA" "g:/proj" "$R"); b=$(instance_claim_lane "sessB" "g:/proj" "$R")
    [ "$a" = "1" ] && [ "$b" = "2" ] || { echo "BAD a=$a b=$b"; exit 1; }
  ) && ok "t_claim two sessions same project -> lanes 1,2" || no "t_claim lanes 1,2"
  rm -rf "$(dirname "$R")"
}
t_cap(){
  local R; R=$(newreg)
  ( src; _flagcd
    for s in s1 s2 s3 s4 s5; do instance_claim_lane "$s" "g:/proj" "$R" >/dev/null; done
    sixth=$(instance_claim_lane "s6" "g:/proj" "$R" 2>/dev/null); rc=$?
    [ -z "$sixth" ] && [ "$rc" -ne 0 ] || { echo "6th not refused: '$sixth' rc=$rc"; exit 1; }
  ) && ok "t_cap 6th instance refused" || no "t_cap 6th refused"
  rm -rf "$(dirname "$R")"
}
t_find(){
  local R; R=$(newreg)
  ( src; _flagcd
    instance_claim_lane "sA" "g:/p" "$R" >/dev/null; instance_claim_lane "sB" "g:/p" "$R" >/dev/null
    [ "$(instance_find_by_session sA "$R")" = "1" ] || { echo "find sA"; exit 1; }
    [ "$(instance_find_by_session sB "$R")" = "2" ] || { echo "find sB"; exit 1; }
    instance_find_by_session sZ "$R" >/dev/null 2>&1 && { echo "unknown found"; exit 1; }
    true
  ) && ok "t_find returns correct lane; unknown -> not found" || no "t_find lookup"
  rm -rf "$(dirname "$R")"
}
t_release_reuse(){
  local R; R=$(newreg)
  ( src; _flagcd
    instance_claim_lane "sA" "g:/p" "$R" >/dev/null; instance_claim_lane "sB" "g:/p" "$R" >/dev/null
    instance_release sB "$R"
    instance_find_by_session sB "$R" >/dev/null 2>&1 && { echo "sB still present"; exit 1; }
    [ "$(instance_find_by_session sA "$R")" = "1" ] || { echo "sA gone"; exit 1; }
    g=$(instance_claim_lane "sG" "g:/p" "$R")   # lowest free now = 2
    [ "$g" = "2" ] || { echo "reuse got $g not 2"; exit 1; }
    true
  ) && ok "t_release_reuse releases only sB; new claim reuses lane 2" || no "t_release_reuse"
  rm -rf "$(dirname "$R")"
}
# per-project independence (AC13)
t_project_independent(){
  local R; R=$(newreg)
  ( src; _flagcd
    for s in a1 a2 a3 a4 a5; do instance_claim_lane "$s" "g:/projA" "$R" >/dev/null; done
    b=$(instance_claim_lane "b1" "g:/projB" "$R")   # projB unaffected by projA's 5
    [ "$b" = "1" ] || { echo "projB got $b not 1"; exit 1; }
    true
  ) && ok "t_project_independent projB gets lane 1 despite projA full" || no "t_project_independent"
  rm -rf "$(dirname "$R")"
}

# ---- resolve_instance + lane paths (AC2/AC3) ----
t_resolve_lane1_flat(){
  local R; R=$(newreg)
  ( src; _flagcd
    instance_claim_lane "sA" "g:/p" "$R" >/dev/null
    # payload as ARG; stdin EMPTY (must not read stdin)
    resolve_instance '{"session_id":"sA"}' "g:/p" "PreToolUse" "$R" < /dev/null
    [ "$LANE" = "1" ] || { echo "LANE=$LANE"; exit 1; }
    [ "$STATE_DIR" = ".claude/state" ] || { echo "STATE_DIR=$STATE_DIR"; exit 1; }
    [ "$CONTRACTS_DIR" = ".claude/contracts" ] || { echo "CONTRACTS_DIR=$CONTRACTS_DIR"; exit 1; }
    [ "$MUSTDO_FILE" = "docs/must do/must-do.md" ] || { echo "MUSTDO=$MUSTDO_FILE"; exit 1; }
    true
  ) && ok "t_resolve_lane1_flat lane1 = flat paths; stdin not read" || no "t_resolve_lane1_flat"
  rm -rf "$(dirname "$R")"
}
t_resolve_lane2_subdir(){
  local R; R=$(newreg)
  ( src; _flagcd
    instance_claim_lane "sA" "g:/p" "$R" >/dev/null; instance_claim_lane "sB" "g:/p" "$R" >/dev/null
    resolve_instance '{"session_id":"sB"}' "g:/p" "PreToolUse" "$R" < /dev/null
    [ "$LANE" = "2" ] || { echo "LANE=$LANE"; exit 1; }
    [ "$STATE_DIR" = ".claude/state/lane-2" ] || { echo "STATE_DIR=$STATE_DIR"; exit 1; }
    [ "$CONTRACTS_DIR" = ".claude/contracts/lane-2" ] || { echo "CONTRACTS=$CONTRACTS_DIR"; exit 1; }
    [ "$MUSTDO_FILE" = "docs/must do/must-do-1.md" ] || { echo "MUSTDO=$MUSTDO_FILE"; exit 1; }
    true
  ) && ok "t_resolve_lane2_subdir lane2 = subdir paths; must-do-1.md" || no "t_resolve_lane2_subdir"
  rm -rf "$(dirname "$R")"
}
# lazy claim (AC7/AC8/AC37)
t_lazy_claim(){
  local R; R=$(newreg)
  ( src; _flagcd
    # new session via PreToolUse (read-only) -> NO claim, default lane 1 flat
    resolve_instance '{"session_id":"sNew"}' "g:/p" "PreToolUse" "$R" < /dev/null
    instance_find_by_session sNew "$R" >/dev/null 2>&1 && { echo "PreToolUse claimed!"; exit 1; }
    [ "$LANE" = "1" ] || { echo "default LANE=$LANE"; exit 1; }
    # first UserPromptSubmit -> claims
    resolve_instance '{"session_id":"sNew"}' "g:/p" "UserPromptSubmit" "$R" < /dev/null
    [ "$(instance_find_by_session sNew "$R")" = "1" ] || { echo "UserPromptSubmit did not claim"; exit 1; }
    true
  ) && ok "t_lazy_claim PreToolUse no-claim; UserPromptSubmit claims" || no "t_lazy_claim"
  rm -rf "$(dirname "$R")"
}

# ---- v1->v2 migration is NON-DESTRUCTIVE (AC25; safety: never clobber live watchers) ----
v1reg(){ local d; d=$(mktemp -d); local r="$d/REGISTRY.json"
  printf '{"version":"1.0.0","watchers":[{"slot":1,"status":"active","claimed_by":"Claude","project":"g:/p","cron_job_id":"abc"}]}' > "$r"; echo "$r"; }
t_migrate_preserves_watchers(){
  local R; R=$(v1reg)
  ( src; _flagcd
    _ensure_reg_v2 "$R"
    [ "$(jq -r '.watchers | length' "$R")" = "1" ] || { echo "watchers lost"; exit 1; }
    [ "$(jq -r '.watchers[0].status' "$R")" = "active" ] || { echo "watcher mangled"; exit 1; }
    [ "$(jq -r '.instances | type' "$R")" = "array" ] || { echo "no instances array"; exit 1; }
    [ "$(jq -r '.version' "$R")" = "2.0.0" ] || { echo "version not bumped"; exit 1; }
    true
  ) && ok "t_migrate_preserves_watchers v1 .watchers preserved + .instances added" || no "t_migrate_preserves_watchers"
  rm -rf "$(dirname "$R")"
}
t_claim_on_v1_keeps_watchers(){
  local R; R=$(v1reg)
  ( src; _flagcd
    l=$(instance_claim_lane "sX" "g:/p" "$R")
    [ "$l" = "1" ] || { echo "claim got $l"; exit 1; }
    [ "$(jq -r '.watchers | length' "$R")" = "1" ] || { echo "watchers lost after claim"; exit 1; }
    [ "$(jq -r '.instances | length' "$R")" = "1" ] || { echo "instance not added"; exit 1; }
    true
  ) && ok "t_claim_on_v1_keeps_watchers claim adds instance, preserves watchers" || no "t_claim_on_v1_keeps_watchers"
  rm -rf "$(dirname "$R")"
}

echo "== Sprint 31a foundation TDD =="
t_claim; t_cap; t_find; t_release_reuse; t_project_independent
t_resolve_lane1_flat; t_resolve_lane2_subdir; t_lazy_claim
t_migrate_preserves_watchers; t_claim_on_v1_keeps_watchers
echo "-- RESULT: $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]
